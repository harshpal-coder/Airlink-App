import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';

class ProfilePreviewDialog extends StatelessWidget {
  final String peerName;
  final String? peerProfileImage;
  final String peerUuid;
  final VoidCallback onChatPressed;
  final VoidCallback onInfoPressed;

  const ProfilePreviewDialog({
    super.key,
    required this.peerName,
    this.peerProfileImage,
    required this.peerUuid,
    required this.onChatPressed,
    required this.onInfoPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Name Overlay
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Text(
                    peerName,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Profile Image
                GestureDetector(
                  onTap: onInfoPressed,
                  child: Hero(
                    tag: 'preview_$peerUuid',
                    child: Container(
                      height: 280,
                      width: 280,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        image: peerProfileImage != null && File(peerProfileImage!).existsSync()
                            ? DecorationImage(
                                image: FileImage(File(peerProfileImage!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: peerProfileImage == null || !File(peerProfileImage!).existsSync()
                          ? Center(
                              child: Text(
                                peerName.isNotEmpty ? peerName.substring(0, 1).toUpperCase() : '?',
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 80,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                // Action Buttons
                Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: onChatPressed,
                        icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.primary),
                        tooltip: 'Message',
                      ),
                      IconButton(
                        onPressed: onInfoPressed,
                        icon: const Icon(Icons.info_outline_rounded, color: AppColors.primary),
                        tooltip: 'Info',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
