import 'dart:ui';
import 'dart:isolate';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import '../models/message_model.dart' as model;
import '../models/chat_model.dart' as model_chat;
import '../models/user_model.dart' as model_user;

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
      // Mark as read immediately on reply
      await _markChatAsRead(peerUuid);
      debugPrint('Reply to $peerUuid: $replyText');
      
      final SendPort? sendPort = IsolateNameServer.lookupPortByName('notification_reply_port');
      if (sendPort != null) {
        sendPort.send({
          'peerUuid': peerUuid,
          'text': replyText,
        });
        debugPrint('Sent reply payload to main isolate via SendPort');
      } else {
        debugPrint('Main isolate port not found! Queuing message in DB.');
        
        // Fallback: Queue message so it sends on next app start/reconnect
        final dbHelper = DatabaseHelper.instance;
        final model_user.User? me = await dbHelper.getUser('me');
        final String myUuid = me?.uuid ?? 'me';
        final String msgId = const Uuid().v4();
        
        final message = model.Message(
          id: msgId,
          senderUuid: myUuid,
          receiverUuid: peerUuid,
          content: replyText,
          timestamp: DateTime.now(),
          type: model.MessageType.text,
          status: model.MessageStatus.queued,
          hopCount: 0,
        );
        await dbHelper.insertMessage(message);
        
        final chat = await dbHelper.getChatByPeerUuid(peerUuid);
        final peerName = chat?.peerName ?? 'Unknown';
        await dbHelper.insertChat(
          model_chat.Chat(
            id: chat?.id ?? 'chat_$peerUuid',
            peerUuid: peerUuid,
            peerName: peerName,
            peerProfileImage: chat?.peerProfileImage,
            lastMessage: replyText,
            lastMessageTime: message.timestamp,
            unreadCount: 0,
            isFavorite: chat?.isFavorite ?? false,
          )
        );
      }
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
