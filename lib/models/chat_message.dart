enum MessageStatus {
  none, // For received messages
  sending, // Optimistic: message is on its way
  delivered, // Confirmed: message received by the module (via ACK)
  failed, // If sending fails or times out
}

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String receiverId;
  final DateTime timestamp;
  final bool isSentByUser;
  final MessageStatus status;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    this.isSentByUser = false,
    // Default to 'sending' for user messages, not applicable for received ones.
    this.status = MessageStatus.none,
  });

  ChatMessage copyWith({
    String? id,
    String? text,
    String? senderId,
    String? receiverId,
    DateTime? timestamp,
    bool? isSentByUser,
    MessageStatus? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      timestamp: timestamp ?? this.timestamp,
      isSentByUser: isSentByUser ?? this.isSentByUser,
      status: status ?? this.status,
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
      );
}
