import 'package:permission_handler/permission_handler.dart';

class BackgroundUtils {
  static Future<bool> isBatteryOptimizationIgnored() async {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status.isDenied) {
      // If the direct request is denied or not supported on some OS versions,
      // we can try to open the battery optimization settings manually.
      await openAppSettings();
    }
  }

  static const String samsungLockGuide = 
    "1. Open Recent Apps (swipe up and hold).\n"
    "2. Tap the App Icon above the AirLink window.\n"
    "3. Select 'Keep open' or 'Lock this app'.";

  static const String commonBackgroundGuide = 
    "1. Go to App Info > Battery.\n"
    "2. Select 'Unrestricted' or 'No restrictions'.\n"
    "3. Enable 'Allow background activity' if available.";
}
