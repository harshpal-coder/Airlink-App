import 'dart:async';
import 'package:flutter/widgets.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../models/device_model.dart';
import 'package:uuid/uuid.dart';
import 'database_helper.dart';
import 'discovery_service.dart';
import '../models/session_state.dart';
import 'messaging_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'notification_service.dart';

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService discoveryService;
  final MessagingService messagingService;
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  List<Device> discoveredDevices = [];
  Device? connectedDevice;
  List<Chat> chats = [];
  List<Group> groups = [];
  User? currentUser;
  bool isBrowsing = false;
  bool isAdvertising = false;
  bool get isDiscovering => isBrowsing || isAdvertising;
  
  StreamSubscription? _discoveredSubscription;
  StreamSubscription? _connectedSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _qualitySubscription;

  // Local state for typing indicators: peerUuid -> isTyping
  final Map<String, bool> _typingPeers = {};
  Map<String, bool> get typingPeers => _typingPeers;

  int get totalNodesInMesh => discoveryService.getConnectedDevices().length + 1; // Direct + Me
  
  /// Returns count of all unique reachable peers in the mesh (direct + indirect)
  int get reachablePeersCount {
    final Set<String> allUuids = {};
    // Direct
    for (var d in discoveryService.getConnectedDevices()) {
      if (d.uuid != null) allUuids.add(d.uuid!);
    }
    // Indirect (from topology)
    for (var neighbors in messagingService.meshTopology.values) {
      allUuids.addAll(neighbors);
    }
    return allUuids.length;
  }

  /// Tracking for proximity alerts to avoid duplicate spam: peerUuid -> timestamp
  final Map<String, DateTime> _proximityAlertsSent = {};

  /// Periodic timer that restarts discovery to catch returning peers.
  Timer? _rescanTimer;
  static const Duration _rescanInterval = Duration(seconds: 60);
  
  Timer? _batteryTimer;
  static const Duration _batteryInterval = Duration(seconds: 45);

  ChatProvider({
    required this.discoveryService,
    required this.messagingService,
  }) {
    _init();
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadCurrentUser();
    await _loadSettings();
    await loadChats();
    await loadGroups();
    await _refreshKnownDevices();

    _discoveredSubscription = discoveryService.discoveredDevices.listen((
      devices,
    ) async {
      // Safety Filter: Ensure no duplicates by UUID and exclude self
      final myUuid = currentUser?.uuid;
      final uniqueDevices = <String, Device>{};
      for (var d in devices) {
        final key = d.uuid ?? d.deviceId;
        if (key == myUuid || key == 'me') continue;
        
        // If we have a duplicate UUID, prefer the one with a more active state
        if (!uniqueDevices.containsKey(key) || 
            (d.state == SessionState.connected && uniqueDevices[key]!.state != SessionState.connected)) {
          uniqueDevices[key] = d;
        }
      }
      discoveredDevices = uniqueDevices.values.toList();
      
      // Proximity Alerts for Favorites
      for (var device in discoveredDevices) {
        if (device.uuid != null && device.state == SessionState.notConnected) {
          // Check if this peer is a favorite in our chats
          final chat = await dbHelper.getChatByPeerUuid(device.uuid!);
          if (chat != null && chat.isFavorite) {
            // Rate limit alerts to once every 5 minutes per peer
            final lastAlert = _proximityAlertsSent[device.uuid!];
            if (lastAlert == null || DateTime.now().difference(lastAlert).inMinutes > 5) {
              _proximityAlertsSent[device.uuid!] = DateTime.now();
              NotificationService.showProximityAlert(device.deviceName);
              debugPrint('[ChatProvider] Proximity Alert triggered for ${device.deviceName}');
            }
          }
        }
      }
      
      notifyListeners();
    });

    _connectedSubscription = discoveryService.connectedDevice.listen((
      device,
    ) async {
      connectedDevice = device;
      if (device.state == SessionState.connected) {
        // Save to chats using UUID to ensure auto-reconnect works next time
        if (device.uuid != null) {
          await messagingService.saveConnectionToChat(
            device.uuid!,
            device.deviceName,
          );
          // Sync profile photo
          await messagingService.sendProfileImage(device.uuid!);
          // Process any queued messages for this device
          await messagingService.processPendingDelivery(device.uuid!);
          // Refresh known devices so this peer is recognized on next scan
          await _refreshKnownDevices();
        }
      } else if (device.state == SessionState.notConnected) {
        // A peer disconnected
        _batteryTimer?.cancel();
        debugPrint('[ChatProvider] Peer disconnected: ${device.deviceName}. '
            'Will attempt reconnect on next scan cycle.');
        _ensureRescanTimer();
      }
      notifyListeners();
    });

    _messageSubscription = messagingService.messageUpdated.listen((_) {
      loadChats();
      loadGroups();
    });

    _typingSubscription = messagingService.typingUpdated.listen((data) {
      final String uuid = data['uuid'];
      final bool isTyping = data['isTyping'];
      _typingPeers[uuid] = isTyping;
      notifyListeners();
    });

    _qualitySubscription = messagingService.connectionQualityUpdated.listen((_) {
      notifyListeners();
    });

    // Automatically start services if they should be active
    if (isBrowsing) await startBrowsing();
    if (isAdvertising) await startAdvertising();
    
    if (isDiscovering) {
      _ensureRescanTimer();
      _startBatteryTimer();
    }

    // Listen for background keep-alive pokes
    final service = FlutterBackgroundService();
    service.on('keep_alive_poke').listen((event) async {
      if (isDiscovering) {
        // Only refresh radio if we have 0 connections to avoid dropping active sessions
        final connected = discoveryService.getConnectedDevices();
        if (connected.isEmpty) {
          debugPrint('[ChatProvider] Received background keep-alive poke. Refreshing radio (no active connections).');
          if (isBrowsing) await discoveryService.startBrowsing(forceRestart: true);
          if (isAdvertising) await discoveryService.startAdvertising(forceRestart: true);
        } else {
          debugPrint('[ChatProvider] Received background keep-alive poke. Passive (active connections: ${connected.length}).');
        }
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Defaulting to true: "Invisible Mode" OFF (Visible) and "Auto Discovery" ON
    isBrowsing = prefs.getBool('isBrowsing') ?? true;
    isAdvertising = prefs.getBool('isAdvertising') ?? true;
    notifyListeners();
  }

  /// Loads known peer UUIDs from the database and passes them to the
  /// discovery service so the auto-reconnect logic in [startBrowsing] works.
  Future<void> _refreshKnownDevices() async {
    final knownDevices = await dbHelper.getKnownDevices();
    discoveryService.setKnownDevices(knownDevices);
  }

  /// Starts the periodic re-scan timer if discovery is active.
  /// Each tick restarts browsing so [onEndpointFound] fires again for
  /// any peers that have come back in range.
  void _ensureRescanTimer() {
    if (_rescanTimer?.isActive == true) return;
    _rescanTimer = Timer.periodic(_rescanInterval, (_) async {
      if (!isDiscovering) {
        _rescanTimer?.cancel();
        return;
      }
      debugPrint('[ChatProvider] Periodic re-scan: restarting discovery...');
      await _refreshKnownDevices();
      // Restart browsing so onEndpointFound fires for returning peers
      if (isBrowsing) {
        await discoveryService.stopDiscovery();
        await Future.delayed(const Duration(milliseconds: 200));
        await discoveryService.startBrowsing();
      }
    });
  }

  void _startBatteryTimer() {
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(_batteryInterval, (_) async {
      final connected = discoveryService.getConnectedDevices();
      for (var device in connected) {
        await messagingService.sendBatteryUpdate(device.deviceId);
        await messagingService.sendMeshUpdate(device.deviceId);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isDiscovering) {
      debugPrint('[ChatProvider] App resumed — ensuring discovery is active.');
      _refreshKnownDevices();
      // startBrowsing() internally handles "already active" check now
      if (isBrowsing) startBrowsing();
      if (isAdvertising) startAdvertising();
    }
  }

  Future<void> _loadCurrentUser() async {
    currentUser = await dbHelper.getUser('me');
    notifyListeners();
  }

  Future<void> ensureCurrentUser(String fallbackDeviceName) async {
    // If currentUser is still null (initial load in _init might be slow), check DB first
    currentUser ??= await dbHelper.getUser('me');

    if (currentUser == null) {
      String deviceName = fallbackDeviceName;
      try {
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      } catch (_) {}

      final user = User(
        id: 'me',
        uuid: const Uuid().v4(),
        deviceName: deviceName,
        isMe: true,
      );
      await dbHelper.createUser(user);
      currentUser = user;
      notifyListeners();
    }
  }


  Future<void> updateCurrentUserName(String newName) async {
    if (currentUser != null) {
      final updatedUser = currentUser!.copyWith(deviceName: newName);
      await dbHelper.createUser(updatedUser);
      currentUser = updatedUser;

      // Update advertising name if discovering
      // Update advertising name if active
      if (isAdvertising || isBrowsing) {
        if (isAdvertising) await stopAdvertising();
        if (isBrowsing) await stopBrowsing();
        
        if (isAdvertising) await startAdvertising();
        if (isBrowsing) await startBrowsing();
      } else {
        notifyListeners();
      }
    }
  }

  /// Save a profile image from an already-resolved local file path.
  /// Used by [ProfileSetupScreen] where the image was already picked.
  Future<void> updateProfileImageFromPath(String imagePath) async {
    if (currentUser == null) return;

    final directory = await getApplicationDocumentsDirectory();
    final String fileName =
        'profile_${currentUser!.uuid}${p.extension(imagePath)}';
    final String localPath = p.join(directory.path, fileName);

    await File(imagePath).copy(localPath);

    final updatedUser = currentUser!.copyWith(profileImage: localPath);
    await dbHelper.createUser(updatedUser);
    currentUser = updatedUser;
    notifyListeners();
  }

  Future<void> updateProfileImage(ImageSource source) async {
    if (currentUser == null) return;

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final String fileName =
          'profile_${currentUser!.uuid}${p.extension(image.path)}';
      final String localPath = p.join(directory.path, fileName);

      // Copy file to local storage
      await File(image.path).copy(localPath);

      final updatedUser = currentUser!.copyWith(profileImage: localPath);
      await dbHelper.createUser(updatedUser);
      currentUser = updatedUser;
      notifyListeners();
    }
  }

  Future<void> loadChats() async {
    chats = await dbHelper.getChats();
    // Sort chats by name or time if needed, but DB currently does by time DESC
    notifyListeners();
  }

  Future<void> loadGroups() async {
    groups = await dbHelper.getGroups();
    notifyListeners();
  }

  Future<void> startBrowsing() async {
    if (currentUser == null) return;
    isBrowsing = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isBrowsing', true);
    notifyListeners();

    final String broadcastName = "${currentUser!.deviceName}|${currentUser!.uuid}";
    await discoveryService.init(broadcastName, localUuid: currentUser!.uuid);
    await discoveryService.startBrowsing();
  }

  Future<void> stopBrowsing() async {
    await discoveryService.stopDiscovery();
    isBrowsing = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isBrowsing', false);
    notifyListeners();
  }

  Future<void> startAdvertising() async {
    if (currentUser == null) return;
    isAdvertising = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAdvertising', true);
    notifyListeners();

    final String broadcastName = "${currentUser!.deviceName}|${currentUser!.uuid}";
    await discoveryService.init(broadcastName, localUuid: currentUser!.uuid);
    await discoveryService.startAdvertising();
  }

  Future<void> stopAdvertising() async {
    await discoveryService.stopAdvertising();
    isAdvertising = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAdvertising', false);
    notifyListeners();
  }

  Future<void> stopAllNetwork() async {
    await discoveryService.stopAll();
    isBrowsing = false;
    isAdvertising = false;
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    await _refreshKnownDevices();
    await startBrowsing();
    _ensureRescanTimer();
    _startBatteryTimer();
  }

  Future<void> stopDiscovery() async {
    _rescanTimer?.cancel();
    await stopAllNetwork();
  }

  Future<void> clearAllChats() async {
    await dbHelper.deleteAllChats();
    await loadChats();
  }

  Future<void> connectToDevice(Device device) async {
    if (device.isMesh) {
      debugPrint('[ChatProvider] Virtualizing connection to mesh peer ${device.deviceName}');
      discoveryService.updateDeviceState(device.deviceId, SessionState.connected);
      return;
    }
    await discoveryService.connect(device);
  }

  Future<void> disconnectFromDevice(Device device) async {
    if (device.isMesh) {
      discoveryService.updateDeviceState(device.deviceId, SessionState.notConnected);
      return;
    }
    await discoveryService.disconnect(device);
  }

  Future<void> sendMessage(String receiverUuid, String content) async {
    String peerName = _resolvePeerNameByUuid(receiverUuid);
    await messagingService.sendTextMessage(receiverUuid, peerName, content);
  }

  Future<void> retryMessage(String messageId) async {
    await messagingService.resendMessage(messageId);
  }

  Future<void> sendImage(String receiverUuid, String imagePath) async {
    String peerName = _resolvePeerNameByUuid(receiverUuid);
    await messagingService.sendImageMessage(receiverUuid, peerName, imagePath);
  }

  Future<void> sendTypingStatus(String receiverUuid, bool isTyping) async {
    await messagingService.sendTypingStatus(receiverUuid, isTyping);
  }

  Future<void> meshShout(String content) async {
    await messagingService.sendBroadcast(content);
  }

  Future<void> sendSOS({String content = "I need help! Immediate assistance required."}) async {
    await messagingService.broadcastSOS(content: content);
  }

  // --- Group Methods ---

  Future<void> createGroup(String name, List<String> memberUuids) async {
    await messagingService.createGroup(name, memberUuids);
    await loadGroups();
  }

  Future<void> sendGroupMessage(String groupId, String groupName, String content) async {
    await messagingService.sendGroupTextMessage(groupId, groupName, content);
  }

  Future<void> deleteGroup(String groupId) async {
    await dbHelper.deleteGroup(groupId);
    await loadGroups();
  }

  Future<void> markGroupAsRead(String groupId) async {
    final existingIndex = groups.indexWhere((g) => g.id == groupId);
    if (existingIndex >= 0) {
      if (groups[existingIndex].unreadCount == 0) return;
      
      final group = groups[existingIndex].copyWith(unreadCount: 0);
      await dbHelper.insertGroup(group);
      await dbHelper.markMessagesAsRead(groupId, currentUser?.uuid ?? '');
      await loadGroups();
    }
  }

  Future<void> sendPdf(String receiverUuid) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      String peerName = _resolvePeerNameByUuid(receiverUuid);
      await messagingService.sendPdfMessage(
        receiverUuid,
        peerName,
        result.files.single.path!,
      );
    }
  }

  // --- Voice Notes ---

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<void> startVoiceRecording() async {
    _isRecording = true;
    notifyListeners();
    await messagingService.startAudioRecording();
  }

  Future<void> stopAndSendVoiceNote(String receiverUuid) async {
    _isRecording = false;
    notifyListeners();
    final path = await messagingService.stopAudioRecording();
    if (path != null) {
      String peerName = _resolvePeerNameByUuid(receiverUuid);
      await messagingService.sendVoiceNote(receiverUuid, peerName, path);
    }
  }

  Future<void> playAudio(String path) async {
    await messagingService.playAudioMsg(path);
  }

  Future<void> pauseAudio() async {
    await messagingService.pauseAudio();
  }

  Future<void> acceptFile(String messageId) async {
    await messagingService.acceptFile(messageId);
    await loadChats();
  }

  Future<void> openFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await OpenFilex.open(path);
    } else {
      debugPrint('[ChatProvider] Cannot open file: File does not exist at $path');
    }
  }

  Future<void> shareFile(String path, {String? fileName}) async {
    final file = File(path);
    if (await file.exists()) {
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(path, name: fileName)],
        text: 'Sharing file: ${fileName ?? 'document'}',
      );
    }
  }

  Future<List<Message>> getMessages(String peerUuid) async {
    if (currentUser == null) return [];
    return await dbHelper.getMessages(peerUuid, currentUser!.uuid);
  }

  Future<void> markChatAsRead(String peerUuid) async {
    if (currentUser == null) return;
    
    final existingIndex = chats.indexWhere((c) => c.peerUuid == peerUuid);
    if (existingIndex >= 0) {
      if (chats[existingIndex].unreadCount == 0) return; // Already read
      
      final chat = chats[existingIndex].copyWith(unreadCount: 0);
      await dbHelper.insertChat(chat);
      await dbHelper.markMessagesAsRead(peerUuid, currentUser!.uuid);
      await loadChats();
    }
  }

  Future<void> deleteMessage(String id) async {
    await dbHelper.deleteMessage(id);
    notifyListeners();
  }

  Future<void> deleteChat(String peerUuid) async {
    await dbHelper.deleteChat(peerUuid);
    await loadChats();
  }

  String _resolvePeerNameByUuid(String uuid) {
    if (connectedDevice?.uuid == uuid) {
      return connectedDevice!.deviceName;
    }
    try {
      return discoveredDevices.firstWhere((d) => d.uuid == uuid).deviceName;
    } catch (_) {
      try {
        return chats.firstWhere((c) => c.peerUuid == uuid).peerName;
      } catch (_) {
        return "Unknown";
      }
    }
  }

  /// Returns true if the peer is currently connected.
  bool isPeerConnected(String peerUuid) {
    try {
      final device = discoveredDevices.firstWhere((d) => d.uuid == peerUuid);
      return device.state == SessionState.connected;
    } catch (_) {
      return false;
    }
  }

  int? getBatteryForPeer(String peerUuid) {
    try {
      final device = discoveredDevices.firstWhere((d) => d.uuid == peerUuid);
      return device.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  double getRssiForPeer(String peerUuid) {
    try {
      final device = discoveredDevices.firstWhere((d) => d.uuid == peerUuid);
      return device.rssi;
    } catch (_) {
      return -100.0;
    }
  }

  Future<void> toggleFavorite(String peerUuid) async {
    final chat = await dbHelper.getChatByPeerUuid(peerUuid);
    if (chat != null) {
      final updatedChat = chat.copyWith(isFavorite: !chat.isFavorite);
      await dbHelper.insertChat(updatedChat);
      await loadChats();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rescanTimer?.cancel();
    _discoveredSubscription?.cancel();
    _connectedSubscription?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _qualitySubscription?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }
}
