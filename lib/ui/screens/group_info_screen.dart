import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/chat_provider.dart';
import '../../models/group_model.dart';
import '../../models/chat_model.dart';
import '../../models/session_state.dart';
import '../../core/constants.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final group = chatProvider.groups.firstWhere((g) => g.id == widget.groupId, orElse: () => Group(
      id: '', name: 'Deleted', createdBy: '', createdAt: DateTime.now(), members: [], lastMessageTime: DateTime.now()
    ));

    if (group.id.isEmpty) {
      return Scaffold(body: Center(child: Text('Group not found', style: TextStyle(color: Colors.white))));
    }

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppColors.surfaceDark,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                group.name,
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(Icons.group_rounded, size: 80, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${group.members.length} Members',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _buildActionList(context, chatProvider, group),
                  const SizedBox(height: 24),
                  Text(
                    'MEMBERS',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final memberUuid = group.members[index];
                return _buildMemberTile(context, chatProvider, memberUuid, group.createdBy == memberUuid);
              },
              childCount: group.members.length,
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    );
  }

  Widget _buildActionList(BuildContext context, ChatProvider chatProvider, Group group) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.person_add_rounded, color: AppColors.primary),
            title: Text('Add Members', style: GoogleFonts.inter(color: AppColors.textPrimary)),
            onTap: () => _showAddMembersSheet(context, chatProvider, group),
          ),
          const Divider(height: 1, color: Colors.white10, indent: 56),
          ListTile(
            leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
            title: Text('Leave Group', style: GoogleFonts.inter(color: Colors.redAccent)),
            onTap: () {
              // TODO: Implement leaveGroup in Provider
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, ChatProvider chatProvider, String memberUuid, bool isAdmin) {
    final isMe = memberUuid == chatProvider.currentUser?.uuid || memberUuid == 'me';
    String name = isMe ? 'You' : 'Unknown';
    
    // Try to find peer name
    try {
      if (!isMe) {
        final device = chatProvider.discoveredDevices.firstWhere((d) => d.uuid == memberUuid);
        name = device.deviceName;
      }
    } catch (_) {
      // Check in chats
      final chat = chatProvider.chats.firstWhere((c) => c.peerUuid == memberUuid, orElse: () => Chat(id: '', peerUuid: '', peerName: 'Unknown', lastMessage: '', lastMessageTime: DateTime.now(), unreadCount: 0));
      if (chat.id.isNotEmpty) name = chat.peerName;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Text(name[0], style: TextStyle(color: AppColors.primary)),
      ),
      title: Text(name, style: GoogleFonts.inter(color: AppColors.textPrimary)),
      trailing: isAdmin 
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Admin', style: GoogleFonts.inter(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.bold)),
            ) 
          : null,
    );
  }

  void _showAddMembersSheet(BuildContext context, ChatProvider chatProvider, Group group) {
    // Reusing the connection-based logic to only show online peers for additions
    final connectedPeers = chatProvider.discoveredDevices
        .where((p) => p.state == SessionState.connected && !group.members.contains(p.uuid))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final List<String> selectedUuids = [];
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Add Members',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      TextButton(
                        onPressed: selectedUuids.isEmpty ? null : () async {
                          Navigator.pop(context);
                          await chatProvider.addMembersToGroup(group.id, selectedUuids);
                          if (mounted) setState(() {});
                        },
                        child: Text('ADD', style: TextStyle(color: selectedUuids.isEmpty ? Colors.grey : AppColors.primary, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: connectedPeers.isEmpty
                      ? Center(child: Text('No new connected peers found', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          itemCount: connectedPeers.length,
                          itemBuilder: (context, index) {
                            final peer = connectedPeers[index];
                            final isSelected = selectedUuids.contains(peer.uuid);
                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (val) {
                                setModalState(() {
                                  if (val == true) {
                                    selectedUuids.add(peer.uuid!);
                                  } else {
                                    selectedUuids.remove(peer.uuid);
                                  }
                                });
                              },
                              title: Text(peer.deviceName, style: const TextStyle(color: Colors.white)),
                              secondary: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(peer.deviceName[0], style: TextStyle(color: AppColors.primary)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          }
        );
      },
    );
  }
}
