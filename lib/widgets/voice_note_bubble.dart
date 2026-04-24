import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/audio_service.dart';

class VoiceNoteBubble extends StatefulWidget {
  final ChatMessage message;
  final AudioService audioService;

  const VoiceNoteBubble({
    super.key,
    required this.message,
    required this.audioService,
  });

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _waveController;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  void _togglePlayback() async {
    if (_isPlaying) {
      await widget.audioService.stopPlaying();
      _waveController.stop();
      setState(() => _isPlaying = false);
    } else {
      if (widget.message.mediaBytes != null) {
        await widget.audioService.playAudio(
          widget.message.id,
          widget.message.mediaBytes!,
        );
        _waveController.repeat();
        setState(() => _isPlaying = true);

        // Auto-stop when done
        Future.delayed(
          Duration(seconds: widget.message.mediaDuration ?? 5),
          () {
            if (mounted && _isPlaying) {
              _waveController.stop();
              setState(() => _isPlaying = false);
            }
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSent = widget.message.isSentByUser;
    final duration = widget.message.mediaDuration ?? 0;
    final durationStr = '0:${duration.toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/Pause button
        GestureDetector(
          onTap: _togglePlayback,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isSent ? null : AppGradients.primary,
              color: isSent ? Colors.white.withOpacity(0.2) : null,
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: isSent ? Colors.white : Colors.white,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Waveform visualization
        Expanded(
          child: AnimatedBuilder(
            animation: _waveController,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(double.infinity, 28),
                painter: _WaveformPainter(
                  progress: _isPlaying ? _waveController.value : 0.0,
                  isPlaying: _isPlaying,
                  color: isSent
                      ? Colors.white.withOpacity(0.6)
                      : AppColors.primary.withOpacity(0.5),
                  activeColor: isSent ? Colors.white : AppColors.primary,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),

        // Duration
        Text(
          durationStr,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSent
                ? Colors.white.withOpacity(0.7)
                : AppColors.textHint,
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color color;
  final Color activeColor;

  _WaveformPainter({
    required this.progress,
    required this.isPlaying,
    required this.color,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = 24;
    final barWidth = size.width / (barCount * 2);
    final maxHeight = size.height * 0.9;

    // Generate pseudo-random bar heights (deterministic)
    final heights = List.generate(barCount, (i) {
      final seed = (i * 7 + 3) % 11;
      return 0.2 + (seed / 11) * 0.8;
    });

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth * 2) + barWidth / 2;
      final barHeight = heights[i] * maxHeight;
      final y = (size.height - barHeight) / 2;

      final isActive = isPlaying && (i / barCount) < progress;

      final paint = Paint()
        ..color = isActive ? activeColor : color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;

      canvas.drawLine(
        Offset(x, y),
        Offset(x, y + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying;
  }
}
