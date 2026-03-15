class Peer {
  final String uuid;
  final String deviceName;
  final DateTime lastSeen;
  final String connectionType; // 'bluetooth', 'wifi_direct', 'nearby'

  Peer({
    required this.uuid,
    required this.deviceName,
    required this.lastSeen,
    required this.connectionType,
  });

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'deviceName': deviceName,
      'lastSeen': lastSeen.toIso8601String(),
      'connectionType': connectionType,
    };
  }

  factory Peer.fromMap(Map<String, dynamic> map) {
    return Peer(
      uuid: map['uuid'],
      deviceName: map['deviceName'],
      lastSeen: DateTime.parse(map['lastSeen']),
      connectionType: map['connectionType'],
    );
  }
}
