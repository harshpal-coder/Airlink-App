import 'dart:io';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/chat_provider.dart';
import '../../services/notification_service.dart';
import '../../models/message_model.dart';
import '../../core/constants.dart';
import 'user_profile_screen.dart';
import 'image_viewer_screen.dart';
import 'security_screen.dart';
import '../providers/call_provider.dart';

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
  Message? _replyToMessage;
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
    setState(() {}); 
    
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
    
    _provider.markChatAsRead(widget.peerUuid);
    
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

    final String? replyToId = _replyToMessage?.id;
    _msgController.clear();
    setState(() {
      _replyToMessage = null;
    });
    
    _isTyping = false;
    _provider.sendTypingStatus(widget.peerUuid, false);
    await _provider.sendMessage(widget.peerUuid, text, burnDuration: _burnDuration, replyToId: replyToId);
  }

  void _onReply(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    HapticFeedback.lightImpact();
  }

  void _onReact(Message message, String emoji) {
    _provider.sendReaction(widget.peerUuid, message.id, emoji);
    HapticFeedback.mediumImpact();
  }

  Message? _findMessageById(String? id) {
    if (id == null) return null;
    try {
      return _messages.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
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

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final int size = file.size; // bytes
      if (size > 20 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File must be under 20MB')),
        );
        return;
      }
      await _provider.sendFile(widget.peerUuid, file.path!, file.name, size);
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
        actions: [
          IconButton(
            icon: const Icon(Icons.phone, size: 22, color: AppColors.primary),
            tooltip: 'Voice Call',
            onPressed: () {
              context.read<CallProvider>().makeCall(
                widget.peerUuid,
                widget.peerName,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline, size: 22, color: AppColors.primary),
            tooltip: 'End-to-End Encrypted',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SecurityScreen(
                    peerUuid: widget.peerUuid,
                    peerName: widget.peerName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
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
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final quotedMsg = _findMessageById(message.replyToId);
                  return _MessageBubble(
                    key: ValueKey(message.id),
                    message: message,
                    quotedMessage: quotedMsg,
                    isMe: message.senderUuid == (_provider.currentUser?.uuid ?? 'me') || message.senderUuid == 'me',
                    peerProfileImage: widget.peerProfileImage,
                    peerName: widget.peerName,
                    onDelete: () => _showDeleteConfirmation(message),
                    onReply: () => _onReply(message),
                    onReact: (emoji) => _onReact(message, emoji),
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

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachOption(
                    icon: Icons.image,
                    color: Colors.purpleAccent,
                    label: 'Gallery',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndSendImage();
                    },
                  ),
                  _buildAttachOption(
                    icon: Icons.insert_drive_file,
                    color: Colors.blueAccent,
                    label: 'Document',
                    onTap: () {
                      Navigator.pop(context);
                      _pickAndSendFile();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachOption({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: EdgeInsets.only(
        left: 12, 
        right: 12, 
        top: 12, 
        bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 12
      ),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyToMessage != null) _buildReplyPreview(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, color: AppColors.textMuted, size: 24),
                            onPressed: _showAttachmentOptions,
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _msgController,
                              minLines: 1,
                              maxLines: 5,
                              style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16),
                              decoration: InputDecoration(
                                hintText: _burnDuration != null 
                                  ? 'Burning (${_burnDuration!.inSeconds}s)...' 
                                  : 'Message',
                                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 16),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _burnDuration == null ? Icons.local_fire_department_outlined : Icons.local_fire_department,
                              color: _burnDuration == null ? AppColors.textMuted : Colors.orangeAccent,
                              size: 24,
                            ),
                            onPressed: _toggleBurnMode,
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  gradient: hasText 
                      ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight])
                      : const LinearGradient(colors: [Color(0xFF00BFA5), Color(0xFF1DE9B6)]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: (hasText ? AppColors.glowBlue : const Color(0xFF00BFA5)).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: hasText
                    ? IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                        onPressed: _sendMessage,
                        padding: const EdgeInsets.all(14),
                        constraints: const BoxConstraints(),
                      )
                    : GestureDetector(
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
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: provider.isRecording ? Colors.redAccent : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                provider.isRecording ? Icons.mic : Icons.mic_none_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            );
                          }
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 12, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyToMessage!.senderUuid == (_provider.currentUser?.uuid ?? 'me') || _replyToMessage!.senderUuid == 'me' ? 'You' : widget.peerName,
                  style: GoogleFonts.inter(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  _replyToMessage!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
            onPressed: () => setState(() => _replyToMessage = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final Message? quotedMessage;
  final bool isMe;
  final String? peerProfileImage;
  final String peerName;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final Function(String) onReact;

  const _MessageBubble({
    super.key,
    required this.message,
    this.quotedMessage,
    required this.isMe,
    this.peerProfileImage,
    required this.peerName,
    required this.onDelete,
    required this.onReply,
    required this.onReact,
  });

  void _showActionMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    final List<String> commonEmojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reactions Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: commonEmojis.map((emoji) => GestureDetector(
                    onTap: () {
                      onReact(emoji);
                      Navigator.pop(context);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 30)),
                  )).toList(),
                ),
              ),
              const Divider(color: Colors.white12, height: 32),
              ListTile(
                leading: const Icon(Icons.reply, color: AppColors.textPrimary),
                title: Text('Reply', style: GoogleFonts.inter(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  onReply();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: AppColors.textPrimary),
                title: Text('Copy Text', style: GoogleFonts.inter(color: AppColors.textPrimary)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text('Delete', style: GoogleFonts.inter(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = isMe ? AppColors.primary : AppColors.surfaceElevated;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showActionMenu(context),
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe) ...[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.surfaceElevated,
                    backgroundImage: peerProfileImage != null && File(peerProfileImage!).existsSync()
                        ? FileImage(File(peerProfileImage!))
                        : null,
                    child: peerProfileImage == null || !File(peerProfileImage!).existsSync()
                        ? Text(peerName.isNotEmpty ? peerName[0].toUpperCase() : '?', style: const TextStyle(fontSize: 10, color: Colors.white70))
                        : null,
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: themeColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft: Radius.circular(isMe ? 20 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (quotedMessage != null) _buildQuotedMessage(context),
                            _buildMessageContent(),
                          ],
                        ),
                      ),
                      if (message.reactions != null && message.reactions!.isNotEmpty)
                        _buildReactionsDisplay(),
                    ],
                  ),
                ),
                if (isMe) const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 40, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.sent || message.status == MessageStatus.read ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.status == MessageStatus.read ? AppColors.primary : AppColors.textMuted,
                  ),
                ],
                if (message.expiresAt != null) ...[
                  const SizedBox(width: 6),
                  _BurnCountdown(message: message),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotedMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quotedMessage!.senderUuid == message.senderUuid ? 'You' : (isMe ? peerName : 'You'),
            style: GoogleFonts.inter(color: AppColors.primaryLight, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            quotedMessage!.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: isMe ? Colors.white70 : AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    switch (message.type) {
      case MessageType.image:
        return _ImageMessageBubble(message: message, isMe: isMe);
      case MessageType.file:
        return _FileMessageBubble(message: message, isMe: isMe);
      case MessageType.audio:
        return _AudioMessageBubble(message: message, isMe: isMe);
      default:
        return Text(
          message.content,
          style: GoogleFonts.inter(
            color: isMe ? Colors.white : AppColors.textPrimary,
            fontSize: 15,
            height: 1.4,
          ),
        );
    }
  }

  Widget _buildReactionsDisplay() {
    // Group reactions by emoji
    final Map<String, int> counts = {};
    for (var emoji in message.reactions!.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: counts.entries.map((e) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.key, style: const TextStyle(fontSize: 12)),
              if (e.value > 1) ...[
                const SizedBox(width: 2),
                Text(e.value.toString(), style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ],
            ],
          ),
        )).toList(),
      ),
    );
  }
}

class _BurnCountdown extends StatefulWidget {
  final Message message;
  const _BurnCountdown({required this.message});

  @override
  State<_BurnCountdown> createState() => _BurnCountdownState();
}

class _BurnCountdownState extends State<_BurnCountdown> {
  late Timer _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateRemaining();
      if (_secondsRemaining <= 0) {
        timer.cancel();
      }
    });
  }

  void _calculateRemaining() {
    if (widget.message.expiresAt == null) return;
    final diff = widget.message.expiresAt!.difference(DateTime.now()).inSeconds;
    if (mounted) {
      setState(() {
        _secondsRemaining = diff > 0 ? diff : 0;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsRemaining <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_fire_department, size: 12, color: Colors.orangeAccent),
        const SizedBox(width: 2),
        Text(
          '${_secondsRemaining}s',
          style: GoogleFonts.inter(fontSize: 10, color: Colors.orangeAccent, fontWeight: FontWeight.bold),
        ),
      ],
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _duration = d));
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));
    _audioPlayer.onPlayerComplete.listen((_) => setState(() => _isPlaying = false));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: widget.isMe ? Colors.white : AppColors.primary,
              size: 36,
            ),
            onPressed: () async {
              if (_isPlaying) {
                await _audioPlayer.pause();
              } else {
                if (widget.message.imagePath != null) {
                  await _audioPlayer.play(DeviceFileSource(widget.message.imagePath!));
                }
              }
              setState(() => _isPlaying = !_isPlaying);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0,
                  backgroundColor: widget.isMe ? Colors.white24 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation(widget.isMe ? Colors.white : AppColors.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_isPlaying ? _position : _duration),
                  style: TextStyle(fontSize: 10, color: widget.isMe ? Colors.white70 : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _ImageMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _ImageMessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final filePath = message.imagePath;
    if (filePath == null || !File(filePath).existsSync()) {
      return const Icon(Icons.broken_image, color: AppColors.textMuted);
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => ImageViewerScreen(imagePath: filePath, heroTag: message.id)));
      },
      child: Hero(
        tag: message.id,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(filePath),
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image),
          ),
        ),
      ),
    );
  }
}

class _FileMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _FileMessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final fileName = message.fileName ?? "File";
    final fileSize = message.fileSize ?? 0;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file, color: isMe ? Colors.white : AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: GoogleFonts.inter(fontSize: 13, color: isMe ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatBytes(fileSize),
                  style: GoogleFonts.inter(fontSize: 10, color: isMe ? Colors.white70 : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}
