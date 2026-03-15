import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';
import '../../core/help_content.dart';
import 'help_detail_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & Support',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Support Center'),
            const SizedBox(height: 12),
            _buildHelpCard([
              _buildHelpTile(
                context,
                Icons.description_outlined,
                'Terms & Privacy Policy',
                'Read our commitment to your privacy',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HelpDetailScreen(
                      title: 'Terms & Privacy',
                      content: "${HelpContent.termsOfService}\n\n---\n\n${HelpContent.privacyPolicy}",
                    ),
                  ),
                ),
              ),
              _buildHelpTile(
                context,
                Icons.info_outline_rounded,
                'App Information',
                'Version details and developer info',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HelpDetailScreen(
                      title: 'App Info',
                      content: HelpContent.appInfo,
                    ),
                  ),
                ),
              ),
              _buildHelpTile(
                context,
                Icons.account_tree_outlined,
                'How it Works',
                'Deep dive into AirLink mesh networking',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HelpDetailScreen(
                      title: 'Working',
                      content: HelpContent.workingMesh,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSectionHeader('Legal'),
            const SizedBox(height: 12),
            _buildHelpCard([
              _buildHelpTile(
                context,
                Icons.gavel_rounded,
                'Licenses',
                'Open source libraries and licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: '2.0.0',
                  applicationIcon: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.wifi_tethering_rounded, size: 48, color: AppColors.primary),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'AirLink Mesh v2.0.0',
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildHelpCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildHelpTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
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
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
        size: 20,
      ),
    );
  }
}
