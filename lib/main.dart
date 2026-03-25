import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:isolate';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/discovery_service.dart';
import 'services/messaging_service.dart';
import 'services/peer_ai_service.dart';
import 'services/notification_service.dart';
import 'services/chat_provider.dart';
import 'services/heartbeat_manager.dart';
import 'services/reconnection_manager.dart';
import 'services/reputation_service.dart';
import 'services/connectivity_state_monitor.dart';
import 'services/message_queue_manager.dart';
import 'services/database_helper.dart';
import 'services/adaptive_discovery_manager.dart';
import 'services/motion_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'background/background_tasks.dart';
import 'background/radio_state_receiver.dart';

import 'ui/screens/splash_screen.dart';
import 'ui/screens/profile_setup_screen.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/discovery_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/network_map_screen.dart';
import 'ui/screens/qr_link_screen.dart';
import 'repositories/chat_repository.dart';
import 'injection.dart';
import 'core/event_bus.dart';
import 'core/app_events.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure database is ready
  await DatabaseHelper.instance.database;

  // Setup Dependency Injection
  setupInjection();

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize notification service
  await NotificationService.init();

  // Initialize and schedule background maintenance tasks
  if (!kIsWeb) {
    await AirLinkBackgroundTasks.init();
    await AirLinkBackgroundTasks.scheduleMaintenance();
  }

  // ── Access services via Service Locator ──
  getIt<ReputationService>(); 
  final aiService = getIt<PeerAIService>();
  final motionService = getIt<MotionService>();
  final discoveryService = getIt<DiscoveryService>();
  getIt<HeartbeatManager>();
  final reconnectionManager = getIt<ReconnectionManager>();
  final connectivityStateMonitor = getIt<ConnectivityStateMonitor>();
  final messageQueueManager = getIt<MessageQueueManager>();
  final messagingService = getIt<MessagingService>();
  final adaptiveDiscoveryManager = getIt<AdaptiveDiscoveryManager>();

  // Start standalone monitoring services
  motionService.start();
  adaptiveDiscoveryManager.start();

  // Wire Motion to AI
  motionService.stateChanges.listen((state) {
    aiService.updateLocalMotionState(state);
  });

  // Wire the instant-disconnect callback
  reconnectionManager.installOn(discoveryService);

  // ── Wire cross-manager events via Event Bus ──

  // Peer Lost → Reconnect
  appEventBus.on<PeerLostEvent>().listen((event) {
    final device = discoveryService.getDeviceByUuid(event.uuid);
    if (device != null) {
      reconnectionManager.scheduleReconnect(device);
      connectivityStateMonitor.updateState(
        uuid: event.uuid,
        deviceName: event.deviceName,
        isConnected: false,
      );
    }
  });

  // Reconnect Succeeded → Flush Queue
  appEventBus.on<ReconnectSucceededEvent>().listen((event) {
    messageQueueManager.processQueueForPeer(event.uuid);
    connectivityStateMonitor.updateState(
      uuid: event.uuid,
      deviceName: event.deviceName,
      isConnected: true,
    );
  });

  // Restore connection state from previous session
  await connectivityStateMonitor.restoreState();

  // ── Radio State Handler ──
  final radioStateHandler = RadioStateHandler();
  radioStateHandler.init(
    onStateChanged: (radioType, enabled) {
      discoveryService.onRadioStateChanged(radioType, enabled);
      appEventBus.fire(RadioStateChangedEvent(radioType: radioType, isEnabled: enabled));
      if (enabled) {
        reconnectionManager.triggerImmediateBurst();
      }
    },
  );

  // ── Background Service Bridge ──
  final bgService = FlutterBackgroundService();

  bgService.on('keep_alive_poke').listen((_) {
    discoveryService.refreshRadio();
    appEventBus.fire(BackgroundPokeEvent());
  });

  bgService.on('save_connection_state').listen((_) {
    connectivityStateMonitor.saveState();
    discoveryService.persistDiscoveryState();
  });

  bgService.on('flush_message_queue').listen((_) {
    messageQueueManager.processAllQueues();
  });

  bgService.on('connectivity_restore').listen((_) async {
    await discoveryService.restoreDiscoveryState();
  });

  // ── Notification Action Reply Port ──
  final ReceivePort notificationReceivePort = ReceivePort();
  IsolateNameServer.removePortNameMapping('notification_reply_port');
  IsolateNameServer.registerPortWithName(notificationReceivePort.sendPort, 'notification_reply_port');
  
  notificationReceivePort.listen((message) async {
    try {
      if (message is Map<String, dynamic>) {
        final String peerUuid = message['peerUuid'];
        final String replyText = message['text'];
        
        final chat = await DatabaseHelper.instance.getChatByPeerUuid(peerUuid);
        final peerName = chat?.peerName ?? 'Unknown';
        
        await messagingService.sendTextMessage(peerUuid, peerName, replyText);
      }
    } catch (e) {
      debugPrint('[Main] Error handling notification reply: $e');
    }
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatProvider(
            discoveryService: getIt<DiscoveryService>(),
            messagingService: getIt<MessagingService>(),
            reconnectionManager: getIt<ReconnectionManager>(),
            heartbeatManager: getIt<HeartbeatManager>(),
            connectivityStateMonitor: getIt<ConnectivityStateMonitor>(),
            messageQueueManager: getIt<MessageQueueManager>(),
            reputationService: getIt<ReputationService>(),
            chatRepository: getIt<ChatRepository>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Airlink',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/profile_setup': (context) => const ProfileSetupScreen(),
          '/main': (context) => const MainScreen(),
          '/discovery': (context) => const DiscoveryScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/network_map': (context) => const NetworkMapScreen(),
          '/qr_link': (context) => const QrLinkScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/chat') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) => ChatScreen(
                peerUuid: args['peerUuid'],
                peerName: args['peerName'],
                peerProfileImage: args['peerProfileImage'],
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}
