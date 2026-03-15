import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'services/database_helper.dart';
import 'services/discovery_service.dart';
import 'services/messaging_service.dart';
import 'services/notification_service.dart';
import 'services/chat_provider.dart';

import 'ui/screens/splash_screen.dart';
import 'ui/screens/profile_setup_screen.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/discovery_screen.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/network_map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ensure database is ready
  await DatabaseHelper.instance.database;

  // Set system UI style for edge-to-edge display and transparent navigation bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));

  // Enable edge-to-edge
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Initialize notification service
  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Instantiate core services
    final discoveryService = DiscoveryService();
    final messagingService = MessagingService(
      discoveryService: discoveryService,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ChatProvider(
            discoveryService: discoveryService,
            messagingService: messagingService,
          ),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, // Defaulting to dark as per design
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/profile_setup': (context) => const ProfileSetupScreen(),
          '/home': (context) => const MainScreen(),
          '/discovery': (context) => const DiscoveryScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/network_map': (context) => const NetworkMapScreen(),
        },
        onGenerateRoute: (settings) {
          if (settings.name == '/chat') {
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (context) {
                return ChatScreen(
                  peerUuid: args['peerUuid'],
                  peerName: args['peerName'],
                  peerProfileImage: args['peerProfileImage'],
                );
              },
            );
          }
          return null;
        },
      ),
    );
  }
}
