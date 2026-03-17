class Peer {
  final String uuid;
  final String deviceName;
  final DateTime lastSeen;
  final String connectionType; // 'bluetooth', 'wifi_direct', 'nearby'
  final bool isVerified;

  Peer({
    required this.uuid,
    required this.deviceName,
    required this.lastSeen,
    required this.connectionType,
    this.isVerified = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'deviceName': deviceName,
      'lastSeen': lastSeen.toIso8601String(),
      'connectionType': connectionType,
      'isVerified': isVerified ? 1 : 0,
    };
  }

  factory Peer.fromMap(Map<String, dynamic> map) {
    return Peer(
      uuid: map['uuid'],
      deviceName: map['deviceName'],
      lastSeen: DateTime.parse(map['lastSeen']),
      connectionType: map['connectionType'],
      isVerified: map['isVerified'] == 1,
    );
  }

  Peer copyWith({
    String? uuid,
    String? deviceName,
    DateTime? lastSeen,
    String? connectionType,
    bool? isVerified,
  }) {
    return Peer(
      uuid: uuid ?? this.uuid,
      deviceName: deviceName ?? this.deviceName,
      lastSeen: lastSeen ?? this.lastSeen,
      connectionType: connectionType ?? this.connectionType,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
