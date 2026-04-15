import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants.dart';
import '../../services/chat_provider.dart';

/// Generates the JSON payload that is embedded in the QR code.
/// Format: {"type":"airlink_link","name":"User Name","uuid":"..."}
String buildLinkPayload(String name, String uuid) {
  return jsonEncode({
    'type': 'airlink_link',
    'name': name,
    'uuid': uuid,
  });
}

/// Returns null if the barcode is not a valid AirLink link payload.
Map<String, dynamic>? parseLinkPayload(String? raw) {
  if (raw == null) return null;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    if (map['type'] == 'airlink_link' &&
        map['uuid'] is String &&
        map['name'] is String) {
      return map;
    }
  } catch (_) {}
  return null;
}

class QrLinkScreen extends StatefulWidget {
  const QrLinkScreen({super.key});

  @override
  State<QrLinkScreen> createState() => _QrLinkScreenState();
}

class _QrLinkScreenState extends State<QrLinkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _scanController = MobileScannerController();
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          _scanController.stop();
        } else {
          setState(() => _scanned = false);
          _scanController.start();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture, ChatProvider provider) async {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final data = parseLinkPayload(raw);
    if (data == null) return;

    final String peerName = data['name'] as String;
    final String peerUuid = data['uuid'] as String;

    // Prevent linking to yourself
    if (peerUuid == provider.currentUser?.uuid) {
      if (!mounted) return;
      _showResultDialog(
        context,
        success: false,
        title: "That's You!",
        message: "You cannot link to your own QR code.",
        peerName: peerName,
      );
      return;
    }

    setState(() => _scanned = true);
    await _scanController.stop();

    await provider.linkPeerViaQr(peerName, peerUuid);

    if (!mounted) return;
    _showResultDialog(
      context,
      success: true,
      title: 'Linked!',
      message:
          '$peerName has been added to your contacts. You\'ll connect automatically when they\'re nearby.',
      peerName: peerName,
    );
  }

  void _showResultDialog(
    BuildContext context, {
    required bool success,
    required String title,
    required String message,
    required String peerName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (success ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.15),
              ),
              child: Icon(
                success ? Icons.link_rounded : Icons.error_outline_rounded,
                color: success ? AppColors.success : AppColors.error,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // close dialog
                  if (success) Navigator.of(context).pop(); // close screen
                  if (!success) setState(() => _scanned = false);
                  if (!success) _scanController.start();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: success ? AppColors.success : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  success ? 'Done' : 'Try Again',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context, listen: false);
    final user = provider.currentUser;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Link via QR',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.bold),
                unselectedLabelStyle:
                    GoogleFonts.inter(fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('My QR'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 18),
                        SizedBox(width: 6),
                        Text('Scan'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── My QR Tab ──
          _MyQrTab(user: user),

          // ── Scan Tab ──
          _ScanTab(
            provider: provider,
            scanController: _scanController,
            scanned: _scanned,
            onDetect: (capture) => _onDetect(capture, provider),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// My QR Tab
// ─────────────────────────────────────────
class _MyQrTab extends StatelessWidget {
  final dynamic user;
  const _MyQrTab({this.user});

  @override
  Widget build(BuildContext context) {
    final name = user?.deviceName ?? 'Unknown';
    final uuid = user?.uuid ?? '';
    final payload = uuid.isNotEmpty ? buildLinkPayload(name, uuid) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // ── Heading ──
          Text(
            'Share this QR Code',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Let others scan it to link with you instantly.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 32),

          // ── QR Card ──
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.surfaceDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                // QR Code
                if (payload != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 220,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 220,
                    height: 220,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Profile not set up yet.',
                      style: GoogleFonts.inter(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 24),
                // User info
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryLight,
                            AppColors.primary,
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.wifi_tethering,
                                size: 12,
                                color: AppColors.primaryLight),
                            const SizedBox(width: 4),
                            Text(
                              'AirLink',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Info note ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.glassBorder.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 18, color: AppColors.primaryLight),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'When someone scans your QR, you\'ll auto-connect whenever both devices are in range.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textMuted, height: 1.5),
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

// ─────────────────────────────────────────
// Scan Tab
// ─────────────────────────────────────────
class _ScanTab extends StatelessWidget {
  final ChatProvider provider;
  final MobileScannerController scanController;
  final bool scanned;
  final Function(BarcodeCapture) onDetect;

  const _ScanTab({
    required this.provider,
    required this.scanController,
    required this.scanned,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Camera preview ──
        ClipRRect(
          child: MobileScanner(
            controller: scanController,
            onDetect: onDetect,
          ),
        ),

        // ── Overlay ──
        Positioned.fill(
          child: Column(
            children: [
              // Top dark panel with instructions
              Container(
                color: AppColors.bgDark.withValues(alpha: 0.75),
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
                child: Column(
                  children: [
                    Text(
                      'Scan AirLink QR Code',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Point your camera at another AirLink user\'s QR code.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Scanner frame
              Expanded(
                child: Center(
                  child: _ScannerFrame(
                    size: MediaQuery.of(context).size.width * 0.7,
                  ),
                ),
              ),
              // Bottom hint
              Container(
                color: AppColors.bgDark.withValues(alpha: 0.75),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 16, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Text(
                      'Linking adds them to your contacts',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Processing overlay ──
        if (scanned)
          Positioned.fill(
            child: Container(
              color: AppColors.bgDark.withValues(alpha: 0.8),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                      color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Linking...',
                    style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Decorative scanner frame ──
class _ScannerFrame extends StatelessWidget {
  final double size;
  const _ScannerFrame({required this.size});

  @override
  Widget build(BuildContext context) {
    const cornerLen = 28.0;
    const cornerThick = 4.0;
    const cornerRadius = 8.0;
    final color = AppColors.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Semi-transparent centre
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cornerRadius),
                border: Border.all(
                  color: color.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
          ),
          // Corners
          ..._corners(size, cornerLen, cornerThick, cornerRadius, color),
        ],
      ),
    );
  }

  List<Widget> _corners(double size, double len, double thick, double radius,
      Color color) {
    return [
      // Top-left
      Positioned(
          top: 0,
          left: 0,
          child: _CornerWidget(
              color: color,
              thick: thick,
              len: len,
              topBorder: true,
              leftBorder: true,
              radius: radius)),
      // Top-right
      Positioned(
          top: 0,
          right: 0,
          child: _CornerWidget(
              color: color,
              thick: thick,
              len: len,
              topBorder: true,
              rightBorder: true,
              radius: radius)),
      // Bottom-left
      Positioned(
          bottom: 0,
          left: 0,
          child: _CornerWidget(
              color: color,
              thick: thick,
              len: len,
              bottomBorder: true,
              leftBorder: true,
              radius: radius)),
      // Bottom-right
      Positioned(
          bottom: 0,
          right: 0,
          child: _CornerWidget(
              color: color,
              thick: thick,
              len: len,
              bottomBorder: true,
              rightBorder: true,
              radius: radius)),
    ];
  }
}

class _CornerWidget extends StatelessWidget {
  final Color color;
  final double thick;
  final double len;
  final double radius;
  final bool topBorder;
  final bool bottomBorder;
  final bool leftBorder;
  final bool rightBorder;

  const _CornerWidget({
    required this.color,
    required this.thick,
    required this.len,
    required this.radius,
    this.topBorder = false,
    this.bottomBorder = false,
    this.leftBorder = false,
    this.rightBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: len,
      height: len,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thick: thick,
          radius: radius,
          top: topBorder,
          bottom: bottomBorder,
          left: leftBorder,
          right: rightBorder,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thick;
  final double radius;
  final bool top, bottom, left, right;

  _CornerPainter({
    required this.color,
    required this.thick,
    required this.radius,
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;
    final r = radius;

    if (top && left) {
      path.moveTo(0, h);
      path.lineTo(0, r);
      path.arcToPoint(Offset(r, 0),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(w, 0);
    } else if (top && right) {
      path.moveTo(0, 0);
      path.lineTo(w - r, 0);
      path.arcToPoint(Offset(w, r),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(w, h);
    } else if (bottom && left) {
      path.moveTo(w, h);
      path.lineTo(r, h);
      path.arcToPoint(Offset(0, h - r),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(0, 0);
    } else if (bottom && right) {
      path.moveTo(0, h);
      path.lineTo(w, h - r);
      path.arcToPoint(Offset(w - r, h),
          radius: Radius.circular(r), clockwise: false);
      path.lineTo(0, h);
      // Simpler approach:
      path.reset();
      path.moveTo(w, 0);
      path.lineTo(w, h - r);
      path.arcToPoint(Offset(w - r, h),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(0, h);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
