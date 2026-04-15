import 'dart:ui';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[WorkManager] Executing task: $task');
    
    try {
      final service = FlutterBackgroundService();
      bool isRunning = await service.isRunning();
      
      if (!isRunning) {
        debugPrint('[WorkManager] Background service NOT running. Triggering restart...');
        await service.startService();
        // Give the service a moment to start, then trigger restoration
        await Future.delayed(const Duration(seconds: 2));
        service.invoke('connectivity_restore');
      } else {
        debugPrint('[WorkManager] Background service is healthy. Triggering maintenance cycle...');
        service.invoke('keep_alive_poke');
        service.invoke('save_connection_state');
        service.invoke('flush_message_queue');
      }
      
      return Future.value(true);
    } catch (e) {
      debugPrint('[WorkManager] Error during maintenance task: $e');
      return Future.value(false);
    }
  });
}

class AirLinkBackgroundTasks {
  static const String maintenanceTask = "com.example.airlink.maintenance";

  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> scheduleMaintenance() async {
    await Workmanager().registerPeriodicTask(
      "1", // Unique ID
      maintenanceTask,
      frequency: const Duration(minutes: 15), // Android minimum
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
    debugPrint('[WorkManager] Maintenance task scheduled (15 min interval)');
  }
}

