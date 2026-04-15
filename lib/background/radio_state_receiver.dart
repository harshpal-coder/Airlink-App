import 'package:flutter/services.dart';
import '../utils/connectivity_logger.dart';

/// Callback type for radio state changes.
typedef RadioStateCallback = void Function(String radioType, bool enabled);

/// Flutter-side handler for native BroadcastReceiver events.
///
/// Listens on MethodChannel 'com.airlink/radio_state' for
/// Bluetooth and WiFi state changes from native Android.
class RadioStateHandler {
  static const _channel = MethodChannel('com.airlink/radio_state');

  RadioStateCallback? onRadioStateChanged;

  bool _bluetoothEnabled = true;
  bool _wifiEnabled = true;

  bool get isBluetoothEnabled => _bluetoothEnabled;
  bool get isWifiEnabled => _wifiEnabled;

  /// Initialize the MethodChannel listener.
  void init({RadioStateCallback? onStateChanged}) {
    onRadioStateChanged = onStateChanged;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRadioStateChanged') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String type = args['type'] ?? '';
        final bool enabled = args['enabled'] ?? false;

        ConnectivityLogger.event(
          LogCategory.radio,
          '$type ${enabled ? "ON" : "OFF"}',
        );

        if (type == 'bluetooth') {
          _bluetoothEnabled = enabled;
        } else if (type == 'wifi') {
          _wifiEnabled = enabled;
        }

        onRadioStateChanged?.call(type, enabled);
      }
    });

    ConnectivityLogger.info(
      LogCategory.radio,
      'RadioStateHandler initialized — listening for BT/WiFi state changes',
    );
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
