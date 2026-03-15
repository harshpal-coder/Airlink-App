import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'discovery_service.dart';
import 'database_helper.dart';
import 'notification_service.dart';
import '../models/session_state.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/peer_model.dart';
import '../models/group_model.dart';
import '../encryption/signal_protocol_service.dart';

class MessagingService {
  final DiscoveryService discoveryService; // 
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  final SignalProtocolService _signalService = SignalProtocolService();
  final Battery _battery = Battery();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  final _messageUpdatedController = StreamController<void>.broadcast();
  Stream<void> get messageUpdated => _messageUpdatedController.stream;

  // Cache to prevent re-relaying the same message ID (prevents infinite loops in mesh)
  final Set<String> _processedMessageIds = {};
  static const int _maxCacheSize = 100;

  // Track message IDs for incoming/outgoing payloads
  final Map<int, String> _payloadToMessageId = {};

  // Track mesh topology: peerUuid -> List of its connected neighbor Uuids
  final Map<String, List<String>> _meshTopology = {};
  Map<String, List<String>> get meshTopology => _meshTopology;

  // Track incoming files: payloadId -> temporary local path
  final Map<int, String> _incomingFilePaths = {};

  // SOS Alerts stream
  final _sosAlertController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sosAlerts => _sosAlertController.stream;

  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get typingUpdated => _typingController.stream;

  final _connectionQualityController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get connectionQualityUpdated => _connectionQualityController.stream;

  StreamSubscription? _dataSubscription;

  // Heartbeat tracking: peerUuid -> missed pings count
  final Map<String, int> _heartbeatMisses = {};
  Timer? _heartbeatTimer;

  // Store-and-Forward Relay Buffer: targetUuid -> List of messages
  final Map<String, List<Map<String, dynamic>>> _relayBuffer = {};

  bool _isPluggedIn = false;

  MessagingService({required this.discoveryService}) {
    _dataSubscription = discoveryService.dataReceived.listen(
      _handleIncomingData,
    );
    discoveryService.payloadProgress.listen(_handlePayloadProgress);
    discoveryService.fileReceived.listen(_handleIncomingFile);
    _initBatteryMonitoring();
    _startHeartbeatTimer();
  }

  void _initBatteryMonitoring() {
    _battery.onBatteryStateChanged.listen((state) {
      _isPluggedIn = (state == BatteryState.charging || state == BatteryState.full);
      _broadcastBackboneStatus();
    });
  }

  Future<void> _broadcastBackboneStatus() async {
    final connected = discoveryService.getConnectedDevices();
    for (var device in connected) {
      await sendBatteryUpdate(device.deviceId);
    }
  }

  bool get isBackbone {
    // Backbone if battery > 80% OR plugged in
    return _isPluggedIn; // We'll add battery check in calculation
  }

  Future<bool> _calculateBackboneStatus() async {
    final level = await _battery.batteryLevel;
    return level > 80 || _isPluggedIn;
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkPeerHealth();
    });
  }

  void _checkPeerHealth() async {
    final connectedPeers = discoveryService.getConnectedDevices();
    for (final peer in connectedPeers) {
      if (peer.uuid == null) continue;
      
      final misses = _heartbeatMisses[peer.uuid] ?? 0;
      if (misses >= 3) {
        debugPrint('[Heartbeat] Ghost connection detected for ${peer.deviceName} (${peer.uuid}). Force disconnecting...');
        _heartbeatMisses.remove(peer.uuid);
        discoveryService.disconnect(peer);
        continue;
      }

      // Send Ping
      _heartbeatMisses[peer.uuid!] = misses + 1;
      _sendPing(peer.deviceId, peer.uuid!);
    }
  }

  Future<void> _sendPing(String deviceId, String targetUuid) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = json.encode({
        'type': 'ping',
        'timestamp': now,
        'senderUuid': (await dbHelper.getUser('me'))?.uuid ?? 'me',
      });
      await discoveryService.sendMessageToEndpoint(deviceId, payload);
    } catch (e) {
      debugPrint('[Heartbeat] Error sending ping to $targetUuid: $e');
    }
  }

  Future<void> _sendPong(String deviceId, String targetUuid, int? originalTimestamp) async {
    try {
      final payload = json.encode({
        'type': 'pong',
        'senderUuid': (await dbHelper.getUser('me'))?.uuid ?? 'me',
        'pingTimestamp': originalTimestamp,
      });
      await discoveryService.sendMessageToEndpoint(deviceId, payload);
    } catch (e) {
      debugPrint('[Heartbeat] Error sending pong to $targetUuid: $e');
    }
  }

  void _handleIncomingFile(Map<String, dynamic> data) async {
    final String senderId = data['senderId'];
    final String? filePath = data['filePath'];
    final int payloadId = data['payloadId'];

    debugPrint('File payload received from $senderId (ID: $payloadId, Path: $filePath)');
    
    if (filePath != null) {
      _incomingFilePaths[payloadId] = filePath;
      
      // Check if we already have a message record for this payloadId
      final message = await dbHelper.getMessageByPayloadId(payloadId);
      if (message != null) {
        // Use the filename from metadata (stored in content) if it's not already a path
        String fileName = p.basename(filePath);
        if (!message.content.contains(Platform.pathSeparator) && !message.content.contains('/')) {
          fileName = message.content;
        }
        
        // Move to permanent location
        final permanentPath = await _moveToPermanentLocation(filePath, fileName);
        await dbHelper.updateMessageContent(message.id, permanentPath);
        _messageUpdatedController.sink.add(null);
      }
    }
  }

  Future<String> _moveToPermanentLocation(String tempPath, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(directory.path, 'received_media'));
      if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
      
      final permanentFile = File(p.join(mediaDir.path, fileName));
      final tempFile = File(tempPath);
      
      if (await tempFile.exists()) {
        await tempFile.copy(permanentFile.path);
        debugPrint('[MessagingService] File moved to permanent location: ${permanentFile.path}');
        return permanentFile.path;
      }
    } catch (e) {
      debugPrint('[MessagingService] Error moving file: $e');
    }
    return tempPath;
  }

  void _estimateSignalQuality(String deviceId, int rtt) {
    // Map RTT to synthetic RSSI
    // Very fast (<100ms): Excellent (-40 to -50)
    // Fast (100-300ms): Good (-50 to -60)
    // Medium (300-800ms): Fair (-60 to -75)
    // Slow (>800ms): Weak (-75 to -90)
    
    double estimatedRssi;
    if (rtt < 100) {
      estimatedRssi = -45.0;
    } else if (rtt < 300) {
      estimatedRssi = -55.0;
    } else if (rtt < 800) {
      estimatedRssi = -70.0;
    } else {
      estimatedRssi = -85.0;
    }
    
    discoveryService.updateDeviceRssi(deviceId, estimatedRssi);
    _connectionQualityController.add({deviceId: estimatedRssi});
    debugPrint('[SignalHealth] Estimated RSSI for $deviceId: $estimatedRssi dBm (RTT: ${rtt}ms)');
  }

  void _handlePayloadProgress(PayloadProgress update) async {
    String? messageId = _payloadToMessageId[update.payloadId];
    
    if (messageId != null) {
      await dbHelper.updateMessageProgress(messageId, update.progress);
      
      if (update.status == PayloadStatus.SUCCESS) {
        // Update path if we have it
        if (_incomingFilePaths.containsKey(update.payloadId)) {
          final tempPath = _incomingFilePaths[update.payloadId]!;
          final message = await dbHelper.getMessageById(messageId);
          String fileName = p.basename(tempPath);
          if (message != null && !message.content.contains(Platform.pathSeparator) && !message.content.contains('/')) {
            fileName = message.content;
          }
          
          final permanentPath = await _moveToPermanentLocation(tempPath, fileName);
          await dbHelper.updateMessageContent(messageId, permanentPath);
          _incomingFilePaths.remove(update.payloadId);
        }
      } else if (update.status == PayloadStatus.FAILURE) {
        // Handled below mainly
      }
      _messageUpdatedController.sink.add(null);
      return;
    }

    final message = await dbHelper.getMessageByPayloadId(update.payloadId);
    if (message != null) {
      await dbHelper.updateMessageProgress(message.id, update.progress);
      
      if (update.status == PayloadStatus.SUCCESS) {
        String finalContent = message.content;
        if (_incomingFilePaths.containsKey(update.payloadId)) {
          final tempPath = _incomingFilePaths[update.payloadId]!;
          String fileName = p.basename(tempPath);
          if (!message.content.contains(Platform.pathSeparator) && !message.content.contains('/')) {
            fileName = message.content;
          }
          
          final permanentPath = await _moveToPermanentLocation(tempPath, fileName);
          finalContent = permanentPath;
          _incomingFilePaths.remove(update.payloadId);
        }

        await dbHelper.insertMessage(message.copyWith(
          status: MessageStatus.delivered,
          progress: 1.0,
          content: finalContent,
        ));
      } else if (update.status == PayloadStatus.FAILURE) {
        await dbHelper.insertMessage(message.copyWith(
          status: MessageStatus.failed,
        ));
      }
      _messageUpdatedController.sink.add(null);
    }
  }

  void _handleIncomingData(Map<String, dynamic> data) async {
    final String senderId = data['senderId'];
    final String rawPayload = data['payload'];
    final int? incomingPayloadId = data['payloadId'] as int?;

    debugPrint('[MessagingService] Received raw payload from $senderId (ID: $incomingPayloadId)');

    try {
      final Map<String, dynamic> payload = json.decode(rawPayload);
      final String type = payload['type'] ?? 'text';
      debugPrint('[MessagingService] Processing payload type: $type from $senderId');
      final String? messageId = payload['messageId'] as String?;
      final String? targetUuid = payload['targetUuid'] as String?;
      final String? originalSenderUuid = payload['senderUuid'] as String?;
      final String? originalSenderName = payload['senderName'] as String?;

      if (type == 'profile_sync') {
        final profileBase64 = payload['content'] as String?;
        final extension = payload['extension'] as String? ?? '.jpg';
        if (originalSenderUuid != null && profileBase64 != null) {
          final directory = await getApplicationDocumentsDirectory();
          final filePath = p.join(directory.path, 'profile_$originalSenderUuid$extension');
          await File(filePath).writeAsBytes(base64Decode(profileBase64));
          await _updateChatRecord(originalSenderUuid, null, null, 0, peerName: originalSenderName, peerProfileImage: filePath);
          debugPrint('[MessagingService] Synced profile image for $originalSenderUuid');
          _messageUpdatedController.add(null);
          return;
        }
      }

      final User? me = await dbHelper.getUser('me');
      final String myUuid = me?.uuid ?? 'me';

      // Handle battery update
      if (type == 'battery_update') {
        final int? level = payload['level'] as int?;
        final bool isBackbone = payload['isBackbone'] == true;
        final bool isPluggedIn = payload['isPluggedIn'] == true;
        if (level != null) {
          discoveryService.updateDeviceBattery(senderId, level, isBackbone: isBackbone, isPluggedIn: isPluggedIn);
        }
        return;
      }

      // Handle mesh topology update
      if (type == 'mesh_update') {
        final List<dynamic>? neighbors = payload['neighbors'] as List<dynamic>?;
        if (originalSenderUuid != null && neighbors != null) {
          _meshTopology[originalSenderUuid] = neighbors.cast<String>();
          
          // EXTEND DISCOVERY: Add these neighbors as mesh devices in DiscoveryService
          for (var neighborUuid in neighbors) {
            if (neighborUuid == myUuid || neighborUuid == 'me') continue;
            // We only know UID, but we can try to find their name if they were 
            // previously seen or just use "Mesh Peer"
            final peer = await dbHelper.getPeer(neighborUuid);
            final displayName = peer?.deviceName ?? 'Mesh Peer';
            discoveryService.addMeshDevice(neighborUuid, displayName, senderId);
          }
          
          _messageUpdatedController.add(null);
        }
        return;
      }

      // Handle Heartbeats
      if (type == 'ping') {
        if (originalSenderUuid != null) {
          final int? pingTimestamp = payload['timestamp'] as int?;
          _sendPong(senderId, originalSenderUuid, pingTimestamp);
        }
        return;
      }
      if (type == 'pong') {
        if (originalSenderUuid != null) {
          _heartbeatMisses[originalSenderUuid] = 0; // Reset miss count
          
          // Calculate RTT for signal health estimation
          final int? pingTimestamp = payload['pingTimestamp'] as int?;
          if (pingTimestamp != null) {
            final rtt = DateTime.now().millisecondsSinceEpoch - pingTimestamp;
            _estimateSignalQuality(senderId, rtt);
          }
        }
        return;
      }

      // 2. Check deduplication
      if (messageId != null) {
        if (_processedMessageIds.contains(messageId)) return;
        _processedMessageIds.add(messageId);
        if (_processedMessageIds.length > _maxCacheSize) {
          _processedMessageIds.remove(_processedMessageIds.first);
        }
      }

      // 3. Update Peer
      if (originalSenderUuid != null && originalSenderName != null) {
        await dbHelper.insertPeer(Peer(
          uuid: originalSenderUuid,
          deviceName: originalSenderName,
          lastSeen: DateTime.now(),
          connectionType: 'nearby', 
        ));
      }

      // 4. Relay if not for me (Store-and-Forward)
      if (targetUuid != null && targetUuid != myUuid) {
        debugPrint('[StoreAndForward] Storing relay message for $targetUuid');
        _addToRelayBuffer(targetUuid, payload);
        _relayMessage(targetUuid, payload, excludeEndpointId: senderId);
        return;
      }

      // 5. Encrypt if needed
      String? decryptedContent;
      if (payload['encrypted'] == true && payload['encryptedPayload'] != null && originalSenderUuid != null) {
        decryptedContent = await _signalService.decryptMessage(
          originalSenderUuid, 
          payload['encryptedPayload']
        );
      }

      if (type == 'text') {
        final String content = decryptedContent ?? (payload['content'] as String? ?? '');
        await _processIncomingText(
          senderId,
          content,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
        );
      } else if (type == 'file_metadata') {
        final int? filePayloadId = payload['filePayloadId'] as int?;
        final String? fileName = payload['fileName'] as String?;
        final String? subType = payload['subType'] as String?; // 'image', 'pdf', 'audio'
        
        if (filePayloadId != null) {
          await _processIncomingFileMetadata(
            senderId,
            filePayloadId,
            fileName ?? 'received_file',
            subType ?? 'file',
            senderName: originalSenderName,
            senderUuid: originalSenderUuid,
            incomingPayloadId: incomingPayloadId,
          );
        }
      } else if (type == 'typing') {
        final bool isTyping = payload['isTyping'] == true;
        // Broadcast this locally to UI
        if (originalSenderUuid != null) {
          _typingController.add({'uuid': originalSenderUuid, 'isTyping': isTyping});
        }
      } else if (type == 'mesh_shout') {
        final String content = payload['content'] ?? '';
        await _processIncomingText(
          senderId,
          "[SHOUT] $content",
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
        );
      } else if (type == 'image') {
        // Fallback for older versions using base64
        final String base64Content = payload['content'] as String;
        final String fileName = payload['fileName'] ?? 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _processIncomingImage(
          senderId,
          base64Content,
          fileName,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
        );
      } else if (type == 'pdf') {
        // Fallback for older versions using base64
        final String base64Content = payload['content'] as String;
        final String fileName = payload['fileName'] ?? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await _processIncomingPdf(
          senderId,
          base64Content,
          fileName,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
        );
      } else if (type == 'sos') {
        final String content = payload['content'] ?? 'Emergency SOS Alert!';
        _sosAlertController.add({
          'senderId': senderId,
          'senderUuid': originalSenderUuid,
          'senderName': originalSenderName,
          'content': content,
          'timestamp': DateTime.now().toIso8601String(),
        });
        
        // Relaying SOS is high priority and uses flooding
        _relayMessage(targetUuid ?? 'broadcast', payload, excludeEndpointId: senderId);
        
        NotificationService.showSOSAlert(
          originalSenderName ?? senderId,
          content,
        );
      } else if (type == 'group_invite') {
        final String? groupId = payload['groupId'];
        final String? groupName = payload['groupName'];
        final List<dynamic>? memberUuids = payload['members'];
        if (groupId != null && groupName != null && memberUuids != null) {
          final group = Group(
            id: groupId,
            name: groupName,
            createdBy: originalSenderUuid ?? senderId,
            createdAt: DateTime.now(),
            members: memberUuids.cast<String>(),
            lastMessage: 'You were invited to this group',
            lastMessageTime: DateTime.now(),
          );
          await dbHelper.insertGroup(group);
          _messageUpdatedController.add(null);
          NotificationService.showIncomingMessage(
            'New Group: $groupName',
            'You were added to this group by ${originalSenderName ?? senderId}',
            senderUuid: groupId,
            senderName: groupName,
          );
        }
      } else if (type == 'group_message') {
        final String? groupId = payload['groupId'];
        final String content = decryptedContent ?? (payload['content'] as String? ?? '');
        if (groupId != null) {
          debugPrint('[MessagingService] Processing group message for group: $groupId');
          await _processIncomingGroupMessage(
            senderId,
            groupId,
            content,
            senderName: originalSenderName,
            senderUuid: originalSenderUuid,
            incomingPayloadId: incomingPayloadId,
          );
          
          // Re-relay for mesh propagation (flooding)
          _relayMessage('broadcast', payload, excludeEndpointId: senderId);
        }
      } else if (type == 'profile_sync') {
        final String base64Content = payload['content'] as String;
        final String extension = payload['extension'] ?? '.jpg';
        await _processIncomingProfileImage(
          senderId,
          base64Content,
          extension,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
        );
      }
    } catch (e) {
      debugPrint('[MessagingService] Error handling data: $e');
      await _processIncomingText(senderId, rawPayload);
    }
  }

  Future<void> sendBatteryUpdate(String endpointId) async {
    try {
      final int level = await _battery.batteryLevel;
      final bool status = await _calculateBackboneStatus();
      final String payload = json.encode({
        'type': 'battery_update',
        'level': level,
        'isBackbone': status,
        'isPluggedIn': _isPluggedIn,
      });
      await discoveryService.sendMessageToEndpoint(endpointId, payload);
    } catch (e) {
      debugPrint('[MessagingService] Error sending battery update: $e');
    }
  }

  Future<void> sendMeshUpdate(String endpointId) async {
    try {
      final User? me = await dbHelper.getUser('me');
      final connected = discoveryService.getConnectedDevices();
      final neighborUuids = connected
          .map((d) => d.uuid)
          .whereType<String>()
          .toList();

      final String payload = json.encode({
        'type': 'mesh_update',
        'neighbors': neighborUuids,
        'senderUuid': me?.uuid ?? 'me',
      });
      await discoveryService.sendMessageToEndpoint(endpointId, payload);
    } catch (e) {
      debugPrint('[MessagingService] Error sending mesh update: $e');
    }
  }

  Future<void> _relayMessage(String targetUuid, Map<String, dynamic> payload, {String? excludeEndpointId}) async {
    int hops = (payload['hopCount'] ?? 0) + 1;
    payload['hopCount'] = hops;
    if (hops > 12) return;

    final String updatedPayload = json.encode(payload);
    
    // If it's a broadcast to everyone (like a group message), skip the direct path logic
    if (targetUuid == 'broadcast') {
      debugPrint('[SmartRelay] Broadcasting payload via flooding (hops: $hops)');
    } else {
      // 1. Direct connection check
      final directDevice = discoveryService.getDeviceByUuid(targetUuid);
      if (directDevice != null && directDevice.state == SessionState.connected) {
        if (directDevice.deviceId == excludeEndpointId) return;
        debugPrint('[SmartRelay] Direct path found for $targetUuid via ${directDevice.deviceId}');
        await discoveryService.sendMessageToEndpoint(directDevice.deviceId, updatedPayload);
        return;
      }

      // 2. Smart Path check (is target a neighbor of any of my neighbors?)
      String? viaEndpoint;
      int highestBattery = -1;

      for (var entry in _meshTopology.entries) {
        if (entry.value.contains(targetUuid)) {
          final neighborDevice = discoveryService.getDeviceByUuid(entry.key);
          if (neighborDevice != null && neighborDevice.state == SessionState.connected) {
            // Prioritize neighbors with better battery
            int battery = neighborDevice.batteryLevel;
            if (battery > highestBattery) {
              highestBattery = battery;
              viaEndpoint = neighborDevice.deviceId;
            }
          }
        }
      }

      if (viaEndpoint != null && highestBattery > 15) {
        debugPrint('[SmartRelay] Smart path found for $targetUuid via neighbor $viaEndpoint (Battery: $highestBattery%)');
        await discoveryService.sendMessageToEndpoint(viaEndpoint, updatedPayload);
        return;
      }

      debugPrint('[SmartRelay] No smart path for $targetUuid. Flooding to all neighbors.');
    }

    // 3. Fallback: Flooding
    final neighbors = discoveryService.getConnectedDevices();
    
    // Sort neighbors: Backbones first, then highest battery
    neighbors.sort((a, b) {
      if (a.isBackbone && !b.isBackbone) return -1;
      if (!a.isBackbone && b.isBackbone) return 1;
      return b.batteryLevel.compareTo(a.batteryLevel);
    });

    for (var peer in neighbors) {
      if (peer.deviceId == excludeEndpointId) continue;
      
      // Signal Check: Don't relay heavily through extremely weak links
      if (peer.rssi < -85 && !peer.isBackbone) { // Allow weak links if it's a backbone
        debugPrint('[SmartRelay] Skipping weak link ${peer.deviceName} (${peer.rssi} dBm)');
        continue;
      }

      // Battery Check: Don't relay through low battery non-backbone nodes if hops > 3
      if (peer.batteryLevel < 15 && !peer.isBackbone && hops > 3) {
        debugPrint('[SmartRelay] Skipping low battery node ${peer.deviceName} (${peer.batteryLevel}%)');
        continue;
      }

      await discoveryService.sendMessageToEndpoint(peer.deviceId, updatedPayload);
    }
  }

  Future<void> broadcastSOS({String content = "I need help! Immediate assistance required."}) async {
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();
    
    final payloadObj = {
      'type': 'sos',
      'content': content,
      'senderName': me?.deviceName ?? 'Unknown User',
      'senderUuid': me?.uuid ?? '',
      'messageId': messageId,
      'hopCount': 0,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final String payloadJson = json.encode(payloadObj);
    
    // Save locally as SOS message
    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: 'broadcast',
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.sos,
      status: MessageStatus.sent,
    );
    await dbHelper.insertMessage(message);
    _messageUpdatedController.sink.add(null);

    // Flood to all neighbors
    final neighbors = discoveryService.getConnectedDevices();
    for (var peer in neighbors) {
      await discoveryService.sendMessageToEndpoint(peer.deviceId, payloadJson);
    }
    
    debugPrint('[SOS] SOS Broadcast sent to ${neighbors.length} neighbors');
  }

  Future<void> _processIncomingFileMetadata(String senderEndpointId, int filePayloadId, String fileName, String type, {String? senderName, String? senderUuid, int? incomingPayloadId}) async {
    // This is called when we receive the metadata BYTES for a FILE payload
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    
    String finalContent = fileName;
    if (_incomingFilePaths.containsKey(filePayloadId)) {
      final tempPath = _incomingFilePaths[filePayloadId]!;
      finalContent = await _moveToPermanentLocation(tempPath, fileName);
      _incomingFilePaths.remove(filePayloadId);
    }

    final msgId = const Uuid().v4();
    final message = Message(
      id: msgId,
      senderUuid: senderUuid ?? senderEndpointId,
      receiverUuid: myUuid,
      content: finalContent,
      timestamp: DateTime.now(),
      type: type == 'image' ? MessageType.image : (type == 'pdf' ? MessageType.pdf : (type == 'audio' ? MessageType.audio : MessageType.file)),
      status: MessageStatus.delivered,
      payloadId: filePayloadId,
      progress: 0.0,
      isFileAccepted: false,
    );
    
    await dbHelper.insertMessage(message);
    String displayMsg = 'File: $fileName';
    if (type == 'image') displayMsg = '📷 Photo';
    if (type == 'pdf') displayMsg = '📄 PDF Document';
    if (type == 'audio') displayMsg = '🎙️ Voice Note';

    int unreadIncrement = (NotificationService.activeChatUuid == (senderUuid ?? senderEndpointId)) ? 0 : 1;
    await _updateChatRecord(senderUuid ?? senderEndpointId, displayMsg, message.timestamp, unreadIncrement, peerName: senderName);
    _messageUpdatedController.sink.add(null);
    
    NotificationService.showIncomingMessage(
      'Message from ${senderName ?? senderEndpointId}',
      displayMsg,
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: senderName,
    );
  }

  Future<void> _processIncomingText(String senderEndpointId, String text, {String? senderName, String? senderUuid, int? incomingPayloadId}) async {
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final msgId = const Uuid().v4();
    final message = Message(
      id: msgId,
      senderUuid: senderUuid ?? senderEndpointId,
      receiverUuid: myUuid,
      content: text,
      timestamp: DateTime.now(),
      type: MessageType.text,
      status: MessageStatus.delivered,
      payloadId: incomingPayloadId,
      progress: 1.0,
    );
    if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
    await dbHelper.insertMessage(message);
    int unreadIncrement = (NotificationService.activeChatUuid == (senderUuid ?? senderEndpointId)) ? 0 : 1;
    await _updateChatRecord(senderUuid ?? senderEndpointId, text, message.timestamp, unreadIncrement, peerName: senderName);
    _messageUpdatedController.sink.add(null);
    final chat = await dbHelper.getChatByPeerUuid(senderUuid ?? senderEndpointId);
    NotificationService.showIncomingMessage(
      'Message from ${chat?.peerName ?? senderName ?? senderEndpointId}',
      text,
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: chat?.peerName ?? senderName,
      senderProfileImage: chat?.peerProfileImage,
    );
  }

  Future<void> _processIncomingImage(String senderEndpointId, String base64Content, String fileName, {String? senderName, String? senderUuid, int? incomingPayloadId}) async {
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final bytes = base64Decode(base64Content);
    final directory = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(directory.path, 'received_media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    final file = File(p.join(mediaDir.path, fileName));
    await file.writeAsBytes(bytes);

    final msgId = const Uuid().v4();
    final message = Message(
      id: msgId,
      senderUuid: senderUuid ?? senderEndpointId,
      receiverUuid: myUuid,
      content: file.path,
      timestamp: DateTime.now(),
      type: MessageType.image,
      status: MessageStatus.delivered,
      payloadId: incomingPayloadId,
      progress: 1.0,
      isFileAccepted: false,
    );
    if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
    await dbHelper.insertMessage(message);
    int unreadIncrement = (NotificationService.activeChatUuid == (senderUuid ?? senderEndpointId)) ? 0 : 1;
    await _updateChatRecord(senderUuid ?? senderEndpointId, '📷 Photo', message.timestamp, unreadIncrement, peerName: senderName);
    _messageUpdatedController.sink.add(null);
    final chat = await dbHelper.getChatByPeerUuid(senderUuid ?? senderEndpointId);
    NotificationService.showIncomingMessage(
      'Message from ${chat?.peerName ?? senderName ?? senderEndpointId}',
      '📷 Photo',
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: chat?.peerName ?? senderName,
      senderProfileImage: chat?.peerProfileImage,
    );
  }

  Future<void> _processIncomingPdf(String senderEndpointId, String base64Content, String fileName, {String? senderName, String? senderUuid, int? incomingPayloadId}) async {
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final bytes = base64Decode(base64Content);
    final directory = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(directory.path, 'received_media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    final file = File(p.join(mediaDir.path, fileName));
    await file.writeAsBytes(bytes);

    final msgId = const Uuid().v4();
    final message = Message(
      id: msgId,
      senderUuid: senderUuid ?? senderEndpointId,
      receiverUuid: myUuid,
      content: file.path,
      timestamp: DateTime.now(),
      type: MessageType.pdf,
      status: MessageStatus.delivered,
      payloadId: incomingPayloadId,
      progress: 1.0,
      isFileAccepted: false,
    );
    if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
    await dbHelper.insertMessage(message);
    int unreadIncrement = (NotificationService.activeChatUuid == (senderUuid ?? senderEndpointId)) ? 0 : 1;
    await _updateChatRecord(senderUuid ?? senderEndpointId, '📄 PDF Document', message.timestamp, unreadIncrement, peerName: senderName);
    _messageUpdatedController.sink.add(null);
    final chat = await dbHelper.getChatByPeerUuid(senderUuid ?? senderEndpointId);
    NotificationService.showIncomingMessage(
      'Message from ${chat?.peerName ?? senderName ?? senderEndpointId}',
      '📄 PDF Document',
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: chat?.peerName ?? senderName,
      senderProfileImage: chat?.peerProfileImage,
    );
  }

  Future<void> acceptFile(String messageId) async {
    final message = await dbHelper.getMessageById(messageId);
    if (message == null) return;
    if (message.type == MessageType.image) {
      try {
        await Gal.putImage(message.content);
      } catch (e) {
        debugPrint('Error saving to gallery: $e');
      }
    }
    await dbHelper.insertMessage(message.copyWith(isFileAccepted: true));
    _messageUpdatedController.sink.add(null);
  }

  Future<void> _processIncomingProfileImage(String senderEndpointId, String base64Content, String extension, {String? senderName, String? senderUuid}) async {
    if (senderUuid == null) return;
    final bytes = base64Decode(base64Content);
    final directory = await getApplicationDocumentsDirectory();
    final profileDir = Directory(p.join(directory.path, 'peer_profiles'));
    if (!await profileDir.exists()) await profileDir.create(recursive: true);
    final file = File(p.join(profileDir.path, 'profile_$senderUuid$extension'));
    await file.writeAsBytes(bytes);

    await _updateChatRecord(senderUuid, null, null, 0, peerName: senderName, peerProfileImage: file.path);
    _messageUpdatedController.sink.add(null);
  }

  Future<void> sendTextMessage(String receiverUuid, String receiverName, String content) async {
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();
    String? encryptedPayload;
    bool isEncrypted = false;
    try {
      encryptedPayload = await _signalService.encryptMessage(receiverUuid, content);
      if (encryptedPayload != content && encryptedPayload != "[Decryption Failed]") isEncrypted = true;
    } catch (_) {}

    final String payloadObj = json.encode({
      'type': 'text',
      'content': isEncrypted ? null : content,
      'encrypted': isEncrypted,
      'encryptedPayload': isEncrypted ? encryptedPayload : null,
      'senderName': me?.deviceName ?? 'Unknown User',
      'senderUuid': me?.uuid ?? '',
      'targetUuid': receiverUuid,
      'messageId': messageId,
      'hopCount': 0,
    });

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.text,
      status: MessageStatus.sending,
      hopCount: 0,
      encryptedPayload: isEncrypted ? encryptedPayload : null,
    );
    
    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, content, message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(null);

    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        final payloadId = await discoveryService.sendMessageToEndpoint(device.deviceId, payloadObj);
        if (payloadId != null) {
          _payloadToMessageId[payloadId] = messageId;
          await dbHelper.updateMessagePayloadId(messageId, payloadId);
        }
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: payloadId));
      } else {
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.queued));
        _relayMessage(receiverUuid, json.decode(payloadObj));
      }
    } catch (e) {
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
    }
    _messageUpdatedController.sink.add(null);
  }

  Future<void> sendImageMessage(String receiverUuid, String receiverName, String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return;
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: imagePath,
      timestamp: DateTime.now(),
      type: MessageType.image,
      status: MessageStatus.sending,
    );
    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, '📷 Photo', message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(null);

    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        // 1. Send File Payload
        final filePayloadId = await discoveryService.sendFileToEndpoint(device.deviceId, imagePath);
        
        if (filePayloadId != null) {
          // 2. Send Metadata Bytes
          final String metadata = json.encode({
            'type': 'file_metadata',
            'subType': 'image',
            'fileName': p.basename(imagePath),
            'filePayloadId': filePayloadId,
            'senderName': me?.deviceName ?? 'Unknown User',
            'senderUuid': me?.uuid ?? '',
            'targetUuid': receiverUuid,
            'messageId': messageId,
          });
          
          await discoveryService.sendMessageToEndpoint(device.deviceId, metadata);
          await dbHelper.updateMessagePayloadId(messageId, filePayloadId);
          await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: filePayloadId));
        }
      } else {
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.queued));
      }
    } catch (e) {
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
    }
    _messageUpdatedController.sink.add(null);
  }

  Future<void> sendPdfMessage(String receiverUuid, String receiverName, String pdfPath) async {
    final file = File(pdfPath);
    if (!await file.exists()) return;
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: pdfPath,
      timestamp: DateTime.now(),
      type: MessageType.pdf,
      status: MessageStatus.sending,
    );
    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, '📄 PDF Document', message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(null);

    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        final filePayloadId = await discoveryService.sendFileToEndpoint(device.deviceId, pdfPath);
        
        if (filePayloadId != null) {
          final String metadata = json.encode({
            'type': 'file_metadata',
            'subType': 'pdf',
            'fileName': p.basename(pdfPath),
            'filePayloadId': filePayloadId,
            'senderName': me?.deviceName ?? 'Unknown User',
            'senderUuid': me?.uuid ?? '',
            'targetUuid': receiverUuid,
            'messageId': messageId,
          });
          
          await discoveryService.sendMessageToEndpoint(device.deviceId, metadata);
          await dbHelper.updateMessagePayloadId(messageId, filePayloadId);
          await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: filePayloadId));
        }
      } else {
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.queued));
      }
    } catch (e) {
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
    }
    _messageUpdatedController.sink.add(null);
  }

  // --- Voice Notes Implementation ---

  Future<void> startAudioRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final String path = p.join(directory.path, 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await _recorder.start(const RecordConfig(), path: path);
        debugPrint('[VoiceNote] Recording started: $path');
      }
    } catch (e) {
      debugPrint('[VoiceNote] Error starting recording: $e');
    }
  }

  Future<String?> stopAudioRecording() async {
    try {
      final String? path = await _recorder.stop();
      debugPrint('[VoiceNote] Recording stopped: $path');
      return path;
    } catch (e) {
      debugPrint('[VoiceNote] Error stopping recording: $e');
      return null;
    }
  }

  Future<void> sendVoiceNote(String receiverUuid, String receiverName, String audioPath) async {
    final file = File(audioPath);
    if (!await file.exists()) return;
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: audioPath,
      timestamp: DateTime.now(),
      type: MessageType.audio,
      status: MessageStatus.sending,
    );
    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, '🎙️ Voice Note', message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(null);

    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        final filePayloadId = await discoveryService.sendFileToEndpoint(device.deviceId, audioPath);
        
        if (filePayloadId != null) {
          final String metadata = json.encode({
            'type': 'file_metadata',
            'subType': 'audio',
            'fileName': p.basename(audioPath),
            'filePayloadId': filePayloadId,
            'senderName': me?.deviceName ?? 'Unknown User',
            'senderUuid': me?.uuid ?? '',
            'targetUuid': receiverUuid,
            'messageId': messageId,
          });
          
          await discoveryService.sendMessageToEndpoint(device.deviceId, metadata);
          await dbHelper.updateMessagePayloadId(messageId, filePayloadId);
          await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: filePayloadId));
        }
      } else {
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.queued));
        _relayMessage(receiverUuid, {
          'type': 'audio_metadata_relay', // Basic relay for metadata
          ...json.decode(json.encode(message.toMap())),
        });
      }
    } catch (e) {
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
    }
    _messageUpdatedController.sink.add(null);
  }

  Future<void> playAudioMsg(String path) async {
    try {
      await _player.play(DeviceFileSource(path));
    } catch (e) {
      debugPrint('[VoiceNote] Error playing audio: $e');
    }
  }

  Future<void> pauseAudio() async {
    await _player.pause();
  }

  Future<void> stopAudio() async {
    await _player.stop();
  }


  Future<void> sendTypingStatus(String receiverUuid, bool isTyping) async {
    final User? me = await dbHelper.getUser('me');
    final payload = json.encode({
      'type': 'typing',
      'isTyping': isTyping,
      'senderUuid': me?.uuid ?? '',
      'targetUuid': receiverUuid,
    });
    
    final device = discoveryService.getDeviceByUuid(receiverUuid);
    if (device != null && device.state == SessionState.connected) {
      await discoveryService.sendMessageToEndpoint(device.deviceId, payload);
    }
  }

  Future<void> sendBroadcast(String content) async {
    final User? me = await dbHelper.getUser('me');
    final payload = json.encode({
      'type': 'mesh_shout',
      'content': content,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': me?.uuid ?? '',
      'messageId': const Uuid().v4(),
      'hopCount': 0,
    });
    
    final neighbors = discoveryService.getConnectedDevices();
    for (var peer in neighbors) {
      await discoveryService.sendMessageToEndpoint(peer.deviceId, payload);
    }
  }

  Future<void> sendProfileImage(String receiverUuid) async {
    final User? me = await dbHelper.getUser('me');
    if (me?.profileImage == null) return;
    final file = File(me!.profileImage!);
    if (!await file.exists()) return;
    final String payloadObj = json.encode({
      'type': 'profile_sync',
      'extension': p.extension(file.path),
      'content': base64Encode(await file.readAsBytes()),
      'senderName': me.deviceName,
      'senderUuid': me.uuid,
      'targetUuid': receiverUuid,
      'messageId': const Uuid().v4(),
      'hopCount': 0,
    });
    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        await discoveryService.sendMessageToEndpoint(device.deviceId, payloadObj);
      }
    } catch (_) {}
  }

  Future<void> resendMessage(String messageId) async {
    final message = await dbHelper.getMessageById(messageId);
    if (message == null) return;

    final device = discoveryService.getDeviceByUuid(message.receiverUuid);
    if (device == null || device.state != SessionState.connected) {
      debugPrint('[MessagingService] Cannot resend $messageId: Receiver not connected');
      return;
    }

    final User? me = await dbHelper.getUser('me');
    try {
      if (message.type == MessageType.text) {
        bool isEncrypted = message.encryptedPayload != null;
        final String payloadObj = json.encode({
          'type': 'text',
          'content': isEncrypted ? null : message.content,
          'encrypted': isEncrypted,
          'encryptedPayload': message.encryptedPayload,
          'senderName': me?.deviceName ?? 'Unknown User',
          'senderUuid': me?.uuid ?? '',
          'targetUuid': message.receiverUuid,
          'messageId': message.id,
          'hopCount': 0,
        });

        final payloadId = await discoveryService.sendMessageToEndpoint(device.deviceId, payloadObj);
        if (payloadId != null) {
          _payloadToMessageId[payloadId] = message.id;
          await dbHelper.updateMessagePayloadId(message.id, payloadId);
        }
        await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: payloadId));
      } else {
        // File, Image, PDF, Audio
        final file = File(message.content);
        if (!await file.exists()) {
          debugPrint('[MessagingService] Cannot resend $messageId: File not found');
          await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
          return;
        }

        final filePayloadId = await discoveryService.sendFileToEndpoint(device.deviceId, message.content);
        if (filePayloadId != null) {
          String subType = 'file';
          if (message.type == MessageType.image) subType = 'image';
          if (message.type == MessageType.pdf) subType = 'pdf';
          if (message.type == MessageType.audio) subType = 'audio';

          final String metadata = json.encode({
            'type': 'file_metadata',
            'subType': subType,
            'fileName': p.basename(message.content),
            'filePayloadId': filePayloadId,
            'senderName': me?.deviceName ?? 'Unknown User',
            'senderUuid': me?.uuid ?? '',
            'targetUuid': message.receiverUuid,
            'messageId': message.id,
          });

          await discoveryService.sendMessageToEndpoint(device.deviceId, metadata);
          await dbHelper.updateMessagePayloadId(message.id, filePayloadId);
          await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: filePayloadId));
        }
      }
    } catch (e) {
      debugPrint('[MessagingService] Error resending message $messageId: $e');
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.failed));
    }
    _messageUpdatedController.sink.add(null);
  }

  Future<void> processPendingDelivery(String peerUuid) async {
    // 1. Send direct queued messages
    final queuedMessages = await dbHelper.getQueuedMessages(peerUuid);
    if (queuedMessages.isNotEmpty) {
      debugPrint('[MessagingService] Processing ${queuedMessages.length} queued messages for $peerUuid');
      for (var message in queuedMessages) {
        await resendMessage(message.id);
      }
    }

    // 2. Elite Store-and-Forward: Hand over relay buffer to this neighbor
    _handoverRelayBuffer(peerUuid);
  }

  void _addToRelayBuffer(String targetUuid, Map<String, dynamic> payload) {
    if (!_relayBuffer.containsKey(targetUuid)) {
      _relayBuffer[targetUuid] = [];
    }
    
    // Deduplicate in buffer
    final messageId = payload['messageId'];
    if (_relayBuffer[targetUuid]!.any((m) => m['messageId'] == messageId)) return;

    _relayBuffer[targetUuid]!.add(payload);
    
    // Cap buffer size per target
    if (_relayBuffer[targetUuid]!.length > 10) {
      _relayBuffer[targetUuid]!.removeAt(0);
    }
  }

  void _handoverRelayBuffer(String peerUuid) async {
    final device = discoveryService.getDeviceByUuid(peerUuid);
    if (device == null || device.state != SessionState.connected) return;

    debugPrint('[StoreAndForward] Handing over relay buffer to ${device.deviceName}');
    
    // Hand over messages meant for this peer
    if (_relayBuffer.containsKey(peerUuid)) {
      for (var payload in _relayBuffer[peerUuid]!) {
        debugPrint('[StoreAndForward] Delivering buffered message to target $peerUuid');
        await discoveryService.sendMessageToEndpoint(device.deviceId, json.encode(payload));
      }
      _relayBuffer.remove(peerUuid);
    }

    // Hand over a subset of OTHER relay messages (Epidemic Routing)
    int handoverCount = 0;
    for (var entry in _relayBuffer.entries) {
      if (entry.key == peerUuid) continue;
      for (var payload in entry.value) {
        if (handoverCount >= 5) break; 
        debugPrint('[StoreAndForward] Opportunistic handover for ${entry.key} via $peerUuid');
        await discoveryService.sendMessageToEndpoint(device.deviceId, json.encode(payload));
        handoverCount++;
      }
    }
  }

  Future<void> _updateChatRecord(String peerUuid, String? lastMessage, DateTime? timestamp, int incrementUnread, {String? peerName, String? peerProfileImage}) async {
    final chats = await dbHelper.getChats();
    final existingIndex = chats.indexWhere((c) => c.peerUuid == peerUuid);
    String finalPeerName = peerName ?? peerUuid;
    int unreadCount = incrementUnread;
    String chatId = peerUuid;
    if (existingIndex >= 0) {
      final existingChat = chats[existingIndex];
      finalPeerName = peerName ?? existingChat.peerName;
      unreadCount = existingChat.unreadCount + incrementUnread;
      chatId = existingChat.id;
      peerProfileImage ??= existingChat.peerProfileImage;
    }
    final chat = Chat(
      id: chatId,
      peerUuid: peerUuid,
      peerName: finalPeerName,
      lastMessage: lastMessage ?? (existingIndex >= 0 ? chats[existingIndex].lastMessage : ''),
      lastMessageTime: timestamp ?? (existingIndex >= 0 ? chats[existingIndex].lastMessageTime : DateTime.now()),
      unreadCount: unreadCount,
      peerProfileImage: peerProfileImage,
    );
    await dbHelper.insertChat(chat);
  }

  Future<void> saveConnectionToChat(String peerUuid, String peerName) async {
    await _updateChatRecord(peerUuid, null, DateTime.now(), 0, peerName: peerName);
    _messageUpdatedController.sink.add(null);
  }

  // --- Group Messaging Methods ---

  Future<void> createGroup(String name, List<String> memberUuids) async {
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final String groupId = 'group_${const Uuid().v4()}';
    
    // Include self in members
    final allMembers = [...memberUuids];
    if (!allMembers.contains(myUuid)) allMembers.add(myUuid);

    final group = Group(
      id: groupId,
      name: name,
      createdBy: myUuid,
      createdAt: DateTime.now(),
      members: allMembers,
      lastMessage: 'Group created',
      lastMessageTime: DateTime.now(),
    );

    await dbHelper.insertGroup(group);

    // Send invites to all members
    final payload = json.encode({
      'type': 'group_invite',
      'groupId': groupId,
      'groupName': name,
      'members': allMembers,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': myUuid,
      'messageId': const Uuid().v4(),
    });

    for (var memberUuid in memberUuids) {
      if (memberUuid == myUuid) continue;
      final device = discoveryService.getDeviceByUuid(memberUuid);
      if (device != null && device.state == SessionState.connected) {
        await discoveryService.sendMessageToEndpoint(device.deviceId, payload);
      } else {
        _relayMessage(memberUuid, json.decode(payload));
      }
    }
    _messageUpdatedController.add(null);
  }

  Future<void> sendGroupTextMessage(String groupId, String groupName, String content) async {
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final messageId = const Uuid().v4();

    final payload = {
      'type': 'group_message',
      'groupId': groupId,
      'content': content,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': myUuid,
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
      'hopCount': 0,
    };

    final message = Message(
      id: messageId,
      senderUuid: myUuid,
      senderName: 'Me',
      receiverUuid: groupId, // Note: receiver is Group ID
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.text,
      status: MessageStatus.sent,
    );

    await dbHelper.insertMessage(message);
    await _updateGroupRecord(groupId, content, message.timestamp, 0, name: groupName);
    _messageUpdatedController.sink.add(null);

    // Broadcast to all neighbors for mesh propagation
    final payloadJson = json.encode(payload);
    final neighbors = discoveryService.getConnectedDevices();
    debugPrint('[MessagingService] Broadcasting group message to ${neighbors.length} neighbors');
    for (var peer in neighbors) {
      await discoveryService.sendMessageToEndpoint(peer.deviceId, payloadJson);
    }
  }

  Future<void> _processIncomingGroupMessage(String senderEndpointId, String groupId, String text, {String? senderName, String? senderUuid, int? incomingPayloadId}) async {
    debugPrint('[MessagingService] _processIncomingGroupMessage: from=$senderUuid, group=$groupId, text=$text');
    final msgId = const Uuid().v4();
    final message = Message(
      id: msgId,
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: senderName ?? 'Unknown',
      receiverUuid: groupId,
      content: text,
      timestamp: DateTime.now(),
      type: MessageType.text,
      status: MessageStatus.delivered,
      payloadId: incomingPayloadId,
      progress: 1.0,
    );
    
    try {
      await dbHelper.insertMessage(message);
      debugPrint('[MessagingService] Group message inserted into DB: ${message.id}');
    } catch (e) {
      debugPrint('[MessagingService] Error inserting group message: $e');
    }
    
    // Check if we are in this group chat in UI
    int unreadIncrement = (NotificationService.activeChatUuid == groupId) ? 0 : 1;
    
    final group = await dbHelper.getGroupById(groupId);
    await _updateGroupRecord(groupId, '$senderName: $text', message.timestamp, unreadIncrement, name: group?.name);
    _messageUpdatedController.sink.add(null);
    
    NotificationService.showIncomingMessage(
      'Group: ${group?.name ?? 'Unknown Group'}',
      '${senderName ?? "Someone"}: $text',
      senderUuid: groupId,
      senderName: group?.name,
    );

    // Re-relay for mesh
    // We don't want to re-relay what we just received if we already processed it (messageId check is earlier)
  }

  Future<void> _updateGroupRecord(String groupId, String lastMessage, DateTime timestamp, int incrementUnread, {String? name}) async {
    final group = await dbHelper.getGroupById(groupId);
    if (group == null) return;

    final updatedGroup = group.copyWith(
      lastMessage: lastMessage,
      lastMessageTime: timestamp,
      unreadCount: group.unreadCount + incrementUnread,
      name: name ?? group.name,
    );
    await dbHelper.insertGroup(updatedGroup);
  }

  Future<int?> sendMessageToEndpoint(String endpointId, String message) async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(message));
      final payloadId = DateTime.now().millisecondsSinceEpoch;
      
      // Check if target is a mesh peer (virtual deviceId == uuid)
      final device = discoveryService.getDeviceByUuid(endpointId);
      if (device != null && device.isMesh) {
        debugPrint('[MessagingService] Target $endpointId is a mesh peer. Using relay.');
        final payload = json.decode(message);
        await _relayMessage(endpointId, payload);
        return payloadId;
      }

      await Nearby().sendBytesPayload(
        endpointId,
        bytes,
      );
      return payloadId; 
    } catch (e) {
      debugPrint('Error sending message: $e');
      // If direct send fails, fallback to relay if we are in a mesh
      try {
        final payload = json.decode(message);
        final targetUuid = payload['targetUuid'];
        if (targetUuid != null) {
          debugPrint('[MessagingService] Direct send failed. Attempting relay fallback to $targetUuid');
          await _relayMessage(targetUuid, payload);
          return DateTime.now().millisecondsSinceEpoch;
        }
      } catch (_) {}
      return null;
    }
  }

  void dispose() {
    _dataSubscription?.cancel();
    _messageUpdatedController.close();
  }
}
