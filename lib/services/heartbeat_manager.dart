import 'dart:async';
import 'dart:convert';
import '../utils/connectivity_logger.dart';
import 'discovery_service.dart';
import 'database_helper.dart';

/// Events emitted by the HeartbeatManager.
class HeartbeatEvent {
  final String uuid;
  final String deviceName;
  final HeartbeatEventType type;
  final Map<String, dynamic>? data;

  HeartbeatEvent({
    required this.uuid,
    required this.deviceName,
    required this.type,
    this.data,
  });
}

enum HeartbeatEventType {
  pingSent,
  pongReceived,
  peerHealthy,
  peerDegraded,
  peerLost,
}

/// Standalone heartbeat system for monitoring connection health.
///
/// Sends adaptive pings based on signal quality and detects ghost
/// connections via missed pong responses.
class HeartbeatManager {
  final DiscoveryService _discoveryService;
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Number of missed pings before declaring a peer lost.
  static const int _missThreshold = 2; // Reduced from 3

  /// Tracks missed pings per peer UUID.
  final Map<String, int> _heartbeatMisses = {};

  /// RTT tracking for signal quality estimation.
  final Map<String, int> _lastRtt = {};

  bool _isActive = false;
  bool get isActive => _isActive;
  Timer? _pingTimer;

  final _eventController = StreamController<HeartbeatEvent>.broadcast();
  Stream<HeartbeatEvent> get events => _eventController.stream;

  HeartbeatManager({required DiscoveryService discoveryService})
      : _discoveryService = discoveryService;

  /// UUIDs of peers that are in our saved contacts/known list.
  /// Ghost-eviction (active disconnect) is suppressed for known peers — if the
  /// socket is dead the OS will surface it; if it's a momentary glitch we don't
  /// want to force a reconnect cycle on a peer that is physically in range.
  final Set<String> knownUuids = {};

  void setKnownUuids(Iterable<String> uuids) {
    knownUuids
      ..clear()
      ..addAll(uuids);
  }

  /// Start the adaptive heartbeat monitoring loop.
  void startMonitoring() {
    if (_isActive) return;
    _isActive = true;
    ConnectivityLogger.info(LogCategory.heartbeat, 'Heartbeat monitoring started');
    _scheduleNextPing();
  }

  /// Stop heartbeat monitoring.
  void stopMonitoring() {
    _isActive = false;
    _pingTimer?.cancel();
    _pingTimer = null;
    _heartbeatMisses.clear();
    _lastRtt.clear();
    ConnectivityLogger.info(LogCategory.heartbeat, 'Heartbeat monitoring stopped');
  }

  Future<void> _scheduleNextPing() async {
    if (!_isActive) return;

    final int nextDelaySeconds = await _checkPeerHealth();
    
    if (!_isActive) return;

    ConnectivityLogger.debug(
      LogCategory.heartbeat,
      'Next heartbeat in ${nextDelaySeconds}s',
    );
    
    _pingTimer?.cancel();
    _pingTimer = Timer(Duration(seconds: nextDelaySeconds), () {
      if (_isActive) {
        _scheduleNextPing();
      }
    });
  }

  /// Checks health of all connected peers. Returns adaptive delay in seconds.
  Future<int> _checkPeerHealth() async {
    final connectedPeers = _discoveryService.getConnectedDevices();
    if (connectedPeers.isEmpty) return 60; // Long delay when isolated

    double worstRssi = 0;
    bool hasInitializedWorst = false;

    for (final peer in connectedPeers) {
      if (peer.uuid == null) continue;

      // Track worst RSSI for adaptive timing
      if (!hasInitializedWorst || peer.rssi < worstRssi) {
        worstRssi = peer.rssi;
        hasInitializedWorst = true;
      }

      final misses = _heartbeatMisses[peer.uuid] ?? 0;

      // Check for ghost connection
      if (misses >= _missThreshold) {
        ConnectivityLogger.warning(
          LogCategory.heartbeat,
          'Ghost connection detected: ${peer.deviceName} (${peer.uuid}) — $misses missed pings',
        );
        _heartbeatMisses.remove(peer.uuid);

        if (knownUuids.contains(peer.uuid)) {
          // Known peer: don't force-disconnect. The OS-level socket drop will
          // surface naturally. Resetting the miss counter gives it a fresh window.
          ConnectivityLogger.info(
            LogCategory.heartbeat,
            'Known peer ${peer.deviceName} — skipping active disconnect to avoid churn',
          );
          _eventController.add(HeartbeatEvent(
            uuid: peer.uuid!,
            deviceName: peer.deviceName,
            type: HeartbeatEventType.peerDegraded,
            data: {'missedPings': misses, 'suppressed': true},
          ));
        } else {
          _discoveryService.disconnect(peer);
          _eventController.add(HeartbeatEvent(
            uuid: peer.uuid!,
            deviceName: peer.deviceName,
            type: HeartbeatEventType.peerLost,
          ));
        }
        continue;
      }

      // Emit degraded warning at 2 misses
      if (misses == 2) {
        _eventController.add(HeartbeatEvent(
          uuid: peer.uuid!,
          deviceName: peer.deviceName,
          type: HeartbeatEventType.peerDegraded,
          data: {'missedPings': misses},
        ));
      }

      // Increment miss count and send ping
      _heartbeatMisses[peer.uuid!] = misses + 1;
      await _sendPing(peer.deviceId, peer.uuid!);

      _eventController.add(HeartbeatEvent(
        uuid: peer.uuid!,
        deviceName: peer.deviceName,
        type: HeartbeatEventType.pingSent,
      ));
    }

    // Adapt timing based on signal quality
    if (worstRssi < -85) return 3; // Extreme: 3s
    if (worstRssi < -70) return 7; // Extreme: 7s
    return 10; // Extreme: 10s for stable
  }

  Future<void> _sendPing(String deviceId, String targetUuid) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final user = await _dbHelper.getUser('me');
      final payload = json.encode({
        'type': 'ping',
        'timestamp': now,
        'senderUuid': user?.uuid ?? 'me',
      });
      await _discoveryService.sendMessageToEndpoint(deviceId, payload);
    } catch (e) {
      ConnectivityLogger.error(
        LogCategory.heartbeat,
        'Error sending ping to $targetUuid',
        e,
      );
    }
  }

  /// Send a pong response to a ping.
  Future<void> sendPong(String deviceId, String targetUuid, int? originalTimestamp) async {
    try {
      final user = await _dbHelper.getUser('me');
      final payload = json.encode({
        'type': 'pong',
        'senderUuid': user?.uuid ?? 'me',
        'pingTimestamp': originalTimestamp,
      });
      await _discoveryService.sendMessageToEndpoint(deviceId, payload);
    } catch (e) {
      ConnectivityLogger.error(
        LogCategory.heartbeat,
        'Error sending pong to $targetUuid',
        e,
      );
    }
  }

  /// Handle an incoming pong response. Resets miss count and estimates signal quality.
  void handlePong(String senderUuid, String deviceId, int? pingTimestamp) {
    _heartbeatMisses[senderUuid] = 0; // Reset miss count

    _eventController.add(HeartbeatEvent(
      uuid: senderUuid,
      deviceName: deviceId,
      type: HeartbeatEventType.pongReceived,
    ));

    // Calculate RTT for signal health estimation
    if (pingTimestamp != null) {
      final rtt = DateTime.now().millisecondsSinceEpoch - pingTimestamp;
      _lastRtt[senderUuid] = rtt;
      _estimateSignalQuality(deviceId, rtt);
    }

    // If this peer was previously degraded, emit healthy
    _eventController.add(HeartbeatEvent(
      uuid: senderUuid,
      deviceName: deviceId,
      type: HeartbeatEventType.peerHealthy,
      data: {'rtt': _lastRtt[senderUuid]},
    ));
  }

  void _estimateSignalQuality(String deviceId, int rtt) {
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

    _discoveryService.updateDeviceRssi(deviceId, estimatedRssi);
    ConnectivityLogger.debug(
      LogCategory.heartbeat,
      'Signal quality for $deviceId: ${estimatedRssi}dBm (RTT: ${rtt}ms)',
    );
  }

  /// Get the last known RTT for a peer.
  int? getLastRtt(String uuid) => _lastRtt[uuid];

  /// Get the current miss count for a peer.
  int getMissCount(String uuid) => _heartbeatMisses[uuid] ?? 0;

  void dispose() {
    stopMonitoring();
    _eventController.close();
  }
}
