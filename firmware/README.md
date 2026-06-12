# 🔧 Heltec LoRa 32 — BLE + LoRa Bridge Firmware

This folder contains the Arduino sketch that turns a **Heltec WiFi LoRa 32** board into a wireless bridge between the Flutter app (over BLE) and other LoRa devices.

---

## 📋 Table of Contents

- [Hardware Required](#hardware-required)
- [How It Works](#how-it-works)
- [Arduino IDE Setup](#arduino-ide-setup)
- [Board & Library Installation](#board--library-installation)
- [Configuration](#configuration)
- [Flashing the Firmware](#flashing-the-firmware)
- [Message Protocol](#message-protocol)
- [BLE UUIDs](#ble-uuids)
- [Testing Without the App](#testing-without-the-app)
- [Troubleshooting](#troubleshooting)

---

## 🛒 Hardware Required

| Item | Notes |
|---|---|
| **Heltec WiFi LoRa 32 (V2 or V3)** | The board this firmware targets |
| USB-C / Micro-USB cable | For flashing and Serial monitoring |
| LoRa antenna | **Required** — transmitting without antenna damages the RF stage |
| Second Heltec board (optional) | For end-to-end testing |

> ⚠️ Always attach the LoRa antenna **before** powering the board.

---

## ⚙️ How It Works

```
Flutter App (Phone)
      │
      │  BLE (UART NUS profile)
      ▼
Heltec LoRa 32  ◄──────────────────► Other Heltec LoRa 32
      │              LoRa 865.2 MHz
      └── OLED display (status & messages)
```

1. The Flutter app connects over BLE and sends `"recipient_id,message"`.
2. The board wraps it into a LoRa packet (`"sender_id,recipient_id,message"`) and transmits.
3. Incoming LoRa packets addressed to this device are forwarded to the phone over BLE as `"sender_id,message"`.
4. The OLED shows live status — connection state, sent/received messages.

---

## 🖥️ Arduino IDE Setup

### 1. Install Arduino IDE

Download from [arduino.cc/en/software](https://www.arduino.cc/en/software). Version **2.x** is recommended.

### 2. Add Heltec Board Package

1. Open **File → Preferences**
2. Paste the following URL into **Additional Boards Manager URLs**:
   ```
   https://resource.heltec.cn/download/package_heltec_esp32_index.json
   ```
3. Click **OK**

### 3. Install the Board

1. Open **Tools → Board → Boards Manager**
2. Search for **Heltec ESP32**
3. Install **Heltec ESP32 Series Dev-boards** (latest version)

---

## 📦 Board & Library Installation

### Required Libraries

Install all of these via **Tools → Manage Libraries**:

| Library | Search Term | Notes |
|---|---|---|
| Heltec ESP32 Dev-Boards | `Heltec ESP32` | Includes LoRa + OLED drivers |
| ESP32 BLE Arduino | Built into ESP32 core | No separate install needed |

> The `LoRaWan_APP.h`, `HT_SSD1306Wire.h`, and BLE headers all come bundled with the Heltec board package — no extra installs required.

---

## ⚙️ Configuration

Open `heltec_lora_ble_bridge.ino` and update the following defines before flashing:

```cpp
// --- Each physical device must have a unique ID (1, 2, 3, ...)
#define MY_ADDRESS  1         // <-- CHANGE THIS PER DEVICE

// --- LoRa Radio Settings (must match on ALL devices in the network)
#define RF_FREQUENCY          865200000  // 865.2 MHz — Indian LoRa band
#define TX_OUTPUT_POWER       14         // dBm (max 20 for most regions)
#define LORA_SPREADING_FACTOR 7          // SF7 = faster, SF12 = longer range
#define LORA_BANDWIDTH        0          // 0 = 125 kHz
#define LORA_CODINGRATE       1          // 1 = 4/5
```

### Multi-Device Setup

Flash each board with a **different `MY_ADDRESS`**. All other radio parameters must be identical across every device in the network.

| Board | `MY_ADDRESS` | BLE Name Advertised |
|---|---|---|
| Device 1 | `1` | `Heltec-LoRa-1` |
| Device 2 | `2` | `Heltec-LoRa-2` |
| Device 3 | `3` | `Heltec-LoRa-3` |

### Frequency Note

| Region | Frequency |
|---|---|
| India | 865.0 – 867.0 MHz ✅ (default) |
| Europe | 868.0 MHz |
| USA | 915.0 MHz |
| Asia (other) | 433.0 MHz |

Change `RF_FREQUENCY` accordingly and verify local regulations.

---

## ⚡ Flashing the Firmware

1. Connect the Heltec board via USB
2. Open Arduino IDE and load `heltec_lora_ble_bridge.ino`
3. Select the correct board:
   - **Tools → Board → Heltec ESP32 Series → WiFi LoRa 32(V2)** or **(V3)**
4. Select the correct port:
   - **Tools → Port → COMx** (Windows) or `/dev/ttyUSBx` (Linux/macOS)
5. Set upload speed:
   - **Tools → Upload Speed → 921600**
6. Click **Upload** (→)
7. Watch the OLED — it should show:

   ```
   Device 1
   BLE+LoRa Bridge
   Initializing...
   LoRa: Ready
   BLE: Advertising
   Ready!
   ```

---

## 📨 Message Protocol

All messages use comma-separated plain text.

### LoRa Packet (over radio)

```
sender_id,recipient_id,message_content
```

Example: `1,2,Hello from device 1`

### BLE: Phone → Device (write to RX characteristic)

```
recipient_id,message_content
```

Example: `2,Hello from phone`

### BLE: Device → Phone (notify on TX characteristic)

```
sender_id,message_content
```

Example: `1,Hello from device 1`

### Broadcast

Use `recipient_id = 0` to send to **all devices** in range.

---

## 🔑 BLE UUIDs

These match the Flutter app's `ble_service.dart` exactly — do not change them.

| Name | UUID |
|---|---|
| Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` |
| RX Characteristic (Phone → Device) | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |
| TX Characteristic (Device → Phone) | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |

This is the standard **Nordic UART Service (NUS)** profile.

---

## 🧪 Testing Without the App

You can test the board using the Arduino **Serial Monitor** (115200 baud):

```
# Send a message to device 2
2,Hello world

# Send a broadcast to all devices
0,Broadcast message
```

The OLED will show the outgoing/incoming messages in real time.

You can also use any BLE terminal app (e.g., **nRF Connect** on Android/iOS) to write to the RX characteristic and observe notifications on TX.

---

## 🛠️ Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| OLED blank | Vext not enabled or wrong board variant | Confirm board selection matches your hardware version |
| Upload fails | Wrong port or board | Check **Tools → Port** and board variant (V2 vs V3) |
| BLE not visible | Board not advertising | Check Serial output — look for `BLE: Advertising` |
| No LoRa reception | Antenna missing or frequency mismatch | Attach antenna; verify `RF_FREQUENCY` matches on both devices |
| Messages not received | `MY_ADDRESS` mismatch | Ensure recipient ID in packet matches the target board's `MY_ADDRESS` |
| TX Timeout on display | Poor signal or obstruction | Move devices closer; increase `TX_OUTPUT_POWER` |

---

## 📁 File Structure

```
firmware/
└── heltec_lora_ble_bridge/
    ├── heltec_lora_ble_bridge.ino   ← Main Arduino sketch
    └── README.md                    ← This file
```

---

<p align="center">Flash it, connect it, go off-grid.</p>
