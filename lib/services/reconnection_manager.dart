import 'dart:async';
import 'dart:math';
import '../models/device_model.dart';
import '../models/session_state.dart';
import '../utils/connectivity_logger.dart';
import 'discovery_service.dart';
import 'reputation_service.dart';
import '../core/event_bus.dart';
import '../core/app_events.dart';

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
  final ReputationService _reputationService;

  /// Ultra-aggressive backoff schedule in seconds: 0 (immediate), 1, 3, 7, 15, 30
  static const List<int> _backoffSchedule = [0, 1, 3, 7, 15, 30];

  /// Maximum number of reconnection attempts before giving up (or switching to monitoring).
  static const int _maxAttempts = 15;

  /// Reputation score above which we keep trying indefinitely (Long-term Monitoring).
  static const double _minHighReputationScore = 70.0;

  /// Interval for long-term monitoring of stable but currently missing peers.
  static const Duration _longTermMonitoringInterval = Duration(minutes: 5);

  /// Tracks active reconnection state per device UUID.
  final Map<String, _ReconnectState> _activeReconnections = {};

  final _eventController = StreamController<ReconnectEvent>.broadcast();
  Stream<ReconnectEvent> get events => _eventController.stream;

  final _random = Random();

  /// Timers waiting for onConnectionResult to fire after a connect() call.
  /// If the callback fires first, the timer is cancelled. If not, we schedule
  /// the next backoff step — avoiding the fragile 300ms state poll.
  final Map<String, Timer> _pendingConnectionTimers = {};

  ReconnectionManager({
    required DiscoveryService discoveryService,
    required ReputationService reputationService,
  })  : _discoveryService = discoveryService,
        _reputationService = reputationService;

  /// Wire this manager into [discoveryService] so that direct peer disconnections
  /// immediately schedule a reconnect (attempt 0 = instant, no delay).
  void installOn(DiscoveryService discoveryService) {
    discoveryService.onDirectDisconnect = (device) {
      ConnectivityLogger.info(
        LogCategory.reconnection,
        'Direct disconnect from ${device.deviceName} — scheduling instant reconnect',
      );
      scheduleReconnect(device);
    };
    
    // Periodically sync known devices (every 2 mins) to catch devices that 
    // were never connected in this session but are in the "Known" list.
    Timer.periodic(const Duration(minutes: 2), (_) => _syncKnownDevices());
    _syncKnownDevices(); // Initial sync
  }

  void _syncKnownDevices() {
    final known = _discoveryService.knownDevices;
    for (var entry in known.entries) {
      final uuid = entry.key;
      final name = entry.value;
      
      final device = _discoveryService.getDeviceByUuid(uuid);
      if (device != null && device.state == SessionState.notConnected) {
        if (!_activeReconnections.containsKey(uuid)) {
           ConnectivityLogger.debug(
             LogCategory.reconnection,
             'Proactive sync: scheduling reconnect for known device $name ($uuid)',
           );
           scheduleReconnect(device);
        }
      }
    }
  }

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

  Future<void> _scheduleNextAttempt(String uuid) async {
    final state = _activeReconnections[uuid];
    if (state == null) return;

    // Check reputation to see if we should give up or switch to long-term monitoring
    final reputation = await _reputationService.getReputation(uuid);
    final score = (reputation?['composite_score'] as num?)?.toDouble() ?? 50.0;

    if (state.attemptCount >= _maxAttempts) {
      if (score >= _minHighReputationScore) {
        ConnectivityLogger.info(
          LogCategory.reconnection,
          'Switching to long-term monitoring (every 5m) for stable peer ${state.device.deviceName} (Score: ${score.toStringAsFixed(1)})',
        );
        
        state.timer?.cancel();
        state.timer = Timer(_longTermMonitoringInterval, () => _attemptReconnect(uuid));
        
        _eventController.add(ReconnectEvent(
          uuid: uuid,
          deviceName: state.device.deviceName,
          type: ReconnectEventType.scheduled,
          attemptNumber: state.attemptCount,
          nextRetryIn: _longTermMonitoringInterval,
        ));
        return;
      }

      ConnectivityLogger.warning(
        LogCategory.reconnection,
        'Giving up on ${state.device.deviceName} after ${state.attemptCount} attempts (Score: ${score.toStringAsFixed(1)})',
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

    // Calculate delay using backoff schedule + Reputation Multiplier
    // If score is very high (>80), we can retry slightly faster
    double multiplier = 1.0;
    if (score >= 85) {
      multiplier = 0.7; // 30% faster retries for highly stable peers
    } else if (score < 40) {
      multiplier = 1.5; // 50% slower retries for unstable peers
    }

    final backoffIndex = state.attemptCount.clamp(0, _backoffSchedule.length - 1);
    var delaySeconds = (_backoffSchedule[backoffIndex] * multiplier).round();
    
    // For the very first attempt (0s), add a small sub-second jitter to prevent collisions
    int delayMillis = delaySeconds * 1000;
    if (state.attemptCount == 0) {
      delayMillis = _random.nextInt(800); // 0-800ms jitter
    }

    // Add jitter (±15% or min 1s) to avoid collisions for subsequent attempts
    final jitter = (delaySeconds * 0.15).round();
    if (jitter > 0) {
      delayMillis += (_random.nextInt(jitter * 2) - jitter) * 1000;
    }
    
    final delay = Duration(milliseconds: max(0, delayMillis));

    ConnectivityLogger.info(
      LogCategory.reconnection,
      'Scheduling reconnect to ${state.device.deviceName} in ${delay.inSeconds}s (attempt ${state.attemptCount + 1}/$_maxAttempts, score: ${score.toStringAsFixed(1)})',
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
      // Boost discovery radio temporarily if this is a high-priority peer
      final reputation = await _reputationService.getReputation(uuid);
      final score = (reputation?['composite_score'] as num?)?.toDouble() ?? 50.0;
      if (score >= _minHighReputationScore) {
        _discoveryService.boostDiscovery();
      }

      await _discoveryService.connect(device);

      // Don't poll state — onConnectionResult fires the callback which calls
      // onConnectionRestored(). We set a 2s safety timeout in case the callback
      // never arrives (e.g. the platform swallows the result).
      _pendingConnectionTimers[uuid]?.cancel();
      _pendingConnectionTimers[uuid] = Timer(const Duration(seconds: 4), () { // Increased to 4s for reliability
        _pendingConnectionTimers.remove(uuid);
        // Only retry if we're still not connected
        final check = _discoveryService.getDeviceByUuid(uuid);
        if (check != null && check.state != SessionState.connected) {
          _reputationService.recordConnectionEvent(uuid, false);
          ConnectivityLogger.debug(
            LogCategory.reconnection,
            'No connection result within 4s for ${device.deviceName}. Scheduling next attempt.',
          );
          _eventController.add(ReconnectEvent(
            uuid: uuid,
            deviceName: device.deviceName,
            type: ReconnectEventType.failed,
            attemptNumber: state.attemptCount,
          ));
          _scheduleNextAttempt(uuid);
        }
      });
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
    _pendingConnectionTimers.remove(uuid)?.cancel();
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
      // Publish to Global Event Bus
      appEventBus.fire(ReconnectSucceededEvent(uuid: uuid, deviceName: state.device.deviceName));
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
    for (final t in _pendingConnectionTimers.values) {
      t.cancel();
    }
    _pendingConnectionTimers.clear();
    _eventController.close();
  }
}

class _ReconnectState {
  final Device device;
  int attemptCount = 0;
  Timer? timer;

  _ReconnectState({required this.device});
}
