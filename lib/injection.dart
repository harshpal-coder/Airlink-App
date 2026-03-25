import 'package:get_it/get_it.dart';
import 'services/database_helper.dart';
import 'services/reputation_service.dart';
import 'services/peer_ai_service.dart';
import 'services/motion_service.dart';
import 'services/discovery_service.dart';
import 'services/heartbeat_manager.dart';
import 'services/reconnection_manager.dart';
import 'services/connectivity_state_monitor.dart';
import 'services/message_queue_manager.dart';
import 'services/messaging_service.dart';
import 'services/adaptive_discovery_manager.dart';
import 'repositories/chat_repository.dart';
import 'encryption/signal_protocol_service.dart';

final getIt = GetIt.instance;

/// Setup Dependency Injection for all core services.
/// Note: Services are registered in dependency order or as lazy singletons.
void setupInjection() {
  // 0. Security Services
  getIt.registerSingleton<SignalProtocolService>(SignalProtocolService());

  // 1. Independent Services
  getIt.registerSingleton<ReputationService>(ReputationService());
  getIt.registerSingleton<PeerAIService>(PeerAIService());
  getIt.registerSingleton<MotionService>(MotionService());
  getIt.registerSingleton<ConnectivityStateMonitor>(ConnectivityStateMonitor());

  // 2. Network Stack (Level 1)
  getIt.registerLazySingleton<DiscoveryService>(() => DiscoveryService(
    reputationService: getIt<ReputationService>(),
    aiService: getIt<PeerAIService>(),
  ));

  // 3. Management Stack (Level 2)
  getIt.registerLazySingleton<HeartbeatManager>(() => HeartbeatManager(
    discoveryService: getIt<DiscoveryService>(),
  ));

  getIt.registerLazySingleton<ReconnectionManager>(() => ReconnectionManager(
    discoveryService: getIt<DiscoveryService>(),
    reputationService: getIt<ReputationService>(),
  ));

  getIt.registerLazySingleton<MessageQueueManager>(() => MessageQueueManager(
    discoveryService: getIt<DiscoveryService>(),
  ));

  getIt.registerLazySingleton<AdaptiveDiscoveryManager>(() => AdaptiveDiscoveryManager(
    discoveryService: getIt<DiscoveryService>(),
  ));

  // 4. Core Messaging Logic (Level 3 - depends on everything)
  getIt.registerLazySingleton<MessagingService>(() => MessagingService(
    discoveryService: getIt<DiscoveryService>(),
    heartbeatManager: getIt<HeartbeatManager>(),
    messageQueueManager: getIt<MessageQueueManager>(),
    reputationService: getIt<ReputationService>(),
    aiService: getIt<PeerAIService>(),
  ));

  // 5. Repositories
  getIt.registerLazySingleton<ChatRepository>(() => ChatRepository(
    dbHelper: DatabaseHelper.instance,
    messagingService: getIt<MessagingService>(),
  ));
}
