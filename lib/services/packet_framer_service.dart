import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
  static const Duration _chunkTimeout = Duration(seconds: 30);

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

    // Reset/start timeout timer
    _chunkTimeouts[bufferKey]?.cancel();
    _chunkTimeouts[bufferKey] = Timer(_chunkTimeout, () {
      debugPrint("⏰ Chunk timeout for $bufferKey — discarding incomplete message");
      _cleanupChunkBuffer(bufferKey);
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
      _processReceivedMessage(senderId, reassembled.toString());
    }
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

    // Extract embedded sender name from "username|message" format
    String senderDisplayName;
    final pipeIndex = displayText.indexOf('|');
    if (pipeIndex != -1 && pipeIndex < 11) {
      senderDisplayName = displayText.substring(0, pipeIndex);
      displayText = displayText.substring(pipeIndex + 1);
      debugPrint("👤 Embedded sender name: $senderDisplayName");
    } else {
      senderDisplayName = _bleService.resolveDisplayName(senderId);
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

    // Embed sender's username (max 10 chars) in the message body
    final senderName = _bleService.username.length > 10
        ? _bleService.username.substring(0, 10)
        : _bleService.username;
    String bodyWithName = '$senderName|$messagePart';

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

  /// Split a long message body into numbered chunks and send each one.
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

    for (int i = 0; i < totalChunks; i++) {
      // Format: "recipientId,CHK:msgId:chunkIndex:totalChunks:chunkData"
      // chunkIndex is 1-based
      final chunkPacket =
          '$recipientPart,$_chunkPrefix$msgId:${i + 1}:$totalChunks:${chunks[i]}';
      final data = utf8.encode(chunkPacket);
      await _bleService.sendToDevice([data]);

      debugPrint('📤 Sent chunk ${i + 1}/$totalChunks (${chunks[i].length} bytes)');

      // Small delay between chunks to avoid overwhelming the ESP32/LoRa
      if (i < totalChunks - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint('✅ All $totalChunks chunks sent for msgId: $msgId');
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
