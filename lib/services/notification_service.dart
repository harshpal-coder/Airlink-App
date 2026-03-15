import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_action_handler.dart';
import 'database_helper.dart';
import '../models/user_model.dart';
import '../models/message_model.dart' as model;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? activeChatUuid;

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('launcher_icon');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle foreground notification tap
        debugPrint('Notification foreground response: ${response.actionId}');
        // We could navigate here or trigger a callback
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'airlink_mesh_v2', // id must match AndroidConfiguration
      'AirLink Mesh Active', // title
      description: 'Maintains offline mesh connectivity',
      importance: Importance.low, // Silent as requested
      playSound: false,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidNotificationChannel messagesChannel = AndroidNotificationChannel(
      'airlink_messages',
      'AirLink Messages',
      description: 'Notifications for incoming messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(messagesChannel);

    const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
      'airlink_sos',
      'AirLink SOS Alerts',
      description: 'Emergency SOS alerts from nearby devices',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.red,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(sosChannel);

    debugPrint('[NotificationService] Notification channels created.');
  }

  static Future<void> showIncomingMessage(
    String title, 
    String body, {
    String? senderUuid, 
    String? senderName,
    String? senderProfileImage,
  }) async {
    if (activeChatUuid != null && activeChatUuid == senderUuid) {
      debugPrint('Suppressing notification for active chat: $senderUuid');
      return;
    }

    // person representing the sender
    final Person sender = Person(
      name: senderName ?? title.replaceAll('Message from ', ''),
      key: senderUuid,
      icon: senderProfileImage != null ? BitmapFilePathAndroidIcon(senderProfileImage) : null,
    );

    // Fetch conversation history
    final dbHelper = DatabaseHelper.instance;
    final User? me = await dbHelper.getUser('me');
    final String myUuid = me?.uuid ?? 'me';

    // person representing "Me" (the receiver/device user)
    final String? myProfileImage = me?.profileImage;
    final Person mePerson = Person(
      name: me?.deviceName ?? 'Me',
      key: myUuid,
      icon: myProfileImage != null ? BitmapFilePathAndroidIcon(myProfileImage) : null,
    );

    final recentMessages = await dbHelper.getRecentMessages(senderUuid ?? '', myUuid);

    final List<Message> notificationMessages = recentMessages.map((model.Message m) {
      final bool isFromMe = m.senderUuid == myUuid || m.senderUuid == 'me';
      return Message(
        m.content,
        m.timestamp,
        isFromMe ? null : sender, // null means it's from "me" (the user)
      );
    }).toList();

    // If history is empty, add the current message at least
    if (notificationMessages.isEmpty) {
      notificationMessages.add(Message(body, DateTime.now(), sender));
    }

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      mePerson,
      groupConversation: false,
      messages: notificationMessages,
    );

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'airlink_messages',
      'AirLink Messages',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: messagingStyle,
      color: const Color(0xFF0D47A1), // AirLink Blue
      showWhen: true,
      category: AndroidNotificationCategory.message,
      shortcutId: senderUuid,
      largeIcon: senderProfileImage != null ? FilePathAndroidBitmap(senderProfileImage) : null,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'reply_action',
          'Reply',
          inputs: [
            AndroidNotificationActionInput(
              label: 'Type your message...',
            ),
          ],
        ),
        const AndroidNotificationAction(
          'mark_read_action',
          'Mark as Read',
        ),
      ],
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id: senderUuid?.hashCode.remainder(100000) ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: senderName ?? title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: senderUuid, // Pass senderUuid as payload for navigation
    );
  }

  static Future<void> showSOSAlert(String senderName, String content) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'airlink_sos',
      'AirLink SOS Alerts',
      channelDescription: 'Emergency SOS alerts from nearby devices',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'SOS',
      color: Colors.red,
      ledColor: Colors.red,
      ledOnMs: 1000,
      ledOffMs: 500,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id: 911, // Unique ID for SOS
      title: '🚨 SOS ALERT: $senderName',
      body: content,
      notificationDetails: platformChannelSpecifics,
      payload: 'sos_alert',
    );
  }

  static Future<void> showProximityAlert(String peerName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'airlink_proximity',
      'AirLink Proximity Alerts',
      channelDescription: 'Alerts when favorite devices are nearby',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      color: Colors.green,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id: 777, // Unique ID for Proximity
      title: '📍 Favorite Nearby!',
      body: '$peerName is now in your mesh range.',
      notificationDetails: platformChannelSpecifics,
      payload: 'proximity_alert',
    );
  }
}
