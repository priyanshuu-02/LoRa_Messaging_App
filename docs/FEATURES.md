# LoRa Messaging App: Features

This document provides a detailed overview of the core features of the LoRa Messaging App.

## 1. Offline Messaging
The core functionality of this application is its ability to operate completely independently of traditional internet or cellular networks. It achieves this by communicating with external LoRa (Long Range) hardware modules, allowing users to send messages over radio frequencies over long distances.

## 2. Media Support (Images, Audio, and GIFs)
Beyond simple text messages, the application supports transmitting various media types:
- **Audio Messages:** Record and send voice notes.
- **Images:** Send photos. The app processes and compresses images to accommodate LoRa bandwidth constraints while maintaining acceptable quality.
- **GIFs:** Send short, animated GIFs over the LoRa network.(Future Implementation needed)

## 3. End-to-End Encryption
Privacy and security are prioritized. All data (text and media) transmitted over the LoRa radio link is securely encrypted. This ensures that even if the radio signals are intercepted, the messages cannot be read by unauthorized parties.

## 4. Chunked Data Transfer
LoRa networks have very low bandwidth and strict payload size limits. To send larger files like images or audio, the app uses a chunked transfer system:
- Large payloads are split into smaller chunks.
- These chunks are transmitted sequentially.
- The UI provides granular progress bars to show the transfer status.
- A UI lockout mechanism prevents users from initiating conflicting transfers, avoiding data synchronization issues.

## 5. BLE Integration
The mobile application interfaces with the external LoRa hardware using Bluetooth Low Energy (BLE). This allows any modern smartphone to seamlessly connect to the custom hardware without requiring physical cables, enabling a portable and wireless experience.
