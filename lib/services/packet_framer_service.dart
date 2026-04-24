import 'dart:async';
import 'dart:convert';
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

  // Buffer to hold incoming frames for reassembly
  final Map<String, List<String>> _frameBuffer = {};
  final Map<String, int> _totalFramesForPacket = {};

  // Deduplication: track recently received message hashes with timestamps
  final Map<String, DateTime> _recentMessageHashes = {};
  static const Duration _deduplicationWindow = Duration(seconds: 2);

  bool _isPeerSending = false;
  Timer? _peerSendingTimer;

  final StreamController<ChatMessage> _reassembledMessageController =
      StreamController.broadcast();
  Stream<ChatMessage> get reassembledMessageStream =>
      _reassembledMessageController.stream;

  final StreamController<String> _ackController = StreamController.broadcast();
  Stream<String> get ackStream =>
      _ackController.stream; // Stream of packet IDs that have been ACK'd

  // Public getter for the UI
  bool get isPeerSending => _isPeerSending;

  // Expose the senderId from the underlying BleService
  String get senderId => _bleService.senderId;

  // Expose encryption status
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
    // Listen to the raw data stream from the BLE service
    _rawDataSubscription =
        _bleService.rawDataStream.listen(_onDataReceived, onError: (error) {
      debugPrint("Error on raw data stream: $error");
    });
  }

  // Called when raw data comes in from the BLE Service
  void _onDataReceived(List<int> data) {
    String message = utf8.decode(data, allowMalformed: true);
    debugPrint("🔄 RAW BLE RECEIVED: $message");
    debugPrint(
        "📊 Data length: ${data.length}, Message length: ${message.length}");

    // Handle ACK frames
    if (message.startsWith('ACK:')) {
      final ackContent = message.substring(4);
      debugPrint("✅ ACK received: $ackContent");
      _ackController.add(ackContent);
      return;
    }

    // Parse "sender_id,message" format from LoRa
    int commaIndex = message.indexOf(',');
    if (commaIndex != -1) {
      String senderId = message.substring(0, commaIndex);
      String messageContent = message.substring(commaIndex + 1);

      debugPrint("📨 Parsed - Sender: $senderId, Message: $messageContent");

      // Deduplication: skip if we've seen this exact message recently
      final messageHash = '$senderId:$messageContent';
      final now = DateTime.now();
      _cleanupOldHashes(now);

      if (_recentMessageHashes.containsKey(messageHash)) {
        debugPrint("⚠️ Duplicate message suppressed: $messageHash");
        return;
      }
      _recentMessageHashes[messageHash] = now;

      // Handle encrypted messages
      _processReceivedMessage(senderId, messageContent);
    } else {
      debugPrint("❌ Malformed message received: $message");
    }
  }

  /// Process a received message, decrypting if necessary.
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
        // Decryption failed — wrong key or no key set
        displayText = "🔒 Encrypted message (wrong key)";
        debugPrint("❌ Decryption failed — wrong key or no key set.");
      }
    }

    final chatMessage = ChatMessage(
      id: _uuid.v4(),
      text: displayText,
      senderId: _bleService.resolveDisplayName(senderId),
      receiverId: _bleService.senderId,
      timestamp: DateTime.now(),
      isSentByUser: false,
      status: MessageStatus.none,
      isEncrypted: wasEncrypted,
    );

    _reassembledMessageController.add(chatMessage);
  }

  void _reassembleAndNotify(
      String packetId, String senderId, String receiverId) {
    String fullMessageText = _frameBuffer[packetId]!.join('');

    final message = ChatMessage(
      id: packetId,
      text: fullMessageText,
      senderId: senderId,
      receiverId: receiverId,
      timestamp: DateTime.now(),
      isSentByUser: false,
    );

    _reassembledMessageController.add(message);

    // Clean up buffers
    _frameBuffer.remove(packetId);
    _totalFramesForPacket.remove(packetId);

    // Send ACK back to the sender
    String ackPacket = 'ACK:$packetId';
    // We can't easily send an ACK back in a connectionless model without
    // knowing the peer's address. For now, we'll skip sending ACKs for
    // messages received from LoRa peers.
    debugPrint("ACK not sent in connectionless model for packet: $packetId");
    // Message is fully received, hide the indicator after sending ACK.
    _setPeerSending(false);
  }

  /// Send a message, encrypting if encryption is enabled.
  /// [formattedMessage] is in the format "recipient_id,message_text".
  Future<void> sendMessage(String packetId, String formattedMessage,
      {String receiverId = BROADCAST_ID}) async {
    String messageToSend = formattedMessage;

    // If encryption is enabled, encrypt just the message body
    if (_encryptionService.isEnabled) {
      int commaIndex = formattedMessage.indexOf(',');
      if (commaIndex != -1) {
        String recipientPart = formattedMessage.substring(0, commaIndex);
        String messagePart = formattedMessage.substring(commaIndex + 1);

        final encrypted = await _encryptionService.encrypt(messagePart);
        if (encrypted != null) {
          messageToSend = "$recipientPart,$encrypted";
          debugPrint("🔐 Message encrypted for sending.");
        } else {
          debugPrint(
              "⚠️ Encryption failed, sending plaintext as fallback.");
        }
      }
    }

    final data = utf8.encode(messageToSend);
    await _bleService.sendToDevice([data]);
  }

  void _setPeerSending(bool isSending) {
    if (_isPeerSending == isSending) return;

    _isPeerSending = isSending;
    _peerSendingTimer?.cancel();

    // Add a timeout. If we don't get another packet for 10 seconds,
    // assume the connection was lost or the message was incomplete.
    if (isSending) {
      _peerSendingTimer = Timer(const Duration(seconds: 10), () {
        _setPeerSending(false);
      });
    }
    notifyListeners();
  }

  /// Remove message hashes older than the deduplication window.
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
    super.dispose();
  }
}
