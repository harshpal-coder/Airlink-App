import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import 'package:flutter/foundation.dart';
import 'reputation_service.dart';
import 'peer_ai_service.dart';
import '../utils/connectivity_logger.dart';

import '../models/session_state.dart';

class PayloadProgress {
  final String endpointId;
  final int payloadId;
  final double progress;
  final PayloadStatus status;

  PayloadProgress({
    required this.endpointId,
    required this.payloadId,
    required this.progress,
    required this.status,
  });
}

class DiscoveryService {
  static const String serviceId = "com.example.airlink";
  Strategy strategy =
      Strategy.P2P_CLUSTER; // Using P2P_CLUSTER for mesh-like connectivity

  static const int _targetDirectPeers = 6; // Target number of simultaneous direct connections (Hardware/API limit is ~10)

  final _discoveredDevicesController =
      StreamController<List<Device>>.broadcast();
  final _connectedDeviceController = StreamController<Device>.broadcast();
  final _dataReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<Device>> get discoveredDevices =>
      _discoveredDevicesController.stream;
  Stream<Device> get connectedDevice => _connectedDeviceController.stream;
  Stream<Map<String, dynamic>> get dataReceived =>
      _dataReceivedController.stream;

  final _payloadProgressController =
      StreamController<PayloadProgress>.broadcast();
  Stream<PayloadProgress> get payloadProgress => _payloadProgressController.stream;

  final _fileReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get fileReceived => _fileReceivedController.stream;

  final ReputationService _reputationService;
  final PeerAIService _aiService;
  final Map<String, DateTime> _connectionStartTimes = {};


  final List<Device> _devices = [];
  String _userName = 'Unknown';
  Map<String, String> _knownDevices = {}; // UUID -> Name for quick lookup
  String? _localUuid;
  bool _isBrowsing = false;
  bool _isAdvertising = false;

  bool get isCurrentlyBrowsing => _isBrowsing;
  bool get isCurrentlyAdvertising => _isAdvertising;

  /// Callback invoked when a direct (non-mesh) peer disconnects.
  /// Used by ReconnectionManager to trigger an immediate reconnect attempt.
  void Function(Device)? onDirectDisconnect;

  /// Callback invoked when any peer reaches [SessionState.connected].
  /// Used by MessagingService to auto-send a mesh_update immediately after
  /// a connection is established — accelerates topology convergence.
  void Function(Device)? onPeerConnected;

  /// Callback invoked when a reconnection effort needs more aggressive scanning.
  void Function()? onBoostDiscovery;

  void boostDiscovery() {
    ConnectivityLogger.debug(LogCategory.discovery, 'Reconnection manager requested discovery boost');
    onBoostDiscovery?.call();
  }

  Timer? _refreshTimer;
  int _currentBatteryLevel = 100;

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    
    // Aggressive interval based on battery and current connection count
    int connectedCount = getConnectedDevices().length;
    bool needsMorePeers = connectedCount < _targetDirectPeers;
    
    // Adjusted intervals: 2m default, 4m if battery is low.
    // Ultra-fast (0) now maps to 30s or 60s instead of 15s/30s.
    int minutes = needsMorePeers ? 2 : 4; 
    if (_currentBatteryLevel < 20) {
      minutes = needsMorePeers ? 5 : 10; 
    } else if (_devices.any((d) => d.isPluggedIn)) {
      minutes = 0; // Use seconds for adaptive high performance
    }

    final jitter = Random().nextInt(15) - 7; // Slightly more jitter for collision avoidance
    Duration interval;
    if (minutes == 0) {
      interval = Duration(seconds: needsMorePeers ? 30 : 60); 
    } else {
      interval = Duration(minutes: minutes) + Duration(seconds: jitter);
    }
    
    _refreshTimer = Timer.periodic(interval, (timer) async {
      _executeRefresh();
    });
  }

  Future<int> getBatteryLevel() async {
    return _currentBatteryLevel;
  }

  void updateRefreshInterval(Duration interval) {
    debugPrint('[DiscoveryService] Updating refresh interval to ${interval.inSeconds}s');
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (timer) async {
      _executeRefresh();
    });
  }

  Future<void> _executeRefresh() async {
      int connectedCount = getConnectedDevices().length;
      
      if (connectedCount == 0) {
          ConnectivityLogger.debug(LogCategory.discovery,
              'Periodic refresh (No peers): Force-restarting browsing/advertising...');
          if (_isBrowsing) await startBrowsing(forceRestart: true);
          if (_isAdvertising) await startAdvertising(forceRestart: true);
      } else {
          ConnectivityLogger.debug(LogCategory.discovery,
              'Periodic refresh (Active connections: $connectedCount): Ensuring radio is alive without restart...');
          // If already connected, only start if NOT already browsing/advertising (passive check)
          // Do NOT forceRestart as it drops existing connections
          if (!_isBrowsing) await startBrowsing(forceRestart: false);
          if (!_isAdvertising) await startAdvertising(forceRestart: false);
      }
  }

  Map<String, String> get knownDevices => _knownDevices;

  void setKnownDevices(List<Map<String, String>> devices) {
    _knownDevices = {for (var d in devices) d['uuid']!: d['name']!};
    debugPrint(
      '[DiscoveryService] Known devices for auto-reconnect: $_knownDevices',
    );
  }


  /// Updates a peer device's battery level and emits the updated device list.
  void updateDeviceBattery(String deviceId, int batteryLevel, {bool? isBackbone, bool? isPluggedIn}) {
    final index = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (index < 0) {
      debugPrint(
        '[DiscoveryService] updateDeviceBattery: device $deviceId not found',
      );
      return;
    }

    final oldBattery = _devices[index].batteryLevel;
    final oldBackbone = _devices[index].isBackbone;
    final oldPluggedIn = _devices[index].isPluggedIn;

    // Only update if significant change to reduce UI churn and timer resets
    bool significant = (oldBattery - batteryLevel).abs() >= 5 || 
                      (isBackbone != null && isBackbone != oldBackbone) ||
                      (isPluggedIn != null && isPluggedIn != oldPluggedIn) ||
                      (batteryLevel < 20 && oldBattery >= 20); // Always notify low battery crossing

    _devices[index].batteryLevel = batteryLevel;
    if (isBackbone != null) _devices[index].isBackbone = isBackbone;
    if (isPluggedIn != null) _devices[index].isPluggedIn = isPluggedIn;
    
    // Update local state if it's "me" or just use it to adjust frequency
    _currentBatteryLevel = batteryLevel;
    if (significant) {
      _startRefreshTimer(); // Adaptive frequency update (less frequent now)
    }

    if (significant) {
      _discoveredDevicesController.sink.add(List.from(_devices));
      debugPrint(
        '[DiscoveryService] Battery of ${_devices[index].deviceName}: $batteryLevel% (Backbone: $isBackbone) - Notifying listeners');
    }
  }

  /// Updates a peer device's RSSI (signal strength)
  void updateDeviceRssi(String deviceId, double rssi) {
    final index = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (index < 0) return;
    
    final oldRssi = _devices[index].rssi;
    // Only update if RSSI changed by more than 5dB to reduce UI jitter
    if ((oldRssi - rssi).abs() > 5.0 || _devices[index].state == SessionState.connecting) {
      _devices[index].rssi = rssi;
      _discoveredDevicesController.sink.add(List.from(_devices));
      debugPrint(
          '[DiscoveryService] RSSI of ${_devices[index].deviceName}: $rssi dBm - Notifying listeners');
    } else {
      _devices[index].rssi = rssi;
      _aiService.recordTelemetry(_devices[index].uuid ?? deviceId, rssi);
      _discoveredDevicesController.sink.add(List.from(_devices));
    }
  }


  DiscoveryService({ReputationService? reputationService, PeerAIService? aiService})
      : _reputationService = reputationService ?? ReputationService(),
        _aiService = aiService ?? PeerAIService();

  Future<bool> init(String userName, {String? localUuid}) async {
    _userName = userName;
    _localUuid = localUuid;
    _devices.clear();
    _startRefreshTimer();
    return true;
  }

  void setStrategy(Strategy newStrategy) {
    strategy = newStrategy;
    debugPrint('[DiscoveryService] Strategy changed to: $newStrategy');
  }


  Future<void> startBrowsing({bool forceRestart = false}) async {
    if (_isBrowsing && !forceRestart) {
      debugPrint('[DiscoveryService] Already browsing. Skipping redundant start.');
      return;
    }
    
    // Aggressively try to stop to prevent STATUS_ALREADY_DISCOVERING
    if (_isBrowsing || forceRestart) {
      await stopDiscovery();
      await Future.delayed(const Duration(milliseconds: 100)); // Minimal safety delay
    }

    try {
      debugPrint('[DiscoveryService] Starting discovery...');
      _isBrowsing = true;
      await Nearby().startDiscovery(
        _userName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: (id, name, serviceId) {
          debugPrint('[DiscoveryService] Endpoint found: $name ($id)');
          String displayName = name;
          String? discoveredUuid;

          if (name.contains('|')) {
            final parts = name.split('|');
            displayName = parts[0];
            if (parts.length > 1) discoveredUuid = parts[1];
          }

          final device = Device(
            deviceId: id,
            deviceName: displayName,
            uuid: discoveredUuid,
          );
          _addOrUpdateDevice(device);

          // Auto-reconnect logic by UUID
          if (discoveredUuid != null &&
              _knownDevices.containsKey(discoveredUuid)) {
            final existingIndex = _devices.indexWhere((d) => d.deviceId == id);
            if (existingIndex >= 0 &&
                (_devices[existingIndex].state == SessionState.notConnected)) {

              // No throttle: when a known peer is in direct range, reconnect immediately.
              // Tie-breaker: one side initiates to avoid simultaneous collision.
              // Nearby resolves collisions gracefully via STATUS_ENDPOINT_IO_ERROR.
              if (_localUuid != null &&
                  _localUuid!.compareTo(discoveredUuid) > 0) {
                debugPrint(
                  '[DiscoveryService] Found known device "$displayName" ($discoveredUuid). Tie-breaker WON. Initiating instant reconnect...',
                );
                connect(_devices[existingIndex]);
              } else {
                debugPrint(
                  '[DiscoveryService] Found known device "$displayName" ($discoveredUuid). Tie-breaker LOST. Waiting 100ms for peer...',
                );
                // IMP #9: Wider fallback window (100ms → 400ms) gives the
                // peer-side adequate time to initiate on congested BT radios.
                Future.delayed(const Duration(milliseconds: 400), () {
                  final idx = _devices.indexWhere((d) => d.deviceId == id);
                  if (idx >= 0 && _devices[idx].state == SessionState.notConnected) {
                    debugPrint(
                      '[DiscoveryService] Peer did not connect within 400ms. Initiating as fallback...',
                    );
                    connect(_devices[idx]);
                  }
                });
              }
            }
          }
        },
        onEndpointLost: (id) {
          debugPrint('[DiscoveryService] Endpoint lost: $id');
          // Only remove if NOT connected. If connected, we want to keep the device
          final index = _devices.indexWhere((d) => d.deviceId == id);
          if (index >= 0) {
            if (_devices[index].state == SessionState.notConnected) {
              _removeDevice(id!);
            } else {
              debugPrint(
                '[DiscoveryService] Keeping connected device $id despite endpoint loss',
              );
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Error starting discovery: $e');
    }
  }

  Future<void> stopDiscovery() async {
    if (!_isBrowsing) return;
    try {
      await Nearby().stopDiscovery();
      _isBrowsing = false;
    } catch (e) {
      debugPrint('Error stopping discovery: $e');
    }
  }

  Future<void> startAdvertising({bool forceRestart = false}) async {
    if (_isAdvertising && !forceRestart) {
      debugPrint('[DiscoveryService] Already advertising. Skipping redundant start.');
      return;
    }
    
    // Aggressively try to stop to prevent STATUS_ALREADY_ADVERTISING
    if (_isAdvertising || forceRestart) {
      await stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 100)); // Minimal safety delay
    }

    try {
      debugPrint('[DiscoveryService] Starting advertising...');
      _isAdvertising = true;
      await Nearby().startAdvertising(
        _userName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: (id, info) async {
          debugPrint(
            '[DiscoveryService] Connection initiated from ${info.endpointName} ($id)',
          );

          String? peerUuid;
          String displayName = info.endpointName;

          if (info.endpointName.contains('|')) {
            final parts = info.endpointName.split('|');
            displayName = parts[0];
            if (parts.length > 1) peerUuid = parts[1];
          }

          final device = Device(
            deviceId: id,
            deviceName: displayName,
            uuid: peerUuid,
          );
          _addOrUpdateDevice(device);

          // Auto accept connection
          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              debugPrint(
                '[DiscoveryService] Payload received from $endpointId (ID: ${payload.id})',
              );
              if (payload.type == PayloadType.BYTES) {
                Uint8List bytes = payload.bytes!;
                String str;
                
                if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
                  try {
                    final decoded = gzip.decode(bytes);
                    str = utf8.decode(decoded);
                  } catch (e) {
                    str = utf8.decode(bytes);
                  }
                } else {
                  str = utf8.decode(bytes);
                }
                _dataReceivedController.sink.add({
                  'senderId': endpointId,
                  'payload': str,
                  'payloadId': payload.id,
                });
              } else if (payload.type == PayloadType.FILE) {
                _fileReceivedController.sink.add({
                  'senderId': endpointId,
                  'payloadId': payload.id,
                  // ignore: deprecated_member_use
                  'filePath': payload.uri ?? payload.filePath,
                });
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {
              _payloadProgressController.sink.add(PayloadProgress(
                endpointId: endpointId,
                payloadId: update.id,
                progress: update.bytesTransferred / (update.totalBytes > 0 ? update.totalBytes : 1),
                status: update.status,
              ));
            },
          );
        },
        onConnectionResult: (id, status) {
          debugPrint('[DiscoveryService] Connection result for $id: $status');
          final device = getDeviceById(id);
          final uuid = device?.uuid;
          
          if (status == Status.CONNECTED) {
            _connectionStartTimes[id] = DateTime.now();
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, true);
            }
            updateDeviceState(id, SessionState.connected);
            // IMP #8: Notify MessagingService so it can send an immediate mesh_update.
            final connectedDevice = getDeviceById(id);
            if (connectedDevice != null) {
              onPeerConnected?.call(connectedDevice);
            }
          } else {
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, false);
            }
            updateDeviceState(id, SessionState.notConnected);
          }
        },
        onDisconnected: (id) {
          final startTime = _connectionStartTimes.remove(id);
          final droppedDevice = getDeviceById(id);
          if (startTime != null) {
            final duration = DateTime.now().difference(startTime).inMinutes;
            final uuid = droppedDevice?.uuid;
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, true, durationMinutes: duration);
            }
          }
          updateDeviceState(id, SessionState.notConnected);
          // Notify ReconnectionManager immediately for instant re-attempt
          if (droppedDevice != null && !droppedDevice.isMesh) {
            onDirectDisconnect?.call(droppedDevice);
          }
        },
      );
    } catch (e) {
      debugPrint('Error starting advertising: $e');
    }
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await Nearby().stopAdvertising();
      _isAdvertising = false;
    } catch (e) {
      debugPrint('Error stopping advertising: $e');
    }
  }

  /// Refreshes the radio by restarting discovery and advertising if they were active.
  /// This is used for background wake-ups to ensure the Nearby radio stays alive.
  void refreshRadio() {
    debugPrint('[DiscoveryService] Refreshing radio (Active: Discovery=$_isBrowsing, Advertising=$_isAdvertising)');
    if (_isBrowsing) startBrowsing(forceRestart: true);
    if (_isAdvertising) startAdvertising(forceRestart: true);
  }

  Future<void> connect(Device device) async {
    if (device.state == SessionState.connecting ||
        device.state == SessionState.connected) {
      debugPrint(
        '[DiscoveryService] Already connecting/connected to ${device.deviceName} (${device.uuid ?? device.deviceId}). Skipping.',
      );
      return;
    }

    // Double check by UUID to prevent redundant connections to the same peer via different IDs
    if (device.uuid != null) {
      final existing = getDeviceByUuid(device.uuid!);
      if (existing != null && (existing.state == SessionState.connected || existing.state == SessionState.connecting)) {
         debugPrint('[DiscoveryService] Already have an active session with UUID ${device.uuid}. Skipping connect to ${device.deviceId}.');
         updateDeviceState(device.deviceId, existing.state);
         return;
      }
    }

    debugPrint(
      '[DiscoveryService] Requesting connection to ${device.deviceName} (${device.deviceId})',
    );
    updateDeviceState(device.deviceId, SessionState.connecting);
    try {
      await Nearby().requestConnection(
        _userName,
        device.deviceId,
        onConnectionInitiated: (id, info) async {
          debugPrint(
            '[DiscoveryService] Connection initiated to ${info.endpointName} ($id)',
          );

          String? peerUuid;
          String displayName = info.endpointName;

          if (info.endpointName.contains('|')) {
            final parts = info.endpointName.split('|');
            displayName = parts[0];
            if (parts.length > 1) peerUuid = parts[1];
          }

          final device = Device(
            deviceId: id,
            deviceName: displayName,
            uuid: peerUuid,
          );
          _addOrUpdateDevice(device);

          await Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {
              debugPrint(
                '[DiscoveryService] Payload received from $endpointId (ID: ${payload.id})',
              );
              if (payload.type == PayloadType.BYTES) {
                Uint8List bytes = payload.bytes!;
                String str;
                
                // GZIP Consistency Fix: Check for magic bytes
                if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
                  try {
                    final decoded = gzip.decode(bytes);
                    str = utf8.decode(decoded);
                  } catch (e) {
                    str = utf8.decode(bytes);
                  }
                } else {
                  str = utf8.decode(bytes);
                }

                _dataReceivedController.sink.add({
                  'senderId': endpointId,
                  'payload': str,
                  'payloadId': payload.id,
                });
              } else if (payload.type == PayloadType.FILE) {
                _fileReceivedController.sink.add({
                  'senderId': endpointId,
                  'payloadId': payload.id,
                  // ignore: deprecated_member_use
                  'filePath': payload.uri ?? payload.filePath,
                });
              }
            },
            onPayloadTransferUpdate: (endpointId, update) {
              _payloadProgressController.sink.add(PayloadProgress(
                endpointId: endpointId,
                payloadId: update.id,
                progress: update.bytesTransferred / (update.totalBytes > 0 ? update.totalBytes : 1),
                status: update.status,
              ));
            },
          );
        },
        onConnectionResult: (id, status) {
          debugPrint('[DiscoveryService] Connection result for $id: $status');
          final device = getDeviceById(id);
          final uuid = device?.uuid;

          if (status == Status.CONNECTED) {
            _connectionStartTimes[id] = DateTime.now();
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, true);
            }
            updateDeviceState(id, SessionState.connected);
            // IMP #8: Notify MessagingService so it can send an immediate mesh_update.
            final connectedDevice = getDeviceById(id);
            if (connectedDevice != null) {
              onPeerConnected?.call(connectedDevice);
            }
          } else {
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, false);
            }
            updateDeviceState(id, SessionState.notConnected);
          }
        },
        onDisconnected: (id) {
          final startTime = _connectionStartTimes.remove(id);
          final droppedDevice = getDeviceById(id);
          if (startTime != null) {
            final duration = DateTime.now().difference(startTime).inMinutes;
            final uuid = droppedDevice?.uuid;
            if (uuid != null) {
              _reputationService.recordConnectionEvent(uuid, true, durationMinutes: duration);
            }
          }
          updateDeviceState(id, SessionState.notConnected);
          // Notify ReconnectionManager immediately for instant re-attempt
          if (droppedDevice != null && !droppedDevice.isMesh) {
            onDirectDisconnect?.call(droppedDevice);
          }
        },
      );
    } catch (e) {
      debugPrint('Connection request error: $e');
      final errStr = e.toString();
      if (errStr.contains('STATUS_ALREADY_CONNECTED_TO_ENDPOINT')) {
        debugPrint('[DiscoveryService] Already connected to ${device.deviceName}. Updating state.');
        updateDeviceState(device.deviceId, SessionState.connected);
      } else if (errStr.contains('STATUS_ENDPOINT_IO_ERROR')) {
        // IO error often means both sides tried simultaneously — don't mark
        // as disconnected, just leave state alone and let the next scan retry.
        debugPrint('[DiscoveryService] IO error connecting to ${device.deviceName}. Will retry on next scan.');
        updateDeviceState(device.deviceId, SessionState.notConnected);
      } else {
        updateDeviceState(device.deviceId, SessionState.notConnected);
      }
    }
  }

  Future<void> disconnect(Device device) async {
    try {
      await Nearby().disconnectFromEndpoint(device.deviceId);
      updateDeviceState(device.deviceId, SessionState.notConnected);
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }

  Future<int?> sendMessageToEndpoint(String endpointId, String message) async {
    try {
      Uint8List bytes = Uint8List.fromList(utf8.encode(message));
      
      // Compress if larger than 128 bytes to save bandwidth
      if (bytes.length > 128) {
        try {
          final compressed = gzip.encode(bytes);
          bytes = Uint8List.fromList(compressed);
          debugPrint('[DiscoveryService] Compressed payload from ${utf8.encode(message).length} to ${bytes.length} bytes');
        } catch (e) {
          debugPrint('[DiscoveryService] Compression failed: $e');
        }
      }

      final payloadId = DateTime.now().millisecondsSinceEpoch;
      await Nearby().sendBytesPayload(
        endpointId,
        bytes,
      );
      return payloadId; 
    } catch (e) {
      debugPrint('Error sending message: $e');
      return null;
    }
  }

  Future<int?> sendFileToEndpoint(String endpointId, String filePath) async {
    try {
      final payloadId = await Nearby().sendFilePayload(endpointId, filePath);
      return payloadId;
    } catch (e) {
      debugPrint('Error sending file: $e');
      return null;
    }
  }

  void _addOrUpdateDevice(Device device) {
    // 1. Find existing device by UUID (if available) or deviceId
    int index = -1;
    if (device.uuid != null) {
      index = _devices.indexWhere((d) => d.uuid == device.uuid);
    } else {
      index = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    }

    if (index >= 0) {
      final existingDevice = _devices[index];
      
      // 2. Preserve state if we are "updating" a device
      // If the incoming device is NOT a mesh device, it's a direct connection upgrade/update
      // If the existing device was connected/connecting, keep that state UNLESS the new state is more specific
      SessionState newState = device.state;
      if (existingDevice.state == SessionState.connected || existingDevice.state == SessionState.connecting) {
        if (newState == SessionState.notConnected) {
          newState = existingDevice.state;
        }
      }

      // Preserve persistent metadata
      _devices[index] = device.copyWith(
        state: newState,
        batteryLevel: device.batteryLevel != -1 ? device.batteryLevel : existingDevice.batteryLevel,
        isBackbone: device.isBackbone || existingDevice.isBackbone,
        isPluggedIn: device.isPluggedIn || existingDevice.isPluggedIn,
        profileImage: device.profileImage ?? existingDevice.profileImage,
        // If we found it by UUID but deviceId changed, update deviceId (stale endpoint cleanup)
        deviceId: device.deviceId,
      );
      
      debugPrint('[DiscoveryService] Updated device: ${device.deviceName} (${device.uuid ?? device.deviceId}) | State: $newState');
    } else {
      _devices.add(device);
      debugPrint('[DiscoveryService] Added new device: ${device.deviceName} (${device.uuid ?? device.deviceId})');
    }
    _discoveredDevicesController.sink.add(List.from(_devices));
  }

  void _removeDevice(String id) {
    _devices.removeWhere((d) => d.deviceId == id);
    _discoveredDevicesController.sink.add(List.from(_devices));
  }

  /// Promotes an indirectly discovered peer (from mesh topology) to the visible device list.
  void addMeshDevice(String uuid, String deviceName, String relayedBy) {
    // 0. Safety: Don't show ourselves
    if (_localUuid != null && uuid == _localUuid) {
      return;
    }

    // 1. Check if we already have this device by UUID
    final index = _devices.indexWhere((d) => d.uuid == uuid);
    
    if (index >= 0) {
      final existing = _devices[index];
      // If it's a direct connection (not mesh) or already connected, don't "downgrade" to mesh view
      if (!existing.isMesh || existing.state == SessionState.connected) {
        // Just update metadata if needed
        if (existing.deviceName != deviceName && deviceName != 'Mesh Peer') {
           _devices[index] = existing.copyWith(deviceName: deviceName);
           _discoveredDevicesController.sink.add(List.from(_devices));
        }
        return;
      }
      
      // Update its relay path if it changed
      if (existing.relayedBy != relayedBy || (existing.deviceName != deviceName && deviceName != 'Mesh Peer')) {
        _devices[index] = existing.copyWith(
          deviceName: deviceName != 'Mesh Peer' ? deviceName : existing.deviceName,
          relayedBy: relayedBy,
        );
        _discoveredDevicesController.sink.add(List.from(_devices));
      }
      return;
    }

    // 2. New Mesh Device
    debugPrint('[DiscoveryService] Adding indirect mesh peer: $deviceName ($uuid) via $relayedBy');
    _devices.add(Device(
      deviceId: uuid, // Use UUID as surrogate ID for mesh peers
      deviceName: deviceName,
      uuid: uuid,
      isMesh: true,
      relayedBy: relayedBy,
      rssi: -85.0, // Assume weak signal for mesh peers as a baseline
    ));
    _discoveredDevicesController.sink.add(List.from(_devices));
  }

  void updateDeviceState(String id, SessionState state) {
    int index = _devices.indexWhere((d) => d.deviceId == id);
    if (index >= 0) {
      _devices[index].state = state;
      _discoveredDevicesController.sink.add(List.from(_devices));
      // Emit for all state changes so ChatProvider can react to disconnections
      _connectedDeviceController.sink.add(_devices[index]);
    }
  }

  int getDiscoveredDeviceCount() {
    return _devices.length;
  }

  Device? getDeviceById(String id) {
    try {
      return _devices.firstWhere((d) => d.deviceId == id);
    } catch (_) {
      return null;
    }
  }

  List<Device> getConnectedDevices() {
    return _devices.where((d) => d.state == SessionState.connected).toList();
  }

  Device? getDeviceByUuid(String uuid) {
    try {
      return _devices.firstWhere((d) => d.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  Future<void> stopAll() async {
    try {
      await stopAdvertising();
      await stopDiscovery();
      await Nearby().stopAllEndpoints();
    } catch (e) {
      debugPrint('[DiscoveryService] Error stopping all: $e');
    }
  }

  /// Handle radio (Bluetooth/WiFi) state changes.
  /// Automatically restarts discovery when radios come back online.
  Future<void> onRadioStateChanged(String radioType, bool enabled) async {
    ConnectivityLogger.event(
      LogCategory.radio,
      '$radioType ${enabled ? "enabled" : "disabled"}',
      data: {'browsing': _isBrowsing, 'advertising': _isAdvertising},
    );

    if (enabled) {
      // Radio turned ON — restart discovery after a ultra-short stabilization delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isBrowsing) {
        ConnectivityLogger.info(LogCategory.discovery,
            'Radio ON ($radioType) — restarting browsing');
        await startBrowsing(forceRestart: true);
      }
      if (_isAdvertising) {
        ConnectivityLogger.info(LogCategory.discovery,
            'Radio ON ($radioType) — restarting advertising');
        await startAdvertising(forceRestart: true);
      }
    } else {
      // Radio turned OFF — pause gracefully (connections will drop anyway)
      ConnectivityLogger.warning(LogCategory.discovery,
          'Radio OFF ($radioType) — discovery paused');
    }
  }

  /// Persist discovery state (browsing/advertising) for crash recovery.
  Future<void> persistDiscoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('discovery_was_browsing', _isBrowsing);
      await prefs.setBool('discovery_was_advertising', _isAdvertising);
      ConnectivityLogger.debug(LogCategory.discovery,
          'Persisted state: browsing=$_isBrowsing, advertising=$_isAdvertising');
    } catch (e) {
      ConnectivityLogger.error(LogCategory.discovery, 'Failed to persist state', e);
    }
  }

  /// Restore discovery state after crash/restart.
  /// Returns true if discovery should be restarted.
  Future<bool> restoreDiscoveryState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasBrowsing = prefs.getBool('discovery_was_browsing') ?? false;
      final wasAdvertising = prefs.getBool('discovery_was_advertising') ?? false;
      ConnectivityLogger.info(LogCategory.discovery,
          'Restored state: wasBrowsing=$wasBrowsing, wasAdvertising=$wasAdvertising');
      return wasBrowsing || wasAdvertising;
    } catch (e) {
      ConnectivityLogger.error(LogCategory.discovery, 'Failed to restore state', e);
      return false;
    }
  }

  void dispose() {
    _discoveredDevicesController.close();
    _connectedDeviceController.close();
    _dataReceivedController.close();
    _payloadProgressController.close();
    _fileReceivedController.close();
    _refreshTimer?.cancel();
    stopAll();
  }
}
