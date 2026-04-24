import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Service for recording and playing back voice notes.
/// Records AAC audio at low quality suitable for LoRa transmission.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _currentPlayingId;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get currentPlayingId => _currentPlayingId;

  /// Start recording a voice note.
  /// Records in AAC format at low bitrate for minimal file size.
  Future<bool> startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('❌ Microphone permission denied');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 16000, // 16kbps — low but intelligible
        ),
        path: path,
      );

      _isRecording = true;
      debugPrint('🎙️ Recording started: $path');
      return true;
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      return false;
    }
  }

  /// Stop recording and return the audio bytes.
  /// Returns null if recording failed or was not started.
  Future<Uint8List?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null) {
        debugPrint('❌ Recording returned null path');
        return null;
      }

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('❌ Recording file not found: $path');
        return null;
      }

      final bytes = await file.readAsBytes();
      debugPrint('🎙️ Recording stopped: ${bytes.length} bytes');

      // Clean up temp file
      await file.delete().catchError((_) {});

      return bytes;
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel an ongoing recording without saving.
  Future<void> cancelRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      _isRecording = false;
      if (path != null) {
        await File(path).delete().catchError((_) {});
      }
      debugPrint('🎙️ Recording cancelled');
    }
  }

  /// Play a voice note from raw bytes.
  Future<void> playAudio(String messageId, Uint8List audioBytes) async {
    try {
      // Stop any currently playing audio
      if (_isPlaying) {
        await _player.stop();
      }

      _currentPlayingId = messageId;
      _isPlaying = true;

      await _player.play(BytesSource(audioBytes));

      // Listen for completion
      _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _currentPlayingId = null;
      });

      debugPrint('🔊 Playing voice note: ${audioBytes.length} bytes');
    } catch (e) {
      debugPrint('❌ Error playing audio: $e');
      _isPlaying = false;
      _currentPlayingId = null;
    }
  }

  /// Stop the currently playing audio.
  Future<void> stopPlaying() async {
    await _player.stop();
    _isPlaying = false;
    _currentPlayingId = null;
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
