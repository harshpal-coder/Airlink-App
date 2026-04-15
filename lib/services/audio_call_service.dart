import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:logger/logger.dart';
import 'package:audio_session/audio_session.dart';

class AudioCallService {
  static final AudioCallService _instance = AudioCallService._internal();
  factory AudioCallService() => _instance;
  AudioCallService._internal();

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  
  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _recordingDataSubscription;
  
  bool _isInit = false;
  bool _isRecording = false;
  bool _isMuted = false;

  Future<void> init() async {
    if (_isInit) return;
    
    _recorder = FlutterSoundRecorder(logLevel: Level.error);
    _player = FlutterSoundPlayer(logLevel: Level.error);

    await _recorder!.openRecorder();
    await _player!.openPlayer();
    
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth | AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    // CRITICAL: Activate the session
    await session.setActive(true);

    _isInit = true;
    debugPrint('[AudioCallService] Initialized Audio Engines and Activated Session');
  }

  /// Starts capturing audio from the microphone and yields PCM chunks.
  Future<void> startRecording(Function(Uint8List) onAudioChunk) async {
    if (!_isInit) await init();
    if (_isRecording) return;

    _recordingDataController = StreamController<Uint8List>();
    _recordingDataSubscription = _recordingDataController!.stream.listen((buffer) {
      if (!_isMuted) {
        onAudioChunk(buffer);
      }
    });

    await _recorder!.startRecorder(
      toStream: _recordingDataController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
    );
    _isRecording = true;
    debugPrint('[AudioCallService] Started recording stream');
  }

  /// Sets the mute state. If muted, audio chunks are still captured but not sent.
  void setMute(bool muted) {
    _isMuted = muted;
    debugPrint('[AudioCallService] Mute set to: $muted');
  }

  /// Toggles the speakerphone. (TODO: Fix method defining for FlutterSoundPlayer)
  Future<void> setSpeakerphone(bool enabled) async {
    // if (!_isInit) await init();
    // await _player!.setSpeakerphone(enabled);
    debugPrint('[AudioCallService] Speakerphone toggle requested (Not implemented yet): $enabled');
  }

  /// Stops capturing audio.
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    await _recorder!.stopRecorder();
    await _recordingDataSubscription?.cancel();
    await _recordingDataController?.close();
    
    _recordingDataSubscription = null;
    _recordingDataController = null;
    _isRecording = false;
    debugPrint('[AudioCallService] Stopped recording stream');
  }

  /// Starts the playback engine eagerly waiting for chunks
  Future<void> startPlaying() async {
    if (!_isInit) await init();
    // We check _isPlaying as a state flag for "should be playing"
    
    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      interleaved: false,
      bufferSize: 8192,
    );
    debugPrint('[AudioCallService] Started playback stream');
  }

  /// Feed a received audio chunk into the player buffer
  Future<void> playAudioChunk(Uint8List chunk) async {
    if (!_player!.isPlaying) {
      await startPlaying();
    }
    // feed the raw PCM bytes into the player
    try {
      await _player!.feedUint8FromStream(chunk);
    } catch (e) {
      debugPrint('[AudioCallService] Error feeding audio chunk: $e');
    }
  }

  /// Stops playback
  Future<void> stopPlaying() async {
    if (!_player!.isPlaying) return;
    await _player!.stopPlayer();
    debugPrint('[AudioCallService] Stopped playback stream');
  }

  /// Tears down both recording and playback completely 
  Future<void> endCallSession() async {
    debugPrint('[AudioCallService] Ending Call Session');
    _isMuted = false; // Reset mute for next call
    await stopRecording();
    await stopPlaying();
    
    // Deactivate session to be a good citizen
    final session = await AudioSession.instance;
    await session.setActive(false);
  }

  void dispose() {
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _isInit = false;
  }
}
