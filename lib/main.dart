import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:isolate';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'services/database_helper.dart';
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
import 'services/adaptive_discovery_manager.dart';
import 'services/motion_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'background/background_tasks.dart';
import 'background/radio_state_receiver.dart';
import 'utils/connectivity_logger.dart';

import 'ui/screens/splash_screen.dart';
import 'ui/screens/profile_setup_screen.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/discovery_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/network_map_screen.dart';
import 'ui/screens/qr_link_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure database is ready
  await DatabaseHelper.instance.database;

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

  // ── Instantiate core services in dependency order ──
  final reputationService = ReputationService();
  final aiService = PeerAIService();
  final motionService = MotionService();
  motionService.start();

  // Link Motion to AI
  motionService.stateChanges.listen((state) {
    aiService.updateLocalMotionState(state);
  });

  final discoveryService = DiscoveryService(
    reputationService: reputationService,
    aiService: aiService,
  );

  final heartbeatManager = HeartbeatManager(
    discoveryService: discoveryService,
  );

  final reconnectionManager = ReconnectionManager(
    discoveryService: discoveryService,
    reputationService: reputationService,
  );
  // Wire the instant-disconnect callback so peer drops trigger an immediate
  // reconnect attempt (attempt 0 = no delay) instead of waiting for the next
  // periodic refresh cycle.
  reconnectionManager.installOn(discoveryService);

  final connectivityStateMonitor = ConnectivityStateMonitor();

  final messageQueueManager = MessageQueueManager(
    discoveryService: discoveryService,
  );

  final messagingService = MessagingService(
    discoveryService: discoveryService,
    heartbeatManager: heartbeatManager,
    messageQueueManager: messageQueueManager,
    reputationService: reputationService,
    aiService: aiService,
  );

  final adaptiveDiscoveryManager = AdaptiveDiscoveryManager(
    discoveryService: discoveryService,
  );
  adaptiveDiscoveryManager.start();

  // ── Wire cross-manager event listeners ──

  // HeartbeatManager → ReconnectionManager: auto-reconnect on peer loss
  heartbeatManager.events.listen((event) {
    if (event.type == HeartbeatEventType.peerLost) {
      final device = discoveryService.getDeviceByUuid(event.uuid);
      if (device != null) {
        reconnectionManager.scheduleReconnect(device);
        connectivityStateMonitor.updateState(
          uuid: event.uuid,
          deviceName: event.deviceName,
          isConnected: false,
        );
      }
    }
  });

  // ReconnectionManager → MessageQueueManager: flush queue on reconnect
  reconnectionManager.events.listen((event) {
    if (event.type == ReconnectEventType.succeeded) {
      messageQueueManager.processQueueForPeer(event.uuid);
      connectivityStateMonitor.updateState(
        uuid: event.uuid,
        deviceName: event.deviceName,
        isConnected: true,
      );
    }
  });

  // Restore connection state from previous session (crash recovery)
  final previouslyConnected = await connectivityStateMonitor.restoreState();
  if (previouslyConnected.isNotEmpty) {
    ConnectivityLogger.info(
      LogCategory.connection,
      'Will reconnect to ${previouslyConnected.length} previously connected peers',
    );
  }

  // ── Radio State Handler — BT/WiFi on/off detection ──
  final radioStateHandler = RadioStateHandler();
  radioStateHandler.init(
    onStateChanged: (radioType, enabled) {
      discoveryService.onRadioStateChanged(radioType, enabled);
      if (enabled) {
        // When radio (BT/WiFi) is turned back on, immediately try to reconnect to all lost peers
        reconnectionManager.triggerImmediateBurst();
      }
    },
  );

  // ── Background Service Bridge ──
  final bgService = FlutterBackgroundService();

  bgService.on('keep_alive_poke').listen((_) {
    ConnectivityLogger.debug(LogCategory.background, 'Received keep-alive poke');
    discoveryService.refreshRadio();
  });

  bgService.on('save_connection_state').listen((_) {
    connectivityStateMonitor.saveState();
    discoveryService.persistDiscoveryState();
  });

  bgService.on('flush_message_queue').listen((_) {
    messageQueueManager.processAllQueues();
  });

  bgService.on('connectivity_restore').listen((_) async {
    ConnectivityLogger.info(LogCategory.background, 'Connectivity restore triggered');
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
        
        debugPrint('[Main] Received notification reply to send to $peerName ($peerUuid): $replyText');
        await messagingService.sendTextMessage(peerUuid, peerName, replyText);
      }
    } catch (e) {
      debugPrint('[Main] Error handling notification reply: $e');
    }
  });

  runApp(MyApp(
    discoveryService: discoveryService,
    messagingService: messagingService,
    reconnectionManager: reconnectionManager,
    heartbeatManager: heartbeatManager,
    connectivityStateMonitor: connectivityStateMonitor,
    messageQueueManager: messageQueueManager,
    reputationService: reputationService,
  ));
}

class MyApp extends StatelessWidget {
  final DiscoveryService discoveryService;
  final MessagingService messagingService;
  final ReconnectionManager reconnectionManager;
  final HeartbeatManager heartbeatManager;
  final ConnectivityStateMonitor connectivityStateMonitor;
  final MessageQueueManager messageQueueManager;
  final ReputationService reputationService;

  const MyApp({
    super.key,
    required this.discoveryService,
    required this.messagingService,
    required this.reconnectionManager,
    required this.heartbeatManager,
    required this.connectivityStateMonitor,
    required this.messageQueueManager,
    required this.reputationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatProvider(
            discoveryService: discoveryService,
            messagingService: messagingService,
            reconnectionManager: reconnectionManager,
            heartbeatManager: heartbeatManager,
            connectivityStateMonitor: connectivityStateMonitor,
            messageQueueManager: messageQueueManager,
            reputationService: reputationService,
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/profile_setup': (context) => const ProfileSetupScreen(),
          '/home': (context) => const MainScreen(),
          '/discovery': (context) => const DiscoveryScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/network_map': (context) => const NetworkMapScreen(),
          '/qr_link': (context) => const QrLinkScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/chat') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) {
                return ChatScreen(
                  peerUuid: args['peerUuid'],
                  peerName: args['peerName'],
                  peerProfileImage: args['peerProfileImage'],
                );
              },
            );
          }
          return null;
        },
      ),
    );
  }
}
