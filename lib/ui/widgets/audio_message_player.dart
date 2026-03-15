import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/chat_provider.dart';
import '../../core/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class AudioMessagePlayer extends StatefulWidget {
  final String path;
  final bool isMe;

  const AudioMessagePlayer({
    super.key,
    required this.path,
    required this.isMe,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  bool _isPlaying = false;
  final double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);

    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: widget.isMe ? Colors.white : AppColors.primary,
              size: 32,
            ),
            onPressed: () async {
              setState(() {
                _isPlaying = !_isPlaying;
              });
              
              if (_isPlaying) {
                await provider.playAudio(widget.path);
                // Simple simulation of progress for now as audioplayers Stream
                // can be complex to sync without a dedicated controller.
                // In a real app, we'd listen to position streams.
              } else {
                await provider.pauseAudio();
              }
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: (widget.isMe ? Colors.white : AppColors.primary).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: _progress,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: widget.isMe ? Colors.white : AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Voice Note',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: widget.isMe ? Colors.white70 : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(
                      Icons.graphic_eq,
                      size: 14,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
