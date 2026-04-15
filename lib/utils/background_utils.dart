import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class BackgroundUtils {
  static Future<bool> isBatteryOptimizationIgnored() async {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status.isDenied) {
      await openAppSettings();
    }
  }

  /// Get the device manufacturer for OEM-specific guidance.
  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return 'unknown';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.manufacturer.toLowerCase();
    } catch (_) {
      return 'unknown';
    }
  }

  /// Returns OEM-specific battery optimization instructions.
  static Future<String> getBatteryOptimizationGuide() async {
    final manufacturer = await getDeviceManufacturer();

    switch (manufacturer) {
      case 'samsung':
        return samsungGuide;
      case 'xiaomi':
      case 'redmi':
      case 'poco':
        return xiaomiGuide;
      case 'huawei':
      case 'honor':
        return huaweiGuide;
      case 'oneplus':
        return oneplusGuide;
      case 'oppo':
      case 'realme':
        return oppoGuide;
      case 'vivo':
        return vivoGuide;
      default:
        return commonBackgroundGuide;
    }
  }

  /// Launch the battery optimization settings directly.
  static Future<void> launchBatteryOptimizationSettings() async {
    await openAppSettings();
  }

  // ── OEM-specific guides ──

  static const String samsungGuide =
    "Samsung — Keep AirLink Running:\n"
    "1. Open Recent Apps → tap AirLink icon → 'Keep open'\n"
    "2. Settings → Battery → Background usage limits\n"
    "   → Remove AirLink from 'Sleeping' and 'Deep sleeping'\n"
    "3. Settings → Apps → AirLink → Battery → Unrestricted";

  static const String xiaomiGuide =
    "Xiaomi/Redmi/POCO — Keep AirLink Running:\n"
    "1. Settings → Apps → Manage apps → AirLink\n"
    "   → Autostart: ON\n"
    "2. Battery saver → No restrictions for AirLink\n"
    "3. Security app → Permissions → Autostart → Enable AirLink\n"
    "4. Lock AirLink in Recent Apps (swipe down on card)";

  static const String huaweiGuide =
    "Huawei/Honor — Keep AirLink Running:\n"
    "1. Settings → Apps → AirLink → Battery → Enable all\n"
    "2. Settings → Battery → App launch → AirLink → Manage manually\n"
    "   → Enable: Auto-launch, Secondary launch, Run in background\n"
    "3. Lock AirLink in Recent Apps";

  static const String oneplusGuide =
    "OnePlus — Keep AirLink Running:\n"
    "1. Settings → Battery → Battery optimization\n"
    "   → All apps → AirLink → Don't optimize\n"
    "2. Settings → Apps → AirLink → Battery → No restrictions\n"
    "3. Lock AirLink in Recent Apps";

  static const String oppoGuide =
    "OPPO/Realme — Keep AirLink Running:\n"
    "1. Settings → Apps → AirLink → Battery usage → Allow\n"
    "2. Settings → Battery → Energy Saver\n"
    "   → AirLink: Allow Background running\n"
    "3. Lock AirLink in Recent Apps (swipe down on card)";

  static const String vivoGuide =
    "Vivo — Keep AirLink Running:\n"
    "1. Settings → Battery → Background power consumption\n"
    "   → AirLink → Allow\n"
    "2. Settings → Apps → Autostart → Enable AirLink\n"
    "3. Lock AirLink in Recent Apps";

  static const String samsungLockGuide =
    "1. Open Recent Apps (swipe up and hold).\n"
    "2. Tap the App Icon above the AirLink window.\n"
    "3. Select 'Keep open' or 'Lock this app'.";

  static const String commonBackgroundGuide =
    "1. Go to App Info > Battery.\n"
    "2. Select 'Unrestricted' or 'No restrictions'.\n"
    "3. Enable 'Allow background activity' if available.\n"
    "4. Lock AirLink in Recent Apps to prevent it being killed.";
}
