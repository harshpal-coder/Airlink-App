import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/session_state.dart';
import '../../services/chat_provider.dart';
import '../../models/device_model.dart';
import '../../core/constants.dart';

class NetworkMapScreen extends StatefulWidget {
  const NetworkMapScreen({super.key});

  @override
  State<NetworkMapScreen> createState() => _NetworkMapScreenState();
}

class _NetworkMapScreenState extends State<NetworkMapScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final devices = chatProvider.discoveredDevices;
    final currentUser = chatProvider.currentUser;
    final meshTopology = chatProvider.messagingService.meshTopology;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1720),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Mesh Topology',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final center = Offset(size.width / 2, size.height / 2);
          final double radius = math.min(size.width, size.height) * 0.35;

          // Build map of UUID to position
          final Map<String, Offset> uuidToPos = {};
          final int count = devices.length;

          for (int i = 0; i < count; i++) {
            final angle = (2 * math.pi * i / count) - (math.pi / 2);
            final offset = Offset(
              center.dx + radius * math.cos(angle),
              center.dy + radius * math.sin(angle),
            );
            uuidToPos[devices[i].uuid ?? devices[i].deviceId] = offset;
          }

          // Build unique edges for drawing and pulses
          final List<TopologyEdge> edges = [];
          final Set<String> drawnEdges = {};

          // 1. Mesh Topology links
          meshTopology.forEach((uuid1, connections) {
            final pos1 = uuidToPos[uuid1];
            if (pos1 != null) {
              for (var uuid2 in connections) {
                final pos2 = uuidToPos[uuid2];
                if (pos2 != null) {
                  final edgeKey = uuid1.compareTo(uuid2) < 0
                      ? '$uuid1-$uuid2'
                      : '$uuid2-$uuid1';
                  if (!drawnEdges.contains(edgeKey)) {
                    edges.add(TopologyEdge(pos1, pos2));
                    drawnEdges.add(edgeKey);
                  }
                }
              }
            }
          });

          // 2. Direct edges from Me (Center)
          for (var device in devices) {
            final String uuid = device.uuid ?? device.deviceId;
            final pos = uuidToPos[uuid];
            if (pos != null &&
                (device.state == SessionState.connected ||
                    device.state == SessionState.connecting)) {
              edges.add(TopologyEdge(center, pos, isDirect: true));
            }
          }

          // if (edges.length > 3) {
          //    _pulseController.duration = Duration(seconds: (edges.length * 1.5).clamp(8, 20).toInt());
          // }

          return Stack(
            children: [
              // Background Grid
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(
                    color: Colors.white.withValues(alpha: 0.1),
                    spacing: 30,
                  ),
                ),
              ),

              // Topology Painter (Links and Pulses)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return CustomPaint(
                    size: size,
                    painter: TopologyPainter(
                      edges: edges,
                      pulseValue: _pulseController.value,
                      center: center,
                      radius: radius,
                    ),
                  );
                },
              ),

              // Peer Nodes
              ...devices.map((device) {
                final pos = uuidToPos[device.uuid ?? device.deviceId]!;
                return Positioned(
                  left: pos.dx - 30,
                  top: pos.dy - 30,
                  child: _buildDeviceNode(device, false),
                );
              }),

              // Center Node (Me)
              Positioned(
                left: center.dx - 35,
                top: center.dy - 35,
                child: _buildDeviceNode(
                  Device(
                    deviceId: 'me',
                    deviceName: currentUser?.deviceName ?? 'YOU',
                    profileImage: currentUser?.profileImage,
                    uuid: currentUser?.uuid,
                    state: SessionState.connected,
                    isBackbone: chatProvider.messagingService.isBackbone,
                  ),
                  true,
                ),
              ),

              // Legend
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: _buildInfoCard(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceNode(Device device, bool isMe) {
    final bool isConnected = device.state == SessionState.connected;
    final bool isConnecting = device.state == SessionState.connecting;
    final double nodeSize = isMe ? 70 : 60;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isConnected && !isMe && device.batteryLevel > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (device.isBackbone)
                  const Icon(Icons.workspace_premium, color: Colors.amber, size: 10),
                Text(
                  '${device.batteryLevel}%',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 8),
                ),
              ],
            ),
          ),
        Container(
          width: nodeSize,
          height: nodeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: device.isBackbone 
                  ? Colors.amber 
                  : (isConnected ? AppColors.success : (isConnecting ? AppColors.primary : Colors.white24)),
              width: isMe ? 3 : 2,
            ),
            boxShadow: [
              if (isConnected)
                BoxShadow(
                  color: (device.isBackbone ? Colors.amber : (isConnected ? AppColors.success : AppColors.primary))
                      .withValues(alpha: 0.3),
                  blurRadius: device.isBackbone ? 15 : 10,
                  spreadRadius: device.isBackbone ? 4 : 2,
                ),
            ],
          ),
          child: ClipOval(child: _buildAvatar(device)),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: isMe
              ? BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Text(
            isMe ? 'YOU' : device.deviceName,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: isConnected ? 1.0 : 0.6),
              fontSize: isMe ? 10 : 10,
              fontWeight: (isConnected || isMe)
                  ? FontWeight.bold
                  : FontWeight.normal,
              letterSpacing: isMe ? 1.1 : 0,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(Device device) {
    if (device.profileImage != null && device.profileImage!.isNotEmpty) {
      return Image.file(
        File(device.profileImage!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildInitials(device.deviceName),
      );
    }
    return _buildInitials(device.deviceName);
  }

  Widget _buildInitials(String name) {
    final String initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: const Color(0xFF1E2A38),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16212C).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(AppColors.success, 'Connected'),
          _buildLegendItem(AppColors.primary, 'Scanning'),
          _buildLegendItem(Colors.white30, 'Offline'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class TopologyEdge {
  final Offset start;
  final Offset end;
  final bool isDirect;
  TopologyEdge(this.start, this.end, {this.isDirect = false});
}

class GridPainter extends CustomPainter {
  final Color color;
  final double spacing;

  GridPainter({required this.color, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += spacing) {
      for (double j = 0; j < size.height; j += spacing) {
        canvas.drawCircle(Offset(i, j), 0.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TopologyPainter extends CustomPainter {
  final List<TopologyEdge> edges;
  final double pulseValue;
  final Offset center;
  final double radius;

  TopologyPainter({
    required this.edges,
    required this.pulseValue,
    required this.center,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;

    // Background Pulse
    paint.color = AppColors.primary.withValues(alpha: 0.05 * (1 - pulseValue));
    canvas.drawCircle(center, radius * (1 + pulseValue * 1.5), paint);

    // Links
    final directLinkPaint = Paint()
      ..color = AppColors.success.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final meshLinkPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (var edge in edges) {
      canvas.drawLine(
        edge.start,
        edge.end,
        edge.isDirect ? directLinkPaint : meshLinkPaint,
      );
    }

    // Transmission Pulse (One at a time)
    if (edges.isNotEmpty) {
      final int activeIndex =
          (pulseValue * edges.length).floor() % edges.length;
      final double progress = (pulseValue * edges.length) % 1.0;
      final edge = edges[activeIndex];

      final Offset pulsePos = Offset.lerp(edge.start, edge.end, progress)!;

      // Pulse Glow
      paint.color = (edge.isDirect ? AppColors.success : AppColors.primary)
          .withValues(alpha: 0.3);
      canvas.drawCircle(pulsePos, 4, paint);

      // Pulse Core
      paint.color = Colors.white;
      canvas.drawCircle(pulsePos, 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant TopologyPainter oldDelegate) =>
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.edges.length != edges.length;
}
