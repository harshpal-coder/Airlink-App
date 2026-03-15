class User {
  final String id;
  final String uuid;
  final String deviceName;
  final String? profileImage;
  final bool isMe;

  User({
    required this.id,
    required this.uuid,
    required this.deviceName,
    this.profileImage,
    required this.isMe,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'deviceName': deviceName,
      'profileImage': profileImage,
      'isMe': isMe ? 1 : 0,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      uuid: map['uuid'] ?? '',
      deviceName: map['deviceName'],
      profileImage: map['profileImage'],
      isMe: map['isMe'] == 1,
    );
  }

  User copyWith({
    String? id,
    String? uuid,
    String? deviceName,
    String? profileImage,
    bool? isMe,
  }) {
    return User(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      deviceName: deviceName ?? this.deviceName,
      profileImage: profileImage ?? this.profileImage,
      isMe: isMe ?? this.isMe,
    );
  }
}
