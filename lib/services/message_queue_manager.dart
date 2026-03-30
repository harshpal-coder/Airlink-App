import 'dart:async';
import '../utils/connectivity_logger.dart';
import '../models/message_model.dart';
import 'database_helper.dart';
import 'discovery_service.dart';
import '../models/session_state.dart';
import '../core/event_bus.dart';
import '../core/app_events.dart';

/// Persistent message queue with guaranteed delivery.
///
/// Manages queued/failed messages and automatically retries them
/// when connections are restored.
class MessageQueueManager {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final DiscoveryService _discoveryService;

  /// Maximum retry attempts before permanently marking a message as failed.
  static const int _maxRetries = 5;

  /// Retry backoff delays in seconds.
  static const List<int> _retryDelays = [1, 3, 5, 10, 30];

  /// Track retry counts per message ID.
  final Map<String, int> _retryCounts = {};

  /// Callback for actually resending a message (set by MessagingService).
  Future<void> Function(String messageId)? onResendMessage;

  /// Track active retry timers to prevent leaks.
  final Map<String, Timer> _activeRetryTimers = {};

  final _queueUpdatedController = StreamController<void>.broadcast();
  Stream<void> get queueUpdated => _queueUpdatedController.stream;

  MessageQueueManager({required DiscoveryService discoveryService})
      : _discoveryService = discoveryService;

  /// Enqueue a message for later delivery.
  /// The message should already be saved in the database with queued status.
  Future<void> enqueue(Message message) async {
    ConnectivityLogger.info(
      LogCategory.messageQueue,
      'Message ${message.id} queued for ${message.receiverUuid}',
    );
    _queueUpdatedController.add(null);
  }

  /// Process the message queue for a specific peer that just connected.
  /// This is the main entry point when a connection is restored.
  Future<int> processQueueForPeer(String peerUuid) async {
    final queuedMessages = await _dbHelper.getQueuedMessages(peerUuid);
    if (queuedMessages.isEmpty) return 0;

    ConnectivityLogger.info(
      LogCategory.messageQueue,
      'Processing ${queuedMessages.length} queued messages for $peerUuid',
    );

    int sentCount = 0;
    for (final message in queuedMessages) {
      // Verify peer is still connected before each send
      final device = _discoveryService.getDeviceByUuid(peerUuid);
      if (device == null || device.state != SessionState.connected) {
        ConnectivityLogger.warning(
          LogCategory.messageQueue,
          'Peer $peerUuid disconnected during queue processing. Stopping.',
        );
        break;
      }

      final retryCount = _retryCounts[message.id] ?? 0;
      if (retryCount >= _maxRetries) {
        ConnectivityLogger.warning(
          LogCategory.messageQueue,
          'Message ${message.id} exceeded max retries. Marking as failed.',
        );
        await _dbHelper.insertMessage(
          message.copyWith(status: MessageStatus.failed),
        );
        _retryCounts.remove(message.id);
        continue;
      }

      try {
        if (onResendMessage != null) {
          await onResendMessage!(message.id);
          _retryCounts.remove(message.id);
          sentCount++;
          ConnectivityLogger.event(
            LogCategory.messageQueue,
            'Queued message delivered',
            data: {'messageId': message.id, 'peer': peerUuid},
          );
        }
      } catch (e) {
        _retryCounts[message.id] = retryCount + 1;
        ConnectivityLogger.error(
          LogCategory.messageQueue,
          'Failed to resend message ${message.id} (retry ${retryCount + 1}/$_maxRetries)',
          e,
        );

        // Schedule a delayed retry if connection is still active
        final delayIndex = retryCount.clamp(0, _retryDelays.length - 1);
        _activeRetryTimers[message.id]?.cancel();
        _activeRetryTimers[message.id] = Timer(Duration(seconds: _retryDelays[delayIndex]), () {
          _activeRetryTimers.remove(message.id);
          final dev = _discoveryService.getDeviceByUuid(peerUuid);
          if (dev != null && dev.state == SessionState.connected) {
            processQueueForPeer(peerUuid);
          }
        });
        break; // Don't continue with remaining messages after a failure
      }
    }

    if (sentCount > 0) {
      _queueUpdatedController.add(null);
      ConnectivityLogger.info(
        LogCategory.messageQueue,
        'Delivered $sentCount queued messages to $peerUuid',
      );
    }

    return sentCount;
  }

  /// Process queues for all currently connected peers.
  Future<void> processAllQueues() async {
    final connected = _discoveryService.getConnectedDevices();
    for (final device in connected) {
      if (device.uuid != null) {
        await processQueueForPeer(device.uuid!);
      }
    }
  }

  /// Get the count of pending messages in the queue.
  Future<int> getPendingCount() async {
    int total = 0;
    final connected = _discoveryService.getConnectedDevices();
    for (final device in connected) {
      if (device.uuid != null) {
        final msgs = await _dbHelper.getQueuedMessages(device.uuid!);
        total += msgs.length;
      }
    }
    return total;
  }

  /// Clear all retry counts (useful on app restart).
  void clearRetryCounts() {
    _retryCounts.clear();
  }

  /// Wire this manager to the global event bus.
  ///
  /// When [ReconnectSucceededEvent] fires, immediately flushes all queued
  /// messages for that peer so they are delivered within milliseconds of
  /// the connection being restored — not on the next manual send attempt.
  ///
  /// Call this **once** from your injection / setup code after
  /// [ReconnectionManager.installOn] has been called.
  void installOn() {
    appEventBus.on<ReconnectSucceededEvent>().listen((event) {
      ConnectivityLogger.info(
        LogCategory.messageQueue,
        'ReconnectSucceededEvent for ${event.deviceName} — flushing queued messages',
      );
      // Small delay to let the transport layer fully stabilise before sending.
      Future.delayed(const Duration(milliseconds: 200), () {
        processQueueForPeer(event.uuid);
      });
    });
  }

  void dispose() {
    clearRetryCounts();
    for (var timer in _activeRetryTimers.values) {
      timer.cancel();
    }
    _activeRetryTimers.clear();
    _queueUpdatedController.close();
  }
}
