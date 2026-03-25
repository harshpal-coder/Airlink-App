import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/chat_provider.dart';
import '../../core/constants.dart';
import 'help_screen.dart';
import '../../utils/background_utils.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final user = chatProvider.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.bgDark,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Decorative Glows
                  Positioned(
                    top: -100,
                    right: -100,
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ),

                  // Centered Profile Content
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 50),
                      Hero(
                        tag: 'profile_avatar',
                        child: GestureDetector(
                          onTap: () =>
                              _showImageSourceDialog(context, chatProvider),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 60,
                                  backgroundColor: AppColors.surfaceElevated,
                                  backgroundImage:
                                      user?.profileImage != null &&
                                          File(user!.profileImage!).existsSync()
                                      ? FileImage(File(user.profileImage!))
                                      : null,
                                  child:
                                      user?.profileImage == null ||
                                          !File(
                                            user!.profileImage!,
                                          ).existsSync()
                                      ? Text(
                                          user?.deviceName.isNotEmpty == true
                                              ? user!.deviceName[0]
                                                    .toUpperCase()
                                              : '?',
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 42,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.bgDark,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        user?.deviceName ?? 'Unknown User',
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${user?.uuid.substring(0, 8) ?? 'N/A'}',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Profile Identity'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      context,
                      Icons.person_rounded,
                      'Display Name',
                      user?.deviceName ?? 'Set your name',
                      onTap: () => _showEditNameDialog(context, chatProvider),
                    ),
                    _buildSettingsTile(
                      context,
                      Icons.qr_code_2_rounded,
                      'My AirID',
                      'Share your discovery code',
                      onTap: () {},
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Connectivity'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSwitchTile(
                      Icons.wifi_tethering_rounded,
                      'Invisible Mode',
                      'Stop others from finding you',
                      !chatProvider.isAdvertising,
                      (val) {
                        if (!val) {
                          chatProvider.startAdvertising();
                        } else {
                          chatProvider.stopAdvertising();
                        }
                      },
                    ),
                    _buildSwitchTile(
                      Icons.radar_rounded,
                      'Auto Discovery',
                      'Search for nearby devices',
                      chatProvider.isBrowsing,
                      (val) {
                        if (val) {
                          chatProvider.startBrowsing();
                        } else {
                          chatProvider.stopBrowsing();
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Appearance'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      context,
                      Icons.wallpaper_rounded,
                      'Chat Wallpaper',
                      chatProvider.chatWallpaperPath != null ? 'Custom wallpaper set' : 'Default texture',
                      onTap: () => _showWallpaperOptions(context, chatProvider),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Stability & Battery'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildBatteryOptimizationTile(context),
                    _buildSettingsTile(
                      context,
                      Icons.lock_person_rounded,
                      'Locking Guide',
                      'Keep AirLink alive in recent apps',
                      onTap: () => _showLockingGuide(context),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Help & Support'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      context,
                      Icons.help_outline_rounded,
                      'Help Center',
                      'Terms, Privacy, and how it works',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HelpScreen()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 32),
                  _buildSectionHeader('Data Management'),
                  const SizedBox(height: 12),
                  _buildSettingsCard([
                    _buildSettingsTile(
                      context,
                      Icons.delete_sweep_rounded,
                      'Clear Memories',
                      'Wipe all chat history',
                      onTap: () => _showClearChatsDialog(context, chatProvider),
                      isDestructive: true,
                    ),
                  ]),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: AppColors.primaryLight.withValues(alpha: 0.2),
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (isDestructive ? Colors.redAccent : AppColors.primary)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: isDestructive ? Colors.redAccent : AppColors.primaryLight,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
        size: 20,
      ),
    );
  }

  Widget _buildSwitchTile(
    IconData icon,
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          Icons.wifi_rounded,
          color: AppColors.primaryLight,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.6),
      ),
    );
  }

  void _showClearChatsDialog(BuildContext context, ChatProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Clear All Chats?',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'This will permanently delete all your message history. This action cannot be undone.',
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
                provider.clearAllChats();
                Navigator.pop(context);
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('All chats cleared'),
                    backgroundColor: AppColors.surfaceElevated,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              },
              child: Text(
                'Clear All',
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showImageSourceDialog(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Change Profile Photo',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildImageOption(
                      context,
                      Icons.photo_library_rounded,
                      'Gallery',
                      () {
                        provider.updateProfileImage(ImageSource.gallery);
                        Navigator.pop(context);
                      },
                    ),
                    _buildImageOption(
                      context,
                      Icons.camera_alt_rounded,
                      'Camera',
                      () {
                        provider.updateProfileImage(ImageSource.camera);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImageOption(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Icon(icon, color: AppColors.primaryLight, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, ChatProvider provider) {
    final controller = TextEditingController(
      text: provider.currentUser?.deviceName,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Edit Username',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppColors.bgDark,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            autofocus: true,
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
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  provider.updateCurrentUserName(newName);
                  Navigator.pop(context);
                  HapticFeedback.lightImpact();
                }
              },
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBatteryOptimizationTile(BuildContext context) {
    return FutureBuilder<bool>(
      future: BackgroundUtils.isBatteryOptimizationIgnored(),
      builder: (context, snapshot) {
        final isIgnored = snapshot.data ?? true;
        return ListTile(
          onTap: () async {
            await BackgroundUtils.requestIgnoreBatteryOptimizations();
            // In a real app, you might want to force a rebuild here
          },
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isIgnored ? AppColors.primary : Colors.orangeAccent)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isIgnored ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded,
              color: isIgnored ? AppColors.primaryLight : Colors.orangeAccent,
              size: 24,
            ),
          ),
          title: Text(
            'Battery Optimization',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            isIgnored ? 'Optimized for background activity' : 'Tap to allow background activity',
            style: GoogleFonts.inter(
              fontSize: 13, 
              color: isIgnored ? AppColors.textSecondary : Colors.orangeAccent
            ),
          ),
          trailing: Icon(
            isIgnored ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            color: isIgnored ? Colors.greenAccent : Colors.orangeAccent,
            size: 20,
          ),
        );
      },
    );
  }

  void _showLockingGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Keep AirLink Active',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                _buildGuideItem(
                  '1. Lock in Recent Apps',
                  BackgroundUtils.samsungLockGuide,
                  Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 20),
                _buildGuideItem(
                  '2. Background Activity',
                  BackgroundUtils.commonBackgroundGuide,
                  Icons.battery_saver_rounded,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Got it!',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuideItem(String title, String description, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primaryLight, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showWallpaperOptions(BuildContext context, ChatProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Chat Wallpaper',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildWallpaperOption(
                      context,
                      Icons.photo_library_rounded,
                      'Gallery',
                      () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          provider.updateChatWallpaper(image.path);
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    _buildWallpaperOption(
                      context,
                      Icons.restart_alt_rounded,
                      'Default',
                      () {
                        provider.updateChatWallpaper(null);
                        Navigator.pop(context);
                      },
                      isDestructive: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWallpaperOption(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Icon(
              icon,
              color: isDestructive ? Colors.redAccent : AppColors.primaryLight,
              size: 32,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
