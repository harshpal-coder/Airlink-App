import 'dart:async';
import '../models/device_model.dart';
import '../models/session_state.dart';
import '../utils/connectivity_logger.dart';
import 'discovery_service.dart';

/// Event emitted by the ReconnectionManager.
class ReconnectEvent {
  final String uuid;
  final String deviceName;
  final ReconnectEventType type;
  final int attemptNumber;
  final Duration? nextRetryIn;

  ReconnectEvent({
    required this.uuid,
    required this.deviceName,
    required this.type,
    this.attemptNumber = 0,
    this.nextRetryIn,
  });
}

enum ReconnectEventType {
  scheduled,
  attempting,
  succeeded,
  failed,
  gaveUp,
  cancelled,
}

/// Centralized reconnection engine with exponential backoff.
///
/// Manages reconnection state per device, schedules retries with
/// increasing delays, and emits events for monitoring.
class ReconnectionManager {
  final DiscoveryService _discoveryService;

  /// Ultra-aggressive backoff schedule in seconds: 0 (immediate), 1, 3, 7, 15, 30
  static const List<int> _backoffSchedule = [0, 1, 3, 7, 15, 30];

  /// Maximum number of reconnection attempts before giving up.
  static const int _maxAttempts = 15;

  /// Tracks active reconnection state per device UUID.
  final Map<String, _ReconnectState> _activeReconnections = {};

  final _eventController = StreamController<ReconnectEvent>.broadcast();
  Stream<ReconnectEvent> get events => _eventController.stream;

  ReconnectionManager({required DiscoveryService discoveryService})
      : _discoveryService = discoveryService;

  /// Schedule a reconnection attempt for a device.
  /// If already reconnecting, this is a no-op.
  void scheduleReconnect(Device device) {
    if (device.uuid == null) {
      ConnectivityLogger.warning(
        LogCategory.reconnection,
        'Cannot schedule reconnect for device without UUID: ${device.deviceName}',
      );
      return;
    }

    final uuid = device.uuid!;

    // Don't schedule if already connected or reconnecting
    if (device.state == SessionState.connected) return;
    if (_activeReconnections.containsKey(uuid) &&
        _activeReconnections[uuid]!.timer?.isActive == true) {
      ConnectivityLogger.debug(
        LogCategory.reconnection,
        'Reconnection already scheduled for ${device.deviceName}',
      );
      return;
    }

    final state = _activeReconnections[uuid] ?? _ReconnectState(device: device);
    _activeReconnections[uuid] = state;

    _scheduleNextAttempt(uuid);
  }

  /// Trigger an immediate reconnection burst for all disconnected peers.
  /// Useful for radio-on events or background-wake.
  void triggerImmediateBurst() {
    ConnectivityLogger.info(LogCategory.reconnection, 'Triggering immediate reconnection burst');
    final uuids = _activeReconnections.keys.toList();
    for (final uuid in uuids) {
      final state = _activeReconnections[uuid];
      if (state != null) {
        state.timer?.cancel();
        _attemptReconnect(uuid);
      }
    }
  }

  void _scheduleNextAttempt(String uuid) {
    final state = _activeReconnections[uuid];
    if (state == null) return;

    if (state.attemptCount >= _maxAttempts) {
      ConnectivityLogger.warning(
        LogCategory.reconnection,
        'Giving up on ${state.device.deviceName} after ${state.attemptCount} attempts',
      );
      _eventController.add(ReconnectEvent(
        uuid: uuid,
        deviceName: state.device.deviceName,
        type: ReconnectEventType.gaveUp,
        attemptNumber: state.attemptCount,
      ));
      _activeReconnections.remove(uuid);
      return;
    }

    // Calculate delay using backoff schedule
    final backoffIndex = state.attemptCount.clamp(0, _backoffSchedule.length - 1);
    final delaySeconds = _backoffSchedule[backoffIndex];
    final delay = Duration(seconds: delaySeconds);

    ConnectivityLogger.info(
      LogCategory.reconnection,
      'Scheduling reconnect to ${state.device.deviceName} in ${delaySeconds}s (attempt ${state.attemptCount + 1}/$_maxAttempts)',
    );

    _eventController.add(ReconnectEvent(
      uuid: uuid,
      deviceName: state.device.deviceName,
      type: ReconnectEventType.scheduled,
      attemptNumber: state.attemptCount + 1,
      nextRetryIn: delay,
    ));

    state.timer?.cancel();
    state.timer = Timer(delay, () => _attemptReconnect(uuid));
  }

  Future<void> _attemptReconnect(String uuid) async {
    final state = _activeReconnections[uuid];
    if (state == null) return;

    state.attemptCount++;

    // Get fresh device reference (endpoint ID may have changed)
    final device = _discoveryService.getDeviceByUuid(uuid);

    if (device == null) {
      ConnectivityLogger.debug(
        LogCategory.reconnection,
        'Device $uuid not in discovered list. Will retry on next scan.',
      );
      _scheduleNextAttempt(uuid);
      return;
    }

    // Already connected (perhaps via the other side initiating)
    if (device.state == SessionState.connected) {
      ConnectivityLogger.info(
        LogCategory.reconnection,
        '${device.deviceName} already connected. Cancelling reconnection.',
      );
      onConnectionRestored(uuid);
      return;
    }

    ConnectivityLogger.event(
      LogCategory.reconnection,
      'Attempting reconnect',
      data: {
        'device': device.deviceName,
        'attempt': state.attemptCount,
        'uuid': uuid,
      },
    );

    _eventController.add(ReconnectEvent(
      uuid: uuid,
      deviceName: device.deviceName,
      type: ReconnectEventType.attempting,
      attemptNumber: state.attemptCount,
    ));

    try {
      await _discoveryService.connect(device);

      // Ultra-short window: 300ms is enough for Nearby to start the handshake.
      await Future.delayed(const Duration(milliseconds: 300));

      // Check if connection succeeded
      final updatedDevice = _discoveryService.getDeviceByUuid(uuid);
      if (updatedDevice != null && updatedDevice.state == SessionState.connected) {
        onConnectionRestored(uuid);
      } else {
        ConnectivityLogger.debug(
          LogCategory.reconnection,
          'Reconnect attempt ${state.attemptCount} failed for ${device.deviceName}',
        );
        _eventController.add(ReconnectEvent(
          uuid: uuid,
          deviceName: device.deviceName,
          type: ReconnectEventType.failed,
          attemptNumber: state.attemptCount,
        ));
        _scheduleNextAttempt(uuid);
      }
    } catch (e) {
      ConnectivityLogger.error(
        LogCategory.reconnection,
        'Reconnect error for ${device.deviceName}',
        e,
      );
      _scheduleNextAttempt(uuid);
    }
  }

  /// Called when a connection is restored (either by us or the peer).
  /// Resets retry state and emits success event.
  void onConnectionRestored(String uuid) {
    final state = _activeReconnections.remove(uuid);
    if (state != null) {
      state.timer?.cancel();
      ConnectivityLogger.info(
        LogCategory.reconnection,
        'Connection restored to ${state.device.deviceName} after ${state.attemptCount} attempts',
      );
      _eventController.add(ReconnectEvent(
        uuid: uuid,
        deviceName: state.device.deviceName,
        type: ReconnectEventType.succeeded,
        attemptNumber: state.attemptCount,
      ));
    }
  }

  /// Cancel reconnection for a specific device.
  void cancelFor(String uuid) {
    final state = _activeReconnections.remove(uuid);
    if (state != null) {
      state.timer?.cancel();
      ConnectivityLogger.debug(
        LogCategory.reconnection,
        'Cancelled reconnection for ${state.device.deviceName}',
      );
      _eventController.add(ReconnectEvent(
        uuid: uuid,
        deviceName: state.device.deviceName,
        type: ReconnectEventType.cancelled,
      ));
    }
  }

  /// Cancel all active reconnections.
  void cancelAll() {
    for (final entry in _activeReconnections.entries) {
      entry.value.timer?.cancel();
    }
    _activeReconnections.clear();
    ConnectivityLogger.info(
      LogCategory.reconnection,
      'All reconnections cancelled',
    );
  }

  /// Returns true if actively trying to reconnect to the given UUID.
  bool isReconnecting(String uuid) => _activeReconnections.containsKey(uuid);

  /// Returns the number of active reconnection attempts.
  int get activeReconnectionCount => _activeReconnections.length;

  void dispose() {
    cancelAll();
    _eventController.close();
  }
}

class _ReconnectState {
  final Device device;
  int attemptCount = 0;
  Timer? timer;

  _ReconnectState({required this.device});
}
