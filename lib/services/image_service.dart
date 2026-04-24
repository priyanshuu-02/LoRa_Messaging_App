import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Image quality modes for LoRa transmission.
enum ImageQuality {
  /// 64×64, 1-bit black/white dithered. ~512 bytes. Fast transfer.
  dithered,

  /// 32×32, 8-bit grayscale. ~1024 bytes. Better tonal detail.
  grayscale,
}

/// Service for capturing, compressing, and decompressing images
/// optimized for LoRa transmission.
class ImageService {
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from camera or gallery.
  Future<Uint8List?> pickImage({required ImageSource source}) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 50,
      );
      if (picked == null) return null;
      return await picked.readAsBytes();
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      return null;
    }
  }

  /// Compress an image for LoRa transmission.
  /// Returns packed bytes ready for sending.
  static Uint8List compress(Uint8List imageBytes, ImageQuality quality) {
    final source = img.decodeImage(imageBytes);
    if (source == null) throw Exception('Failed to decode image');

    switch (quality) {
      case ImageQuality.dithered:
        return _compressDithered(source);
      case ImageQuality.grayscale:
        return _compressGrayscale(source);
    }
  }

  /// 64×64, 1-bit Floyd-Steinberg dithered. Output: 512 bytes.
  static Uint8List _compressDithered(img.Image source) {
    // Resize to 64×64
    final resized = img.copyResize(source, width: 64, height: 64);

    // Convert to grayscale
    final gray = img.grayscale(resized);

    // Floyd-Steinberg dithering
    final pixels = List<List<double>>.generate(
      64,
      (y) => List.generate(64, (x) {
        final pixel = gray.getPixel(x, y);
        return img.getLuminance(pixel).toDouble();
      }),
    );

    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final oldPixel = pixels[y][x];
        final newPixel = oldPixel > 128 ? 255.0 : 0.0;
        final error = oldPixel - newPixel;
        pixels[y][x] = newPixel;

        if (x + 1 < 64) pixels[y][x + 1] += error * 7 / 16;
        if (y + 1 < 64) {
          if (x - 1 >= 0) pixels[y + 1][x - 1] += error * 3 / 16;
          pixels[y + 1][x] += error * 5 / 16;
          if (x + 1 < 64) pixels[y + 1][x + 1] += error * 1 / 16;
        }
      }
    }

    // Pack 8 pixels per byte (MSB first)
    final packed = Uint8List(512); // 64*64/8
    for (int y = 0; y < 64; y++) {
      for (int x = 0; x < 64; x++) {
        final bitIndex = y * 64 + x;
        final byteIndex = bitIndex ~/ 8;
        final bitPosition = 7 - (bitIndex % 8);
        if (pixels[y][x] > 128) {
          packed[byteIndex] |= (1 << bitPosition);
        }
      }
    }

    return packed;
  }

  /// 32×32, 8-bit grayscale. Output: 1024 bytes.
  static Uint8List _compressGrayscale(img.Image source) {
    final resized = img.copyResize(source, width: 32, height: 32);
    final gray = img.grayscale(resized);

    final bytes = Uint8List(1024); // 32*32
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        final pixel = gray.getPixel(x, y);
        bytes[y * 32 + x] = img.getLuminance(pixel).toInt();
      }
    }
    return bytes;
  }

  /// Decompress packed image bytes back to a displayable Flutter Image.
  /// Returns the raw RGBA pixel data and dimensions.
  static ({Uint8List rgba, int width, int height}) decompress(
      Uint8List packed, ImageQuality quality) {
    switch (quality) {
      case ImageQuality.dithered:
        return _decompressDithered(packed);
      case ImageQuality.grayscale:
        return _decompressGrayscale(packed);
    }
  }

  static ({Uint8List rgba, int width, int height}) _decompressDithered(
      Uint8List packed) {
    final rgba = Uint8List(64 * 64 * 4);
    for (int i = 0; i < 64 * 64; i++) {
      final byteIndex = i ~/ 8;
      final bitPosition = 7 - (i % 8);
      final isWhite =
          byteIndex < packed.length && (packed[byteIndex] >> bitPosition) & 1 == 1;
      final value = isWhite ? 255 : 0;
      rgba[i * 4] = value; // R
      rgba[i * 4 + 1] = value; // G
      rgba[i * 4 + 2] = value; // B
      rgba[i * 4 + 3] = 255; // A
    }
    return (rgba: rgba, width: 64, height: 64);
  }

  static ({Uint8List rgba, int width, int height}) _decompressGrayscale(
      Uint8List packed) {
    final rgba = Uint8List(32 * 32 * 4);
    for (int i = 0; i < 32 * 32 && i < packed.length; i++) {
      final value = packed[i];
      rgba[i * 4] = value; // R
      rgba[i * 4 + 1] = value; // G
      rgba[i * 4 + 2] = value; // B
      rgba[i * 4 + 3] = 255; // A
    }
    return (rgba: rgba, width: 32, height: 32);
  }

  /// Detect quality from packed data size.
  static ImageQuality detectQuality(Uint8List packed) {
    if (packed.length <= 512) return ImageQuality.dithered;
    return ImageQuality.grayscale;
  }
}
