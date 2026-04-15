import 'dart:math';
import '../models/device_model.dart';
import 'motion_service.dart';

/// Type of peer based on behavioral analysis.
enum PeerClass {
  stableBackbone, // High uptime, good battery, stationary
  mobileTransient, // Moving frequently, inconsistent uptime
  unreliable, // Frequent drops, low reputation
  me
}

/// Metadata for AI training and prediction
class PeerTelemetry {
  final List<double> rssiHistory = [];
  final List<double> latencyHistory = [];
  int lastUpdate = 0;
  
  void addRssi(double rssi) {
    if (rssiHistory.length > 20) rssiHistory.removeAt(0);
    rssiHistory.add(rssi);
  }
}

class PeerAIService {
  final Map<String, PeerTelemetry> _telemetry = {};
  MotionState _localMotionState = MotionState.stationary;

  void updateLocalMotionState(MotionState state) {
    _localMotionState = state;
  }
  
  /// Records signal strength telemetry for a peer.
  void recordTelemetry(String peerUuid, double rssi) {
    final data = _telemetry.putIfAbsent(peerUuid, () => PeerTelemetry());
    data.addRssi(rssi);
    data.lastUpdate = DateTime.now().millisecondsSinceEpoch;
  }

  /// Predicts the probability of a connection drop (0.0 to 1.0).
  /// Uses a simple linear trend analysis of RSSI values + local motion risk.
  double predictDropProbability(String peerUuid) {
    // Factor in Local Motion Risk
    double motionRisk = 1.0;
    if (_localMotionState == MotionState.walking) motionRisk = 1.5;
    if (_localMotionState == MotionState.vehicular) motionRisk = 3.0;

    final data = _telemetry[peerUuid];
    if (data == null || data.rssiHistory.length < 5) {
      return (0.2 * motionRisk).clamp(0.0, 1.0);
    }

    // Simple Linear Regression on RSSI trend
    double sumX = 0;
    double sumY = 0;
    double sumXY = 0;
    double sumXX = 0;
    int n = data.rssiHistory.length;

    for (int i = 0; i < n; i++) {
      double x = i.toDouble();
      double y = data.rssiHistory[i];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }

    double slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
    
    // If signal is dropping rapidly (negative slope), increase drop probability
    // For example, if slope is -2dB/measurement, that's high risk.
    if (slope >= 0) return 0.1; // Stable or improving
    
    // Normalize: A slope of -1.0 or less is considered high risk (1.0)
    double risk = (slope.abs() * 0.5).clamp(0.0, 1.0);
    
    // Also consider absolute signal level
    double lastRssi = data.rssiHistory.last;
    if (lastRssi < -85) risk = max(risk, 0.8);
    
    // Combine with motion risk
    return (risk * motionRisk).clamp(0.0, 1.0);
  }

  /// Classifies a peer based on their behavior patterns.
  PeerClass classifyPeer(Device device) {
    if (device.isBackbone && device.reputationScore > 80) {
      return PeerClass.stableBackbone;
    }
    
    if (device.reputationScore < 30) {
      return PeerClass.unreliable;
    }
    
    return PeerClass.mobileTransient;
  }
}
