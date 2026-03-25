/// Base interface for all application events.
abstract class AppEvent {}

/// Triggered when a peer is permanently lost from the heartbeat monitoring.
class PeerLostEvent extends AppEvent {
  final String uuid;
  final String deviceName;
  PeerLostEvent({required this.uuid, required this.deviceName});
}

/// Triggered when a reconnection attempt to a specific peer succeeds.
class ReconnectSucceededEvent extends AppEvent {
  final String uuid;
  final String deviceName;
  ReconnectSucceededEvent({required this.uuid, required this.deviceName});
}

/// Triggered when the physical radio (Bluetooth/WiFi) state changes.
class RadioStateChangedEvent extends AppEvent {
  final String radioType; // 'BT' or 'WiFi'
  final bool isEnabled;
  RadioStateChangedEvent({required this.radioType, required this.isEnabled});
}

/// Triggered when the background service pokes the app to stay alive.
class BackgroundPokeEvent extends AppEvent {}

/// Triggered when a high-priority SOS broadcast is received.
class SOSReceivedEvent extends AppEvent {
  final String senderUuid;
  final String senderName;
  final String content;
  SOSReceivedEvent({required this.senderUuid, required this.senderName, required this.content});
}
