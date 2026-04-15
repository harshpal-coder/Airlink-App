import '../models/message_model.dart';
import '../services/database_helper.dart';
import '../services/messaging_service.dart';
import '../core/event_bus.dart';

class ChatRepository {
  final DatabaseHelper _dbHelper;
  final MessagingService _messagingService;

  ChatRepository({
    required DatabaseHelper dbHelper,
    required MessagingService messagingService,
  })  : _dbHelper = dbHelper,
        _messagingService = messagingService;

  Future<List<Message>> getMessages(String peerUuid, String myUuid, {int? limit, int? offset}) async {
    return _dbHelper.getMessages(peerUuid, myUuid, limit: limit, offset: offset);
  }

  Future<void> sendMessage(String peerUuid, String peerName, String text) async {
    await _messagingService.sendTextMessage(peerUuid, peerName, text);
  }

  Stream<T> onEvent<T>() => appEventBus.on<T>();
}
