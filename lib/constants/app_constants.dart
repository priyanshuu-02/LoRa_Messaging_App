import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// --- IMPORTANT ---
// These are the standard UUIDs for the Nordic UART Service (NUS).
// Make sure these match the UUIDs on your ESP32 LoRa module firmware.
final Guid SERVICE_UUID = Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e");

// RX Characteristic: App -> Device (Write)
final Guid RX_CHARACTERISTIC_UUID =
    Guid("6e400002-b5a3-f393-e0a9-e50e24dcca9e");
// TX Characteristic: Device -> App (Notify)
final Guid TX_CHARACTERISTIC_UUID =
    Guid("6e400003-b5a3-f393-e0a9-e50e24dcca9e");

// Special ID for broadcast messages
const String BROADCAST_ID = "BROADCAST";

// The maximum payload size for each BLE frame.
// BLE's default MTU is 23 bytes. After headers (ATT, L2CAP), you have ~20 bytes.
// We leave a buffer, so we'll use 15 bytes for our payload chunk.
const int PAYLOAD_LIMIT = 15;
