import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';

class SecurityScreen extends StatelessWidget {
  final String peerUuid;
  final String peerName;

  const SecurityScreen({
    super.key,
    required this.peerUuid,
    required this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Security Verification',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Lock Icon Animation Placeholder
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.enhanced_encryption_rounded,
                      color: AppColors.primaryLight,
                      size: 64,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  Text(
                    'End-to-End Encrypted',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Messages and calls with $peerName are protected with 256-bit AES encryption. No one outside of this chat, not even AirLink, can read or listen to them.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Device Verification Section
                  _buildSectionHeader('Verify Safety Number'),
                  const SizedBox(height: 16),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.qr_code_2_rounded,
                          color: Colors.white,
                          size: 200,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Scan this code on $peerName\'s device or compare the numbers below to verify encryption.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Fake Safety Number Grid
                        _buildSafetyNumber('48291 00213 55901 22847'),
                        const SizedBox(height: 8),
                        _buildSafetyNumber('11928 33405 66712 00938'),
                        const SizedBox(height: 8),
                        _buildSafetyNumber('33490 88712 00234 55671'),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Privacy Learn More
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
                    ),
                    title: Text(
                      'How it works',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Learn more about AirLink\'s P2P encryption protocols.',
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: AppColors.textMuted, size: 16),
                    onTap: () {},
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.primaryLight.withValues(alpha: 0.4),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSafetyNumber(String number) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        number,
        style: GoogleFonts.jetBrainsMono(
          color: Colors.white70,
          fontSize: 16,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
