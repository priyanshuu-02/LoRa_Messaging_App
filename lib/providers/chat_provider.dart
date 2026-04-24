import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lora_communicator/constants/app_constants.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/packet_framer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ChatProvider with ChangeNotifier {
  PacketFramerService _framerService;
  StreamSubscription? _ackSubscription;
  StreamSubscription? _messageSubscription;
  final List<ChatMessage> _messages = [];
  static const _messagesKey = 'chat_messages';
  final Uuid _uuid = const Uuid();

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  ChatProvider({required PacketFramerService framerService})
      : _framerService = framerService {
    _loadMessages();
    _subscribeToFramer();
  }

  void updateFramerService(PacketFramerService newFramerService) {
    if (_framerService != newFramerService) {
      _framerService = newFramerService;
      _messageSubscription?.cancel();
      _ackSubscription?.cancel();
      _subscribeToFramer();
    }
  }

  void _subscribeToFramer() {
    // Listen for fully reassembled messages from the framer service
    _messageSubscription =
        _framerService.reassembledMessageStream.listen((message) {
      _messages.insert(0, message.copyWith(status: MessageStatus.none));
      _saveMessages();
      notifyListeners();
    });

    // Listen for acknowledged packet IDs
    _ackSubscription = _framerService.ackStream.listen((ackData) {
      // ESP32 sends "ACK:message_content" - extract packetId if needed
      // For now, mark all sending messages as delivered when ACK received
      _messages
          .where((m) => m.status == MessageStatus.sending)
          .forEach((m) => _updateMessageStatus(m.id, MessageStatus.delivered));
    });
  }

  Future<void> sendMessage(String recipientId, String text) async {
    if (text.trim().isEmpty) return;

    final packetId = _uuid.v4();
    final encrypted = _framerService.isEncryptionEnabled;

    // Create optimistic UI message
    final sentMessage = ChatMessage(
      id: packetId,
      text: text,
      senderId: _framerService.senderId, // Use actual sender ID
      receiverId: recipientId, // Now includes recipient
      timestamp: DateTime.now(),
      isSentByUser: true,
      status: MessageStatus.sending,
      isEncrypted: encrypted,
    );

    _messages.insert(0, sentMessage);
    notifyListeners();

    // Send formatted message: "recipient_id,message"
    await _framerService.sendMessage(packetId, "$recipientId,$text");
    _saveMessages();
  }

  /// Send a voice note over LoRa.
  Future<void> sendVoiceNote(
      String recipientId, Uint8List audioBytes, int durationSec) async {
    final packetId = _uuid.v4();
    final encrypted = _framerService.isEncryptionEnabled;

    final sentMessage = ChatMessage(
      id: packetId,
      text: '🎙️ Voice Note',
      senderId: _framerService.senderId,
      receiverId: recipientId,
      timestamp: DateTime.now(),
      isSentByUser: true,
      status: MessageStatus.sending,
      isEncrypted: encrypted,
      messageType: MessageType.voiceNote,
      mediaBytes: audioBytes,
      mediaDuration: durationSec,
    );

    _messages.insert(0, sentMessage);
    notifyListeners();

    await _framerService.sendMediaMessage(
      packetId,
      recipientId,
      audioBytes,
      MessageType.voiceNote,
      duration: durationSec,
    );
    _saveMessages();
  }

  /// Send an image over LoRa.
  Future<void> sendImage(String recipientId, Uint8List imageBytes) async {
    final packetId = _uuid.v4();
    final encrypted = _framerService.isEncryptionEnabled;

    final sentMessage = ChatMessage(
      id: packetId,
      text: '📷 Image',
      senderId: _framerService.senderId,
      receiverId: recipientId,
      timestamp: DateTime.now(),
      isSentByUser: true,
      status: MessageStatus.sending,
      isEncrypted: encrypted,
      messageType: MessageType.image,
      mediaBytes: imageBytes,
    );

    _messages.insert(0, sentMessage);
    notifyListeners();

    await _framerService.sendMediaMessage(
      packetId,
      recipientId,
      imageBytes,
      MessageType.image,
    );
    _saveMessages();
  }

  void _updateMessageStatus(String packetId, MessageStatus status) {
    try {
      final messageIndex = _messages.indexWhere((msg) => msg.id == packetId);
      if (messageIndex != -1) {
        final message = _messages[messageIndex];
        // Create a new instance to ensure the UI updates correctly.
        _messages[messageIndex] = message.copyWith(status: status);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error updating message status for packet $packetId: $e");
    }
  }

  // Saves the current list of messages to local storage.
  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData =
        jsonEncode(_messages.map((msg) => msg.toJson()).toList());
    await prefs.setString(_messagesKey, encodedData);
  }

  // Loads messages from local storage when the app starts.
  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String? messagesString = prefs.getString(_messagesKey);
    if (messagesString != null) {
      final List<dynamic> decodedData = jsonDecode(messagesString);
      _messages.clear();
      _messages.addAll(decodedData
          .map<ChatMessage>((item) => ChatMessage.fromJson(item))
          .toList());
      // Ensure any 'sending' messages from a previous session are marked as 'failed'.
      _messages
          .where((m) => m.status == MessageStatus.sending)
          .forEach((m) => m.copyWith(status: MessageStatus.failed));
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _ackSubscription?.cancel();
    super.dispose();
  }
}
