import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/connectivity_logger.dart';

/// Quality grade for a connection.
enum ConnectionQuality {
  excellent,
  good,
  fair,
  poor,
  dead,
}

/// Information about a single peer connection.
class ConnectionInfo {
  final String uuid;
  final String deviceName;
  final bool isConnected;
  final ConnectionQuality quality;
  final DateTime? connectedSince;
  final DateTime? lastSeen;
  final double rssi;
  final int? lastRtt;

  ConnectionInfo({
    required this.uuid,
    required this.deviceName,
    this.isConnected = false,
    this.quality = ConnectionQuality.dead,
    this.connectedSince,
    this.lastSeen,
    this.rssi = -100.0,
    this.lastRtt,
  });

  ConnectionInfo copyWith({
    String? uuid,
    String? deviceName,
    bool? isConnected,
    ConnectionQuality? quality,
    DateTime? connectedSince,
    DateTime? lastSeen,
    double? rssi,
    int? lastRtt,
  }) {
    return ConnectionInfo(
      uuid: uuid ?? this.uuid,
      deviceName: deviceName ?? this.deviceName,
      isConnected: isConnected ?? this.isConnected,
      quality: quality ?? this.quality,
      connectedSince: connectedSince ?? this.connectedSince,
      lastSeen: lastSeen ?? this.lastSeen,
      rssi: rssi ?? this.rssi,
      lastRtt: lastRtt ?? this.lastRtt,
    );
  }

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'deviceName': deviceName,
        'isConnected': isConnected,
        'quality': quality.index,
        'connectedSince': connectedSince?.toIso8601String(),
        'lastSeen': lastSeen?.toIso8601String(),
        'rssi': rssi,
        'lastRtt': lastRtt,
      };

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) => ConnectionInfo(
        uuid: json['uuid'] ?? '',
        deviceName: json['deviceName'] ?? '',
        isConnected: json['isConnected'] ?? false,
        quality: ConnectionQuality.values[json['quality'] ?? 4],
        connectedSince: json['connectedSince'] != null
            ? DateTime.tryParse(json['connectedSince'])
            : null,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'])
            : null,
        rssi: (json['rssi'] ?? -100.0).toDouble(),
        lastRtt: json['lastRtt'],
      );
}

/// Event emitted when connection state changes.
class ConnectionStateChange {
  final String uuid;
  final String deviceName;
  final bool isConnected;
  final ConnectionQuality quality;

  ConnectionStateChange({
    required this.uuid,
    required this.deviceName,
    required this.isConnected,
    required this.quality,
  });
}

/// Centralized connection lifecycle tracker.
///
/// Maintains the state of all known connections, persists state
/// to SharedPreferences for crash recovery, and emits change events.
class ConnectivityStateMonitor {
  static const String _prefsKey = 'airlink_connection_state';
  static const String _knownPeersKey = 'airlink_known_peers';

  /// Current connection states by UUID.
  final Map<String, ConnectionInfo> _connections = {};

  final _stateChangeController = StreamController<ConnectionStateChange>.broadcast();
  Stream<ConnectionStateChange> get stateChanges => _stateChangeController.stream;

  /// Get current connection info for a peer.
  ConnectionInfo? getConnectionInfo(String uuid) => _connections[uuid];

  /// Get all currently connected peers.
  List<ConnectionInfo> get connectedPeers =>
      _connections.values.where((c) => c.isConnected).toList();

  /// Get all known peers (including disconnected).
  List<ConnectionInfo> get allKnownPeers => _connections.values.toList();

  /// Get connection quality grade for a peer.
  ConnectionQuality getConnectionHealth(String uuid) {
    return _connections[uuid]?.quality ?? ConnectionQuality.dead;
  }

  /// Update connection state for a peer.
  void updateState({
    required String uuid,
    required String deviceName,
    required bool isConnected,
    double? rssi,
    int? rtt,
  }) {
    final existing = _connections[uuid];
    final quality = _calculateQuality(rssi ?? existing?.rssi ?? -100.0, rtt);
    final now = DateTime.now();

    _connections[uuid] = ConnectionInfo(
      uuid: uuid,
      deviceName: deviceName,
      isConnected: isConnected,
      quality: quality,
      connectedSince: isConnected
          ? (existing?.connectedSince ?? now)
          : null,
      lastSeen: now,
      rssi: rssi ?? existing?.rssi ?? -100.0,
      lastRtt: rtt ?? existing?.lastRtt,
    );

    _stateChangeController.add(ConnectionStateChange(
      uuid: uuid,
      deviceName: deviceName,
      isConnected: isConnected,
      quality: quality,
    ));

    ConnectivityLogger.event(
      LogCategory.connection,
      isConnected ? 'Connected' : 'Disconnected',
      data: {
        'device': deviceName,
        'uuid': uuid,
        'quality': quality.name,
      },
    );
  }

  ConnectionQuality _calculateQuality(double rssi, int? rtt) {
    if (rssi > -50 && (rtt == null || rtt < 100)) return ConnectionQuality.excellent;
    if (rssi > -65 && (rtt == null || rtt < 300)) return ConnectionQuality.good;
    if (rssi > -80 && (rtt == null || rtt < 800)) return ConnectionQuality.fair;
    if (rssi > -95) return ConnectionQuality.poor;
    return ConnectionQuality.dead;
  }

  /// Persist current connection state to SharedPreferences.
  /// Called periodically and on important state changes.
  Future<void> saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save full connection info
      final stateMap = _connections.map(
        (key, value) => MapEntry(key, value.toJson()),
      );
      await prefs.setString(_prefsKey, json.encode(stateMap));

      // Save known peer UUIDs separately for quick restoration
      final knownPeers = _connections.values
          .map((c) => {'uuid': c.uuid, 'name': c.deviceName})
          .toList();
      await prefs.setString(_knownPeersKey, json.encode(knownPeers));

      ConnectivityLogger.debug(
        LogCategory.connection,
        'Saved state for ${_connections.length} peers',
      );
    } catch (e) {
      ConnectivityLogger.error(LogCategory.connection, 'Failed to save state', e);
    }
  }

  /// Restore connection state from SharedPreferences after a crash/restart.
  /// Returns list of UUIDs that were previously connected (for reconnection).
  Future<List<String>> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateStr = prefs.getString(_prefsKey);
      if (stateStr == null) return [];

      final Map<String, dynamic> stateMap = json.decode(stateStr);
      final previouslyConnected = <String>[];

      for (final entry in stateMap.entries) {
        final info = ConnectionInfo.fromJson(entry.value);
        // Mark all as disconnected on restore — actual connection will be re-established
        _connections[entry.key] = info.copyWith(isConnected: false);
        if (info.isConnected) {
          previouslyConnected.add(entry.key);
        }
      }

      ConnectivityLogger.info(
        LogCategory.connection,
        'Restored state: ${_connections.length} known peers, '
            '${previouslyConnected.length} were previously connected',
      );

      return previouslyConnected;
    } catch (e) {
      ConnectivityLogger.error(LogCategory.connection, 'Failed to restore state', e);
      return [];
    }
  }

  /// Get previously known peer UUIDs and names for discovery auto-reconnect.
  Future<List<Map<String, String>>> getKnownPeersForDiscovery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final peersStr = prefs.getString(_knownPeersKey);
      if (peersStr == null) return [];

      final List<dynamic> peers = json.decode(peersStr);
      return peers
          .map((p) => <String, String>{
                'uuid': p['uuid'] ?? '',
                'name': p['name'] ?? '',
              })
          .toList();
    } catch (e) {
      return [];
    }
  }

  void dispose() {
    _stateChangeController.close();
  }
}
