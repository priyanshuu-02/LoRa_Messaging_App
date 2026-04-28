# LoRa Messaging App: System Logic

This document details the underlying technical logic driving the LoRa Messaging App.

## Hardware Integration & BLE
- **Discovery:** The app scans for advertising BLE devices matching the specific UUIDs of the LoRa hardware module.
- **Connection:** Upon connection, it subscribes to the relevant BLE characteristics for reading incoming data and writing outgoing data.
- **Stability:** Custom logic handles initial connection instability, implementing retries and delays to ensure a robust link with the hardware.

## Data Chunking & Transfer Protocol
Due to the constraints of LoRa technology, large payloads cannot be sent in a single packet.
1. **Serialization:** Media (like images or audio) is serialized into byte arrays.
2. **Chunking:** The byte array is divided into smaller chunks that fit within the LoRa MTU (Maximum Transmission Unit).
3. **Sequencing:** Each chunk is prefixed with metadata (like message ID, chunk index, and total chunks) so the receiving device can reconstruct the file.
4. **Transmission:** Chunks are sent over BLE to the LoRa module, which then broadcasts them over the radio.
5. **Reconstruction:** The receiving device collects all chunks, verifies them, and reassembles the original byte array before displaying the media.

## Media Processing
- **Image Compression:** Before sending, images are aggressively compressed and resized to minimize the data footprint, ensuring faster transfer times over the slow LoRa link.
- **GIF Handling:** GIFs are processed to extract essential frames or optimized to fit the bandwidth limitations.(future Implementation)

## State Management & UI Lockout
During a data transfer (especially chunked transfers), it is critical that the devices remain synchronized.
- The UI enforces a "lockout" state during transmission or reception.
- This prevents the user from attempting to send another message while a transfer is in progress, which could lead to packet collisions and corrupted data.
