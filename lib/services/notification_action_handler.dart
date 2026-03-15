import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'database_helper.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  // Handle background notification tap/action
  debugPrint('Notification background action: ${notificationResponse.actionId}');
  
  if (notificationResponse.actionId == 'mark_read_action') {
    final String? peerUuid = notificationResponse.payload;
    if (peerUuid != null) {
      await _markChatAsRead(peerUuid);
    }
  } else if (notificationResponse.actionId == 'reply_action') {
    final String? peerUuid = notificationResponse.payload;
    final String? replyText = notificationResponse.input;
    if (peerUuid != null && replyText != null && replyText.isNotEmpty) {
      // In a real app, we'd send the message here. 
      // For this prototype, we'll mark as read and potentially store the reply.
      await _markChatAsRead(peerUuid);
      debugPrint('Reply to $peerUuid: $replyText');
    }
  }
}

Future<void> _markChatAsRead(String peerUuid) async {
  final dbHelper = DatabaseHelper.instance;
  final chats = await dbHelper.getChats();
  final index = chats.indexWhere((c) => c.peerUuid == peerUuid);
  
  if (index >= 0) {
    final chat = chats[index];
    await dbHelper.insertChat(chat.copyWith(unreadCount: 0));
    debugPrint('Marked chat $peerUuid as read from notification action');
  }
}
