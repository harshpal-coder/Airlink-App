import 'dart:async';
import 'dart:convert';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/device_model.dart';
import 'package:flutter/foundation.dart';


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


  final List<Device> _devices = [];
  String _userName = 'Unknown';
  Map<String, String> _knownDevices = {}; // UUID -> Name for quick lookup
  String? _localUuid;
  bool _isBrowsing = false;
  bool _isAdvertising = false;
  
  bool get isCurrentlyBrowsing => _isBrowsing;
  bool get isCurrentlyAdvertising => _isAdvertising;

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

    // Only update if significant change to reduce UI churn
    bool significant = (oldBattery - batteryLevel).abs() > 2 || 
                      (isBackbone != null && isBackbone != oldBackbone) ||
                      (isPluggedIn != null && isPluggedIn != oldPluggedIn) ||
                      (batteryLevel < 20 && oldBattery >= 20); // Always notify low battery crossing

    _devices[index].batteryLevel = batteryLevel;
    if (isBackbone != null) _devices[index].isBackbone = isBackbone;
    if (isPluggedIn != null) _devices[index].isPluggedIn = isPluggedIn;
    
    // Auto-update RSSI if it was extremely low to make it "visible" to mesh logic
    if (_devices[index].rssi <= -100) {
      _devices[index].rssi = -60.0; // Assume decent signal if we get a battery update
      significant = true;
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
      _devices[index].rssi = rssi; // Update silenty
    }
  }


  Future<bool> init(String userName, {String? localUuid}) async {
    _userName = userName;
    _localUuid = localUuid;
    _devices.clear();
    bool permissionsGranted = await _requestPermissions();
    return permissionsGranted;
  }

  void setStrategy(Strategy newStrategy) {
    strategy = newStrategy;
    debugPrint('[DiscoveryService] Strategy changed to: $newStrategy');
  }

  Future<bool> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
      Permission.notification,
    ].request();

    return true;
  }

  Future<void> startBrowsing({bool forceRestart = false}) async {
    if (_isBrowsing && !forceRestart) {
      debugPrint('[DiscoveryService] Already browsing. Skipping redundant start.');
      return;
    }
    
    // Aggressively try to stop to prevent STATUS_ALREADY_DISCOVERING
    if (_isBrowsing || forceRestart) {
      await stopDiscovery();
      await Future.delayed(const Duration(milliseconds: 300)); // Increased safety delay
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
              
              // Enhanced Exponential Backoff / Adaptive retry logic
              int retryCount = _devices[existingIndex].retryCount;
              DateTime? lastRetry = _devices[existingIndex].lastRetry;
              
              if (lastRetry != null) {
                final diff = DateTime.now().difference(lastRetry).inSeconds;
                // Wait time: 0, 10, 30, 60, 120... (max 5 minutes)
                int waitTime = 0;
                if (retryCount > 0) {
                  waitTime = (retryCount == 1 ? 10 : (retryCount == 2 ? 30 : (retryCount == 3 ? 60 : 300)));
                }

                if (diff < waitTime) {
                  debugPrint('[DiscoveryService] Throttling reconnect to $displayName. Waiting ${waitTime - diff}s more.');
                  return;
                }
              }

              // Tie-breaker: Only one side initiates to avoid connection collision
              // We use string comparison of UUIDs as a stable, decentralized way to decide
              if (_localUuid != null &&
                  _localUuid!.compareTo(discoveredUuid) > 0) {
                debugPrint(
                  '[DiscoveryService] Found known device "$displayName" ($discoveredUuid). Tie-breaker WON. Initiating auto-reconnect...',
                );
                _devices[existingIndex].lastRetry = DateTime.now();
                _devices[existingIndex].retryCount++;
                connect(_devices[existingIndex]);
              } else {
                debugPrint(
                  '[DiscoveryService] Found known device "$displayName" ($discoveredUuid). Tie-breaker LOST. Waiting for peer to initiate...',
                );
                // Wait a bit longer (e.g. 15s), then try ourselves if the peer hasn't connected
                // This acts as a fallback in case the peer's tie-breaker implementation fails
                Future.delayed(const Duration(seconds: 15), () {
                  final idx = _devices.indexWhere((d) => d.deviceId == id);
                  if (idx >= 0 && _devices[idx].state == SessionState.notConnected) {
                    debugPrint(
                      '[DiscoveryService] Peer did not connect within fallback timeout. Initiating connection as manual fallback...',
                    );
                    _devices[idx].lastRetry = DateTime.now();
                    _devices[idx].retryCount++;
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
      await Future.delayed(const Duration(milliseconds: 300)); // Increased safety delay
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
                String str = utf8.decode(payload.bytes!);
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
          if (status == Status.CONNECTED) {
            updateDeviceState(id, SessionState.connected);
          } else {
            updateDeviceState(id, SessionState.notConnected);
          }
        },
        onDisconnected: (id) {
          updateDeviceState(id, SessionState.notConnected);
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

  Future<void> connect(Device device) async {
    if (device.state == SessionState.connecting ||
        device.state == SessionState.connected) {
      debugPrint(
        '[DiscoveryService] Already connecting/connected to ${device.deviceName}. Skipping.',
      );
      return;
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
                String str = utf8.decode(payload.bytes!);
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
          if (status == Status.CONNECTED) {
            updateDeviceState(id, SessionState.connected);
          } else {
            updateDeviceState(id, SessionState.notConnected);
          }
        },
        onDisconnected: (id) {
          updateDeviceState(id, SessionState.notConnected);
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
      final bytes = Uint8List.fromList(utf8.encode(message));
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

  void dispose() {
    _discoveredDevicesController.close();
    _connectedDeviceController.close();
    _dataReceivedController.close();
    _payloadProgressController.close();
    _fileReceivedController.close();
    stopAll();
  }
}
