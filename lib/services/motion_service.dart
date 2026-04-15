import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import '../utils/connectivity_logger.dart';

enum MotionState {
  stationary,
  walking,
  vehicular,
}

class MotionService {
  StreamSubscription<UserAccelerometerEvent>? _subscription;
  MotionState _currentState = MotionState.stationary;
  
  final _stateController = StreamController<MotionState>.broadcast();
  Stream<MotionState> get stateChanges => _stateController.stream;
  MotionState get currentState => _currentState;

  // Thresholds for classification (m/s^2)
  static const double walkingThreshold = 1.5;
  static const double vehicularThreshold = 5.0;

  void start() {
    _subscription?.cancel();
    _subscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      _processEvent(event);
    });
    ConnectivityLogger.info(LogCategory.discovery, 'MotionService started.');
  }

  void stop() {
    _subscription?.cancel();
    _stateController.close();
  }

  void _processEvent(UserAccelerometerEvent event) {
    // Vector magnitude of acceleration
    final double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    
    MotionState newState = _currentState;

    if (magnitude > vehicularThreshold) {
      newState = MotionState.vehicular;
    } else if (magnitude > walkingThreshold) {
      newState = MotionState.walking;
    } else {
      newState = MotionState.stationary;
    }

    if (newState != _currentState) {
      _currentState = newState;
      _stateController.add(_currentState);
      ConnectivityLogger.info(LogCategory.discovery, 'Motion State changed to: ${_currentState.name}');
    }
  }
}
