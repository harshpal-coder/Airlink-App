import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/chat_provider.dart';
import '../../services/notification_service.dart';
import 'group_info_screen.dart';
import '../../models/message_model.dart';
import '../../core/constants.dart';
import 'image_viewer_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  late ChatProvider _provider;

  @override
  void initState() {
    super.initState();
    NotificationService.activeChatUuid = widget.groupId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = Provider.of<ChatProvider>(context, listen: false);
    _provider.addListener(_onProviderUpdate);
    _loadMessages();
  }

  @override
  void dispose() {
    if (NotificationService.activeChatUuid == widget.groupId) {
      NotificationService.activeChatUuid = null;
    }
    _provider.removeListener(_onProviderUpdate);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final msgs = await _provider.getMessages(widget.groupId);
    if (!mounted) return;
    
    _provider.markGroupAsRead(widget.groupId);
    
    setState(() {
      _messages = msgs;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    await _provider.sendGroupMessage(widget.groupId, widget.groupName, text);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (picked != null) {
      await _provider.sendGroupImage(widget.groupId, picked.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark.withValues(alpha: 0.95),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GroupInfoScreen(groupId: widget.groupId)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                radius: 18,
                child: const Icon(Icons.group_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupName,
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Tap for group info',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
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
                      image: const NetworkImage('https://www.transparenttextures.com/patterns/cubes.png'),
                      repeat: ImageRepeat.repeat,
                      colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: 0.03), BlendMode.srcOver),
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
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final myUuid = _provider.currentUser?.uuid ?? 'me';
    final isMe = message.senderUuid == myUuid || message.senderUuid == 'me';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                message.senderName,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryLight),
              ),
            ),
          ],
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: message.type == MessageType.image
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: isMe
                  ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(colors: [AppColors.bubbleRec, AppColors.surfaceElevated], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20).copyWith(
                bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
              ),
            ),
            child: message.type == MessageType.image
                ? _GroupImageBubble(message: message)
                : Text(
                    message.content,
                    style: GoogleFonts.inter(fontSize: 15, color: Colors.white, height: 1.4),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('hh:mm a').format(message.timestamp),
            style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Image picker button
            IconButton(
              icon: const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 24),
              tooltip: 'Send Image',
              onPressed: _pickAndSendImage,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.surfaceElevated)),
                child: TextField(
                  controller: _msgController,
                  style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: AppColors.primary, size: 28),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Group Image Bubble ────────────────────────────────────────
class _GroupImageBubble extends StatelessWidget {
  final Message message;
  const _GroupImageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final imagePath = message.imagePath;
    if (imagePath == null || !File(imagePath).existsSync()) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 32),
            const SizedBox(width: 8),
            Text('Image unavailable', style: GoogleFonts.inter(fontSize: 13, color: Colors.white54)),
          ],
        ),
      );
    }
    final heroTag = 'grp_img_${message.id}';
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
            borderRadius: BorderRadius.circular(16),
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
