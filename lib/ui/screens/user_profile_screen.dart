import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';
import 'package:provider/provider.dart';
import '../../services/chat_provider.dart';
import '../../models/device_model.dart';
import 'package:qr_flutter/qr_flutter.dart';

class UserProfileScreen extends StatelessWidget {
  final String peerUuid;
  final String peerName;
  final String? peerProfileImage;

  const UserProfileScreen({
    super.key,
    required this.peerUuid,
    required this.peerName,
    this.peerProfileImage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildHeader(context),
                _buildActionButtons(context),
                const SizedBox(height: 24),
                _buildConnectionInsights(context),
                const SizedBox(height: 24),
                _buildSecurityTrust(context),
                const SizedBox(height: 24),
                _buildMediaSection(context),
                const SizedBox(height: 24),
                _buildInfoList(context),
                const SizedBox(height: 24),
                _buildPrivacySettings(context),
                const SizedBox(height: 32),
                _buildDangerZone(context),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
          onPressed: () {},
        ),
      ],
      pinned: true,
      expandedHeight: 0,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        final isConnected = provider.isPeerConnected(peerUuid);
        return Column(
          children: [
            Stack(
              children: [
                Hero(
                  tag: 'device_$peerUuid',
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: AppColors.surfaceElevated,
                      backgroundImage: peerProfileImage != null && File(peerProfileImage!).existsSync()
                          ? FileImage(File(peerProfileImage!))
                          : null,
                      child: peerProfileImage == null || !File(peerProfileImage!).existsSync()
                          ? Text(
                              peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                              style: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 40),
                            )
                          : null,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isConnected ? AppColors.success : AppColors.offline,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgDark, width: 3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  peerName,
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                if (isConnected) ...[
                  const SizedBox(width: 8),
                  FutureBuilder<Map<String, dynamic>>(
                    future: provider.getSecurityMetadata(peerUuid),
                    builder: (context, snapshot) {
                      final isVerified = snapshot.data?['isVerified'] == true;
                      if (!isVerified) return const SizedBox.shrink();
                      return const Icon(Icons.verified, color: AppColors.success, size: 24);
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_tethering, size: 14, color: AppColors.primaryLight),
                const SizedBox(width: 6),
                Text(
                  'Connected via WiFi Direct',
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.primaryLight, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(Icons.chat_bubble, 'CHAT', () => Navigator.pop(context)),
          _buildActionButton(Icons.search, 'SEARCH', () {}),
        ],
      ),
    );
  }

  Widget _buildConnectionInsights(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        final rssi = provider.getRssiForPeer(peerUuid);
        final device = provider.discoveredDevices.firstWhere((d) => d.uuid == peerUuid, orElse: () => Device(deviceId: '', deviceName: ''));
        
        final signalStrength = _getSignalStrength(rssi);
        final isMesh = device.isMesh;
        final relayName = device.relayedBy;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CONNECTION INSIGHTS',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.2),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildInsightItem(
                      icon: _getSignalIcon(rssi),
                      label: 'Link Quality',
                      value: signalStrength,
                      color: _getSignalColor(rssi),
                    ),
                    Container(height: 40, width: 1, color: AppColors.glassBorder.withValues(alpha: 0.1)),
                    _buildInsightItem(
                      icon: isMesh ? Icons.hub_outlined : Icons.settings_input_antenna,
                      label: 'Network Path',
                      value: isMesh ? 'Mesh Relay' : 'Direct Link',
                      subtitle: isMesh ? 'via $relayName' : 'P2P Cluster',
                      color: isMesh ? AppColors.meshBadge : AppColors.success,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInsightItem({required IconData icon, required String label, required String value, String? subtitle, required Color color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          if (subtitle != null)
            Text(subtitle, style: GoogleFonts.inter(fontSize: 10, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getSignalStrength(double rssi) {
    if (rssi > -60) return 'Excellent';
    if (rssi > -70) return 'Good';
    if (rssi > -85) return 'Fair';
    return 'Poor';
  }

  IconData _getSignalIcon(double rssi) {
    if (rssi > -60) return Icons.signal_cellular_4_bar;
    if (rssi > -70) return Icons.network_cell;
    if (rssi > -85) return Icons.signal_cellular_alt;
    return Icons.signal_cellular_0_bar;
  }

  Color _getSignalColor(double rssi) {
    if (rssi > -60) return AppColors.success;
    if (rssi > -75) return AppColors.primaryLight;
    if (rssi > -85) return AppColors.meshBadge;
    return AppColors.error;
  }

  Widget _buildSecurityTrust(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, child) {
        return FutureBuilder<Map<String, dynamic>>(
          future: provider.getSecurityMetadata(peerUuid),
          builder: (context, snapshot) {
            final metadata = snapshot.data;
            final isVerified = metadata?['isVerified'] == true;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: isVerified ? AppColors.success.withValues(alpha: 0.2) : AppColors.glassBorder.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SECURITY & TRUST',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.2),
                        ),
                        if (isVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'VERIFIED',
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.success),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSecurityDetail(
                      Icons.lock_person_outlined,
                      'Identity Verification',
                      isVerified ? 'You have verified this peer.' : 'Scan code to verify identity.',
                      onTap: () => _showVerificationModal(context, provider, metadata),
                    ),
                    const Divider(height: 32, color: AppColors.glassBorder),
                    _buildSecurityDetail(
                      Icons.terminal_outlined,
                      'Technical Details',
                      'Signal Protocol · X3DH · AES-256',
                      trailing: const Icon(Icons.info_outline, size: 18, color: AppColors.textMuted),
                      onTap: () => _showTechnicalDetails(context, metadata),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSecurityDetail(IconData icon, String title, String subtitle, {Widget? trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bgDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (trailing != null) trailing else const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }

  void _showVerificationModal(BuildContext context, ChatProvider provider, Map<String, dynamic>? metadata) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Verify Identity', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Text(
              'To verify security, scan this code on your peer\'s device or compare the fingerprints.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.textMuted),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: metadata?['localFingerprint'] ?? 'unknown',
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'YOUR SAFETY NUMBER',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 1.2),
            ),
            const SizedBox(height: 8),
            Text(
              _formatFingerprint(metadata?['localFingerprint']),
              textAlign: TextAlign.center,
              style: GoogleFonts.robotoMono(fontSize: 16, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.glassBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('CLOSE', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      provider.verifyPeer(peerUuid, true);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('MARK AS VERIFIED', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTechnicalDetails(BuildContext context, Map<String, dynamic>? metadata) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Technical Details', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 24),
            _buildTechRow('Signal Registration ID', metadata?['registrationId']?.toString() ?? 'Unknown'),
            _buildTechRow('Handshake Protocol', 'X3DH (Extended Triple Diffie-Hellman)'),
            _buildTechRow('Encryption', 'AES-256-CBC / HMAC-SHA256'),
            _buildTechRow('Fingerprint (SHA256)', _formatFingerprint(metadata?['remoteFingerprint'], full: true)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTechRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.robotoMono(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatFingerprint(String? fp, {bool full = false}) {
    if (fp == null) return 'Not yet exchanged';
    if (full) return fp;
    if (fp.length < 12) return fp;
    return '${fp.substring(0, 4)} ${fp.substring(4, 8)} ${fp.substring(8, 12)} ...';
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Media, Links, and Docs',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              TextButton(
                onPressed: () {},
                child: Text('See all', style: GoogleFonts.inter(color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library_outlined, size: 32, color: AppColors.textMuted.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'No media shared yet',
                  style: GoogleFonts.inter(fontSize: 13, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoList(BuildContext context) {
    return Column(
      children: [
        _buildInfoTile(Icons.alternate_email, '@${peerName.toLowerCase().replaceAll(' ', '_')}_airlink_224', 'Identifier'),
        _buildInfoTile(Icons.lock_outline, 'End-to-End Encrypted', 'Messages and calls are secured via offline keys.'),
        _buildInfoTile(Icons.group_outlined, 'Common Groups', 'Design Sync, Weekend Hikers'),
      ],
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
    );
  }

  Widget _buildPrivacySettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Text(
            'PRIVACY & SETTINGS',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryLight, letterSpacing: 1.2),
          ),
        ),
        _buildSettingToggle(Icons.notifications_none, 'Mute Notifications', true),
        _buildSettingTile(Icons.music_note_outlined, 'Custom Notifications'),
        _buildSettingTile(Icons.visibility_outlined, 'Media Visibility'),
      ],
    );
  }

  Widget _buildSettingToggle(IconData icon, String title, bool value) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16)),
      trailing: Switch(
        value: value,
        onChanged: (v) {},
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  Widget _buildSettingTile(IconData icon, String title) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 22),
      title: Text(title, style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () {},
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  Widget _buildDangerZone(BuildContext context) {
    return Column(
      children: [
        _buildDangerTile(Icons.block_flipped, 'Block $peerName', () {}),
      ],
    );
  }

  Widget _buildDangerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.redAccent, size: 22),
      title: Text(title, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w600)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}
