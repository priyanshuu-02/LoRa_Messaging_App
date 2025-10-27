import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lora_communicator/models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isSentByUser = message.isSentByUser;
    final alignment =
        isSentByUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isSentByUser
        ? Theme.of(context).colorScheme.primary.withOpacity(0.4)
        : Colors.grey.shade900;
    final margin = isSentByUser
        ? const EdgeInsets.only(left: 60)
        : const EdgeInsets.only(right: 60);
    final crossAxisAlignment =
        isSentByUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Container(
          margin: margin,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: isSentByUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isSentByUser)
                Text(
                  message.senderId,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                    fontSize: 13,
                  ),
                ),
              if (!isSentByUser) const SizedBox(height: 4),
              Text(
                message.text,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('hh:mm a').format(message.timestamp),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  if (isSentByUser) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(message.status),
                  ],
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule, size: 14, color: Colors.grey.shade600);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
      default:
        // Assuming there's a 'sent' status or others
        // You might want a single grey tick:
        // return const Icon(Icons.check, size: 14, color: Colors.grey.shade600);
        return const SizedBox.shrink();
    }
  }
}
