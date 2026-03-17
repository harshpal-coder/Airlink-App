import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = "AirLink";
  static const String userTable = "users";
  static const String messageTable = "messages";
  static const String chatTable = "chats";
  static const String groupTable = "groups";
  static const String groupMemberTable = "group_members";
}

class AppColors {
  // Brand & Accents
  static const Color primary = Color(0xFF0A85FF);      // Vibrant Blue
  static const Color primaryLight = Color(0xFF60A5FA); // Light Blue for glowing/accents
  
  // Backgrounds & Surfaces
  static const Color bgDark = Color(0xFF0F1923);       // Main app background
  static const Color surfaceDark = Color(0xFF1A2632);  // Cards, Modals, AppBar
  static const Color surfaceElevated = Color(0xFF1E2A38); // Hover/Elevated state
  static const Color bubbleRec = Color(0xFF2A3B4D);    // Incoming message bubble

  // Status Colors
  static const Color success = Color(0xFF10B981);      // Green dot
  static const Color error = Color(0xFFEF4444);        // Disconnect red
  static const Color offline = Color(0xFF64748B);      // Slate grey for offline
  static const Color meshBadge = Color(0xFFF59E0B);    // Amber/Gold for mesh connection
  
  // Premium UI Accents
  static const Color glassBase = Color(0x1AFFFFFF);    // Low opacity white for glass effect
  static const Color glassBorder = Color(0x33FFFFFF);  // Border for glass containers
  static const Color glowBlue = Color(0x400A85FF);     // Soft blue glow
  static const Color glowGreen = Color(0x4010B981);    // Soft green glow
  
  // WhatsApp Colors
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color whatsappDarkGreen = Color(0xFF075E54);
  static const Color whatsappIndicator = Color(0xFF00A884);
  static const Color whatsappSurface = Color(0xFF121B22);
  
  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textMuted = Color(0xFF64748B);     // Slate 500
}
