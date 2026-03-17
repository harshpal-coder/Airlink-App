import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/discovery_service.dart';
import 'package:app/services/heartbeat_manager.dart';
import 'package:app/services/reconnection_manager.dart';
import 'package:app/services/connectivity_state_monitor.dart';
import 'package:app/services/message_queue_manager.dart';
import 'package:app/services/messaging_service.dart';
import 'package:app/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App initializes without crash', (WidgetTester tester) async {
    final discovery = DiscoveryService();
    final heartbeat = HeartbeatManager(discoveryService: discovery);
    final reconnection = ReconnectionManager(discoveryService: discovery);
    final stateMonitor = ConnectivityStateMonitor();
    final messageQueue = MessageQueueManager(discoveryService: discovery);
    final messaging = MessagingService(
      discoveryService: discovery,
      heartbeatManager: heartbeat,
      messageQueueManager: messageQueue,
    );

    await tester.pumpWidget(MyApp(
      discoveryService: discovery,
      messagingService: messaging,
      reconnectionManager: reconnection,
      connectivityStateMonitor: stateMonitor,
      messageQueueManager: messageQueue,
    ));

    // Just verify it builds without errors
    expect(find.byType(MyApp), findsOneWidget);

    heartbeat.dispose();
    reconnection.dispose();
    messageQueue.dispose();
    stateMonitor.dispose();
    messaging.dispose();
    discovery.dispose();
  });
}
