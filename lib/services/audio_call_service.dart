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
  bool _isPlaying = false;

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

    _isInit = true;
    debugPrint('[AudioCallService] Initialized Audio Engines');
  }

  /// Starts capturing audio from the microphone and yields PCM chunks.
  Future<void> startRecording(Function(Uint8List) onAudioChunk) async {
    if (!_isInit) await init();
    if (_isRecording) return;

    _recordingDataController = StreamController<Uint8List>();
    _recordingDataSubscription = _recordingDataController!.stream.listen((buffer) {
      onAudioChunk(buffer);
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
    if (_isPlaying) return;
    
    await _player!.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
      interleaved: false,
      bufferSize: 8192,
    );
    _isPlaying = true;
    debugPrint('[AudioCallService] Started playback stream');
  }

  /// Feed a received audio chunk into the player buffer
  Future<void> playAudioChunk(Uint8List chunk) async {
    if (!_isPlaying) {
      await startPlaying();
    }
    // feed the raw PCM bytes into the player
    await _player!.feedUint8FromStream(chunk);
  }

  /// Stops playback
  Future<void> stopPlaying() async {
    if (!_isPlaying) return;
    await _player!.stopPlayer();
    _isPlaying = false;
    debugPrint('[AudioCallService] Stopped playback stream');
  }

  /// Tears down both recording and playback completely 
  Future<void> endCallSession() async {
    debugPrint('[AudioCallService] Ending Call Session');
    await stopRecording();
    await stopPlaying();
  }

  void dispose() {
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _isInit = false;
  }
}
