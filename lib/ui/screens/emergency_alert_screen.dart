import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class EmergencyAlertScreen extends StatefulWidget {
  final String senderName;
  final String content;

  const EmergencyAlertScreen({
    super.key,
    required this.senderName,
    required this.content,
  });

  @override
  State<EmergencyAlertScreen> createState() => _EmergencyAlertScreenState();
}

class _EmergencyAlertScreenState extends State<EmergencyAlertScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final AudioPlayer _audioPlayer = AudioPlayer();
  double? _originalVolume;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    _setupVolume();
    _setupAudioContext();
    _playSiren();
  }

  Future<void> _setupAudioContext() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.defaultToSpeaker,
          },
        ),
      ));
    } catch (e) {
      debugPrint('[SOS] Error setting audio context: $e');
    }
  }

  Future<void> _setupVolume() async {
    try {
      // Get current media volume
      _originalVolume = await FlutterVolumeController.getVolume(stream: AudioStream.music);
      // Force media volume to 100%
      await FlutterVolumeController.setVolume(1.0, stream: AudioStream.music);
      // Also set alarm volume to 100% just in case
      await FlutterVolumeController.setVolume(1.0, stream: AudioStream.alarm);
      
      debugPrint('[SOS] System volume forced to 100% (was $_originalVolume)');
    } catch (e) {
      debugPrint('[SOS] Error setting system volume: $e');
    }
  }

  Future<void> _playSiren() async {
    try {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('audio/siren.mp3'));
      debugPrint('[SOS] Playing emergency siren from assets/audio/siren.mp3');
    } catch (e) {
      debugPrint('[SOS] Error playing siren: $e');
    }
  }

  @override
  void dispose() {
    _restoreVolume();
    _controller.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _restoreVolume() async {
    if (_originalVolume != null) {
      try {
        await FlutterVolumeController.setVolume(_originalVolume!, stream: AudioStream.music);
        debugPrint('[SOS] System volume restored to $_originalVolume');
      } catch (e) {
        debugPrint('[SOS] Error restoring system volume: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final color = Color.lerp(Colors.red.withValues(alpha: 0.8), Colors.black, _controller.value);
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [color!, Colors.black],
                radius: 1.5,
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 100,
              ),
              const SizedBox(height: 40),
              Text(
                'EMERGENCY SOS',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '${widget.senderName} is in need of assistance!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Text(
                  widget.content,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(40.0),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'DISMISS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
