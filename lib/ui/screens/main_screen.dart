import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../../core/constants.dart';
import 'chat_list_screen.dart';
import 'group_list_screen.dart';
import 'discovery_screen.dart';
import 'settings_screen.dart';
import 'emergency_alert_screen.dart';
import '../../services/chat_provider.dart';
import '../../utils/background_utils.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ChatListScreen(),
    GroupListScreen(),
    DiscoveryScreen(),
    SettingsScreen(),
  ];

  StreamSubscription? _sosSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      _sosSubscription = chatProvider.messagingService.sosAlerts.listen((alert) {
        _showEmergencySOS(alert);
      });
      _checkBatteryOptimizations();
      _checkOverlayPermission();
    });
  }

  Future<void> _checkOverlayPermission() async {
    if (Platform.isAndroid) {
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }
    }
  }

  Future<void> _checkBatteryOptimizations() async {
    if (Platform.isAndroid) {
      final isIgnored = await BackgroundUtils.isBatteryOptimizationIgnored();
      if (!isIgnored) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Background performance may be delayed. Disable battery optimization in Settings.'),
            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.9),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamed(context, '/settings');
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _sosSubscription?.cancel();
    super.dispose();
  }

  Future<void> _showEmergencySOS(Map<String, dynamic> alert) async {
    if (!mounted) return;
    
    if (Platform.isAndroid) {
      try {
        const foregroundChannel = MethodChannel('com.airlink/foreground');
        await foregroundChannel.invokeMethod('bringToForeground');
      } catch (e) {
        debugPrint('[SOS] Error bringing to foreground: $e');
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmergencyAlertScreen(
        senderName: alert['senderName'] ?? alert['senderId'] ?? 'Unknown',
        content: alert['content'] ?? 'Emergency SOS Alert!',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          indicatorColor: AppColors.primary.withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              );
            }
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: AppColors.primary);
            }
            return const IconThemeData(color: AppColors.textSecondary);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 70,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_outlined),
              selectedIcon: Icon(Icons.chat),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Groups',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore),
              label: 'Discovery',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
