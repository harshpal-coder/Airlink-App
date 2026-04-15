import 'dart:convert';

enum MessageType { text, sos, audio, image, file }

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
  final DateTime? expiresAt;
  final bool isBurned;
  final String? imagePath;
  final String? relayedVia;
  final String? fileName;
  final int? fileSize;
  final String? replyToId;
  final Map<String, String>? reactions;

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
    this.expiresAt,
    this.isBurned = false,
    this.imagePath,
    this.relayedVia,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.reactions,
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
      'expiresAt': expiresAt?.toIso8601String(),
      'isBurned': isBurned ? 1 : 0,
      'imagePath': imagePath,
      'relayedVia': relayedVia,
      'fileName': fileName,
      'fileSize': fileSize,
      'replyToId': replyToId,
      'reactions': reactions != null ? jsonEncode(reactions) : null,
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
      expiresAt: map['expiresAt'] != null ? DateTime.parse(map['expiresAt']) : null,
      isBurned: map['isBurned'] == 1,
      imagePath: map['imagePath'] as String?,
      relayedVia: map['relayedVia'] as String?,
      fileName: map['fileName'] as String?,
      fileSize: map['fileSize'] as int?,
      replyToId: map['replyToId'] as String?,
      reactions: map['reactions'] != null ? Map<String, String>.from(jsonDecode(map['reactions'])) : null,
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
    DateTime? expiresAt,
    bool? isBurned,
    String? imagePath,
    String? relayedVia,
    String? fileName,
    int? fileSize,
    String? replyToId,
    Map<String, String>? reactions,
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
      expiresAt: expiresAt ?? this.expiresAt,
      isBurned: isBurned ?? this.isBurned,
      imagePath: imagePath ?? this.imagePath,
      relayedVia: relayedVia ?? this.relayedVia,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      replyToId: replyToId ?? this.replyToId,
      reactions: reactions ?? this.reactions,
    );
  }
}
