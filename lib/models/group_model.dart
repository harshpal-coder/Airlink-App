class Group {
  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final String? groupImage;
  final List<String> members; // List of member Uuids
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;

  Group({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.groupImage,
    required this.members,
    this.lastMessage = '',
    required this.lastMessageTime,
    this.unreadCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'groupImage': groupImage,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.toIso8601String(),
      'unreadCount': unreadCount,
    };
  }

  factory Group.fromMap(Map<String, dynamic> map, List<String> members) {
    return Group(
      id: map['id'],
      name: map['name'],
      createdBy: map['createdBy'],
      createdAt: DateTime.parse(map['createdAt']),
      groupImage: map['groupImage'],
      members: members,
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: DateTime.parse(map['lastMessageTime']),
      unreadCount: map['unreadCount'] ?? 0,
    );
  }

  Group copyWith({
    String? id,
    String? name,
    String? createdBy,
    DateTime? createdAt,
    String? groupImage,
    List<String>? members,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      groupImage: groupImage ?? this.groupImage,
      members: members ?? this.members,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
