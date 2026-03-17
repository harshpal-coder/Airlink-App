import 'package:flutter/material.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import '../../services/chat_provider.dart';
import '../../background/connectivity_service.dart';
import '../../utils/background_utils.dart';

// Extracted Colors based on Tailwind config
class SplashColors {
  static const primary = Color(0xFF0A85FF);
  static const primaryLight = Color(0xFF60A5FA);
  static const bgLight = Color(0xFFF5F7F8);
  static const bgDark = Color(0xFF0F1923);
  static const surfaceDark = Color(0xFF16202C);
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final AnimationController _bounceController;
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    
    // Float animation (up and down)
    _floatController = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Pulse animation (glow size and opacity)
    _pulseController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Bounce animation for wifi/bluetooth
    _bounceController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Progress bar animation loading simulation
    _progressController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 1500),
    )..repeat();

    _initializeApp();
  }

  @override
  void dispose() {
    _floatController.dispose();
    _pulseController.dispose();
    _bounceController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Basic permissions usually required for Bluetooth and WiFi
    await [
      Permission.location,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.notification,
    ].request();

    // Start Background Service once we have permissions
    await AirLinkConnectivityService.initializeService();

    String fallbackName = 'Unknown Device';
    try {
      AndroidDeviceInfo androidInfo = await DeviceInfoPlugin().androidInfo;
      fallbackName = androidInfo.model;
    } catch (_) {}

    if (!mounted) return;
    
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.ensureCurrentUser(fallbackName);
    
    // Simulate some loading time for branding effect
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Check for battery optimizations on Android
    if (Platform.isAndroid) {
      final isIgnored = await BackgroundUtils.isBatteryOptimizationIgnored();
      if (!isIgnored) {
        // We show a simple snackbar or dialog to encourage disabling optimization
        // For splash, a snackbar is less intrusive but might be missed.
        // Let's use a small delay and a snackbar once we land on home.
      }
    }

    // Check if the user has already completed profile setup
    final prefs = await SharedPreferences.getInstance();
    final bool setupDone = prefs.getBool('profile_setup_done') ?? false;
    
    if (!mounted) return;
    if (setupDone) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/profile_setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? SplashColors.bgDark : SplashColors.bgLight;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Custom Mesh Background
          Positioned.fill(
            child: CustomPaint(
              painter: MeshBackgroundPainter(
                dotColor: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.04),
                gradientColor: SplashColors.primary.withValues(alpha: isDark ? 0.05 : 0.08),
              ),
            ),
          ),
          
          // Top subtle gradient element
          Positioned(
            top: 0, left: 0, right: 0,
            height: 128,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ SplashColors.primary.withValues(alpha: 0.1), Colors.transparent ],
                ),
              ),
            ),
          ),

          // Main Center Content
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _floatController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -10 * Curves.easeInOut.transform(_floatController.value)),
                          child: child,
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoIcon(),
                          const SizedBox(height: 32),
                          _buildBrandText(isDark),
                          const SizedBox(height: 12),
                          Text(
                            "Chat Anywhere,\nEven Without Internet",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Footer / Loading Area
                Padding(
                  padding: const EdgeInsets.only(bottom: 32.0),
                  child: Column(
                    children: [
                      // Progress Indicator
                      Container(
                        width: 64,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(9999), 
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return Transform.translate(
                               offset: Offset(
                                 (-64.0) + (128.0 * Curves.easeInOut.transform(_progressController.value)), 
                                 0
                               ),
                               child: Container(
                                 width: 32,
                                 decoration: BoxDecoration(
                                   color: SplashColors.primary,
                                   borderRadius: BorderRadius.circular(9999),
                                 ),
                               ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "CONNECTING TO MESH",
                        style: TextStyle(
                          color: SplashColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
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

  Widget _buildBrandText(bool isDark) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: isDark 
            ? [Colors.white, const Color(0xFFBFDBFE), Colors.white] // dark:from-white dark:via-blue-200 dark:to-white
            : [const Color(0xFF0F172A), SplashColors.primary, const Color(0xFF0F172A)], // from-slate-900 via-primary to-slate-900
      ).createShader(bounds),
      child: Text(
        "AirLink",
        style: GoogleFonts.outfit(
          fontSize: 48,
          fontWeight: FontWeight.w800,
          color: Colors.white, // Required for ShaderMask to apply gradient correctly
          letterSpacing: -1.0,
        ),
      ),
    );
  }

  Widget _buildLogoIcon() {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final val = Curves.easeInOut.transform(_pulseController.value);
              return Container(
                width: 128 + (10 * val),
                height: 128 + (10 * val),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SplashColors.primary.withValues(alpha: 0.1 + (0.1 * (1 - val))),
                  boxShadow: [
                    BoxShadow(
                      color: SplashColors.primary.withValues(alpha: 0.2),
                      blurRadius: 30 + (10 * val),
                      spreadRadius: 5 * val,
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Center Gradient Hub Icon
          Transform.rotate(
            angle: 3 * math.pi / 180, // rotate 3 degrees by default
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [SplashColors.primary, Color(0xFF2563EB)], // primary to blue-600
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: SplashColors.primary.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.hub, color: Colors.white, size: 48),
            ),
          ),
          
          // WiFi bouncing
          Positioned(
            right: 0,
            top: 20,
            child: AnimatedBuilder(
              animation: _bounceController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -6 * math.sin((_bounceController.value * math.pi) + 0.1)),
                  child: child,
                );
              },
              child: Icon(Icons.wifi, color: SplashColors.primary.withValues(alpha: 0.6), size: 24),
            ),
          ),
          
          // Bluetooth bouncing
          Positioned(
            left: 0,
            bottom: 20,
            child: AnimatedBuilder(
              animation: _bounceController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -6 * math.sin((_bounceController.value * math.pi) + 0.5)),
                  child: child,
                );
              },
              child: Icon(Icons.bluetooth, color: SplashColors.primary.withValues(alpha: 0.6), size: 24),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter to draw the mesh background
class MeshBackgroundPainter extends CustomPainter {
  final Color dotColor;
  final Color gradientColor;

  MeshBackgroundPainter({required this.dotColor, required this.gradientColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Top-left radial gradient spotlight
    final Rect rectTL = Rect.fromCircle(center: const Offset(0, 0), radius: size.width * 0.8);
    final Paint paintTL = Paint()
      ..shader = RadialGradient(
        colors: [gradientColor, Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(rectTL);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintTL);

    // Bottom-right radial gradient spotlight
    final Rect rectBR = Rect.fromCircle(center: Offset(size.width, size.height), radius: size.width * 0.8);
    final Paint paintBR = Paint()
      ..shader = RadialGradient(
        colors: [gradientColor, Colors.transparent],
        stops: const [0.0, 1.0],
      ).createShader(rectBR);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintBR);

    // Dotted pattern over the screen
    final Paint dotPaint = Paint()..color = dotColor;
    const double spacing = 24.0;
    for (double i = 0; i < size.width; i += spacing) {
      for (double j = 0; j < size.height; j += spacing) {
        // Draw 1px circles distributed evenly
        canvas.drawCircle(Offset(i + spacing/2, j + spacing/2), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MeshBackgroundPainter oldDelegate) {
    return oldDelegate.dotColor != dotColor || oldDelegate.gradientColor != gradientColor;
  }
}
