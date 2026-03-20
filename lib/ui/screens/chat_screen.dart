import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/chat_provider.dart';
import '../../services/notification_service.dart';
import '../../models/message_model.dart';
import '../../core/constants.dart';
import 'user_profile_screen.dart';
import 'image_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String peerUuid;
  final String peerName;
  final String? peerProfileImage;

  const ChatScreen({
    super.key,
    required this.peerUuid,
    required this.peerName,
    this.peerProfileImage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  bool _isTyping = false;
  Duration? _burnDuration; // null = off
  StreamSubscription? _messageUpdateSub;

  List<Message> _messages = [];
  late ChatProvider _provider;
  bool _isInit = true;

  @override
  void initState() {
    super.initState();
    NotificationService.activeChatUuid = widget.peerUuid;
    _msgController.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _provider = Provider.of<ChatProvider>(context, listen: false);
      _messageUpdateSub = _provider.messageUpdatedStream.listen((peerUuid) {
        if (!mounted) return;
        if (peerUuid == null || peerUuid == widget.peerUuid || peerUuid == 'broadcast') {
          _loadMessages();
        }
      });
      _loadMessages();
      _isInit = false;
    }
  }

  void _onTextChanged() {
    // Only rebuild the send button area by using another local state or a smaller builder if needed,
    // but for now let's just keep the local setState for text field responsiveness, 
    // it's generally fast enough for small text.
    setState(() {}); 
    
    // Typing status logic
    if (!_isTyping && _msgController.text.isNotEmpty) {
      _isTyping = true;
      _provider.sendTypingStatus(widget.peerUuid, true);
    }
    
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        _provider.sendTypingStatus(widget.peerUuid, false);
      }
    });
  }

  @override
  void dispose() {
    if (NotificationService.activeChatUuid == widget.peerUuid) {
      NotificationService.activeChatUuid = null;
    }
    _messageUpdateSub?.cancel();
    _msgController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _loadMessages() async {
    final msgs = await _provider.getMessages(widget.peerUuid);
    if (!mounted) return;
    
    // Mark as read
    _provider.markChatAsRead(widget.peerUuid);
    
    // Reverse messages for use with reversed: true ListView
    final reversedMsgs = msgs.reversed.toList();

    setState(() {
      _messages = reversedMsgs;
      _isInit = false;
    });
  }

  void _toggleBurnMode() {
    setState(() {
      if (_burnDuration == null) {
        _burnDuration = const Duration(seconds: 30);
      } else if (_burnDuration!.inSeconds == 30) {
        _burnDuration = const Duration(minutes: 5);
      } else {
        _burnDuration = null;
      }
    });
    
    HapticFeedback.lightImpact();
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    _isTyping = false;
    _provider.sendTypingStatus(widget.peerUuid, false);
    await _provider.sendMessage(widget.peerUuid, text, burnDuration: _burnDuration);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (picked != null) {
      await _provider.sendImage(widget.peerUuid, picked.path);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.7),
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfileScreen(
                  peerUuid: widget.peerUuid,
                  peerName: widget.peerName,
                  peerProfileImage: widget.peerProfileImage,
                ),
              ),
            );
          },
          child: Consumer<ChatProvider>(
            builder: (context, provider, child) {
              final isConnected = provider.isPeerConnected(widget.peerUuid);
              final battery = provider.getBatteryForPeer(widget.peerUuid);
              final isTyping = provider.typingPeers[widget.peerUuid] ?? false;

              return Row(
                children: [
                  Hero(
                    tag: 'device_${widget.peerUuid}',
                    child: Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.surfaceElevated,
                          radius: 18,
                          backgroundImage: widget.peerProfileImage != null && File(widget.peerProfileImage!).existsSync()
                              ? FileImage(File(widget.peerProfileImage!))
                              : null,
                          child: widget.peerProfileImage == null || !File(widget.peerProfileImage!).existsSync()
                              ? Text(
                                  widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                )
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isConnected ? AppColors.success : AppColors.offline,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surfaceDark, width: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.peerName,
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: isTyping
                              ? Text(
                                  'typing...',
                                  key: const ValueKey('typing'),
                                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
                                )
                              : Text(
                                  isConnected ? (battery != null ? 'Connected • $battery%' : 'Connected') : 'Offline',
                                  key: const ValueKey('status'),
                                  style: GoogleFonts.inter(fontSize: 11, color: isConnected ? AppColors.success.withValues(alpha: 0.8) : AppColors.textMuted),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: Consumer<ChatProvider>(
        builder: (context, provider, child) {
          final wallpaperPath = provider.chatWallpaperPath;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              image: wallpaperPath != null && File(wallpaperPath).existsSync()
                  ? DecorationImage(
                      image: FileImage(File(wallpaperPath)),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.4),
                        BlendMode.darken,
                      ),
                    )
                  : DecorationImage(
                      image: const NetworkImage('https://www.transparenttextures.com/patterns/carbon-fibre.png'),
                      repeat: ImageRepeat.repeat,
                      colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: 0.02), BlendMode.srcOver),
                    ),
            ),
            child: child,
          );
        },
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                reverse: true, // Efficient for chats - new items appear at bottom without scrolling
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _MessageBubble(
                    key: ValueKey(_messages[index].id),
                    message: _messages[index],
                    isMe: _messages[index].senderUuid == (_provider.currentUser?.uuid ?? 'me') || _messages[index].senderUuid == 'me',
                    peerProfileImage: widget.peerProfileImage,
                    peerName: widget.peerName,
                    onDelete: () => _showDeleteConfirmation(_messages[index]),
                  );
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Message message) {
    final bool canRetry = message.status == MessageStatus.queued || message.status == MessageStatus.failed;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(canRetry ? 'Message Options' : 'Delete Message?', style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(canRetry ? 'What would you like to do with this message?' : 'This will remove the message from your device.', style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          if (canRetry)
            TextButton(
              onPressed: () {
                _provider.retryMessage(message.id);
                Navigator.pop(context);
              },
              child: Text('Try Resending', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textMuted))),
          TextButton(
            onPressed: () {
              _provider.deleteMessage(message.id);
              Navigator.pop(context);
            },
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: SafeArea(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onLongPressStart: (_) {
                      HapticFeedback.heavyImpact();
                      Provider.of<ChatProvider>(context, listen: false).startRecording();
                    },
                    onLongPressEnd: (_) {
                      HapticFeedback.mediumImpact();
                      Provider.of<ChatProvider>(context, listen: false).stopRecording(widget.peerUuid, burnDuration: _burnDuration);
                    },
                    child: Consumer<ChatProvider>(
                      builder: (context, provider, child) {
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: provider.isRecording ? Colors.redAccent.withValues(alpha: 0.2) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            provider.isRecording ? Icons.mic : Icons.mic_none_rounded,
                            color: provider.isRecording ? Colors.redAccent : AppColors.textMuted,
                            size: 24,
                          ),
                        );
                      }
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 24),
                    onPressed: _pickAndSendImage,
                    tooltip: 'Send image',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      minLines: 1,
                      maxLines: 5,
                      style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: _burnDuration != null 
                          ? 'Burning (${_burnDuration!.inSeconds}s)...' 
                          : 'Type a message...',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _burnDuration == null ? Icons.local_fire_department_outlined : Icons.local_fire_department,
                      color: _burnDuration == null ? AppColors.textMuted : Colors.orangeAccent,
                      size: 22,
                    ),
                    onPressed: _toggleBurnMode,
                    tooltip: 'Self-destruct mode',
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 2, right: 2),
                    decoration: BoxDecoration(
                      gradient: hasText 
                          ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight])
                          : null,
                      color: hasText ? null : AppColors.surfaceElevated,
                      shape: BoxShape.circle,
                      boxShadow: hasText ? [BoxShadow(color: AppColors.glowBlue, blurRadius: 10, spreadRadius: 1)] : [],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.send_rounded, 
                        color: hasText ? Colors.white : AppColors.textMuted, 
                        size: 22
                      ),
                      onPressed: hasText ? _sendMessage : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Optimized UI Components ---

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String? peerProfileImage;
  final String peerName;
  final VoidCallback onDelete;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.peerProfileImage,
    required this.peerName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.heavyImpact();
          onDelete();
        },
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) ...[
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.surfaceElevated,
                    backgroundImage: peerProfileImage != null && File(peerProfileImage!).existsSync()
                        ? FileImage(File(peerProfileImage!))
                        : null,
                    child: peerProfileImage == null || !File(peerProfileImage!).existsSync()
                        ? Text(
                            peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              colors: [AppColors.primary, Color(0xFF0061AC)], 
                              begin: Alignment.topLeft, 
                              end: Alignment.bottomRight
                            )
                          : LinearGradient(
                              colors: [AppColors.surfaceDark.withValues(alpha: 0.8), AppColors.surfaceElevated.withValues(alpha: 0.6)], 
                              begin: Alignment.topLeft, 
                              end: Alignment.bottomRight
                            ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMe ? 20 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 20),
                      ),
                      border: Border.all(
                        color: isMe ? AppColors.primaryLight.withValues(alpha: 0.3) : AppColors.glassBorder.withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMe ? AppColors.glowBlue : Colors.black.withValues(alpha: 0.1), 
                          blurRadius: 8, 
                          offset: const Offset(0, 4)
                        ),
                      ],
                    ),
                    child: _buildMessageContent(message, isMe: isMe),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(left: isMe ? 0 : 36, right: isMe ? 4 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(message.timestamp),
                    style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
                  ),
                  if (!isMe && message.hopCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 0.5),
                      ),
                      child: Text(
                        '${message.hopCount} hops',
                        style: GoogleFonts.inter(fontSize: 9, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message),
                  ],
                  if (message.expiresAt != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.local_fire_department, size: 12, color: Colors.orangeAccent.withValues(alpha: 0.8)),
                    const SizedBox(width: 2),
                    _BurnCountdown(expiresAt: message.expiresAt!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Message message) {
    switch (message.status) {
      case MessageStatus.queued:
        return const Icon(Icons.schedule, size: 14, color: AppColors.textMuted);
      case MessageStatus.sending:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
        );
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 14, color: AppColors.textMuted);
      case MessageStatus.delivered:
      case MessageStatus.read:
        return Icon(
          Icons.done_all, 
          size: 14, 
          color: message.status == MessageStatus.read ? AppColors.success : AppColors.textMuted
        );
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
      case MessageStatus.relay:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Relaying via ${message.relayedVia ?? 'Mesh'}',
              style: GoogleFonts.inter(fontSize: 9, color: AppColors.primaryLight, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.shortcut, size: 12, color: AppColors.primaryLight),
          ],
        );
    }
  }

  Widget _buildMessageContent(Message message, {required bool isMe}) {
    if (message.type == MessageType.image) {
      return _ImageMessageBubble(message: message, isMe: isMe);
    }
    if (message.type == MessageType.text) {
      return Text(message.content, style: GoogleFonts.inter(fontSize: 15, color: Colors.white, height: 1.4));
    }
    
    if (message.type == MessageType.audio) {
      return _AudioMessageBubble(message: message, isMe: isMe);
    }
    
    return const SizedBox.shrink();
  }

}

class _BurnCountdown extends StatefulWidget {
  final DateTime expiresAt;
  const _BurnCountdown({required this.expiresAt});

  @override
  State<_BurnCountdown> createState() => _BurnCountdownState();
}

class _BurnCountdownState extends State<_BurnCountdown> {
  late Timer _timer;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _calculateSeconds();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _calculateSeconds();
          if (_secondsLeft <= 0) {
            _timer.cancel();
          }
        });
      }
    });
  }

  void _calculateSeconds() {
    _secondsLeft = widget.expiresAt.difference(DateTime.now()).inSeconds;
    if (_secondsLeft < 0) _secondsLeft = 0;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) return const SizedBox.shrink();
    return Text(
      '${_secondsLeft}s',
      style: GoogleFonts.inter(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
    );
  }
}

class _AudioMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  const _AudioMessageBubble({required this.message, required this.isMe});

  @override
  State<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<_AudioMessageBubble> {
  bool _isPlaying = false;
  late AudioPlayer _localPlayer;

  @override
  void initState() {
    super.initState();
    _localPlayer = AudioPlayer();
    _localPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _localPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        if (_isPlaying) {
          await _localPlayer.pause();
        } else {
          await _localPlayer.play(DeviceFileSource(widget.message.content));
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 100,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: _isPlaying ? const LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.transparent) : null,
              ),
              const SizedBox(height: 4),
              Text(
                'Voice Message',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Image Message Bubble ───────────────────────────────────────
class _ImageMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  const _ImageMessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final imagePath = message.imagePath;
    if (imagePath == null || !File(imagePath).existsSync()) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 32),
          const SizedBox(width: 8),
          Text('Image unavailable', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
        ],
      );
    }
    final heroTag = 'img_${message.id}';
    final progress = message.progress ?? 1.0;
    return GestureDetector(
      onTap: progress >= 1.0 ? () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(imagePath: imagePath, heroTag: heroTag),
        ),
      ) : null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Hero(
              tag: heroTag,
              child: Opacity(
                opacity: progress < 1.0 ? 0.6 : 1.0,
                child: Image.file(
                  File(imagePath),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          if (progress < 1.0)
            Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
