import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
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
      await _provider.sendGroupFile(widget.groupId, file.path!, file.name, size);
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
            padding: message.type == MessageType.image || message.type == MessageType.file
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
                : message.type == MessageType.file
                    ? _GroupFileBubble(message: message, isMe: isMe)
                    : Text(
                        message.content,
                        style: GoogleFonts.inter(fontSize: 15, color: Colors.white, height: 1.4),
                      ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('hh:mm a').format(message.timestamp),
                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                _buildStatusIcon(message),
              ] else if (message.hopCount > 0) ...[
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(Message message) {
    if (message.status == MessageStatus.sending) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primaryLight),
      );
    }
    if (message.status == MessageStatus.relay) {
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
    return Icon(
      message.status == MessageStatus.sent || message.status == MessageStatus.delivered || message.status == MessageStatus.read
          ? Icons.done_all
          : Icons.done,
      size: 14,
      color: message.status == MessageStatus.read ? AppColors.success : AppColors.textMuted,
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
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),
                decoration: BoxDecoration(
                  color: AppColors.bgDark, 
                  borderRadius: BorderRadius.circular(28), 
                  border: Border.all(color: AppColors.surfaceElevated),
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
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 16),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (text) {
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
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
                    : const LinearGradient(colors: [AppColors.surfaceElevated, AppColors.surfaceElevated]),
                shape: BoxShape.circle,
                boxShadow: hasText ? [BoxShadow(color: AppColors.glowBlue.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))] : null,
              ),
              child: IconButton(
                icon: Icon(Icons.send_rounded, color: hasText ? Colors.white : AppColors.textMuted, size: 24),
                onPressed: hasText ? _sendMessage : null,
                padding: const EdgeInsets.all(14),
                constraints: const BoxConstraints(),
              ),
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

// ─── Group File Bubble ─────────────────────────────────────────
class _GroupFileBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  const _GroupFileBubble({required this.message, required this.isMe});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d > 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return "${d.toStringAsFixed(1)} ${suffixes[i]}";
  }

  @override
  Widget build(BuildContext context) {
    final fileName = message.fileName ?? 'Unknown File';
    final fileSize = message.fileSize ?? 0;
    final filePath = message.imagePath;

    return InkWell(
      onTap: () {
        if (filePath != null) {
          Provider.of<ChatProvider>(context, listen: false).openFile(filePath);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withValues(alpha: 0.2) : AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.insert_drive_file,
                color: isMe ? Colors.white : AppColors.primaryLight,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatBytes(fileSize),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isMe ? Colors.white70 : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
