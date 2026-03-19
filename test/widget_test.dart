import 'package:flutter_test/flutter_test.dart';
import 'package:airlink/services/discovery_service.dart';
import 'package:airlink/services/heartbeat_manager.dart';
import 'package:airlink/services/reconnection_manager.dart';
import 'package:airlink/services/connectivity_state_monitor.dart';
import 'package:airlink/services/message_queue_manager.dart';
import 'package:airlink/services/messaging_service.dart';
import 'package:airlink/services/reputation_service.dart';
import 'package:airlink/services/peer_ai_service.dart';
import 'package:airlink/services/motion_service.dart';
import 'package:airlink/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App initializes without crash', (WidgetTester tester) async {
    final reputation = ReputationService();
    final aiService = PeerAIService();
    final motionService = MotionService();
    final discovery = DiscoveryService(
      reputationService: reputation,
      aiService: aiService,
    );
    final heartbeat = HeartbeatManager(discoveryService: discovery);
    final reconnection = ReconnectionManager(
      discoveryService: discovery,
      reputationService: reputation,
    );
    final stateMonitor = ConnectivityStateMonitor();
    final messageQueue = MessageQueueManager(discoveryService: discovery);
    final messaging = MessagingService(
      discoveryService: discovery,
      heartbeatManager: heartbeat,
      messageQueueManager: messageQueue,
      reputationService: reputation,
      aiService: aiService,
    );

    await tester.pumpWidget(MyApp(
      discoveryService: discovery,
      messagingService: messaging,
      reconnectionManager: reconnection,
      heartbeatManager: heartbeat,
      connectivityStateMonitor: stateMonitor,
      messageQueueManager: messageQueue,
      reputationService: reputation,
    ));

    // Just verify it builds without errors
    expect(find.byType(MyApp), findsOneWidget);

    heartbeat.dispose();
    reconnection.dispose();
    messageQueue.dispose();
    stateMonitor.dispose();
    messaging.dispose();
    discovery.dispose();
    motionService.stop();
  });
}
