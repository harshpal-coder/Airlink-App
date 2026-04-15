class Chat {
  final String id;
  final String peerUuid;
  final String peerName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final String? peerProfileImage;
  final bool isFavorite;
  final int? lastMessageStatus;
  final bool? lastMessageIsMe;

  Chat({
    required this.id,
    required this.peerUuid,
    required this.peerName,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.peerProfileImage,
    this.isFavorite = false,
    this.lastMessageStatus,
    this.lastMessageIsMe,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'peerUuid': peerUuid,
      'peerName': peerName,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCount': unreadCount,
      'peerProfileImage': peerProfileImage,
      'isFavorite': isFavorite ? 1 : 0,
    };
  }

  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'],
      peerUuid: map['peerUuid'] ?? map['peerId'] ?? '',
      peerName: map['peerName'],
      lastMessage: map['lastMessage'],
      lastMessageTime: DateTime.parse(map['lastMessageTime']),
      unreadCount: map['unreadCount'] ?? 0,
      peerProfileImage: map['peerProfileImage'],
      isFavorite: map['isFavorite'] == 1,
    );
  }

  Chat copyWith({
    String? id,
    String? peerUuid,
    String? peerName,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? peerProfileImage,
    bool? isFavorite,
    int? lastMessageStatus,
    bool? lastMessageIsMe,
  }) {
    return Chat(
      id: id ?? this.id,
      peerUuid: peerUuid ?? this.peerUuid,
      peerName: peerName ?? this.peerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      peerProfileImage: peerProfileImage ?? this.peerProfileImage,
      isFavorite: isFavorite ?? this.isFavorite,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageIsMe: lastMessageIsMe ?? this.lastMessageIsMe,
    );
  }
}
