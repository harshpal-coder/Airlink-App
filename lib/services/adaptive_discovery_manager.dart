import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'discovery_service.dart';
import '../utils/connectivity_logger.dart';

enum DiscoveryArm {
  ultraAggressive, // 15s
  standard,        // 1m
  powerSave,       // 5m
  hibernate,       // 15m
}

class AdaptiveDiscoveryManager {
  final DiscoveryService _discoveryService;
  final Random _random = Random();
  
  // MAB State (Q-values and Counts)
  final Map<DiscoveryArm, double> _qValues = {
    for (var arm in DiscoveryArm.values) arm: 0.0
  };
  final Map<DiscoveryArm, int> _counts = {
    for (var arm in DiscoveryArm.values) arm: 0
  };

  DiscoveryArm _currentArm = DiscoveryArm.standard;
  int _peersAtDecisionStart = 0;
  int _batteryAtDecisionStart = 100;

  static const double epsilon = 0.1; // Exploration rate
  Timer? _adaptationTimer;
  
  AdaptiveDiscoveryManager({required DiscoveryService discoveryService})
      : _discoveryService = discoveryService;

  Future<void> start() async {
    await _loadState();
    _adaptationTimer?.cancel();
    // Rule: Every 15 mins, evaluate and choose a new arm
    _adaptationTimer = Timer.periodic(const Duration(minutes: 15), (_) => _step());
    _step(); // Initial step
  }

  void stop() {
    _adaptationTimer?.cancel();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    for (var arm in DiscoveryArm.values) {
      _qValues[arm] = prefs.getDouble('mab_q_${arm.name}') ?? 0.0;
      _counts[arm] = prefs.getInt('mab_n_${arm.name}') ?? 0;
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    for (var arm in DiscoveryArm.values) {
      await prefs.setDouble('mab_q_${arm.name}', _qValues[arm]!);
      await prefs.setInt('mab_n_${arm.name}', _counts[arm]!);
    }
  }

  Future<void> _step() async {
    // 1. Evaluate previous decision (Reward calculation)
    if (_counts[_currentArm]! > 0 || _qValues[_currentArm]! != 0.0) {
      await _evaluateAndLearn();
    }

    // 2. Select next arm (Epsilon-Greedy)
    if (_random.nextDouble() < epsilon) {
      // Exploration: Random arm
      _currentArm = DiscoveryArm.values[_random.nextInt(DiscoveryArm.values.length)];
      ConnectivityLogger.info(LogCategory.discovery, '[Battery AI] Exploring: ${_currentArm.name}');
    } else {
      // Exploitation: Best known arm
      _currentArm = _qValues.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
      ConnectivityLogger.info(LogCategory.discovery, '[Battery AI] Exploiting: ${_currentArm.name} (Value: ${_qValues[_currentArm]?.toStringAsFixed(2)})');
    }

    // 3. Apply decision
    _applyArm(_currentArm);
    
    // 4. Record state for next evaluation
    _peersAtDecisionStart = _discoveryService.getDiscoveredDeviceCount();
    _batteryAtDecisionStart = await _discoveryService.getBatteryLevel();
  }

  Future<void> _evaluateAndLearn() async {
    final nowPeers = _discoveryService.getDiscoveredDeviceCount();
    final nowBattery = await _discoveryService.getBatteryLevel();
    
    final int newPeersFound = max(0, nowPeers - _peersAtDecisionStart);
    final int batteryDelta = max(0, _batteryAtDecisionStart - nowBattery);
    
    // Reward Function: 
    // Reward = (New Peers * 10) - (Battery % Drop * 50) - (Arm Scanning Cost)
    double scanCost = 0.0;
    switch (_currentArm) {
      case DiscoveryArm.ultraAggressive: scanCost = 5; break;
      case DiscoveryArm.standard: scanCost = 1; break;
      case DiscoveryArm.powerSave: scanCost = 0; break; // Use 0 instead of 0.2 to avoid int cast issues
      case DiscoveryArm.hibernate: scanCost = 0; break;
    }

    double reward = (newPeersFound * 10.0) - (batteryDelta * 50.0) - scanCost;
    
    // Incremental Mean Update: Q(a) = Q(a) + 1/n * [R - Q(a)]
    _counts[_currentArm] = _counts[_currentArm]! + 1;
    _qValues[_currentArm] = _qValues[_currentArm]! + (1 / _counts[_currentArm]!) * (reward - _qValues[_currentArm]!);
    
    await _saveState();
    ConnectivityLogger.info(LogCategory.discovery, '[Battery AI] Evaluated ${_currentArm.name}: Reward=$reward, New Q=${_qValues[_currentArm]?.toStringAsFixed(2)}');
  }

  void _applyArm(DiscoveryArm arm) {
    Duration interval;
    switch (arm) {
      case DiscoveryArm.ultraAggressive: interval = const Duration(seconds: 15); break;
      case DiscoveryArm.standard: interval = const Duration(minutes: 1); break;
      case DiscoveryArm.powerSave: interval = const Duration(minutes: 5); break;
      case DiscoveryArm.hibernate: interval = const Duration(minutes: 15); break;
    }
    _discoveryService.updateRefreshInterval(interval);
  }
}
