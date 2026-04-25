import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/encryption_service.dart';
import 'package:lora_communicator/constants/app_constants.dart';
import 'package:uuid/uuid.dart';

class PacketFramerService with ChangeNotifier {
  BleService _bleService;
  EncryptionService _encryptionService;
  StreamSubscription? _rawDataSubscription;
  final Uuid _uuid = const Uuid();
  final Random _random = Random();

  // ─── Chunking constants ──────────────────────────────────────────────
  // Max bytes for the message body portion of a LoRa packet.
  // LoRa total = 256, minus ~15 bytes for "sender_id,recipient_id," routing
  // minus ~20 bytes for "CHK:XXXX:NN:NN:" header = ~220 safe bytes.
  static const int _maxChunkDataSize = 200;
  static const String _chunkPrefix = 'CHK:';
  static const Duration _chunkTimeout = Duration(seconds: 60);

  // ─── Chunk reassembly buffers ────────────────────────────────────────
  // Key: "senderId:msgId" → Map of chunkIndex → chunkData
  final Map<String, Map<int, String>> _chunkBuffer = {};
  final Map<String, int> _chunkTotalExpected = {};
  final Map<String, Timer> _chunkTimeouts = {};
  // Store the raw senderId for chunk reassembly
  final Map<String, String> _chunkSenderIds = {};

  // ─── Deduplication ───────────────────────────────────────────────────
  final Map<String, DateTime> _recentMessageHashes = {};
  static const Duration _deduplicationWindow = Duration(seconds: 2);

  bool _isPeerSending = false;
  Timer? _peerSendingTimer;

  // ─── Send progress tracking ──────────────────────────────────────────
  bool _isSending = false;
  bool _sendCancelled = false;
  int _chunksSent = 0;
  int _totalChunksToSend = 0;

  // ─── Receive progress tracking ───────────────────────────────────────
  bool _isReceivingChunks = false;
  int _chunksReceived = 0;
  int _totalChunksExpected = 0;

  final StreamController<ChatMessage> _reassembledMessageController =
      StreamController.broadcast();
  Stream<ChatMessage> get reassembledMessageStream =>
      _reassembledMessageController.stream;

  final StreamController<String> _ackController = StreamController.broadcast();
  Stream<String> get ackStream => _ackController.stream;

  // Public getters
  bool get isPeerSending => _isPeerSending;
  String get senderId => _bleService.senderId;
  bool get isEncryptionEnabled => _encryptionService.isEnabled;

  // ─── Progress getters ────────────────────────────────────────────────
  bool get isSending => _isSending;
  int get chunksSent => _chunksSent;
  int get totalChunksToSend => _totalChunksToSend;
  double get sendingProgress =>
      _totalChunksToSend > 0 ? _chunksSent / _totalChunksToSend : 0.0;

  bool get isReceivingChunks => _isReceivingChunks;
  int get chunksReceived => _chunksReceived;
  int get totalChunksExpected => _totalChunksExpected;
  double get receivingProgress =>
      _totalChunksExpected > 0 ? _chunksReceived / _totalChunksExpected : 0.0;

  /// True when either sending or receiving chunked data.
  /// Used by the UI to lock the composer during transmission.
  bool get isTransmitting => _isSending || _isReceivingChunks;

  /// Cancel any ongoing chunked send/receive and reset all progress state.
  /// Should be called before disconnecting from the BLE device to avoid
  /// leaving the ESP32/LoRa module in a half-received state.
  void cancelOngoingTransmission() {
    debugPrint('🛑 Cancelling ongoing transmission...');
    _sendCancelled = true;

    // Reset send progress
    _isSending = false;
    _chunksSent = 0;
    _totalChunksToSend = 0;

    // Reset receive progress
    _isReceivingChunks = false;
    _chunksReceived = 0;
    _totalChunksExpected = 0;

    // Clear all chunk reassembly buffers
    for (final key in _chunkBuffer.keys.toList()) {
      _cleanupChunkBuffer(key);
    }

    _isPeerSending = false;
    _peerSendingTimer?.cancel();

    notifyListeners();
    debugPrint('🛑 Transmission cancelled and state reset.');
  }

  PacketFramerService({
    required BleService bleService,
    required EncryptionService encryptionService,
  })  : _bleService = bleService,
        _encryptionService = encryptionService {
    _subscribeToBle();
  }

  void updateBleService(BleService newBleService) {
    if (_bleService != newBleService) {
      _bleService = newBleService;
      _rawDataSubscription?.cancel();
      _subscribeToBle();
    }
  }

  void updateEncryptionService(EncryptionService newEncryptionService) {
    _encryptionService = newEncryptionService;
  }

  void _subscribeToBle() {
    _rawDataSubscription =
        _bleService.rawDataStream.listen(_onDataReceived, onError: (error) {
      debugPrint("Error on raw data stream: $error");
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  RECEIVE PATH
  // ═══════════════════════════════════════════════════════════════════════

  void _onDataReceived(List<int> data) {
    String message = utf8.decode(data, allowMalformed: true);
    debugPrint("🔄 RAW BLE RECEIVED: $message");

    // Handle ACK frames
    if (message.startsWith('ACK:')) {
      final ackContent = message.substring(4);
      debugPrint("✅ ACK received: $ackContent");
      _ackController.add(ackContent);
      return;
    }

    // Parse "sender_id,message_content" format from LoRa
    int commaIndex = message.indexOf(',');
    if (commaIndex == -1) {
      debugPrint("❌ Malformed message received: $message");
      return;
    }

    String senderId = message.substring(0, commaIndex);
    String messageContent = message.substring(commaIndex + 1);

    debugPrint("📨 Parsed - Sender: $senderId, Content: $messageContent");

    // Deduplication
    final messageHash = '$senderId:$messageContent';
    final now = DateTime.now();
    _cleanupOldHashes(now);
    if (_recentMessageHashes.containsKey(messageHash)) {
      debugPrint("⚠️ Duplicate suppressed: $messageHash");
      return;
    }
    _recentMessageHashes[messageHash] = now;

    // Check if this is a chunk
    if (messageContent.startsWith(_chunkPrefix)) {
      _handleChunk(senderId, messageContent);
    } else {
      // Single message — process directly
      _processReceivedMessage(senderId, messageContent);
    }
  }

  /// Handle an incoming chunk: buffer it, and reassemble when all chunks arrive.
  /// Chunk format: "CHK:msgId:chunkIndex:totalChunks:data"
  void _handleChunk(String senderId, String chunkMessage) {
    // Strip "CHK:" prefix
    final payload = chunkMessage.substring(_chunkPrefix.length);

    // Parse: msgId:chunkIndex:totalChunks:data
    final parts = payload.split(':');
    if (parts.length < 4) {
      debugPrint("❌ Malformed chunk: $chunkMessage");
      return;
    }

    final msgId = parts[0];
    final chunkIndex = int.tryParse(parts[1]);
    final totalChunks = int.tryParse(parts[2]);
    // Rejoin remaining parts in case data contains ':'
    final chunkData = parts.sublist(3).join(':');

    if (chunkIndex == null || totalChunks == null || totalChunks < 1) {
      debugPrint("❌ Invalid chunk header: $chunkMessage");
      return;
    }

    final bufferKey = '$senderId:$msgId';
    debugPrint("📦 Chunk $chunkIndex/$totalChunks for msg $bufferKey");

    // Initialize buffer if new message
    _chunkBuffer.putIfAbsent(bufferKey, () => {});
    _chunkTotalExpected[bufferKey] = totalChunks;
    _chunkSenderIds[bufferKey] = senderId;

    // Store chunk
    _chunkBuffer[bufferKey]![chunkIndex] = chunkData;

    // Update receive progress tracking
    _isReceivingChunks = true;
    _totalChunksExpected = totalChunks;
    _chunksReceived = _chunkBuffer[bufferKey]!.length;
    notifyListeners();

    // Reset/start timeout timer
    _chunkTimeouts[bufferKey]?.cancel();
    _chunkTimeouts[bufferKey] = Timer(_chunkTimeout, () {
      debugPrint("⏰ Chunk timeout for $bufferKey — discarding incomplete message");
      _cleanupChunkBuffer(bufferKey);
      _resetReceiveProgress();
    });

    // Check if all chunks have arrived
    if (_chunkBuffer[bufferKey]!.length == totalChunks) {
      debugPrint("✅ All $totalChunks chunks received for $bufferKey, reassembling...");

      // Reassemble in order: chunk 1, 2, 3, ...
      final reassembled = StringBuffer();
      for (int i = 1; i <= totalChunks; i++) {
        reassembled.write(_chunkBuffer[bufferKey]![i] ?? '');
      }

      _cleanupChunkBuffer(bufferKey);
      _resetReceiveProgress();
      _processReceivedMessage(senderId, reassembled.toString());
    }
  }

  void _resetReceiveProgress() {
    _isReceivingChunks = false;
    _chunksReceived = 0;
    _totalChunksExpected = 0;
    notifyListeners();
  }

  void _cleanupChunkBuffer(String bufferKey) {
    _chunkBuffer.remove(bufferKey);
    _chunkTotalExpected.remove(bufferKey);
    _chunkSenderIds.remove(bufferKey);
    _chunkTimeouts[bufferKey]?.cancel();
    _chunkTimeouts.remove(bufferKey);
  }

  /// Process a received message, decrypting if necessary.
  /// Extracts embedded sender name from "username|message" format.
  Future<void> _processReceivedMessage(
      String senderId, String messageContent) async {
    bool wasEncrypted = EncryptionService.isEncryptedMessage(messageContent);
    String displayText = messageContent;

    if (wasEncrypted) {
      debugPrint("🔐 Encrypted message detected, attempting decryption...");
      final decrypted = await _encryptionService.decrypt(messageContent);
      if (decrypted != null) {
        displayText = decrypted;
        debugPrint("🔓 Decrypted successfully: $displayText");
      } else {
        displayText = "🔒 Encrypted message (wrong key)";
        debugPrint("❌ Decryption failed — wrong key or no key set.");
      }
    }

    // Extract embedded sender identity from "username#uid|message" format
    String senderDisplayName;
    final pipeIndex = displayText.indexOf('|');
    if (pipeIndex != -1 && pipeIndex < 16) {
      // Found embedded identity (username#uid, max ~15 chars before pipe)
      senderDisplayName = displayText.substring(0, pipeIndex);
      displayText = displayText.substring(pipeIndex + 1);
      debugPrint("👤 Embedded sender identity: $senderDisplayName");
    } else {
      // Fallback: use "Device {id}"
      senderDisplayName = _bleService.resolveDisplayName(senderId);
    }

    // Detect message type prefix and extract media data
    MessageType msgType = MessageType.text;
    Uint8List? mediaBytes;
    int? mediaDuration;

    if (displayText.startsWith('AUD:')) {
      msgType = MessageType.voiceNote;
      final audioData = displayText.substring(4);
      // Parse optional duration: "AUD:3:base64data" or "AUD:base64data"
      final colonIdx = audioData.indexOf(':');
      if (colonIdx != -1 && colonIdx < 4) {
        mediaDuration = int.tryParse(audioData.substring(0, colonIdx));
        mediaBytes = base64Decode(audioData.substring(colonIdx + 1));
      } else {
        mediaBytes = base64Decode(audioData);
      }
      displayText = '🎙️ Voice Note';
      debugPrint('🎙️ Voice note received: ${mediaBytes.length} bytes');
    } else if (displayText.startsWith('IMG:')) {
      msgType = MessageType.image;
      mediaBytes = base64Decode(displayText.substring(4));
      displayText = '📷 Image';
      debugPrint('📷 Image received: ${mediaBytes.length} bytes');
    }

    final chatMessage = ChatMessage(
      id: _uuid.v4(),
      text: displayText,
      senderId: senderDisplayName,
      receiverId: _bleService.senderId,
      timestamp: DateTime.now(),
      isSentByUser: false,
      status: MessageStatus.none,
      isEncrypted: wasEncrypted,
      messageType: msgType,
      mediaBytes: mediaBytes,
      mediaDuration: mediaDuration,
    );

    _reassembledMessageController.add(chatMessage);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SEND PATH
  // ═══════════════════════════════════════════════════════════════════════

  /// Generate a short 4-character message ID for chunking.
  String _generateShortId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(_random.nextInt(chars.length))),
    );
  }

  /// Send a message, encrypting if enabled, and chunking if too long.
  /// Embeds sender's username in the format "username|message_text"
  /// before encryption so the receiver can auto-discover the sender's name.
  /// [formattedMessage] is in the format "recipient_id,message_text".
  Future<void> sendMessage(String packetId, String formattedMessage,
      {String receiverId = BROADCAST_ID}) async {
    int commaIndex = formattedMessage.indexOf(',');
    if (commaIndex == -1) {
      // No recipient — just send raw
      final data = utf8.encode(formattedMessage);
      await _bleService.sendToDevice([data]);
      return;
    }

    String recipientPart = formattedMessage.substring(0, commaIndex);
    String messagePart = formattedMessage.substring(commaIndex + 1);

    // Embed sender identity: "username#uid" (max 10 char name + # + 4 char uid = 15)
    final senderName = _bleService.username.length > 10
        ? _bleService.username.substring(0, 10)
        : _bleService.username;
    final senderIdentity = '$senderName#${_bleService.deviceUid}';
    String bodyWithName = '$senderIdentity|$messagePart';

    // Prepare the final message body (encrypt if enabled)
    String finalBody;
    if (_encryptionService.isEnabled) {
      final encrypted = await _encryptionService.encrypt(bodyWithName);
      if (encrypted != null) {
        finalBody = encrypted;
        debugPrint('🔐 Message encrypted for sending.');
      } else {
        finalBody = bodyWithName;
        debugPrint('⚠️ Encryption failed, sending plaintext as fallback.');
      }
    } else {
      finalBody = bodyWithName;
    }

    // Check if chunking is needed
    final bodyBytes = utf8.encode(finalBody);
    if (bodyBytes.length <= _maxChunkDataSize) {
      // Single packet — send directly
      final data = utf8.encode('$recipientPart,$finalBody');
      await _bleService.sendToDevice([data]);
      debugPrint('📤 Sent single packet (${bodyBytes.length} bytes)');
    } else {
      // Chunk the message body
      await _sendChunked(recipientPart, finalBody);
    }
  }

  /// Send a media message (voice note or image) over LoRa.
  /// [recipientId] - target device
  /// [mediaBytes] - raw audio or image bytes
  /// [type] - MessageType.voiceNote or MessageType.image
  /// [duration] - optional duration in seconds (for voice notes)
  Future<void> sendMediaMessage(
    String packetId,
    String recipientId,
    Uint8List mediaBytes,
    MessageType type, {
    int? duration,
  }) async {
    // Build the media payload: "TYPE:identity|TYPE_PREFIX:base64data"
    final senderName = _bleService.username.length > 10
        ? _bleService.username.substring(0, 10)
        : _bleService.username;
    final senderIdentity = '$senderName#${_bleService.deviceUid}';

    String mediaPayload;
    final b64Data = base64Encode(mediaBytes);

    if (type == MessageType.voiceNote) {
      mediaPayload = duration != null
          ? '$senderIdentity|AUD:$duration:$b64Data'
          : '$senderIdentity|AUD:$b64Data';
      debugPrint('🎙️ Preparing voice note: ${mediaBytes.length} bytes');
    } else {
      mediaPayload = '$senderIdentity|IMG:$b64Data';
      debugPrint('📷 Preparing image: ${mediaBytes.length} bytes');
    }

    // Encrypt if enabled
    String finalBody;
    if (_encryptionService.isEnabled) {
      final encrypted = await _encryptionService.encrypt(mediaPayload);
      if (encrypted != null) {
        finalBody = encrypted;
        debugPrint('🔐 Media encrypted for sending.');
      } else {
        finalBody = mediaPayload;
        debugPrint('⚠️ Encryption failed, sending media as plaintext.');
      }
    } else {
      finalBody = mediaPayload;
    }

    // Always chunk media (it's always large)
    final bodyBytes = utf8.encode(finalBody);
    if (bodyBytes.length <= _maxChunkDataSize) {
      final data = utf8.encode('$recipientId,$finalBody');
      await _bleService.sendToDevice([data]);
      debugPrint('📤 Sent media in single packet (${bodyBytes.length} bytes)');
    } else {
      await _sendChunked(recipientId, finalBody);
    }
  }

  /// Split a long message body into numbered chunks and send each one.
  /// Updates send progress for the UI progress bar.
  Future<void> _sendChunked(String recipientPart, String body) async {
    final msgId = _generateShortId();
    final chunks = <String>[];

    // Split body into chunks of max size
    for (int i = 0; i < body.length; i += _maxChunkDataSize) {
      final end = (i + _maxChunkDataSize > body.length)
          ? body.length
          : i + _maxChunkDataSize;
      chunks.add(body.substring(i, end));
    }

    final totalChunks = chunks.length;
    debugPrint('📦 Splitting message into $totalChunks chunks (msgId: $msgId)');

    // Set sending state for progress tracking
    _isSending = true;
    _sendCancelled = false;
    _chunksSent = 0;
    _totalChunksToSend = totalChunks;
    notifyListeners();

    try {
      for (int i = 0; i < totalChunks; i++) {
        // Check if transmission was cancelled (e.g. user disconnected)
        if (_sendCancelled) {
          debugPrint('🛑 Chunked send cancelled at chunk ${i + 1}/$totalChunks');
          return;
        }

        // Format: "recipientId,CHK:msgId:chunkIndex:totalChunks:chunkData"
        // chunkIndex is 1-based
        final chunkPacket =
            '$recipientPart,$_chunkPrefix$msgId:${i + 1}:$totalChunks:${chunks[i]}';
        final data = utf8.encode(chunkPacket);

        final success = await _bleService.sendToDevice([data]);
        if (!success || _sendCancelled) {
          debugPrint('🛑 Send failed or cancelled at chunk ${i + 1}/$totalChunks');
          return;
        }

        // Update progress
        _chunksSent = i + 1;
        notifyListeners();

        debugPrint('📤 Sent chunk ${i + 1}/$totalChunks (${chunks[i].length} bytes)');

        // Small delay between chunks to avoid overwhelming the ESP32/LoRa
        if (i < totalChunks - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      debugPrint('✅ All $totalChunks chunks sent for msgId: $msgId');
    } finally {
      // Always reset sending state, even if an error occurs
      _isSending = false;
      _sendCancelled = false;
      _chunksSent = 0;
      _totalChunksToSend = 0;
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  UTILITY
  // ═══════════════════════════════════════════════════════════════════════

  void _setPeerSending(bool isSending) {
    if (_isPeerSending == isSending) return;
    _isPeerSending = isSending;
    _peerSendingTimer?.cancel();
    if (isSending) {
      _peerSendingTimer = Timer(const Duration(seconds: 10), () {
        _setPeerSending(false);
      });
    }
    notifyListeners();
  }

  void _cleanupOldHashes(DateTime now) {
    _recentMessageHashes.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _deduplicationWindow,
    );
  }

  @override
  void dispose() {
    _rawDataSubscription?.cancel();
    _reassembledMessageController.close();
    _ackController.close();
    _peerSendingTimer?.cancel();
    // Clean up all chunk timers
    for (final timer in _chunkTimeouts.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
