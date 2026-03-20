import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:audioplayers/audioplayers.dart';

import 'discovery_service.dart';
import 'heartbeat_manager.dart';
import 'message_queue_manager.dart';
import 'database_helper.dart';
import 'notification_service.dart';
import 'reputation_service.dart';
import 'peer_ai_service.dart';
import '../models/session_state.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/peer_model.dart';
import '../models/group_model.dart';
import '../encryption/signal_protocol_service.dart';

class MessagingService {
  final DiscoveryService discoveryService;
  final HeartbeatManager heartbeatManager;
  final MessageQueueManager messageQueueManager;
  final ReputationService reputationService;
  final PeerAIService aiService;
  final DatabaseHelper dbHelper = DatabaseHelper.instance;
  final SignalProtocolService _signalService = SignalProtocolService();
  SignalProtocolService get signalService => _signalService;
  final Battery _battery = Battery();
  late final AudioPlayer _player = AudioPlayer();

  final _messageUpdatedController = StreamController<String?>.broadcast();
  Stream<String?> get messageUpdated => _messageUpdatedController.stream;

  // Cache to prevent re-relaying the same message ID (prevents infinite loops in mesh)
  final Set<String> _processedMessageIds = {};
  static const int _maxCacheSize = 100;

  // Track message IDs for incoming/outgoing payloads
  final Map<int, String> _payloadToMessageId = {};

  // Track mesh topology: peerUuid -> List of its connected neighbor Uuids
  final Map<String, List<String>> _meshTopology = {};
  Map<String, List<String>> get meshTopology => _meshTopology;

  // Track link and node metadata for Dijkstra: uuid -> {rssi, battery, isBackbone, lastUpdate}
  final Map<String, Map<String, dynamic>> _meshNodeMetadata = {};
  Map<String, Map<String, dynamic>> get meshNodeMetadata => _meshNodeMetadata;
  
  // Opportunistic buffer: targetUuid -> List of pending message payloads
  final Map<String, List<Map<String, dynamic>>> _opportunisticBuffer = {};

  final Map<String, List<String>> _activePaths = {};
  Map<String, List<String>> get activePaths => _activePaths;


  // SOS Alerts stream
  void _pruneStaleTopology() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleLimit = 1000 * 60 * 15; // 15 minutes

    _meshNodeMetadata.removeWhere((uuid, meta) {
      final lastUpdate = meta['lastUpdate'] as int? ?? 0;
      if (now - lastUpdate > staleLimit) {
        _meshTopology.remove(uuid);
        return true;
      }
      return false;
    });
  }

  void _flushOpportunisticBuffer() async {
    if (_opportunisticBuffer.isEmpty) return;

    final targets = List<String>.from(_opportunisticBuffer.keys);
    for (var targetUuid in targets) {
      final path = await _findNextHop(targetUuid);
      if (path != null) {
        final messages = _opportunisticBuffer.remove(targetUuid);
        if (messages != null) {
          debugPrint('[Opportunistic] Path found to $targetUuid. Flushing ${messages.length} messages.');
          for (var payload in messages) {
            await _relayMessage(targetUuid, payload);
          }
        }
      }
    }
  }

  final _sosAlertController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sosAlerts => _sosAlertController.stream;

  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get typingUpdated => _typingController.stream;

  final _connectionQualityController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get connectionQualityUpdated => _connectionQualityController.stream;

  StreamSubscription? _dataSubscription;
  StreamSubscription? _payloadProgressSubscription;
  StreamSubscription? _batterySubscription;
  Timer? _cleanupTimer;
  Timer? _gossipTimer;

  // Store-and-Forward Relay Buffer: targetUuid -> List of messages
  final Map<String, List<Map<String, dynamic>>> _relayBuffer = {};

  bool _isPluggedIn = false;

  MessagingService({
    required this.discoveryService,
    required this.heartbeatManager,
    required this.messageQueueManager,
    required this.reputationService,
    required this.aiService,
  }) {
    _dataSubscription = discoveryService.dataReceived.listen(
      _handleIncomingData,
    );
    _payloadProgressSubscription = discoveryService.payloadProgress.listen(_handlePayloadProgress);
    _initBatteryMonitoring();

    // Start heartbeat monitoring via the dedicated manager
    heartbeatManager.startMonitoring();


    // Register resend callback for the message queue manager
    messageQueueManager.onResendMessage = resendMessage;

    _startCleanupTimer();
    _startGossipTimer();
  }

  void _startGossipTimer() {
    _gossipTimer?.cancel();
    _gossipTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      final connected = discoveryService.getConnectedDevices();
      for (var device in connected) {
        // Only gossip with peers we already trust
        final rep = await reputationService.getReputation(device.uuid ?? device.deviceId);
        if ((rep?['composite_score'] ?? 50.0) >= 60.0) {
          await sendReputationGossip(device.deviceId);
        }
      }
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      final deletedCount = await dbHelper.deleteExpiredMessages();
      if (deletedCount > 0) {
        debugPrint('[Cleanup] Burned $deletedCount expired messages.');
        _messageUpdatedController.add(null);
      }
    });
  }

  void dispose() {
    _dataSubscription?.cancel();
    _payloadProgressSubscription?.cancel();
    _batterySubscription?.cancel();
    _messageUpdatedController.close();
    _sosAlertController.close();
    _typingController.close();
    _connectionQualityController.close();
    heartbeatManager.stopMonitoring();
    _cleanupTimer?.cancel();
    _gossipTimer?.cancel();
    _player.dispose();
    debugPrint('[MessagingService] Disposed.');
  }

  void _initBatteryMonitoring() {
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
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

  // Ping/Pong now handled by HeartbeatManager



  // Signal quality estimation now handled by HeartbeatManager

  void _handlePayloadProgress(PayloadProgress update) async {
    final message = await dbHelper.getMessageByPayloadId(update.payloadId);
    if (message != null) {
      await dbHelper.updateMessageProgress(message.id, update.progress);
      
      if (update.status == PayloadStatus.SUCCESS) {
        await dbHelper.insertMessage(message.copyWith(
          status: MessageStatus.delivered,
          progress: 1.0,
        ));
      } else if (update.status == PayloadStatus.FAILURE) {
        await dbHelper.insertMessage(message.copyWith(
          status: MessageStatus.failed,
        ));
      }
      _messageUpdatedController.sink.add(message.senderUuid);
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
        final identityKeyBase64 = payload['identityKey'] as String?;

        if (originalSenderUuid != null) {
          if (profileBase64 != null) {
            final directory = await getApplicationDocumentsDirectory();
            final filePath = p.join(directory.path, 'profile_$originalSenderUuid$extension');
            await File(filePath).writeAsBytes(base64Decode(profileBase64));
            await _updateChatRecord(originalSenderUuid, null, null, 0, peerName: originalSenderName, peerProfileImage: filePath);
            debugPrint('[MessagingService] Synced profile image for $originalSenderUuid');
          }
          
          if (identityKeyBase64 != null) {
            final keyBytes = base64Decode(identityKeyBase64);
            await _signalService.saveIdentityForPeer(originalSenderUuid, keyBytes); // basic trust on first use
            debugPrint('[MessagingService] Synced identity key for $originalSenderUuid');
          }

          _messageUpdatedController.add(originalSenderUuid);
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
        final Map<String, dynamic>? nodeInfo = payload['nodeInfo'] as Map<String, dynamic>?;

        if (originalSenderUuid != null && neighbors != null) {
          _meshTopology[originalSenderUuid] = neighbors.cast<String>();
          
          // Update node metadata if provided
          if (nodeInfo != null) {
            _meshNodeMetadata[originalSenderUuid] = {
              ...nodeInfo,
              'lastUpdate': DateTime.now().millisecondsSinceEpoch,
            };
          }
          
          // EXTEND DISCOVERY: Add these neighbors as mesh devices in DiscoveryService
          for (var neighborUuid in neighbors) {
            if (neighborUuid == myUuid || neighborUuid == 'me') continue;
            final peer = await dbHelper.getPeer(neighborUuid);
            final displayName = peer?.deviceName ?? 'Mesh Peer';
            discoveryService.addMeshDevice(neighborUuid, displayName, senderId);
          }
          
          _pruneStaleTopology();
          _flushOpportunisticBuffer();
          _messageUpdatedController.add(originalSenderUuid);
        }
        return;
      }

      // Handle reputation gossip update
      if (type == 'reputation_gossip') {
        final Map<String, dynamic>? gossip = payload['gossip'] as Map<String, dynamic>?;
        if (originalSenderUuid != null && gossip != null) {
          // Verify source integrity: Only take gossip from people we trust
          final sourceRep = await reputationService.getReputation(originalSenderUuid);
          final double sourceScore = sourceRep?['composite_score'] ?? 50.0;
          
          if (sourceScore >= 60.0) { // Only trust gossip from "Stable" peers or better
            await reputationService.mergeGossipData(originalSenderUuid, gossip);
          } else {
            debugPrint('[Gossip] Ignoring reputation gossip from untrusted peer $originalSenderUuid (Score: $sourceScore)');
          }
        }
        return;
      }

      // Handle Mesh ACKs
      if (type == 'mesh_ack') {
        final String? ackMessageId = payload['ackMessageId'];
        if (ackMessageId != null) {
          debugPrint('[MeshACK] Received ACK for message $ackMessageId from $originalSenderUuid');
          await dbHelper.updateMessageStatus(ackMessageId, MessageStatus.delivered);
          _messageUpdatedController.add(originalSenderUuid);
        }
        return;
      }

    // Handle Heartbeats — delegated to HeartbeatManager
      if (type == 'ping') {
        if (originalSenderUuid != null) {
          final int? pingTimestamp = payload['timestamp'] as int?;
          heartbeatManager.sendPong(senderId, originalSenderUuid, pingTimestamp);
        }
        return;
      }
      if (type == 'pong') {
        if (originalSenderUuid != null) {
          final int? pingTimestamp = payload['pingTimestamp'] as int?;
          heartbeatManager.handlePong(originalSenderUuid, senderId, pingTimestamp);
        }
        return;
      }

      // 2. Update Discovery state if we receive data from a peer (Self-Healing)
      if (originalSenderUuid != null && senderId != originalSenderUuid) {
        final device = discoveryService.getDeviceByUuid(originalSenderUuid);
        if (device != null && device.state != SessionState.connected) {
          debugPrint('[MessagingService] Self-Healing: Data received from $originalSenderUuid. Marking as connected.');
          discoveryService.updateDeviceState(senderId, SessionState.connected);
        }
      }

      // 3. Check deduplication
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

      // Handle burn duration/expiration
      DateTime? expiresAt;
      if (payload['burnDuration'] != null) {
        final seconds = payload['burnDuration'] as int;
        expiresAt = DateTime.now().add(Duration(seconds: seconds));
      }

      if (type == 'text') {
        final String content = decryptedContent ?? (payload['content'] as String? ?? '');
        await _processIncomingText(
          senderId,
          content,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
          expiresAt: expiresAt,
        );
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
      } else if (type == 'audio') {
        final String base64Content = payload['content'] as String;
        await _processIncomingAudio(
          senderId,
          base64Content,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
          expiresAt: expiresAt,
        );
        
        // Relaying audio for mesh
        _relayMessage(targetUuid ?? 'broadcast', payload, excludeEndpointId: senderId);
      } else if (type == 'image') {
        final String base64Content = payload['content'] as String;
        final String extension = payload['extension'] as String? ?? '.jpg';
        await _processIncomingImage(
          senderId,
          base64Content,
          extension,
          senderName: originalSenderName,
          senderUuid: originalSenderUuid,
          incomingPayloadId: incomingPayloadId,
          expiresAt: expiresAt,
        );
        _relayMessage(targetUuid ?? 'broadcast', payload, excludeEndpointId: senderId);
      } else if (type == 'group_image') {
        final String? groupId = payload['groupId'];
        final String base64Content = payload['content'] as String;
        final String extension = payload['extension'] as String? ?? '.jpg';
        if (groupId != null) {
          await _processIncomingGroupImage(
            senderId,
            groupId,
            base64Content,
            extension,
            senderName: originalSenderName,
            senderUuid: originalSenderUuid,
            incomingPayloadId: incomingPayloadId,
          );
          _relayMessage('broadcast', payload, excludeEndpointId: senderId);
        }
      } else if (type == 'group_update') {
        final String? groupId = payload['groupId'];
        final List<dynamic>? memberUuids = payload['members'];
        if (groupId != null && memberUuids != null) {
          final group = await dbHelper.getGroupById(groupId);
          if (group != null) {
            final updatedGroup = group.copyWith(members: memberUuids.cast<String>());
            await dbHelper.insertGroup(updatedGroup);
            _messageUpdatedController.add(null);
            debugPrint('[MessagingService] Updated member list for group $groupId');
          }
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

      // Send Mesh ACK if this message was for me and had a messageId
      if (targetUuid == myUuid && messageId != null && type != 'mesh_ack' && type != 'typing' && type != 'ping' && type != 'pong' && type != 'battery_update' && type != 'mesh_update') {
        _sendMeshAck(originalSenderUuid ?? senderId, messageId);
      }
    } catch (e) {
      debugPrint('[MessagingService] Error handling data: $e');
      // Fallback for non-json or malformed data
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

  Future<void> sendReputationGossip(String endpointId) async {
    try {
      final User? me = await dbHelper.getUser('me');
      final gossipData = await reputationService.getTopPeersForGossip();
      if (gossipData.isEmpty) return;

      final String payload = json.encode({
        'type': 'reputation_gossip',
        'senderUuid': me?.uuid ?? 'me',
        'gossip': gossipData,
      });
      await discoveryService.sendMessageToEndpoint(endpointId, payload);
    } catch (e) {
      debugPrint('[MessagingService] Error sending reputation gossip: $e');
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

      final level = await _battery.batteryLevel;
      final status = await _calculateBackboneStatus();

      final String payload = json.encode({
        'type': 'mesh_update',
        'neighbors': neighborUuids,
        'senderUuid': me?.uuid ?? 'me',
        'nodeInfo': {
          'batteryLevel': level,
          'isBackbone': status,
          'isPluggedIn': _isPluggedIn,
        }
      });
      await discoveryService.sendMessageToEndpoint(endpointId, payload);
    } catch (e) {
      debugPrint('[MessagingService] Error sending mesh update: $e');
    }
  }

  Future<void> _sendMeshAck(String targetUuid, String ackMessageId) async {
    try {
      final User? me = await dbHelper.getUser('me');
      final payload = {
        'type': 'mesh_ack',
        'ackMessageId': ackMessageId,
        'senderUuid': me?.uuid ?? 'me',
        'targetUuid': targetUuid,
        'timestamp': DateTime.now().toIso8601String(),
        'hopCount': 0,
      };
      debugPrint('[MeshACK] Sending ACK for $ackMessageId to $targetUuid');
      await _relayMessage(targetUuid, payload);
    } catch (e) {
      debugPrint('[MeshACK] Error sending ACK: $e');
    }
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      final group = await dbHelper.getGroupById(groupId);
      if (group == null) return;
      final me = await dbHelper.getUser('me');
      if (me == null) return;

      final updatedMembers = List<String>.from(group.members)..remove(me.uuid);
      
      final payload = {
        'type': 'group_update',
        'groupId': groupId,
        'members': updatedMembers,
        'senderUuid': me.uuid,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _relayMessage('broadcast', payload);
    } catch (e) {
      debugPrint('[MessagingService] Error leaving group: $e');
    }
  }

  /// Finds the next hop towards [targetUuid] using Dijkstra's algorithm.
  /// Considers link costs based on RSSI and node power status.
  Future<String?> _findNextHop(String targetUuid) async {
    final connected = discoveryService.getConnectedDevices();
    
    // 1. Direct connection is always best - check synchronously for performance
    for (var device in connected) {
      if (device.uuid == targetUuid) return device.deviceId;
    }

    // 2. Dijkstra for weighted path - Offload to background Isolate
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    
    // Prepare data for the isolate
    final params = DijkstraParams(
      myUuid: myUuid,
      targetUuid: targetUuid,
      meshTopology: _meshTopology,
      meshNodeMetadata: _meshNodeMetadata,
      connectedDevices: await Future.wait(connected.map((d) async {
        final rep = await reputationService.getReputation(d.uuid ?? d.deviceId);
        return {
          'uuid': d.uuid,
          'deviceId': d.deviceId,
          'rssi': d.rssi,
          'isBackbone': d.isBackbone,
          'batteryLevel': d.batteryLevel,
          'reputationScore': rep?['composite_score'] ?? 50.0,
        };
      })),
      dropProbabilities: {
        for (var d in connected) d.uuid ?? d.deviceId: aiService.predictDropProbability(d.uuid ?? d.deviceId)
      },
    );

    try {
      final result = await compute(_dijkstraIsolate, params);
      
      if (result != null) {
        _activePaths[targetUuid] = result.path;
        debugPrint('[Dijkstra Isolate] Optimal path to $targetUuid: ${result.path} (Cost: ${result.cost})');
        return result.nextHopDeviceId;
      }
    } catch (e) {
      debugPrint('[Dijkstra Isolate] Error: $e');
    }

    _activePaths.remove(targetUuid);
    return null;
  }

  Future<int?> _relayMessage(String targetUuid, Map<String, dynamic> payload, {String? excludeEndpointId}) async {
    int hops = (payload['hopCount'] ?? 0) + 1;
    payload['hopCount'] = hops;
    if (hops > 12) return null;

    final String updatedPayload = json.encode(payload);
    
    // 1. High-Priority Flooding (ignore Dijkstra for critical alerts)
    if (payload['priority'] == 1) {
      debugPrint('[MeshRelay] High-Priority message. Flooding to all neighbors.');
      final neighbors = discoveryService.getConnectedDevices();
      int? firstPayloadId;
      for (var peer in neighbors) {
        if (peer.deviceId != excludeEndpointId) {
          final pid = await discoveryService.sendMessageToEndpoint(peer.deviceId, updatedPayload);
          firstPayloadId ??= pid;
        }
      }
      return firstPayloadId;
    }

    // 2. Dijkstra pathfinding for unicast messages
    if (targetUuid != 'broadcast') {
      final String? nextHopEndpointId = await _findNextHop(targetUuid);
      
      if (nextHopEndpointId != null && nextHopEndpointId != excludeEndpointId) {
        debugPrint('[MeshRelay] Path found for $targetUuid. Next hop: $nextHopEndpointId (hops: $hops)');
        return await discoveryService.sendMessageToEndpoint(nextHopEndpointId, updatedPayload);
      }
      
      // 3. Buffer for later if no path (Opportunistic Buffering)
      if (hops == 1) { // Only buffer if it's the first hop and no path found
        debugPrint('[MeshRelay] No path for $targetUuid. Buffering message.');
        _opportunisticBuffer.putIfAbsent(targetUuid, () => []).add(payload);
        return null;
      }
      
      debugPrint('[MeshRelay] No path for $targetUuid in topology. Flooding to direct neighbors.');
    } else {
      debugPrint('[MeshRelay] Broadcasting payload via flooding (hops: $hops)');
    }

    // 4. Fallback: Flooding (for broadcast or if Dijkstra failed/no path)
    final neighbors = discoveryService.getConnectedDevices();
    
    // Sort neighbors: Backbones first, then highest battery
    neighbors.sort((a, b) {
      if (a.isBackbone && !b.isBackbone) return -1;
      if (!a.isBackbone && b.isBackbone) return 1;
      return b.batteryLevel.compareTo(a.batteryLevel);
    });

    int? firstFloodPid;
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

      final pid = await discoveryService.sendMessageToEndpoint(peer.deviceId, updatedPayload);
      firstFloodPid ??= pid;
    }
    return firstFloodPid;
  }

  Future<void> broadcastSOS({String content = "I need help! Immediate assistance required."}) async {
    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();
    
    final payload = {
      'type': 'sos',
      'content': content,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': me?.uuid ?? '',
      'messageId': messageId,
      'hopCount': 0,
      'priority': 1, // Phase 4 priority
      'timestamp': DateTime.now().toIso8601String(),
    };

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
    _messageUpdatedController.sink.add('broadcast');

    // Use _relayMessage to handle the flooding with priority logic
    _relayMessage('broadcast', payload);
    
    debugPrint('[SOS] SOS Broadcast initiated via priority flooding');
  }


  Future<void> _processIncomingText(String senderEndpointId, String text, {String? senderName, String? senderUuid, int? incomingPayloadId, DateTime? expiresAt}) async {
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
      expiresAt: expiresAt,
    );
    if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
    await dbHelper.insertMessage(message);
    int unreadIncrement = (NotificationService.activeChatUuid == (senderUuid ?? senderEndpointId)) ? 0 : 1;
    await _updateChatRecord(senderUuid ?? senderEndpointId, text, message.timestamp, unreadIncrement, peerName: senderName);
    _messageUpdatedController.sink.add(senderUuid ?? senderEndpointId);
    final chat = await dbHelper.getChatByPeerUuid(senderUuid ?? senderEndpointId);
    NotificationService.showIncomingMessage(
      'Message from ${chat?.peerName ?? senderName ?? senderEndpointId}',
      text,
      senderUuid: senderUuid ?? senderEndpointId,
      senderName: chat?.peerName ?? senderName,
      senderProfileImage: chat?.peerProfileImage,
    );
    _playMessageSound(true, senderUuid: senderUuid ?? senderEndpointId);
  }



  Future<void> acceptFile(String messageId) async {
    final message = await dbHelper.getMessageById(messageId);
    if (message == null) return;
    await dbHelper.insertMessage(message.copyWith(isFileAccepted: true));
    _messageUpdatedController.sink.add(message.senderUuid);
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
    _messageUpdatedController.sink.add(senderUuid);
  }

  Future<void> sendTextMessage(String receiverUuid, String receiverName, String content, {Duration? burnDuration}) async {
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
      'burnDuration': burnDuration?.inSeconds,
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
      expiresAt: burnDuration != null ? DateTime.now().add(burnDuration) : null,
    );
    
    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, content, message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(null);
    _playMessageSound(false);

    try {
      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        // Direct Send
        final payloadId = await discoveryService.sendMessageToEndpoint(device.deviceId, payloadObj);
        if (payloadId != null) {
          _payloadToMessageId[payloadId] = messageId;
          await dbHelper.updateMessagePayloadId(messageId, payloadId);
          await dbHelper.updateMessageStatus(messageId, MessageStatus.sent);
        } else {
          // If direct send failed at high-level, mark as failed (or queued if you want to retry)
          await dbHelper.updateMessageStatus(messageId, MessageStatus.failed);
        }
      } else {
        // Mesh Send
        final String? nextHopEndpointId = await _findNextHop(receiverUuid);
        if (nextHopEndpointId != null) {
          debugPrint('[MeshSend] Sending $messageId via next hop $nextHopEndpointId');
          await discoveryService.sendMessageToEndpoint(nextHopEndpointId, payloadObj);
          await dbHelper.updateMessageStatus(messageId, MessageStatus.relay);
        } else {
          // No path found, flood to neighbors or queue
          final neighbors = discoveryService.getConnectedDevices();
          if (neighbors.isNotEmpty) {
            debugPrint('[MeshSend] No path found for $receiverUuid. Flooding to ${neighbors.length} neighbors.');
            for (var neighbor in neighbors) {
              await discoveryService.sendMessageToEndpoint(neighbor.deviceId, payloadObj);
            }
            await dbHelper.updateMessageStatus(messageId, MessageStatus.relay);
          } else {
            debugPrint('[MeshSend] Offline. Queuing message $messageId');
            await dbHelper.updateMessageStatus(messageId, MessageStatus.queued);
          }
        }
      }
    } catch (e) {
      debugPrint('[MessagingService] Error in sendTextMessage: $e');
      await dbHelper.updateMessageStatus(messageId, MessageStatus.failed);
    }
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

  Future<void> sendAudioMessage(String receiverUuid, String receiverName, String filePath, {Duration? burnDuration}) async {
    final File file = File(filePath);
    if (!file.existsSync()) return;
    
    final List<int> bytes = await file.readAsBytes();
    final String base64Content = base64.encode(bytes);

    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();
    
    final payload = {
      'type': 'audio',
      'content': base64Content,
      'senderUuid': me?.uuid ?? 'me',
      'senderName': me?.deviceName ?? 'User',
      'targetUuid': receiverUuid,
      'messageId': messageId,
      'hopCount': 0,
      'burnDuration': burnDuration?.inSeconds,
    };

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: filePath, // Locally we store the path
      timestamp: DateTime.now(),
      type: MessageType.audio,
      status: MessageStatus.sending,
      hopCount: 0,
      expiresAt: burnDuration != null ? DateTime.now().add(burnDuration) : null,
    );
    
    await dbHelper.insertMessage(message);
    _messageUpdatedController.sink.add(receiverUuid);
    _playMessageSound(false);

    await _relayMessage(receiverUuid, payload);
    
    // Update status to sent locally (mesh relay will update further if ACKs are implemented for audio)
    await dbHelper.updateMessageStatus(messageId, MessageStatus.sent);
    _messageUpdatedController.sink.add(receiverUuid);
  }

  Future<void> _processIncomingAudio(String senderEndpointId, String base64Content, {String? senderName, String? senderUuid, int? incomingPayloadId, DateTime? expiresAt}) async {
    try {
      final bytes = base64.decode(base64Content);
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final String filePath = p.join(directory.path, 'PTT', fileName);
      
      final file = File(filePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes);

      final User? me = await dbHelper.getUser('me');
      final String myUuid = me?.uuid ?? 'me';
      final msgId = const Uuid().v4();
      
      final message = Message(
        id: msgId,
        senderUuid: senderUuid ?? senderEndpointId,
        receiverUuid: myUuid,
        content: filePath,
        timestamp: DateTime.now(),
        type: MessageType.audio,
        status: MessageStatus.delivered,
        payloadId: incomingPayloadId,
        progress: 1.0,
        expiresAt: expiresAt,
      );
      
      if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
      await dbHelper.insertMessage(message);
      
      if (senderUuid != null) {
        _messageUpdatedController.sink.add(senderUuid);
      } else {
        _messageUpdatedController.sink.add(senderEndpointId);
      }

      NotificationService.showIncomingMessage(
        senderName ?? 'Peer',
        'Sent a voice message',
        senderUuid: senderUuid ?? senderEndpointId,
        senderName: senderName ?? 'Peer',
      );
      _playMessageSound(true, senderUuid: senderUuid ?? senderEndpointId);
    } catch (e) {
      debugPrint('[MessagingService] Error processing incoming audio: $e');
    }
  }

  // ─────────────────── Image Messaging ───────────────────

  /// Compresses and resizes an image for fast mesh transfer.
  /// Targets max 800px and 75% JPEG quality — typically reduces size by 80-95%.
  Future<Uint8List> _compressImage(String filePath) async {
    try {
      final Uint8List? result = await FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: 800,
        minHeight: 800,
        quality: 75,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (result != null && result.isNotEmpty) {
        debugPrint('[Image] Compressed: ${File(filePath).lengthSync()} bytes → ${result.length} bytes');
        return result;
      }
    } catch (e) {
      debugPrint('[Image] Compression failed, using original: $e');
    }
    return await File(filePath).readAsBytes();
  }

  Future<void> sendImageMessage(String receiverUuid, String receiverName, String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync()) return;

    final Uint8List bytes = await _compressImage(filePath);
    final String base64Content = base64.encode(bytes);
    final String extension = '.jpg'; // always JPEG after compression

    final User? me = await dbHelper.getUser('me');
    final messageId = const Uuid().v4();

    final payload = {
      'type': 'image',
      'content': base64Content,
      'extension': extension,
      'senderUuid': me?.uuid ?? 'me',
      'senderName': me?.deviceName ?? 'User',
      'targetUuid': receiverUuid,
      'messageId': messageId,
      'hopCount': 0,
    };

    final message = Message(
      id: messageId,
      senderUuid: me?.uuid ?? 'me',
      receiverUuid: receiverUuid,
      content: '📷 Image',
      timestamp: DateTime.now(),
      type: MessageType.image,
      status: MessageStatus.sending,
      hopCount: 0,
      imagePath: filePath,
    );

    await dbHelper.insertMessage(message);
    await _updateChatRecord(receiverUuid, '📷 Image', message.timestamp, 0, peerName: receiverName);
    _messageUpdatedController.sink.add(receiverUuid);
    _playMessageSound(false);

    final int? payloadId = await _relayMessage(receiverUuid, payload);
    if (payloadId != null) {
      _payloadToMessageId[payloadId] = messageId;
      await dbHelper.updateMessagePayloadId(messageId, payloadId);
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: payloadId));
    } else {
      await dbHelper.updateMessageStatus(messageId, MessageStatus.sent);
    }
    _messageUpdatedController.sink.add(receiverUuid);
  }

  Future<void> sendGroupImageMessage(String groupId, String groupName, String filePath) async {
    final File file = File(filePath);
    if (!file.existsSync()) return;

    final Uint8List bytes = await _compressImage(filePath);
    final String base64Content = base64.encode(bytes);
    const String extension = '.jpg'; // always JPEG after compression

    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';
    final messageId = const Uuid().v4();

    final payload = {
      'type': 'group_image',
      'groupId': groupId,
      'content': base64Content,
      'extension': extension,
      'senderUuid': myUuid,
      'senderName': me?.deviceName ?? 'User',
      'messageId': messageId,
      'timestamp': DateTime.now().toIso8601String(),
      'hopCount': 0,
    };

    final message = Message(
      id: messageId,
      senderUuid: myUuid,
      senderName: me?.deviceName ?? 'Me',
      receiverUuid: groupId,
      content: '📷 Image',
      timestamp: DateTime.now(),
      type: MessageType.image,
      status: MessageStatus.sent,
      imagePath: filePath,
    );

    await dbHelper.insertMessage(message);
    await _updateGroupRecord(groupId, '${me?.deviceName ?? 'You'}: 📷 Image', message.timestamp, 0, name: groupName);
    _messageUpdatedController.sink.add(null);
    _playMessageSound(false);

    final payloadJson = json.encode(payload);
    final neighbors = discoveryService.getConnectedDevices();
    int? firstPayloadId;
    for (var peer in neighbors) {
      final pid = await discoveryService.sendMessageToEndpoint(peer.deviceId, payloadJson);
      firstPayloadId ??= pid;
    }

    if (firstPayloadId != null) {
      _payloadToMessageId[firstPayloadId] = messageId;
      await dbHelper.updateMessagePayloadId(messageId, firstPayloadId);
      await dbHelper.insertMessage(message.copyWith(status: MessageStatus.sent, payloadId: firstPayloadId));
    } else {
      await dbHelper.updateMessageStatus(messageId, MessageStatus.sent);
    }
    _messageUpdatedController.sink.add(null);
  }

  Future<void> _processIncomingImage(
    String senderEndpointId,
    String base64Content,
    String extension, {
    String? senderName,
    String? senderUuid,
    int? incomingPayloadId,
    DateTime? expiresAt,
  }) async {
    try {
      final bytes = base64.decode(base64Content);
      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory(p.join(directory.path, 'Images'));
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      final String fileName = 'img_${DateTime.now().millisecondsSinceEpoch}$extension';
      final String filePath = p.join(imageDir.path, fileName);
      await File(filePath).writeAsBytes(bytes);

      final User? me = await dbHelper.getUser('me');
      final String myUuid = me?.uuid ?? 'me';
      final msgId = const Uuid().v4();

      final message = Message(
        id: msgId,
        senderUuid: senderUuid ?? senderEndpointId,
        receiverUuid: myUuid,
        content: '📷 Image',
        timestamp: DateTime.now(),
        type: MessageType.image,
        status: MessageStatus.delivered,
        payloadId: incomingPayloadId,
        progress: 1.0,
        imagePath: filePath,
        expiresAt: expiresAt,
      );

      if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
      await dbHelper.insertMessage(message);
      final effectiveSender = senderUuid ?? senderEndpointId;
      await _updateChatRecord(effectiveSender, '📷 Image', message.timestamp, 
          NotificationService.activeChatUuid == effectiveSender ? 0 : 1, 
          peerName: senderName);
      _messageUpdatedController.sink.add(effectiveSender);

      NotificationService.showIncomingMessage(
        senderName ?? 'Peer',
        '📷 Sent an image',
        senderUuid: effectiveSender,
        senderName: senderName ?? 'Peer',
      );
      _playMessageSound(true, senderUuid: effectiveSender);
    } catch (e) {
      debugPrint('[MessagingService] Error processing incoming image: $e');
    }
  }

  Future<void> _processIncomingGroupImage(
    String senderEndpointId,
    String groupId,
    String base64Content,
    String extension, {
    String? senderName,
    String? senderUuid,
    int? incomingPayloadId,
  }) async {
    try {
      final bytes = base64.decode(base64Content);
      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory(p.join(directory.path, 'Images'));
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      final String fileName = 'grp_img_${DateTime.now().millisecondsSinceEpoch}$extension';
      final String filePath = p.join(imageDir.path, fileName);
      await File(filePath).writeAsBytes(bytes);

      final msgId = const Uuid().v4();
      final message = Message(
        id: msgId,
        senderUuid: senderUuid ?? senderEndpointId,
        senderName: senderName ?? 'Unknown',
        receiverUuid: groupId,
        content: '📷 Image',
        timestamp: DateTime.now(),
        type: MessageType.image,
        status: MessageStatus.delivered,
        payloadId: incomingPayloadId,
        progress: 1.0,
        imagePath: filePath,
      );

      if (incomingPayloadId != null) _payloadToMessageId[incomingPayloadId] = msgId;
      await dbHelper.insertMessage(message);

      int unreadIncrement = (NotificationService.activeChatUuid == groupId) ? 0 : 1;
      final group = await dbHelper.getGroupById(groupId);
      await _updateGroupRecord(groupId, '${senderName ?? "Someone"}: 📷 Image', message.timestamp, unreadIncrement, name: group?.name);
      _messageUpdatedController.sink.add(null);

      NotificationService.showIncomingMessage(
        'Group: ${group?.name ?? 'Unknown Group'}',
        '${senderName ?? "Someone"}: 📷 Image',
        senderUuid: groupId,
        senderName: group?.name,
      );
      _playMessageSound(true, senderUuid: groupId);
    } catch (e) {
      debugPrint('[MessagingService] Error processing incoming group image: $e');
    }
  }

  Future<void> sendBroadcast(String content) async {
    final User? me = await dbHelper.getUser('me');
    final payload = {
      'type': 'mesh_shout',
      'content': content,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': me?.uuid ?? '',
      'messageId': const Uuid().v4(),
      'hopCount': 0,
      'priority': 1, // Phase 4 priority
    };
    
    _relayMessage('broadcast', payload);
  }

  Future<void> sendProfileImage(String receiverUuid) async {
    final User? me = await dbHelper.getUser('me');
    if (me == null) return;

    String? encodedImage;
    String extension = '.jpg';

    if (me.profileImage != null) {
      final file = File(me.profileImage!);
      if (await file.exists()) {
        encodedImage = base64Encode(await file.readAsBytes());
        extension = p.extension(file.path);
      }
    }

    try {
      final identityBase64 = await _signalService.getLocalFingerprint();

      final String payloadObj = json.encode({
        'type': 'profile_sync',
        'content': encodedImage, // can be null
        'extension': extension,
        'identityKey': identityBase64,
        'senderName': me.deviceName,
        'senderUuid': me.uuid,
        'targetUuid': receiverUuid,
        'messageId': const Uuid().v4(),
        'hopCount': 0,
      });

      final device = discoveryService.getDeviceByUuid(receiverUuid);
      if (device != null && device.state == SessionState.connected) {
        await discoveryService.sendMessageToEndpoint(device.deviceId, payloadObj);
      } else {
        _relayMessage(receiverUuid, json.decode(payloadObj));
      }
    } catch (e) {
      debugPrint('[MessagingService] Error sending profile_sync: $e');
    }
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
    _playMessageSound(false);

    // Broadcast to all neighbors for mesh propagation
    final payloadJson = json.encode(payload);
    final neighbors = discoveryService.getConnectedDevices();
    debugPrint('[MessagingService] Broadcasting group message to ${neighbors.length} neighbors');
    for (var peer in neighbors) {
      await discoveryService.sendMessageToEndpoint(peer.deviceId, payloadJson);
    }
  }

  Future<void> addMembersToGroup(String groupId, List<String> newMemberUuids) async {
    final group = await dbHelper.getGroupById(groupId);
    if (group == null) return;

    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';

    // Combine existing and new members
    final updatedMembers = Set<String>.from(group.members)..addAll(newMemberUuids);
    final finalMembers = updatedMembers.toList();

    final updatedGroup = group.copyWith(members: finalMembers);
    await dbHelper.insertGroup(updatedGroup);

    // 1. Send group_update to existing members
    final updatePayload = json.encode({
      'type': 'group_update',
      'groupId': groupId,
      'members': finalMembers,
      'senderUuid': myUuid,
      'messageId': const Uuid().v4(),
    });

    for (var memberUuid in group.members) {
      if (memberUuid == myUuid) continue;
      _relayMessage(memberUuid, json.decode(updatePayload));
    }

    // 2. Send group_invite to new members
    final invitePayload = json.encode({
      'type': 'group_invite',
      'groupId': groupId,
      'groupName': group.name,
      'members': finalMembers,
      'senderName': me?.deviceName ?? 'User',
      'senderUuid': myUuid,
      'messageId': const Uuid().v4(),
    });

    for (var memberUuid in newMemberUuids) {
      if (group.members.contains(memberUuid)) continue;
      _relayMessage(memberUuid, json.decode(invitePayload));
    }

    _messageUpdatedController.add(null);
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
    _playMessageSound(true, senderUuid: groupId); // Call site updated

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

  Future<void> _playMessageSound(bool isIncoming, {String? senderUuid}) async {
    try {
      // 1. Only play if app is in foreground
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;

      // 2. Only play incoming sound if we are in the active chat with this sender
      if (isIncoming) {
        if (senderUuid == null || NotificationService.activeChatUuid != senderUuid) {
          debugPrint('[MessagingService] Suppressing incoming sound: chat not active or background.');
          return;
        }
      }

      // If we are currently playing something, stop it first to allow new sound to trigger instantly
      await _player.stop();
      await _player.play(AssetSource(isIncoming ? 'audio/message_received.mp3' : 'audio/message_sent.mp3'));
    } catch (e) {
      debugPrint('[MessagingService] Error playing sound: $e');
    }
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

}

// --- Background Isolate Helpers for Threading ---

class DijkstraParams {
  final String myUuid;
  final String targetUuid;
  final Map<String, List<String>> meshTopology;
  final Map<String, Map<String, dynamic>> meshNodeMetadata;
  final List<Map<String, dynamic>> connectedDevices;

  DijkstraParams({
    required this.myUuid,
    required this.targetUuid,
    required this.meshTopology,
    required this.meshNodeMetadata,
    required this.connectedDevices,
    required this.dropProbabilities,
  });
  final Map<String, double> dropProbabilities;
}

class DijkstraResult {
  final List<String> path;
  final double cost;
  final String? nextHopDeviceId;

  DijkstraResult({required this.path, required this.cost, this.nextHopDeviceId});
}

/// Core Dijkstra logic extracted for use in a background Isolate
DijkstraResult? _dijkstraIsolate(DijkstraParams params) {
  final String myUuid = params.myUuid;
  final String targetUuid = params.targetUuid;

  final Map<String, double> dist = {myUuid: 0.0};
  final Map<String, String> parent = {};
  final Set<String> unvisited = {myUuid};

  // Build set of all known Uuids in topology
  final Set<String> allNodes = {myUuid, ...params.meshTopology.keys};
  for (var neighbors in params.meshTopology.values) {
    allNodes.addAll(neighbors);
  }

  for (var node in allNodes) {
    if (node != myUuid) dist[node] = double.infinity;
    unvisited.add(node);
  }

  while (unvisited.isNotEmpty) {
    String? current;
    double minSafeDist = double.infinity;

    for (var node in unvisited) {
      if (dist[node]! < minSafeDist) {
        minSafeDist = dist[node]!;
        current = node;
      }
    }

    if (current == null || dist[current] == double.infinity) break;
    if (current == targetUuid) break;

    unvisited.remove(current);

    List<String> neighbors = [];
    if (current == myUuid) {
      neighbors = params.connectedDevices.map((d) => d['uuid'] as String).toList();
    } else {
      neighbors = params.meshTopology[current] ?? [];
    }

    for (var neighbor in neighbors) {
      if (!unvisited.contains(neighbor)) continue;

      double edgeWeight = 1.0;
      
      // Node metadata and device info for penalty calculation
      final nodeMeta = params.meshNodeMetadata[neighbor];
      final device = params.connectedDevices.firstWhere(
        (d) => d['uuid'] == neighbor, 
        orElse: () => {}
      );

      double rssi = (device['rssi'] as double?) ?? -90.0;
      if (rssi < -70) {
        edgeWeight += (rssi + 70).abs() * 0.1;
      }

      bool isBackbone = (device['isBackbone'] as bool?) ?? nodeMeta?['isBackbone'] ?? false;
      if (!isBackbone) edgeWeight += 0.5;

      int battery = (device['batteryLevel'] as int?) ?? nodeMeta?['batteryLevel'] ?? 50;
      if (battery < 20) edgeWeight += 2.0;

      double reputation = (device['reputationScore'] as double?) ?? 50.0;
      if (reputation < 30) {
        edgeWeight += (30 - reputation) * 0.2; // Penalty for low reputation
      }

      // AI: Predict drop risk and penalize unstable paths
      final dropProb = params.dropProbabilities[neighbor] ?? 0.0;
      if (dropProb > 0.5) {
        edgeWeight += dropProb * 5.0; // Significant penalty for high-risk links
      }

      double alt = dist[current]! + edgeWeight;
      if (alt < (dist[neighbor] ?? double.infinity)) {
        dist[neighbor] = alt;
        parent[neighbor] = current;
      }
    }
  }

  if (!parent.containsKey(targetUuid)) return null;

  List<String> path = [targetUuid];
  String step = targetUuid;
  while (parent[step] != myUuid) {
    step = parent[step]!;
    path.insert(0, step);
  }

  final nextHopDevice = params.connectedDevices.firstWhere(
    (d) => d['uuid'] == step, 
    orElse: () => {}
  );

  return DijkstraResult(
    path: path,
    cost: dist[targetUuid]!,
    nextHopDeviceId: nextHopDevice['deviceId'] as String?,
  );
}
