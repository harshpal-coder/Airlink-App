import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/messaging_service.dart';
import '../../services/discovery_service.dart';
import '../../services/audio_call_service.dart';

enum CallState { none, ringing, inCall }

class CallProvider extends ChangeNotifier {
  final MessagingService messagingService;
  final DiscoveryService discoveryService;
  final AudioCallService audioService = AudioCallService();

  CallState _callState = CallState.none;
  String? _peerUuid;
  String? _peerName;
  bool _isOutgoing = false;
  
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  StreamSubscription? _signalSub;
  StreamSubscription? _audioSub;

  CallState get callState => _callState;
  String? get peerUuid => _peerUuid;
  String? get peerName => _peerName;
  bool get isOutgoing => _isOutgoing;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;

  CallProvider({
    required this.messagingService,
    required this.discoveryService,
  }) {
    _initListeners();
  }

  void _initListeners() {
    _signalSub = messagingService.callSignalReceived.listen((data) {
      _handleCallSignal(data);
    });

    _audioSub = discoveryService.audioChunkReceived.listen((data) {
      final senderId = data['senderId'];
      final chunk = data['chunk'];
      // Verify the sender is our active peer
      if (_callState == CallState.inCall && _peerUuid != null) {
        final peerDevice = discoveryService.getDeviceByUuid(_peerUuid!);
        if (peerDevice?.deviceId == senderId) {
          audioService.playAudioChunk(chunk);
        }
      }
    });
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      return true;
    } else {
      debugPrint('[CallProvider] Microphone permission denied');
      return false;
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    audioService.setMute(_isMuted);
    notifyListeners();
  }

  void toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await audioService.setSpeakerphone(_isSpeakerOn);
    notifyListeners();
  }

  void _handleCallSignal(Map<String, dynamic> data) async {
    final signal = data['signal'];
    final senderUuid = data['senderUuid'];
    final senderName = data['senderName'];

    if (signal == 'request') {
      if (_callState != CallState.none) {
        // Already in a call, auto-reject
        await messagingService.sendCallSignal(senderUuid, 'reject');
        return;
      }
      _callState = CallState.ringing;
      _peerUuid = senderUuid;
      _peerName = senderName;
      _isOutgoing = false;
      notifyListeners();
    } else if (signal == 'accept') {
      if (_callState == CallState.ringing && _peerUuid == senderUuid && _isOutgoing) {
        _startCall();
      }
    } else if (signal == 'reject') {
      if (_callState == CallState.ringing && _peerUuid == senderUuid && _isOutgoing) {
        _endCall();
      }
    } else if (signal == 'end') {
      if (_callState != CallState.none && _peerUuid == senderUuid) {
        _endCall();
      }
    }
  }

  Future<void> makeCall(String targetUuid, String targetName) async {
    if (_callState != CallState.none) return;

    if (!await _requestPermissions()) {
      return;
    }

    _callState = CallState.ringing;
    _peerUuid = targetUuid;
    _peerName = targetName;
    _isOutgoing = true;
    notifyListeners();

    await messagingService.sendCallSignal(targetUuid, 'request');
  }

  Future<void> acceptCall() async {
    if (_callState == CallState.ringing && !_isOutgoing && _peerUuid != null) {
      if (!await _requestPermissions()) {
        await rejectCall();
        return;
      }
      await messagingService.sendCallSignal(_peerUuid!, 'accept');
      _startCall();
    }
  }

  Future<void> rejectCall() async {
    if (_callState == CallState.ringing && !_isOutgoing && _peerUuid != null) {
      await messagingService.sendCallSignal(_peerUuid!, 'reject');
      _endCall();
    }
  }

  Future<void> endCall() async {
    if (_peerUuid != null) {
      await messagingService.sendCallSignal(_peerUuid!, 'end');
    }
    _endCall();
  }

  void _startCall() async {
    _callState = CallState.inCall;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();

    final endpointId = discoveryService.getDeviceByUuid(_peerUuid!)?.deviceId;
    
    await audioService.startRecording((chunk) async {
      if (_callState == CallState.inCall && endpointId != null) {
        await discoveryService.sendAudioChunkToEndpoint(endpointId, chunk);
      }
    });
    await audioService.startPlaying();
  }

  void _endCall() async {
    _callState = CallState.none;
    _peerUuid = null;
    _peerName = null;
    _isOutgoing = false;
    _isMuted = false;
    _isSpeakerOn = false;
    notifyListeners();
    
    await audioService.endCallSession();
  }

  @override
  void dispose() {
    _signalSub?.cancel();
    _audioSub?.cancel();
    audioService.dispose();
    super.dispose();
  }
}
