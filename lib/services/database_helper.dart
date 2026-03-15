import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../models/peer_model.dart';
import '../models/group_model.dart';
import '../core/constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('airlink.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 11,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.userTable} (
        id TEXT PRIMARY KEY,
        uuid TEXT NOT NULL,
        deviceName TEXT NOT NULL,
        profileImage TEXT,
        status TEXT,
        isMe INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.messageTable} (
        id TEXT PRIMARY KEY,
        senderUuid TEXT NOT NULL,
        senderName TEXT NOT NULL DEFAULT 'Unknown',
        receiverUuid TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        type INTEGER NOT NULL,
        status INTEGER NOT NULL,
        hopCount INTEGER NOT NULL DEFAULT 0,
        encryptedPayload TEXT,
        payloadId INTEGER,
        progress REAL,
        isFileAccepted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        uuid TEXT PRIMARY KEY,
        deviceName TEXT NOT NULL,
        lastSeen TEXT NOT NULL,
        connectionType TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.chatTable} (
        id TEXT PRIMARY KEY,
        peerUuid TEXT NOT NULL,
        peerName TEXT NOT NULL,
        lastMessage TEXT NOT NULL,
        lastMessageTime TEXT NOT NULL,
        unreadCount INTEGER NOT NULL,
        peerProfileImage TEXT,
        isFavorite INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.groupTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdBy TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        groupImage TEXT,
        lastMessage TEXT,
        lastMessageTime TEXT NOT NULL,
        unreadCount INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ${AppConstants.groupMemberTable} (
        groupId TEXT NOT NULL,
        userUuid TEXT NOT NULL,
        PRIMARY KEY (groupId, userUuid)
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 11) {
      // Recreate tables or alter table. For prototype, recreate is simpler for major schema jumps.
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.userTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.messageTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.chatTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.groupTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.groupMemberTable}');
      await db.execute('DROP TABLE IF EXISTS peers');
      await _createDB(db, newVersion);
    }
  }

  // --- User Operations ---
  Future<void> createUser(User user) async {
    final db = await instance.database;
    await db.insert(
      AppConstants.userTable,
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<User?> getUser(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      AppConstants.userTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    } else {
      return null;
    }
  }

  // --- Message Operations ---
  Future<void> insertMessage(Message message) async {
    final db = await instance.database;
    await db.insert(
      AppConstants.messageTable,
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Message>> getMessages(String peerUuid, String myUuid) async {
    final db = await instance.database;
    final bool isGroup = peerUuid.contains('group_');
    
    final res = await db.query(
      AppConstants.messageTable,
      where: isGroup
          ? 'receiverUuid = ?'
          : '(senderUuid = ? AND receiverUuid = ?) OR (senderUuid = ? AND receiverUuid = ?)',
      whereArgs: isGroup ? [peerUuid] : [myUuid, peerUuid, peerUuid, myUuid],
      orderBy: 'timestamp ASC',
    );

    return res.map((m) => Message.fromMap(m)).toList();
  }

  Future<List<Message>> getRecentMessages(String peerUuid, String myUuid, {int limit = 5}) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.messageTable,
      where:
          '(senderUuid = ? AND receiverUuid = ?) OR (senderUuid = ? AND receiverUuid = ?)',
      whereArgs: [myUuid, peerUuid, peerUuid, myUuid],
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return res.map((m) => Message.fromMap(m)).toList().reversed.toList();
  }

  Future<List<Message>> getQueuedMessages(String peerUuid) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.messageTable,
      where: 'receiverUuid = ? AND status = ?',
      whereArgs: [peerUuid, MessageStatus.queued.index],
      orderBy: 'timestamp ASC',
    );

    return res.map((m) => Message.fromMap(m)).toList();
  }

  // --- Chat Operations ---
  Future<void> insertChat(Chat chat) async {
    final db = await instance.database;
    await db.insert(
      AppConstants.chatTable,
      chat.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Chat>> getChats() async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.chatTable,
      orderBy: 'lastMessageTime DESC',
    );

    return res.map((c) => Chat.fromMap(c)).toList();
  }

  Future<Chat?> getChatByPeerUuid(String peerUuid) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.chatTable,
      where: 'peerUuid = ?',
      whereArgs: [peerUuid],
      limit: 1,
    );
    if (res.isNotEmpty) return Chat.fromMap(res.first);
    return null;
  }

  // --- Peer Operations ---
  Future<void> insertPeer(Peer peer) async {
    final db = await instance.database;
    await db.insert(
      'peers',
      peer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Peer>> getAllPeers() async {
    final db = await instance.database;
    final res = await db.query('peers', orderBy: 'lastSeen DESC');
    return res.map((p) => Peer.fromMap(p)).toList();
  }

  Future<Peer?> getPeer(String uuid) async {
    final db = await instance.database;
    final res = await db.query(
      'peers',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (res.isNotEmpty) return Peer.fromMap(res.first);
    return null;
  }

  Future<void> updatePeerLastSeen(String uuid) async {
    final db = await instance.database;
    await db.update(
      'peers',
      {'lastSeen': DateTime.now().toIso8601String()},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<List<Map<String, String>>> getKnownDevices() async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.chatTable,
      columns: ['peerName', 'peerUuid'],
      distinct: true,
    );

    return res
        .map(
          (row) => {
            'name': row['peerName'] as String,
            'uuid': row['peerUuid'] as String,
          },
        )
        .toList();
  }

  Future<void> deleteMessage(String id) async {
    final db = await instance.database;
    await db.delete(
      AppConstants.messageTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteChat(String peerUuid) async {
    final db = await instance.database;
    // Delete all messages associated with this peer
    await db.delete(
      AppConstants.messageTable,
      where: 'senderUuid = ? OR receiverUuid = ?',
      whereArgs: [peerUuid, peerUuid],
    );
    // Delete the chat summary
    await db.delete(
      AppConstants.chatTable,
      where: 'peerUuid = ?',
      whereArgs: [peerUuid],
    );
  }

  Future<void> updateMessageProgress(String id, double progress) async {
    final db = await instance.database;
    await db.update(
      AppConstants.messageTable,
      {'progress': progress},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateMessagePayloadId(String id, int payloadId) async {
    final db = await instance.database;
    await db.update(
      AppConstants.messageTable,
      {'payloadId': payloadId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateMessageContent(String id, String content) async {
    final db = await instance.database;
    await db.update(
      AppConstants.messageTable,
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Message?> getMessageByPayloadId(int payloadId) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.messageTable,
      where: 'payloadId = ?',
      whereArgs: [payloadId],
      limit: 1,
    );
    if (res.isNotEmpty) return Message.fromMap(res.first);
    return null;
  }

  Future<void> deleteAllChats() async {
    final db = await instance.database;
    await db.delete(AppConstants.messageTable);
    await db.delete(AppConstants.chatTable);
  }

  Future<Message?> getMessageById(String id) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.messageTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (res.isNotEmpty) return Message.fromMap(res.first);
    return null;
  }

  Future<void> markMessagesAsRead(String peerUuid, String myUuid) async {
    final db = await instance.database;
    await db.update(
      AppConstants.messageTable,
      {'status': MessageStatus.read.index},
      where: 'senderUuid = ? AND receiverUuid = ? AND status != ?',
      whereArgs: [peerUuid, myUuid, MessageStatus.read.index],
    );
  }

  // --- Group Operations ---
  Future<void> insertGroup(Group group) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.insert(
        AppConstants.groupTable,
        group.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Clear existing members if updating
      await txn.delete(
        AppConstants.groupMemberTable,
        where: 'groupId = ?',
        whereArgs: [group.id],
      );

      for (var memberUuid in group.members) {
        await txn.insert(
          AppConstants.groupMemberTable,
          {
            'groupId': group.id,
            'userUuid': memberUuid,
          },
        );
      }
    });
  }

  Future<List<Group>> getGroups() async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.groupTable,
      orderBy: 'lastMessageTime DESC',
    );

    List<Group> groups = [];
    for (var map in res) {
      final members = await getGroupMembers(map['id'] as String);
      groups.add(Group.fromMap(map, members));
    }
    return groups;
  }

  Future<Group?> getGroupById(String id) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.groupTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (res.isNotEmpty) {
      final members = await getGroupMembers(id);
      return Group.fromMap(res.first, members);
    }
    return null;
  }

  Future<List<String>> getGroupMembers(String groupId) async {
    final db = await instance.database;
    final res = await db.query(
      AppConstants.groupMemberTable,
      where: 'groupId = ?',
      whereArgs: [groupId],
    );

    return res.map((m) => m['userUuid'] as String).toList();
  }

  Future<void> deleteGroup(String groupId) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        AppConstants.groupTable,
        where: 'id = ?',
        whereArgs: [groupId],
      );
      await txn.delete(
        AppConstants.groupMemberTable,
        where: 'groupId = ?',
        whereArgs: [groupId],
      );
      // Optional: delete messages too
      await txn.delete(
        AppConstants.messageTable,
        where: 'receiverUuid = ?',
        whereArgs: [groupId],
      );
    });
  }
}
