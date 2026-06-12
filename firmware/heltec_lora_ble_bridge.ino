/**
 * Heltec LoRa 32 - BLE + LoRa Bridge
 *
 * Features:
 *   1. LoRa-to-LoRa direct messaging
 *   2. BLE interface for Flutter app communication
 *   3. OLED display for status and messages
 *
 * Message Formats:
 *   - LoRa:      "sender_id,recipient_id,message"
 *   - BLE Send:  "recipient_id,message"
 *   - BLE Recv:  "sender_id,message"
 */

// LoRa Includes
#include "LoRaWan_APP.h"
#include "Arduino.h"

// OLED Includes
#include <Wire.h>
#include "HT_SSD1306Wire.h"

// BLE Includes
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ----------------------------------------------------------------
// --- BLE Parameters
// ----------------------------------------------------------------
#define SERVICE_UUID           "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_RX "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHARACTERISTIC_UUID_TX "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

// BLE variables
BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
bool bleDeviceConnected = false;
bool oldBleDeviceConnected = false;

// ----------------------------------------------------------------
// --- LoRa Parameters
// ----------------------------------------------------------------
#define MY_ADDRESS                        1         // <-- SET YOUR UNIQUE DEVICE ID HERE

#define RF_FREQUENCY                      865200000 // Indian LoRa band (865.2 MHz)
#define TX_OUTPUT_POWER                   14        // dBm
#define LORA_BANDWIDTH                    0         // [0: 125 kHz]
#define LORA_SPREADING_FACTOR             7         // [SF7..SF12]
#define LORA_CODINGRATE                   1         // [1: 4/5]
#define LORA_PREAMBLE_LENGTH              8         // Same for Tx and Rx
#define LORA_SYMBOL_TIMEOUT               0         // Symbols
#define LORA_FIX_LENGTH_PAYLOAD_ON        false
#define LORA_IQ_INVERSION_ON              false
#define BUFFER_SIZE                       256
#define RX_TIMEOUT_VALUE                  1000      // Receive timeout in ms

char txpacket[BUFFER_SIZE];
char rxpacket[BUFFER_SIZE];

static RadioEvents_t RadioEvents;
int16_t rssi, rxSize;
bool isTransmitting = false;

// ----------------------------------------------------------------
// --- OLED Parameters
// ----------------------------------------------------------------
static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

#define NUM_LINES 6
String displayLines[NUM_LINES];

// ----------------------------------------------------------------
// --- OLED Helper Functions
// ----------------------------------------------------------------

void VextON(void) {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW);
}

void updateDisplay() {
  display.clear();
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.setFont(ArialMT_Plain_10);
  for (int i = 0; i < NUM_LINES; i++) {
    display.drawString(0, i * 10, displayLines[i]);
  }
  display.display();
}

void addDisplayLine(String line) {
  for (int i = 0; i < NUM_LINES - 1; i++) {
    displayLines[i] = displayLines[i + 1];
  }
  displayLines[NUM_LINES - 1] = line;
  updateDisplay();
}

// ----------------------------------------------------------------
// --- LoRa Function Declarations
// ----------------------------------------------------------------
void startReceive();
void startTransmit(uint8_t size);
void OnTxDone();
void OnTxTimeout();
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);

// ----------------------------------------------------------------
// --- BLE Callbacks
// ----------------------------------------------------------------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) {
    bleDeviceConnected = true;
    oldBleDeviceConnected = true;
    addDisplayLine("BLE: Connected");
    Serial.println("BLE Device Connected");
  }

  void onDisconnect(BLEServer *pServer) {
    bleDeviceConnected = false;
    addDisplayLine("BLE: Disconnected");
    Serial.println("BLE Device Disconnected");
    BLEDevice::startAdvertising();
  }
};

class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String message = pCharacteristic->getValue();
    if (message.length() > 0) {
      Serial.print("Received from BLE: ");
      Serial.println(message);

      // Parse "recipient,message" from phone
      int commaIndex = message.indexOf(',');
      if (commaIndex != -1 && !isTransmitting) {
        String recipientStr = message.substring(0, commaIndex);
        String messageContent = message.substring(commaIndex + 1);
        int recipientAddress = recipientStr.toInt();

        if (recipientAddress > 0) {
          isTransmitting = true;
          // Build LoRa packet: "sender,recipient,message"
          sprintf(txpacket, "%d,%d,%s", MY_ADDRESS, recipientAddress, messageContent.c_str());
          addDisplayLine("Phone->" + recipientStr + ": " + messageContent);
          startTransmit(strlen(txpacket));

          // ACK back to phone
          String ack = "ACK:" + messageContent;
          pTxCharacteristic->setValue(ack.c_str());
          pTxCharacteristic->notify();
          Serial.print("Forwarded to LoRa: ");
          Serial.println(txpacket);
        }
      }
    }
  }
};

// ----------------------------------------------------------------
// --- LoRa Implementations
// ----------------------------------------------------------------
void startReceive() {
  Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                   LORA_CODINGRATE, 0, LORA_PREAMBLE_LENGTH,
                   LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                   0, true, 0, 0, LORA_IQ_INVERSION_ON, true);
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void startTransmit(uint8_t size) {
  Serial.printf("Sending LoRa packet: \"%s\"\n", txpacket);
  addDisplayLine("Sending...");
  Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH,
                   LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                   LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                   true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
  Radio.Send((uint8_t *)txpacket, size);
}

void OnTxDone() {
  Radio.Sleep();
  Serial.println("TX Done! Switching back to RX mode.");
  addDisplayLine("TX Done");
  isTransmitting = false;
  startReceive();
}

void OnTxTimeout() {
  Radio.Sleep();
  Serial.println("TX Timeout! Switching back to RX mode.");
  addDisplayLine("TX Timeout");
  isTransmitting = false;
  startReceive();
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  Radio.Sleep();
  rxSize = size;
  memcpy(rxpacket, payload, size);
  rxpacket[size] = '\0';

  String receivedString(rxpacket);
  int firstComma  = receivedString.indexOf(',');
  int secondComma = receivedString.indexOf(',', firstComma + 1);

  if (firstComma != -1 && secondComma != -1) {
    String senderIdStr    = receivedString.substring(0, firstComma);
    String recipientIdStr = receivedString.substring(firstComma + 1, secondComma);
    String messageContent = receivedString.substring(secondComma + 1);

    int senderId    = senderIdStr.toInt();
    int recipientId = recipientIdStr.toInt();

    if (recipientId == MY_ADDRESS || recipientId == 0) {
      Serial.printf("\n*** Message from Device %d ***\n", senderId);
      Serial.printf("Content: %s\n", messageContent.c_str());
      Serial.printf("RSSI: %d, Length: %d\n", rssi, rxSize);
      Serial.println("*");

      addDisplayLine("From " + senderIdStr + ": " + messageContent);

      if (bleDeviceConnected) {
        String bleMessage = senderIdStr + "," + messageContent;
        pTxCharacteristic->setValue(bleMessage.c_str());
        pTxCharacteristic->notify();
        Serial.println("Forwarded to BLE");
      }
    } else {
      Serial.println("Received message for another device. Ignoring.");
    }
  } else {
    Serial.println("Received malformed packet.");
  }

  startReceive();
}

// ----------------------------------------------------------------
// --- Setup
// ----------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  Serial.println("Heltec BLE + LoRa Bridge Starting...");

  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  // OLED
  VextON();
  delay(100);
  display.init();
  display.flipScreenVertically();
  addDisplayLine("Device " + String(MY_ADDRESS));
  addDisplayLine("BLE+LoRa Bridge");
  addDisplayLine("Initializing...");

  // LoRa
  RadioEvents.TxDone    = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;
  RadioEvents.RxDone    = OnRxDone;
  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);
  Serial.printf("Device %d - LoRa initialized\n", MY_ADDRESS);
  addDisplayLine("LoRa: Ready");

  // BLE
  BLEDevice::init("Heltec-LoRa-" + String(MY_ADDRESS));
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  // TX: Device -> Phone (notify)
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  // RX: Phone -> Device (write)
  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE
  );
  pRxCharacteristic->setCallbacks(new MyCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  addDisplayLine("BLE: Advertising");
  addDisplayLine("Ready!");

  startReceive();

  Serial.println("BLE + LoRa Bridge Ready!");
  Serial.println("BLE Name: Heltec-LoRa-" + String(MY_ADDRESS));
  Serial.println("Send via BLE or Serial: 'recipient,message'");
}

// ----------------------------------------------------------------
// --- Main Loop
// ----------------------------------------------------------------
void loop() {
  Radio.IrqProcess();

  // BLE reconnection state machine
  if (!bleDeviceConnected && oldBleDeviceConnected) {
    delay(500);
    oldBleDeviceConnected = bleDeviceConnected;
  }
  if (bleDeviceConnected && !oldBleDeviceConnected) {
    oldBleDeviceConnected = bleDeviceConnected;
  }

  // Serial monitor testing: type "recipient,message"
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    int commaIndex = input.indexOf(',');
    if (commaIndex != -1 && !isTransmitting) {
      String recipientStr = input.substring(0, commaIndex);
      String message      = input.substring(commaIndex + 1);
      int recipientAddress = recipientStr.toInt();

      if (recipientAddress > 0) {
        isTransmitting = true;
        sprintf(txpacket, "%d,%d,%s", MY_ADDRESS, recipientAddress, message.c_str());
        addDisplayLine("Serial->" + recipientStr + ": " + message);
        startTransmit(strlen(txpacket));
      }
    }
  }

  delay(10);
}
