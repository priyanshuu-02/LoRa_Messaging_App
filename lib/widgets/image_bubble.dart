import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/image_service.dart';

/// Displays a LoRa-transmitted image inside a chat bubble.
/// Renders pixel data at native resolution and scales up with
/// nearest-neighbor interpolation for a pixel-art aesthetic.
class ImageBubble extends StatelessWidget {
  final ChatMessage message;

  const ImageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.mediaBytes == null) {
      return Text(
        '📷 Image (data missing)',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textHint,
        ),
      );
    }

    final quality = ImageService.detectQuality(message.mediaBytes!);
    final result = ImageService.decompress(message.mediaBytes!, quality);
    final displaySize = quality == ImageQuality.dithered ? 192.0 : 160.0;
    final label = quality == ImageQuality.dithered ? '64×64 Dithered' : '32×32 Grayscale';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The image
        GestureDetector(
          onTap: () => _showFullscreen(context, result, quality),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              size: Size(displaySize, displaySize),
              painter: _PixelImagePainter(
                rgba: result.rgba,
                width: result.width,
                height: result.height,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Quality label
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.grid_on_rounded,
              size: 10,
              color: message.isSentByUser
                  ? Colors.white.withOpacity(0.5)
                  : AppColors.textHint,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 9,
                color: message.isSentByUser
                    ? Colors.white.withOpacity(0.5)
                    : AppColors.textHint,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showFullscreen(
    BuildContext context,
    ({Uint8List rgba, int width, int height}) result,
    ImageQuality quality,
  ) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'LoRa Image',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  size: const Size(280, 280),
                  painter: _PixelImagePainter(
                    rgba: result.rgba,
                    width: result.width,
                    height: result.height,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${result.width}×${result.height} pixels • ${message.mediaBytes!.length} bytes',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that renders raw RGBA pixel data.
/// Uses nearest-neighbor scaling for the pixel-art look.
class _PixelImagePainter extends CustomPainter {
  final Uint8List rgba;
  final int width;
  final int height;

  _PixelImagePainter({
    required this.rgba,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pixelW = size.width / width;
    final pixelH = size.height / height;
    final paint = Paint();

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (i + 3 >= rgba.length) continue;

        paint.color = Color.fromARGB(
          rgba[i + 3], // A
          rgba[i],     // R
          rgba[i + 1], // G
          rgba[i + 2], // B
        );

        canvas.drawRect(
          Rect.fromLTWH(x * pixelW, y * pixelH, pixelW + 0.5, pixelH + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelImagePainter oldDelegate) {
    return oldDelegate.rgba != rgba;
  }
}
