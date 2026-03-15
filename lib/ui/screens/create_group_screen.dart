import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/session_state.dart';
import '../../services/chat_provider.dart';
import '../../core/constants.dart';


class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<String> _selectedPeerUuids = [];

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final availablePeers = chatProvider.discoveredDevices
        .where((p) => p.state == SessionState.connected)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Create Group',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (_nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a group name')),
                );
                return;
              }
              if (_selectedPeerUuids.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select at least one member')),
                );
                return;
              }

              await chatProvider.createGroup(
                _nameController.text,
                _selectedPeerUuids,
              );
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: Text(
              'CREATE',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Group Name',
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: availablePeers.isEmpty
                ? Center(
                    child: Text(
                      'No connected members available',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: availablePeers.length,
                    itemBuilder: (context, index) {
                      final peer = availablePeers[index];
                      return CheckboxListTile(
                        value: _selectedPeerUuids.contains(peer.uuid),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPeerUuids.add(peer.uuid!);
                            } else {
                              _selectedPeerUuids.remove(peer.uuid);
                            }
                          });
                        },
                        title: Text(
                          peer.deviceName,
                          style: const TextStyle(color: Colors.white),
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          child: Text(
                            peer.deviceName[0],
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
