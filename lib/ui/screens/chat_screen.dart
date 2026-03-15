import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:google_fonts/google_fonts.dart';
import '../../services/chat_provider.dart';
import '../../services/notification_service.dart';
import '../../models/message_model.dart';
import '../../core/constants.dart';
import '../widgets/audio_message_player.dart';

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
  final ImagePicker _picker = ImagePicker();
  Timer? _typingTimer;
  bool _isTyping = false;

  List<Message> _messages = [];
  late ChatProvider _provider;

  @override
  void initState() {
    super.initState();
    NotificationService.activeChatUuid = widget.peerUuid;
    _msgController.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = Provider.of<ChatProvider>(context, listen: false);
    _provider.addListener(_onProviderUpdate);
    _loadMessages();
  }

  void _onTextChanged() {
    setState(() {}); // Rebuild input area
    
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
    _provider.removeListener(_onProviderUpdate);
    _msgController.removeListener(_onTextChanged);
    _typingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final msgs = await _provider.getMessages(widget.peerUuid);
    if (!mounted) return;
    
    // Mark as read whenever messages are loaded/refreshed while on this screen
    _provider.markChatAsRead(widget.peerUuid);
    
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
    _isTyping = false;
    _provider.sendTypingStatus(widget.peerUuid, false);
    await _provider.sendMessage(widget.peerUuid, text);
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      if (!mounted) return;
      await _provider.sendImage(widget.peerUuid, image.path);
    }
  }

  Future<void> _pickPdf() async {
    await _provider.sendPdf(widget.peerUuid);
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.textMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildAttachmentItem(Icons.photo_library, 'Gallery', () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  }),
                  _buildAttachmentItem(Icons.camera_alt, 'Camera', () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  }),
                  _buildAttachmentItem(Icons.picture_as_pdf, 'Document', () {
                    Navigator.pop(context);
                    _pickPdf();
                  }),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentItem(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textPrimary)),
      ],
    );
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
        title: Consumer<ChatProvider>(
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
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDark,
          image: DecorationImage(
            image: const NetworkImage('https://www.transparenttextures.com/patterns/cubes.png'),
            repeat: ImageRepeat.repeat,
            colorFilter: ColorFilter.mode(Colors.white.withValues(alpha: 0.03), BlendMode.srcOver),
          ),
        ),
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
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.heavyImpact();
          _showDeleteConfirmation(message);
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
                    backgroundImage: widget.peerProfileImage != null && File(widget.peerProfileImage!).existsSync()
                        ? FileImage(File(widget.peerProfileImage!))
                        : null,
                    child: widget.peerProfileImage == null || !File(widget.peerProfileImage!).existsSync()
                        ? Text(
                            widget.peerName[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                  padding: message.type == MessageType.image && (isMe || message.isFileAccepted)
                      ? EdgeInsets.zero
                      : const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : const LinearGradient(colors: [AppColors.bubbleRec, AppColors.surfaceElevated], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                      bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2)),
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
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message),
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
        return const Icon(Icons.shortcut, size: 14, color: AppColors.primaryLight);
    }
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

  Widget _buildMessageContent(Message message, {required bool isMe}) {
    if (message.type == MessageType.text) {
      return Text(message.content, style: GoogleFonts.inter(fontSize: 15, color: Colors.white, height: 1.4));
    } else if (message.type == MessageType.image) {
      bool isAccepted = isMe || message.isFileAccepted;
      bool isPathValid = message.content.contains(Platform.pathSeparator) || message.content.contains('/');
      
      return Column(
        children: [
          if (isAccepted)
            if (isPathValid)
              GestureDetector(
                onTap: () => _provider.openFile(message.content),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(message.content),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 150,
                      width: 200,
                      color: AppColors.surfaceElevated,
                      child: const Icon(Icons.broken_image, color: AppColors.textMuted, size: 40),
                    ),
                  ),
                ),
              )
            else
              _buildFilePlaceholder(Icons.image, 'Processing Image...')
          else
            _buildFilePlaceholder(Icons.image, 'Image Shared'),
          if (!isMe && !message.isFileAccepted)
            _buildDownloadButton(message, 'Accept Image'),
        ],
      );
    } else if (message.type == MessageType.pdf) {
      bool isAccepted = isMe || message.isFileAccepted;
      bool isPathValid = message.content.contains(Platform.pathSeparator) || message.content.contains('/');
      bool isDownloading = !isMe && (message.progress ?? 0) < 1.0 && (message.progress ?? 0) > 0;

      return GestureDetector(
        onTap: (isAccepted && isPathValid) ? () => _provider.openFile(message.content) : null,
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.picture_as_pdf, 
                  color: isAccepted ? Colors.white : Colors.white38, 
                  size: 32
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.basename(message.content),
                    style: GoogleFonts.inter(
                      color: isAccepted ? Colors.white : Colors.white38, 
                      fontWeight: FontWeight.w600, 
                      fontSize: 13
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isAccepted && isPathValid)
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white70, size: 18),
                    onPressed: () => _provider.shareFile(message.content, fileName: p.basename(message.content)),
                  ),
              ],
            ),
            if (!isAccepted)
              _buildDownloadButton(message, 'Accept PDF')
            else if (!isPathValid || isDownloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isDownloading ? 'Downloading...' : 'Processing...',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Tap to Open',
                      style: GoogleFonts.inter(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new, color: Colors.white70, size: 12),
                  ],
                ),
              ),
          ],
        ),
      );
    } else if (message.type == MessageType.audio) {
      bool isPathValid = message.content.contains(Platform.pathSeparator) || message.content.contains('/');
      if (!isPathValid) {
        return _buildFilePlaceholder(Icons.mic, 'Processing Voice Note...');
      }
      return AudioMessagePlayer(
        path: message.content,
        isMe: isMe,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFilePlaceholder(IconData icon, String label) {
    return Container(
      height: 120,
      width: 200,
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white24, size: 40),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(Message message, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ElevatedButton.icon(
        onPressed: () => _provider.acceptFile(message.id),
        icon: const Icon(Icons.download_rounded, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }

  Widget _buildInputArea() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            InkWell(
              onTap: _showAttachmentMenu,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceElevated, shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, color: AppColors.primaryLight, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: AppColors.bgDark, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.surfaceElevated)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        minLines: 1,
                        maxLines: 5,
                        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 4),
                      child: hasText
                          ? IconButton(
                              icon: const Icon(Icons.send_rounded, color: AppColors.primary, size: 24),
                              onPressed: _sendMessage,
                            )
                          : Consumer<ChatProvider>(
                              builder: (context, provider, child) {
                                return GestureDetector(
                                  onLongPressStart: (_) {
                                    HapticFeedback.mediumImpact();
                                    provider.startVoiceRecording();
                                  },
                                  onLongPressEnd: (_) {
                                    HapticFeedback.lightImpact();
                                    provider.stopAndSendVoiceNote(widget.peerUuid);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.mic_rounded,
                                      color: provider.isRecording ? Colors.redAccent : AppColors.textMuted,
                                      size: 24,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
