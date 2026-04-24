import 'dart:convert';
import 'dart:typed_data';

enum MessageStatus {
  none, // For received messages
  sending, // Optimistic: message is on its way
  delivered, // Confirmed: message received by the module (via ACK)
  failed, // If sending fails or times out
}

enum MessageType {
  text,
  voiceNote,
  image,
}

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String receiverId;
  final DateTime timestamp;
  final bool isSentByUser;
  final MessageStatus status;
  final bool isEncrypted;
  final MessageType messageType;
  final Uint8List? mediaBytes; // Raw audio or image bytes
  final int? mediaDuration; // Voice note duration in seconds

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    this.isSentByUser = false,
    // Default to 'sending' for user messages, not applicable for received ones.
    this.status = MessageStatus.none,
    this.isEncrypted = false,
    this.messageType = MessageType.text,
    this.mediaBytes,
    this.mediaDuration,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    String? senderId,
    String? receiverId,
    DateTime? timestamp,
    bool? isSentByUser,
    MessageStatus? status,
    bool? isEncrypted,
    MessageType? messageType,
    Uint8List? mediaBytes,
    int? mediaDuration,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      timestamp: timestamp ?? this.timestamp,
      isSentByUser: isSentByUser ?? this.isSentByUser,
      status: status ?? this.status,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      messageType: messageType ?? this.messageType,
      mediaBytes: mediaBytes ?? this.mediaBytes,
      mediaDuration: mediaDuration ?? this.mediaDuration,
    );
  }

  // Convert a ChatMessage into a Map
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'senderId': senderId,
        'receiverId': receiverId,
        'timestamp': timestamp.toIso8601String(),
        'isSentByUser': isSentByUser,
        'status': status.index, // Store enum as index
        'isEncrypted': isEncrypted,
        'messageType': messageType.index,
        'mediaBytes':
            mediaBytes != null ? base64Encode(mediaBytes!) : null,
        'mediaDuration': mediaDuration,
      };

  // Create a ChatMessage from a Map
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        text: json['text'],
        senderId: json['senderId'],
        receiverId: json['receiverId'],
        timestamp: DateTime.parse(json['timestamp']),
        isSentByUser: json['isSentByUser'],
        status: MessageStatus.values[json['status']],
        isEncrypted: json['isEncrypted'] ?? false,
        messageType: json['messageType'] != null
            ? MessageType.values[json['messageType']]
            : MessageType.text,
        mediaBytes: json['mediaBytes'] != null
            ? base64Decode(json['mediaBytes'])
            : null,
        mediaDuration: json['mediaDuration'],
      );
}
