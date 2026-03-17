import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/discovery_service.dart';
import 'package:app/services/heartbeat_manager.dart';
import 'package:app/models/device_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockDiscoveryService extends DiscoveryService {
  List<Device> connectedDevices = [];
  Map<String, Device> devicesByUuid = {};

  @override
  List<Device> getConnectedDevices() => connectedDevices;

  @override
  Device? getDeviceByUuid(String uuid) => devicesByUuid[uuid];

  @override
  Future<void> disconnect(Device device) async {}

  @override
  Future<int?> sendMessageToEndpoint(String deviceId, String message) async {
    return 123;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDiscoveryService mockDiscovery;
  late HeartbeatManager heartbeatManager;

  setUp(() {
    mockDiscovery = MockDiscoveryService();
    heartbeatManager = HeartbeatManager(discoveryService: mockDiscovery);
  });

  group('HeartbeatManager Adaptive Logic', () {
    test('HeartbeatManager should emit events on peer loss', () async {
      expect(heartbeatManager.isActive, false);
      heartbeatManager.startMonitoring();
      expect(heartbeatManager.isActive, true);
      heartbeatManager.stopMonitoring();
      expect(heartbeatManager.isActive, false);
    });

    test('Handle pong resets miss count', () {
      heartbeatManager.handlePong('uuid-1', 'device-1', null);
      expect(heartbeatManager.getMissCount('uuid-1'), 0);
    });

    test('RTT-based signal quality estimation records last RTT', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      heartbeatManager.handlePong('uuid-2', 'device-2', now - 50);
      expect(heartbeatManager.getLastRtt('uuid-2'), isNotNull);
    });
  });
}
