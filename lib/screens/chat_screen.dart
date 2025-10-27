import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lora_communicator/providers/chat_provider.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/packet_framer_service.dart';
import 'package:lora_communicator/widgets/chat_bubble.dart';
import 'package:lora_communicator/screens/settings_screen.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _recipientController =
      TextEditingController(text: "2"); // Default recipient

  @override
  void initState() {
    super.initState();
    // It's better to request permissions right before they are needed (e.g., when tapping "Connect")
    // but checking the adapter state on init is a good practice.
    _checkAdapterState();
  }

  Future<void> _checkAdapterState() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      debugPrint("Bluetooth adapter is off.");
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request Bluetooth permissions
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();

      // Check if permissions are granted
      var scanStatus = await Permission.bluetoothScan.status;
      var connectStatus = await Permission.bluetoothConnect.status;

      if (scanStatus.isGranted && connectStatus.isGranted) {
        return true;
      }
      debugPrint("Bluetooth permissions were not granted.");
      return false;
    }
    return true; // Permissions are not required on other platforms
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  void _sendMessage(String recipientId) {
    if (_textController.text.trim().isEmpty) return;
    context.read<ChatProvider>().sendMessage(recipientId, _textController.text);
    _textController.clear();
    // Animate to the top of the list after sending
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const SettingsScreen()));
            },
          ),
          _buildAppBarAction()
        ],
      ),
      body: Column(
        children: [
          Expanded(
            // Use a Consumer for both services to build the body
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                final messages = chatProvider.messages;
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: ChatBubble(message: messages[index]),
                    );
                  },
                );
              },
            ),
          ),
          // The composer is only enabled when connected
          Consumer<BleService>(builder: (context, bleService, _) {
            final isEnabled = bleService.targetDevice != null;
            return _buildMessageComposer(isEnabled: isEnabled);
          }),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle() {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        if (bleService.targetDevice != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bleService.targetDevice?.platformName.isNotEmpty ?? false
                    ? bleService.targetDevice!.platformName
                    : "Unknown Device",
                style: const TextStyle(fontSize: 16),
              ),
              /* This is harder to track in a connectionless model
              if (framerService.isPeerSending)
                const Text( 
                  "Sending...",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else */
              Builder(builder: (context) {
                final remoteId =
                    bleService.targetDevice?.remoteId.toString() ?? '';
                final last4 = remoteId.length > 4
                    ? remoteId.substring(remoteId.length - 4)
                    : remoteId;
                return Text(
                  "Target: $last4",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                );
              }),
            ],
          );
        } else {
          return const Text("LoRa Communicator");
        }
      },
    );
  }

  Widget _buildAppBarAction() {
    return Consumer<BleService>(
      builder: (context, bleService, _) {
        if (bleService.targetDevice != null) {
          return TextButton(
            key: const Key('disconnectButton'),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text("DISCONNECT"),
            onPressed: () => bleService.disconnect(),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              key: const Key('selectDeviceButton'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text("Select Device"),
              onPressed: () async {
                // 1. Check if Bluetooth is available and on
                if (await FlutterBluePlus.adapterState.first !=
                    BluetoothAdapterState.on) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please turn on Bluetooth."),
                      ),
                    );
                  }
                  return;
                }
                // 2. Request permissions and show dialog
                if (await _requestPermissions()) {
                  _showDeviceSelectionDialog(context);
                }
              },
            ),
          );
        }
      },
    );
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    IconData iconData;
    Color color;
    switch (status) {
      case MessageStatus.sending:
        iconData = Icons.schedule;
        color = Colors.grey.shade500;
        break;
      case MessageStatus.delivered:
        iconData = Icons.done;
        color = Colors.blue;
        break;
      case MessageStatus.failed:
        iconData = Icons.error_outline;
        color = Colors.red;
        break;
      case MessageStatus.none:
      default:
        return const SizedBox.shrink(); // No icon for received or none status
    }
    return Icon(
      iconData,
      size: 16.0,
      color: color,
    );
  }

  void _showDeviceSelectionDialog(BuildContext context) {
    final bleService = context.read<BleService>()..startScan();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Consumer<BleService>(
          builder: (context, service, child) {
            return AlertDialog(
              title: const Text("Select a LoRa Module"),
              content: SizedBox(
                width: double.maxFinite,
                child: Builder(
                  builder: (context) {
                    if (service.isScanning) {
                      return const Center(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text("Scanning..."),
                        ],
                      ));
                    }
                    if (service.scanResults.isEmpty) {
                      return const Center(
                          child: Text("No devices found. Ensure the LoRa "
                              "module is on and in range."));
                    }
                    final loraDevices = service.scanResults
                        .where((r) =>
                            r.device.platformName.contains('Heltec-LoRa'))
                        .toList();

                    if (loraDevices.isEmpty) {
                      return const Center(
                          child: Text("No 'Heltec-LoRa' devices found."));
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: loraDevices.length,
                      itemBuilder: (context, index) {
                        ScanResult result = loraDevices[index];
                        return ListTile(
                          title: Text(result.device.platformName),
                          subtitle: Text(result.device.remoteId.toString()),
                          onTap: () {
                            service.setTargetDevice(result.device);
                            Navigator.of(dialogContext).pop();
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () {
                      service.stopScan();
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text("CANCEL"))
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMessageComposer({required bool isEnabled}) {
    String recipientId = _recipientController.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, -1),
            blurRadius: 2,
            color: Colors.black12,
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Recipient Selection Row
                  Padding(
                    padding: const EdgeInsets.only(left: 14.0, bottom: 4.0),
                    child: Row(
                      children: [
                        Text(
                          "To:",
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 60,
                          child: TextField(
                            controller: _recipientController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.white),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey.shade800,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onChanged: (value) {
                              recipientId = value;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Message Input
                  AbsorbPointer(
                    absorbing: !isEnabled,
                    child: TextField(
                      controller: _textController,
                      style: TextStyle(
                          color:
                              isEnabled ? Colors.white : Colors.grey.shade600),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        hintText: isEnabled
                            ? "Type a message..."
                            : "Select a device to begin",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                      ),
                      onSubmitted:
                          isEnabled ? (_) => _sendMessage(recipientId) : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            Material(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(30),
              child: SizedBox(
                height: 48,
                width: 48,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: isEnabled ? () => _sendMessage(recipientId) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
