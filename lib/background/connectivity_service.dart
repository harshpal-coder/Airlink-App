import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

@pragma('vm:entry-point')
class AirLinkConnectivityService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: 'airlink_mesh_v2', // Changed to v2 for silent channel
        initialNotificationTitle: 'AirLink Mesh Active', // title
        initialNotificationContent: 'Maintains offline mesh connectivity',
        foregroundServiceNotificationId: 1001,
        foregroundServiceTypes: [
          AndroidForegroundType.connectedDevice,
          AndroidForegroundType.location,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // NOTE: We cannot initialize DiscoveryService or MessagingService here
    // because they depend on nearby_connections, which requires an Activity.
    // Background services on Android run without an Activity.

    // Adaptive Notification Update & Radio Keep-Alive Timer
    Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (service is AndroidServiceInstance) {
        // Occasionally "poke" the discovery radio to prevent deep sleep
        // NOTE: We don't start/stop here because nearby_connections needs an activity,
        // but we can emit events that the main isolate listens to.
        service.invoke('keep_alive_poke');

        service.setForegroundNotificationInfo(
          title: "AirLink Active",
          content: "Mesh connectivity running in background",
        );
      }
    });

    debugPrint('[Background] AirLinkConnectivityService started and active');
  }
}
