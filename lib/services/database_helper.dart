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
      version: 19,
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
        isFileAccepted INTEGER NOT NULL DEFAULT 0,
        expiresAt TEXT,
        isBurned INTEGER NOT NULL DEFAULT 0,
        imagePath TEXT,
        relayedVia TEXT,
        fileName TEXT,
        fileSize INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS peers (
        uuid TEXT PRIMARY KEY,
        deviceName TEXT NOT NULL,
        lastSeen TEXT NOT NULL,
        connectionType TEXT NOT NULL,
        isVerified INTEGER NOT NULL DEFAULT 0
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

    await _createSignalTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peer_reputation (
        uuid TEXT PRIMARY KEY,
        score REAL NOT NULL DEFAULT 50.0,
        success_count INTEGER NOT NULL DEFAULT 0,
        fail_count INTEGER NOT NULL DEFAULT 0,
        total_time_minutes INTEGER NOT NULL DEFAULT 0,
        consensus_score REAL NOT NULL DEFAULT 50.0,
        consensus_count INTEGER NOT NULL DEFAULT 0,
        last_updated TEXT NOT NULL
      )
    ''');
    await _createIndices(db);
  }

  Future<void> _createIndices(Database db) async {
    // Message indexing for fast chat history fetching
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_sender ON ${AppConstants.messageTable} (senderUuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_receiver ON ${AppConstants.messageTable} (receiverUuid)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON ${AppConstants.messageTable} (timestamp)');
    
    // Chat indexing for fast lookup
    await db.execute('CREATE INDEX IF NOT EXISTS idx_chats_peer ON ${AppConstants.chatTable} (peerUuid)');
    
    // Peer indexing
    await db.execute('CREATE INDEX IF NOT EXISTS idx_peers_lastseen ON peers (lastSeen)');
  }

  Future<void> _createSignalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signal_sessions (
        address_name TEXT,
        device_id INTEGER,
        session_record BLOB,
        PRIMARY KEY (address_name, device_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS signal_prekeys (
        id INTEGER PRIMARY KEY,
        record BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS signal_signed_prekeys (
        id INTEGER PRIMARY KEY,
        record BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS signal_identities (
        address_name TEXT PRIMARY KEY,
        identity_key BLOB,
        registration_id INTEGER
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 11) {
      // Legacy cleanup for versions before 11 (prototype phase)
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.userTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.messageTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.chatTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.groupTable}');
      await db.execute('DROP TABLE IF EXISTS ${AppConstants.groupMemberTable}');
      await db.execute('DROP TABLE IF EXISTS peers');
      await _createDB(db, newVersion);
    } else {
      // Incremental upgrades from version 11 onwards
      if (oldVersion < 12) {
        await _createSignalTables(db);
      }
      if (oldVersion < 13) {
        await _createIndices(db);
      }
      if (oldVersion < 14) {
        await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN expiresAt TEXT');
        await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN isBurned INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 15) {
        await db.execute('ALTER TABLE peers ADD COLUMN isVerified INTEGER NOT NULL DEFAULT 0');
      }
      if (oldVersion < 16) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS peer_reputation (
            uuid TEXT PRIMARY KEY,
            score REAL NOT NULL DEFAULT 50.0,
            success_count INTEGER NOT NULL DEFAULT 0,
            fail_count INTEGER NOT NULL DEFAULT 0,
            total_time_minutes INTEGER NOT NULL DEFAULT 0,
            consensus_score REAL NOT NULL DEFAULT 50.0,
            consensus_count INTEGER NOT NULL DEFAULT 0,
            last_updated TEXT NOT NULL
          )
        ''');
        // If table exists, add columns
        try {
          await db.execute('ALTER TABLE peer_reputation ADD COLUMN consensus_score REAL NOT NULL DEFAULT 50.0');
          await db.execute('ALTER TABLE peer_reputation ADD COLUMN consensus_count INTEGER NOT NULL DEFAULT 0');
        } catch (e) {
          // Table might have been created fresh in version 16
        }
      }
      if (oldVersion < 17) {
        try {
          await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN imagePath TEXT');
        } catch (e) {
          // Column may already exist
        }
      }
      if (oldVersion < 18) {
        try {
          await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN relayedVia TEXT');
        } catch (e) {
          // Column may already exist
        }
      }
      if (oldVersion < 19) {
        try {
          await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN fileName TEXT');
          await db.execute('ALTER TABLE ${AppConstants.messageTable} ADD COLUMN fileSize INTEGER');
        } catch (e) {
          // Column may already exist
        }
      }
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

  Future<List<Message>> getMessages(String peerUuid, String myUuid, {int? limit, int? offset}) async {
    final db = await instance.database;
    final bool isGroup = peerUuid.contains('group_');
    
    final res = await db.query(
      AppConstants.messageTable,
      where: isGroup
          ? 'receiverUuid = ?'
          : '(senderUuid = ? AND receiverUuid = ?) OR (senderUuid = ? AND receiverUuid = ?)',
      whereArgs: isGroup ? [peerUuid] : [myUuid, peerUuid, peerUuid, myUuid],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );

    return res.map((m) => Message.fromMap(m)).toList();
  }

  Future<List<Message>> getSharedMedia(String peerUuid, String myUuid, {int? limit}) async {
    final db = await instance.database;
    final bool isGroup = peerUuid.contains('group_');
    
    final res = await db.query(
      AppConstants.messageTable,
      where: isGroup
          ? 'receiverUuid = ? AND (type = ? OR type = ?)'
          : '((senderUuid = ? AND receiverUuid = ?) OR (senderUuid = ? AND receiverUuid = ?)) AND (type = ? OR type = ?)',
      whereArgs: isGroup 
          ? [peerUuid, MessageType.image.index, MessageType.file.index] 
          : [myUuid, peerUuid, peerUuid, myUuid, MessageType.image.index, MessageType.file.index],
      orderBy: 'timestamp DESC',
      limit: limit,
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

  Future<int> deleteExpiredMessages() async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.delete(
      AppConstants.messageTable,
      where: 'expiresAt IS NOT NULL AND expiresAt < ?',
      whereArgs: [now],
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

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = await instance.database;
    await db.update(
      AppConstants.messageTable,
      {'status': status.index},
      where: 'id = ?',
      whereArgs: [id],
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

    // Optimized: Fetch all members in one query to avoid N+1 problem
    final allMembersRes = await db.query(AppConstants.groupMemberTable);
    final Map<String, List<String>> groupToMembers = {};
    for (var row in allMembersRes) {
      final gId = row['groupId'] as String;
      final uUuid = row['userUuid'] as String;
      groupToMembers.putIfAbsent(gId, () => []).add(uUuid);
    }

    return res.map((map) {
      final id = map['id'] as String;
      return Group.fromMap(map, groupToMembers[id] ?? []);
    }).toList();
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

  // --- Signal Protocol Store Operations ---

  Future<void> storeSession(String addressName, int deviceId, List<int> record) async {
    final db = await instance.database;
    await db.insert(
      'signal_sessions',
      {
        'address_name': addressName,
        'device_id': deviceId,
        'session_record': record,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<int>?> loadSession(String addressName, int deviceId) async {
    final db = await instance.database;
    final res = await db.query(
      'signal_sessions',
      where: 'address_name = ? AND device_id = ?',
      whereArgs: [addressName, deviceId],
    );
    if (res.isNotEmpty) return res.first['session_record'] as List<int>?;
    return null;
  }

  Future<bool> containsSession(String addressName, int deviceId) async {
    final session = await loadSession(addressName, deviceId);
    return session != null;
  }

  Future<void> deleteSession(String addressName, int deviceId) async {
    final db = await instance.database;
    await db.delete(
      'signal_sessions',
      where: 'address_name = ? AND device_id = ?',
      whereArgs: [addressName, deviceId],
    );
  }

  Future<void> storePreKey(int id, List<int> record) async {
    final db = await instance.database;
    await db.insert('signal_prekeys', {'id': id, 'record': record}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<int>?> loadPreKey(int id) async {
    final db = await instance.database;
    final res = await db.query('signal_prekeys', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first['record'] as List<int>?;
    return null;
  }

  Future<void> deletePreKey(int id) async {
    final db = await instance.database;
    await db.delete('signal_prekeys', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> storeSignedPreKey(int id, List<int> record) async {
    final db = await instance.database;
    await db.insert('signal_signed_prekeys', {'id': id, 'record': record}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<int>?> loadSignedPreKey(int id) async {
    final db = await instance.database;
    final res = await db.query('signal_signed_prekeys', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) return res.first['record'] as List<int>?;
    return null;
  }

  Future<void> deleteSignedPreKey(int id) async {
    final db = await instance.database;
    await db.delete('signal_signed_prekeys', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> storeIdentity(String addressName, List<int> identityKey, int registrationId) async {
    final db = await instance.database;
    await db.insert(
      'signal_identities',
      {
        'address_name': addressName,
        'identity_key': identityKey,
        'registration_id': registrationId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadIdentity(String addressName) async {
    final db = await instance.database;
    final res = await db.query('signal_identities', where: 'address_name = ?', whereArgs: [addressName]);
    if (res.isNotEmpty) return res.first;
    return null;
  }

  // --- Maintenance Operations ---
  Future<int> pruneOldMessages(int days) async {
    final db = await instance.database;
    final cutoff = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return await db.delete(
      AppConstants.messageTable,
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> vacuum() async {
    final db = await instance.database;
    await db.execute('VACUUM');
  }
}
