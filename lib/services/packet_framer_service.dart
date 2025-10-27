import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/constants/app_constants.dart';
import 'package:uuid/uuid.dart';

class PacketFramerService with ChangeNotifier {
  BleService _bleService;
  StreamSubscription? _rawDataSubscription;
  final Uuid _uuid = const Uuid();

  // Buffer to hold incoming frames for reassembly
  final Map<String, List<String>> _frameBuffer = {};
  final Map<String, int> _totalFramesForPacket = {};

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

  PacketFramerService({required BleService bleService})
      : _bleService = bleService {
    _subscribeToBle();
  }

  void updateBleService(BleService newBleService) {
    if (_bleService != newBleService) {
      _bleService = newBleService;
      _rawDataSubscription?.cancel();
      _subscribeToBle();
    }
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

      final chatMessage = ChatMessage(
        id: _uuid.v4(),
        text: messageContent,
        senderId: "Device $senderId", // Show which device sent it
        receiverId: _bleService.senderId,
        timestamp: DateTime.now(),
        isSentByUser: false,
        status: MessageStatus.none,
      );

      _reassembledMessageController.add(chatMessage);
    } else {
      debugPrint("❌ Malformed message received: $message");
    }
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

  Future<void> sendMessage(String packetId, String formattedMessage,
      {String receiverId = BROADCAST_ID}) async {
    // With the simplified protocol, we just send the raw text.
    // The ESP32 will handle the LoRa transmission.
    final data = utf8.encode(formattedMessage);
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

  @override
  void dispose() {
    _rawDataSubscription?.cancel();
    _reassembledMessageController.close();
    _ackController.close();
    _peerSendingTimer?.cancel();
    super.dispose();
  }
}
