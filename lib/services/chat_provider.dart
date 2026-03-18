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
import 'reconnection_manager.dart';
import 'connectivity_state_monitor.dart';
import 'message_queue_manager.dart';
import 'reputation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'notification_service.dart';
import '../utils/connectivity_logger.dart';

class ChatProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService discoveryService;
  final MessagingService messagingService;
  final ReconnectionManager reconnectionManager;
  final ConnectivityStateMonitor connectivityStateMonitor;
  final MessageQueueManager messageQueueManager;
  final ReputationService reputationService;
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
  StreamSubscription? _stateMonitorSubscription;
  
  final _messageUpdatedController = StreamController<String?>.broadcast();
  Stream<String?> get messageUpdatedStream => _messageUpdatedController.stream;

  // Local state for typing indicators: peerUuid -> isTyping
  final Map<String, bool> _typingPeers = {};
  Map<String, bool> get typingPeers => _typingPeers;

  int _reachablePeersCount = 0;
  int get reachablePeersCount => _reachablePeersCount;
  
  int _totalNodesInMesh = 1;
  int get totalNodesInMesh => _totalNodesInMesh;

  // PTT / Audio
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool get isRecording => _isRecording;
  String? _recordingPath;

  void _updateMeshStats() {
    final Set<String> allUuids = {};
    final connected = discoveryService.getConnectedDevices();
    for (var d in connected) {
      if (d.uuid != null) allUuids.add(d.uuid!);
    }
    for (var neighbors in messagingService.meshTopology.values) {
      allUuids.addAll(neighbors);
    }
    _reachablePeersCount = allUuids.length;
    _totalNodesInMesh = connected.length + 1;
  }

  final Map<String, DateTime> _proximityAlertsSent = {};

  Timer? _rescanTimer;
  static const Duration _rescanInterval = Duration(seconds: 60);
  
  Timer? _batteryTimer;
  static const Duration _batteryInterval = Duration(seconds: 45);

  Timer? _discoveryThrottleTimer;
  Timer? _typingThrottleTimer;

  ChatProvider({
    required this.discoveryService,
    required this.messagingService,
    required this.reconnectionManager,
    required this.connectivityStateMonitor,
    required this.messageQueueManager,
    required this.reputationService,
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
      if (_discoveryThrottleTimer?.isActive ?? false) return;
      
      _discoveryThrottleTimer = Timer(const Duration(milliseconds: 500), () async {
        // Safety Filter: Ensure absolute uniqueness by UUID/DeviceId and exclude self
        final myUuid = currentUser?.uuid;
        final uniqueDevicesMap = <String, Device>{};
        
        for (var d in devices) {
          final id = d.uuid ?? d.deviceId;
          if (id == myUuid || id == 'me' || id.isEmpty) continue;
          
          // If we already have this ID, decide which one to keep (prefer connected)
          if (!uniqueDevicesMap.containsKey(id) || 
              (d.state == SessionState.connected && uniqueDevicesMap[id]!.state != SessionState.connected)) {
            
            // Enrich with reputation data
            final reputationInfo = await reputationService.getReputation(id);
            if (reputationInfo != null) {
              d = d.copyWith(
                reputationScore: reputationInfo['score'] as double,
                successfulConnections: reputationInfo['success_count'] as int,
                failedConnections: reputationInfo['fail_count'] as int,
                totalConnectionTimeMinutes: reputationInfo['total_time_minutes'] as int,
              );
            }
            
            uniqueDevicesMap[id] = d;
          }
        }
        
        discoveredDevices = uniqueDevicesMap.values.toList();
        
        // Proximity Alerts for Favorites
        for (var device in discoveredDevices) {
          if (device.uuid != null && device.state == SessionState.notConnected) {
            final chat = await dbHelper.getChatByPeerUuid(device.uuid!);
            if (chat != null && chat.isFavorite) {
              final lastAlert = _proximityAlertsSent[device.uuid!];
              if (lastAlert == null || DateTime.now().difference(lastAlert).inMinutes > 5) {
                _proximityAlertsSent[device.uuid!] = DateTime.now();
                NotificationService.showProximityAlert(device.deviceName);
              }
            }
          }
        }
        _updateMeshStats();
        notifyListeners();
      });
    });

    _connectedSubscription = discoveryService.connectedDevice.listen((
      device,
    ) async {
      connectedDevice = device;
      if (device.state == SessionState.connected) {
        if (device.uuid != null) {
          reconnectionManager.onConnectionRestored(device.uuid!);
          connectivityStateMonitor.updateState(
            uuid: device.uuid!,
            deviceName: device.deviceName,
            isConnected: true,
          );

          await messagingService.saveConnectionToChat(
            device.uuid!,
            device.deviceName,
          );
          await messagingService.sendProfileImage(device.uuid!);
          await messageQueueManager.processQueueForPeer(device.uuid!);
          await messagingService.processPendingDelivery(device.uuid!);
          await _refreshKnownDevices();
          
          ConnectivityLogger.event(
            LogCategory.connection,
            'Peer connected',
            data: {'name': device.deviceName, 'uuid': device.uuid},
          );
        }
      } else if (device.state == SessionState.notConnected) {
        _batteryTimer?.cancel();
        if (device.uuid != null) {
          connectivityStateMonitor.updateState(
            uuid: device.uuid!,
            deviceName: device.deviceName,
            isConnected: false,
          );
          reconnectionManager.scheduleReconnect(device);

          ConnectivityLogger.event(
            LogCategory.connection,
            'Peer disconnected — reconnection scheduled',
            data: {'name': device.deviceName, 'uuid': device.uuid},
          );
        }
        _ensureRescanTimer();
      }
      _updateMeshStats();
      notifyListeners();
    });

    _messageSubscription = messagingService.messageUpdated.listen((peerUuid) {
      loadChats();
      loadGroups();
      _messageUpdatedController.add(peerUuid);
    });

    _typingSubscription = messagingService.typingUpdated.listen((data) {
      final String uuid = data['uuid'];
      final bool isTyping = data['isTyping'];
      _typingPeers[uuid] = isTyping;

      if (_typingThrottleTimer?.isActive ?? false) return;
      _typingThrottleTimer = Timer(const Duration(milliseconds: 300), () {
        notifyListeners();
      });
    });

    _qualitySubscription = messagingService.connectionQualityUpdated.listen((_) {
      notifyListeners();
    });

    // Subscribe to connectivity state monitor for UI updates
    _stateMonitorSubscription = connectivityStateMonitor.stateChanges.listen((_) {
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
        final connected = discoveryService.getConnectedDevices();
        if (connected.isEmpty) {
          debugPrint('[ChatProvider] Received background keep-alive poke. Refreshing radio (no active connections).');
          if (isBrowsing) await discoveryService.startBrowsing(forceRestart: true);
          if (isAdvertising) await discoveryService.startAdvertising(forceRestart: true);
        } else {
          debugPrint('[ChatProvider] Received background keep-alive poke. Actively updating ${connected.length} peers.');
          // Perform a small data exchange to keep OS sockets hot and radio active
          for (var device in connected) {
            messagingService.sendBatteryUpdate(device.deviceId);
            messagingService.sendMeshUpdate(device.deviceId);
          }
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

  Future<void> sendMessage(String receiverUuid, String content, {Duration? burnDuration}) async {
    String peerName = _resolvePeerNameByUuid(receiverUuid);
    await messagingService.sendTextMessage(receiverUuid, peerName, content, burnDuration: burnDuration);
  }

  Future<void> retryMessage(String messageId) async {
    await messagingService.resendMessage(messageId);
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

  Future<void> addMembersToGroup(String groupId, List<String> memberUuids) async {
    await messagingService.addMembersToGroup(groupId, memberUuids);
    await loadGroups();
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




  Future<void> acceptFile(String messageId) async {
    await messagingService.acceptFile(messageId);
    await loadChats();
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

  Future<void> openFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await OpenFilex.open(path);
    } else {
      debugPrint('[ChatProvider] Cannot open file: File does not exist at $path');
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

  Future<Map<String, dynamic>> getSecurityMetadata(String peerUuid) async {
    final localFingerprint = await messagingService.signalService.getLocalFingerprint();
    final remoteFingerprint = await messagingService.signalService.getRemoteFingerprint(peerUuid);
    final registrationId = messagingService.signalService.localRegistrationId;
    
    final peer = await dbHelper.getPeer(peerUuid);
    
    return {
      'localFingerprint': localFingerprint,
      'remoteFingerprint': remoteFingerprint,
      'registrationId': registrationId,
      'isVerified': peer?.isVerified ?? false,
    };
  }

  Future<void> verifyPeer(String peerUuid, bool isVerified) async {
    final peer = await dbHelper.getPeer(peerUuid);
    if (peer != null) {
      await dbHelper.insertPeer(peer.copyWith(isVerified: isVerified));
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _messageUpdatedController.close();
    WidgetsBinding.instance.removeObserver(this);
    _rescanTimer?.cancel();
    _discoveredSubscription?.cancel();
    _connectedSubscription?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _qualitySubscription?.cancel();
    _stateMonitorSubscription?.cancel();
    _batteryTimer?.cancel();
    _discoveryThrottleTimer?.cancel();
    _typingThrottleTimer?.cancel();
    super.dispose();
  }
  // --- PTT Methods ---

  Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final String fileName = 'ptt_temp_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _recordingPath = p.join(directory.path, 'PTT', fileName);
        
        final file = File(_recordingPath!);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }

        const config = RecordConfig(); 
        await _audioRecorder.start(config, path: _recordingPath!);
        _isRecording = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[PTT] Error starting recording: $e');
    }
  }

  Future<void> stopRecording(String receiverUuid, {Duration? burnDuration}) async {
    try {
      final path = await _audioRecorder.stop();
      _isRecording = false;
      notifyListeners();

      if (path != null && _recordingPath != null) {
        String peerName = _resolvePeerNameByUuid(receiverUuid);
        await messagingService.sendAudioMessage(receiverUuid, peerName, path, burnDuration: burnDuration);
      }
    } catch (e) {
      debugPrint('[PTT] Error stopping recording: $e');
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> playAudio(String filePath) async {
    try {
      if (File(filePath).existsSync()) {
        await _audioPlayer.play(DeviceFileSource(filePath));
      }
    } catch (e) {
      debugPrint('[PTT] Error playing audio: $e');
    }
  }
}
