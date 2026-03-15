enum MessageType { text, image, file, audio, pdf, sos }

enum MessageStatus { sending, sent, delivered, read, failed, queued, relay }

class Message {
  final String id;
  final String senderUuid;
  final String senderName;
  final String receiverUuid;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final MessageStatus status;
  final int hopCount;
  final String? encryptedPayload;
  final int? payloadId;
  final double? progress;
  final bool isFileAccepted;

  Message({
    required this.id,
    required this.senderUuid,
    this.senderName = 'Unknown',
    required this.receiverUuid,
    required this.content,
    required this.timestamp,
    required this.type,
    required this.status,
    this.hopCount = 0,
    this.encryptedPayload,
    this.payloadId,
    this.progress,
    this.isFileAccepted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderUuid': senderUuid,
      'senderName': senderName,
      'receiverUuid': receiverUuid,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.index,
      'status': status.index,
      'hopCount': hopCount,
      'encryptedPayload': encryptedPayload,
      'payloadId': payloadId,
      'progress': progress,
      'isFileAccepted': isFileAccepted ? 1 : 0,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      senderUuid: map['senderUuid'] ?? map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Unknown',
      receiverUuid: map['receiverUuid'] ?? map['receiverId'] ?? '',
      content: map['content'],
      timestamp: DateTime.parse(map['timestamp']),
      type: MessageType.values[map['type']],
      status: MessageStatus.values[map['status']],
      hopCount: map['hopCount'] ?? 0,
      encryptedPayload: map['encryptedPayload'],
      payloadId: map['payloadId'],
      progress: map['progress']?.toDouble(),
      isFileAccepted: map['isFileAccepted'] == 1,
    );
  }

  Message copyWith({
    String? id,
    String? senderUuid,
    String? senderName,
    String? receiverUuid,
    String? content,
    DateTime? timestamp,
    MessageType? type,
    MessageStatus? status,
    int? hopCount,
    String? encryptedPayload,
    int? payloadId,
    double? progress,
    bool? isFileAccepted,
  }) {
    return Message(
      id: id ?? this.id,
      senderUuid: senderUuid ?? this.senderUuid,
      senderName: senderName ?? this.senderName,
      receiverUuid: receiverUuid ?? this.receiverUuid,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
      hopCount: hopCount ?? this.hopCount,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      payloadId: payloadId ?? this.payloadId,
      progress: progress ?? this.progress,
      isFileAccepted: isFileAccepted ?? this.isFileAccepted,
    );
  }
}
