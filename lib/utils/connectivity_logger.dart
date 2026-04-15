import 'package:flutter/foundation.dart';

/// Structured logging categories for the connectivity system.
enum LogCategory {
  discovery,
  connection,
  heartbeat,
  reconnection,
  messageQueue,
  background,
  radio,
}

/// Structured logging for all connectivity events.
/// Provides consistent, filterable logs across the entire connectivity system.
class ConnectivityLogger {
  static const Map<LogCategory, String> _prefixes = {
    LogCategory.discovery: 'Discovery',
    LogCategory.connection: 'Connection',
    LogCategory.heartbeat: 'Heartbeat',
    LogCategory.reconnection: 'Reconnect',
    LogCategory.messageQueue: 'MsgQueue',
    LogCategory.background: 'Background',
    LogCategory.radio: 'Radio',
  };

  static void debug(LogCategory category, String message) {
    debugPrint('[AirLink:${_prefixes[category]}] $message');
  }

  static void info(LogCategory category, String message) {
    debugPrint('[AirLink:${_prefixes[category]}] ℹ️ $message');
  }

  static void warning(LogCategory category, String message) {
    debugPrint('[AirLink:${_prefixes[category]}] ⚠️ $message');
  }

  static void error(LogCategory category, String message, [Object? error]) {
    debugPrint('[AirLink:${_prefixes[category]}] ❌ $message${error != null ? ' | Error: $error' : ''}');
  }

  static void event(LogCategory category, String event, {Map<String, dynamic>? data}) {
    final dataStr = data != null ? ' | ${data.entries.map((e) => '${e.key}=${e.value}').join(', ')}' : '';
    debugPrint('[AirLink:${_prefixes[category]}] 📡 $event$dataStr');
  }
}
