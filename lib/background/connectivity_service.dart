import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:intl/intl.dart';

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
        notificationChannelId: 'airlink_mesh_v2',
        initialNotificationTitle: 'AirLink Mesh Active',
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

    // On service start/restart, trigger connectivity restoration
    // This is critical for crash/kill recovery
    service.invoke('connectivity_restore');

    // Adaptive Notification Update & Radio Keep-Alive Timer
    Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (service is AndroidServiceInstance) {
        // Poke the main isolate to keep discovery radio alive
        service.invoke('keep_alive_poke');
        
        // Trigger periodic state save
        service.invoke('save_connection_state');

        final now = DateTime.now();
        final timeString = DateFormat('hh:mm:ss a').format(now);

        service.setForegroundNotificationInfo(
          title: "AirLink Active",
          content: "Mesh connectivity running • $timeString",
        );
      }
    });

    // Slower timer for message queue flush (every 2 minutes)
    Timer.periodic(const Duration(minutes: 2), (timer) async {
      service.invoke('flush_message_queue');
    });

    debugPrint('[Background] AirLinkConnectivityService started and active');
  }
}

