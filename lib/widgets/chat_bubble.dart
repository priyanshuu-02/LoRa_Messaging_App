import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/models/chat_message.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: AppAnimations.normal,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: AppAnimations.defaultCurve),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOut),
    );
    final isSent = widget.message.isSentByUser;
    _slideAnimation = Tween<Offset>(
      begin: Offset(isSent ? 0.15 : -0.15, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: AppAnimations.defaultCurve),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSentByUser = widget.message.isSentByUser;
    final margin = isSentByUser
        ? const EdgeInsets.only(left: 55)
        : const EdgeInsets.only(right: 55);
    final crossAxisAlignment =
        isSentByUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment: isSentByUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Container(
                margin: margin,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                decoration: BoxDecoration(
                  gradient: isSentByUser ? AppGradients.sentBubble : null,
                  color: isSentByUser ? null : AppColors.receivedBubble,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isSentByUser ? 18 : 4),
                    bottomRight: Radius.circular(isSentByUser ? 4 : 18),
                  ),
                  border: isSentByUser
                      ? null
                      : Border.all(
                          color: AppColors.divider,
                          width: 0.5,
                        ),
                  boxShadow: [
                    if (isSentByUser)
                      BoxShadow(
                        color: AppColors.sentBubbleStart.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: isSentByUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSentByUser) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.message.senderId,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      widget.message.text,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.message.isEncrypted) ...[
                          Icon(
                            Icons.lock_rounded,
                            size: 10,
                            color: isSentByUser
                                ? Colors.white.withOpacity(0.55)
                                : AppColors.secondary,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          DateFormat('hh:mm a').format(widget.message.timestamp),
                          style: GoogleFonts.inter(
                            color: isSentByUser
                                ? Colors.white.withOpacity(0.55)
                                : AppColors.textHint,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (isSentByUser) ...[
                          const SizedBox(width: 4),
                          _buildStatusIcon(widget.message.status),
                        ],
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withOpacity(0.5),
            ),
          ),
        );
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: AppColors.primary);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: AppColors.error);
      default:
        return const SizedBox.shrink();
    }
  }
}
