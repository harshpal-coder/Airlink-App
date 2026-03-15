import 'session_state.dart';

class Device {
  final String deviceId;
  final String deviceName;
  final String? uuid;
  final String? profileImage;
  SessionState state;
  double rssi;
  int batteryLevel;
  int retryCount;
  DateTime? lastRetry;
  bool isBackbone;
  bool isPluggedIn;
  final bool isMesh;
  final String? relayedBy;

  Device({
    required this.deviceId,
    required this.deviceName,
    this.uuid,
    this.profileImage,
    this.state = SessionState.notConnected,
    this.rssi = -100.0,
    this.batteryLevel = -1,
    this.retryCount = 0,
    this.lastRetry,
    this.isBackbone = false,
    this.isPluggedIn = false,
    this.isMesh = false,
    this.relayedBy,
  });

  Device copyWith({
    String? deviceId,
    String? deviceName,
    String? uuid,
    String? profileImage,
    SessionState? state,
    double? rssi,
    int? batteryLevel,
    int? retryCount,
    DateTime? lastRetry,
    bool? isBackbone,
    bool? isPluggedIn,
    bool? isMesh,
    String? relayedBy,
  }) {
    return Device(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      uuid: uuid ?? this.uuid,
      profileImage: profileImage ?? this.profileImage,
      state: state ?? this.state,
      rssi: rssi ?? this.rssi,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      retryCount: retryCount ?? this.retryCount,
      lastRetry: lastRetry ?? this.lastRetry,
      isBackbone: isBackbone ?? this.isBackbone,
      isPluggedIn: isPluggedIn ?? this.isPluggedIn,
      isMesh: isMesh ?? this.isMesh,
      relayedBy: relayedBy ?? this.relayedBy,
    );
  }
}
