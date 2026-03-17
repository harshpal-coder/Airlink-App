import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/chat_provider.dart';
import '../../core/constants.dart';
import '../widgets/profile_preview_dialog.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).loadChats();
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark.withValues(alpha: 0.8),
        elevation: 0,
        centerTitle: false,
        title: Text(
          AppConstants.appName,
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        actions: [
          _buildMeshStatusBadge(),
          IconButton(
            icon: const Icon(
              Icons.sos_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            onPressed: () => _showSOSConfirmation(context),
          ),
          IconButton(
            icon: const Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_display_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Glow

          Selector<ChatProvider, List>(
            selector: (_, p) => p.chats,
            builder: (context, chats, _) {
              if (chats.isEmpty) return _buildEmptyState(context);
              return ListView.builder(
                padding: const EdgeInsets.only(top: 110, bottom: 100),
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  return _ChatTile(
                    key: ValueKey(chats[index].peerUuid),
                    chat: chats[index],
                  );
                },
              );
            },
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.pushNamed(context, '/discovery'),
          backgroundColor: AppColors.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(Icons.radar_rounded, color: Colors.white),
          label: Text(
            'Discover',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 80,
              color: AppColors.textMuted.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Quiet here...',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Connect with nearby devices to start chatting',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/discovery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              'Find Friends',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshStatusBadge() {
    return Selector<ChatProvider, int>(
      selector: (_, p) => p.reachablePeersCount,
      builder: (context, nodeCount, _) {
        if (nodeCount == 0) return const SizedBox.shrink();
        return Center(
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.meshBadge.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.meshBadge.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hub_rounded, size: 14, color: AppColors.meshBadge),
                const SizedBox(width: 6),
                Text(
                  '$nodeCount ${nodeCount == 1 ? 'PEER' : 'PEERS'}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.meshBadge,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSOSConfirmation(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              'Broadcast SOS?',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'This will send an emergency alert to all nearby devices in the mesh network. Use only in real emergencies.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              provider.sendSOS();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SOS Broadcast Sent!'),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('BROADCAST'),
          ),
        ],
      ),
    );
  }
}

// --- Optimized List Item Component ---

class _ChatTile extends StatelessWidget {
  final dynamic chat;

  const _ChatTile({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);

    return Selector<ChatProvider, (bool, bool)>(
      selector: (_, p) => (p.isPeerConnected(chat.peerUuid), p.typingPeers[chat.peerUuid] ?? false),
      builder: (context, status, _) {
        final bool isConnected = status.$1;
        final bool isTyping = status.$2;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                provider.markChatAsRead(chat.peerUuid);
                Navigator.pushNamed(
                  context,
                  '/chat',
                  arguments: {
                    'peerUuid': chat.peerUuid,
                    'peerName': chat.peerName,
                    'peerProfileImage': chat.peerProfileImage,
                  },
                ).then((_) {
                  provider.loadChats();
                });
              },
              onLongPress: () {
                HapticFeedback.heavyImpact();
                _showDeleteChatConfirmation(context, provider, chat.peerUuid, chat.peerName);
              },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (chat.unreadCount ?? 0) > 0
                      ? AppColors.surfaceElevated.withValues(alpha: 0.5)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Hero(
                      tag: 'device_${chat.peerUuid}',
                      child: GestureDetector(
                        onTap: () => _showProfilePreview(context, chat),
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isConnected
                                      ? AppColors.primary.withValues(alpha: 0.5)
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: AppColors.surfaceElevated,
                                backgroundImage: chat.peerProfileImage != null && File(chat.peerProfileImage!).existsSync()
                                    ? FileImage(File(chat.peerProfileImage!))
                                    : null,
                                child: chat.peerProfileImage == null || !File(chat.peerProfileImage!).existsSync()
                                    ? Text(
                                        chat.peerName.isNotEmpty ? chat.peerName.substring(0, 1).toUpperCase() : '?',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 22,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            if (isConnected)
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.bgDark,
                                      width: 2.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (chat.isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                ),
                              Expanded(
                                child: Text(
                                  chat.peerName,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: (chat.unreadCount ?? 0) > 0 ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTime(chat.lastMessageTime),
                                style: GoogleFonts.inter(
                                  color: (chat.unreadCount ?? 0) > 0 ? AppColors.primaryLight : AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: (chat.unreadCount ?? 0) > 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: isTyping
                                    ? Text(
                                        'typing...',
                                        style: GoogleFonts.inter(
                                          color: AppColors.primaryLight,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      )
                                    : Text(
                                        (chat.lastMessage == 'Device connected' || chat.lastMessage == 'Connected' || chat.lastMessage.isEmpty)
                                            ? 'Initial connection established'
                                            : chat.lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: (chat.unreadCount ?? 0) > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                                          fontSize: 14,
                                          fontWeight: (chat.unreadCount ?? 0) > 0 ? FontWeight.w500 : FontWeight.normal,
                                        ),
                                      ),
                              ),
                              if ((chat.unreadCount ?? 0) > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    chat.unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showProfilePreview(BuildContext context, dynamic chat) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => ProfilePreviewDialog(
        peerName: chat.peerName,
        peerProfileImage: chat.peerProfileImage,
        peerUuid: chat.peerUuid,
        onChatPressed: () {
          Navigator.pop(context); // Close dialog
          Provider.of<ChatProvider>(context, listen: false).markChatAsRead(chat.peerUuid);
          Navigator.pushNamed(
            context,
            '/chat',
            arguments: {
              'peerUuid': chat.peerUuid,
              'peerName': chat.peerName,
              'peerProfileImage': chat.peerProfileImage,
            },
          );
        },
        onInfoPressed: () {
          Navigator.pop(context); // Close dialog
          // Future: Navigate to info screen
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final aWeekAgo = today.subtract(const Duration(days: 7));

    final dateToCheck = DateTime(time.year, time.month, time.day);

    if (dateToCheck == today) {
      return DateFormat('hh:mm a').format(time);
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else if (dateToCheck.isAfter(aWeekAgo)) {
      return DateFormat('EEEE').format(time);
    } else {
      return DateFormat('MMM d').format(time);
    }
  }

  void _showDeleteChatConfirmation(
    BuildContext context,
    ChatProvider provider,
    String peerUuid,
    String peerName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete chat with $peerName?',
          style: GoogleFonts.outfit(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will remove all messages in this conversation permanently.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              provider.toggleFavorite(peerUuid);
              Navigator.pop(context);
            },
            child: Text(
              'Toggle Favorite',
              style: GoogleFonts.inter(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              provider.deleteChat(peerUuid);
              Navigator.pop(context);
            },
            child: Text(
              'Delete Chat',
              style: GoogleFonts.inter(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
