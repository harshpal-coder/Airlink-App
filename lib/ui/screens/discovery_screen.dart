import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/session_state.dart';
import '../../services/chat_provider.dart';
import '../../models/device_model.dart';
import '../../core/constants.dart';
import '../widgets/radar_animation.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).startDiscovery();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'AirLink Discovery',
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.hub_outlined, color: AppColors.primary),
            onPressed: () {
              Navigator.pushNamed(context, '/network_map');
            },
            tooltip: 'Mesh Topology',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () {
              chatProvider.startDiscovery();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),

          CustomScrollView(
            slivers: [
              // Discovery Scanning Hub Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 100, 16, 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDark.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        RadarAnimation(
                          isDiscovering: chatProvider.isDiscovering,
                          centerWidget: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.radar,
                              color: Colors.white.withValues(alpha: 0.1),
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          chatProvider.isDiscovering
                              ? 'Scanning for peers...'
                              : 'Discovery Paused',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keep AirLink open on other devices',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Devices List Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'NEARBY DEVICES',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (chatProvider.isDiscovering)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.meshBadge.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.hub, size: 12, color: AppColors.meshBadge),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${chatProvider.reachablePeersCount} NODES',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.meshBadge,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'SEARCHING',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              // Devices List
              if (chatProvider.discoveredDevices.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          size: 64,
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No devices found yet',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final device = chatProvider.discoveredDevices[index];
                      return _buildDeviceCard(context, chatProvider, device);
                    }, childCount: chatProvider.discoveredDevices.length),
                  ),
                ),

              // Footer space
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
    BuildContext context,
    ChatProvider provider,
    Device device,
  ) {
    bool isConnected = device.state == SessionState.connected;
    bool isConnecting = device.state == SessionState.connecting;

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? AppColors.success.withValues(alpha: 0.3)
              : (isConnecting
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : Colors.transparent),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.1),
            BlendMode.dstATop,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: Hero(
              tag: 'device_${device.uuid ?? device.deviceId}',
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryLight.withValues(alpha: 0.8),
                      AppColors.primary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: device.profileImage != null && File(device.profileImage!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.file(
                          File(device.profileImage!),
                          fit: BoxFit.cover,
                          width: 56,
                          height: 56,
                        ),
                      )
                    : Center(
                        child: Text(
                          device.deviceName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                      ),
              ),
            ),
            title: Row(
              children: [
                Text(
                  device.deviceName,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    fontSize: 18,
                  ),
                ),
                if (device.isMesh) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.meshBadge.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.meshBadge.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      'MESH',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppColors.meshBadge,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? AppColors.success
                          : (isConnecting
                                ? AppColors.primaryLight
                                : AppColors.offline),
                    ),
                  ),
                  _buildSignalIndicator(context, provider.getRssiForPeer(device.uuid ?? device.deviceId)),
                  const SizedBox(width: 8),
                      Text(
                        isConnected
                            ? 'Connected'
                            : (isConnecting 
                                ? 'Establishing Link...' 
                                : (device.isMesh ? 'Via ${device.relayedBy ?? 'Mesh'}' : 'Available')),
                        style: GoogleFonts.inter(
                          color: isConnected
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: isConnected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
            trailing: _buildDeviceTrailingAction(context, provider, device),
            onTap: () {
              if (isConnected) {
                Navigator.pushNamed(
                  context,
                  '/chat',
                  arguments: {
                    'peerUuid': device.uuid ?? device.deviceId,
                    'peerName': device.deviceName,
                  },
                ).then((_) => provider.loadChats());
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSignalIndicator(BuildContext context, double rssi) {
    // rssi: -40 Excellent, -60 Good, -80 Fair, -90 Poor
    int bars = 0;
    if (rssi > -60) {
      bars = 4;
    } else if (rssi > -75) {
      bars = 3;
    } else if (rssi > -85) {
      bars = 2;
    } else if (rssi > -100) {
      bars = 1;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        bool active = index < bars;
        return Container(
          width: 3,
          height: 4 + (index * 3).toDouble(),
          margin: const EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            color: active
                ? (bars <= 1 ? AppColors.error : (bars <= 2 ? AppColors.meshBadge : AppColors.success))
                : AppColors.textMuted.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Widget _buildDeviceTrailingAction(
    BuildContext context,
    ChatProvider provider,
    Device device,
  ) {
    final bool isConnected = device.state == SessionState.connected;

    if (device.state == SessionState.connecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }

    return ElevatedButton(
      onPressed: () {
        if (isConnected) {
          provider.disconnectFromDevice(device);
        } else {
          provider.connectToDevice(device);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isConnected
            ? AppColors.surfaceElevated
            : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(
        isConnected ? 'Unlink' : 'Link',
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
      ),
    );
  }
}
