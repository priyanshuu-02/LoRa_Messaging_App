import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/providers/chat_provider.dart';
import 'package:lora_communicator/models/chat_message.dart';
import 'package:lora_communicator/services/audio_service.dart';
import 'package:lora_communicator/services/image_service.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/packet_framer_service.dart';
import 'package:lora_communicator/widgets/chat_bubble.dart';
import 'package:lora_communicator/widgets/pulse_dot.dart';
import 'package:lora_communicator/widgets/animated_scan_indicator.dart';
import 'package:lora_communicator/widgets/empty_chat_placeholder.dart';
import 'package:lora_communicator/screens/settings_screen.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _recipientController =
      TextEditingController(text: "2"); // Default recipient
  late AnimationController _sendButtonController;
  late Animation<double> _sendButtonScale;
  final AudioService _audioService = AudioService();
  final ImageService _imageService = ImageService();
  bool _isRecording = false;
  int _recordingSeconds = 0;
  DateTime? _recordingStartTime;

  @override
  void initState() {
    super.initState();
    _checkAdapterState();

    _sendButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _sendButtonScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.easeInOut),
    );
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
    _sendButtonController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _sendMessage(String recipientId) {
    if (_textController.text.trim().isEmpty) return;

    // Animate send button
    _sendButtonController.forward().then((_) {
      _sendButtonController.reverse();
    });

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppGradients.background,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildCustomAppBar(),
              Expanded(
                child: Consumer<ChatProvider>(
                  builder: (context, chatProvider, child) {
                    final messages = chatProvider.messages;
                    if (messages.isEmpty) {
                      return Consumer<BleService>(
                        builder: (context, bleService, _) {
                          return EmptyChatPlaceholder(
                            isConnected: bleService.targetDevice != null,
                          );
                        },
                      );
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 8.0),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: ChatBubble(
                            message: messages[index],
                            audioService: _audioService,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // The composer: enabled when connected AND not transmitting
              Consumer2<BleService, PacketFramerService>(
                builder: (context, bleService, framerService, _) {
                  final isConnected = bleService.targetDevice != null;
                  final isTransmitting = framerService.isTransmitting;
                  final isEnabled = isConnected && !isTransmitting;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar during transmission
                      if (framerService.isSending)
                        _buildProgressBar(
                          label: 'Sending',
                          current: framerService.chunksSent,
                          total: framerService.totalChunksToSend,
                          progress: framerService.sendingProgress,
                        ),
                      if (framerService.isReceivingChunks)
                        _buildProgressBar(
                          label: 'Receiving',
                          current: framerService.chunksReceived,
                          total: framerService.totalChunksExpected,
                          progress: framerService.receivingProgress,
                        ),
                      _buildMessageComposer(
                        isEnabled: isEnabled,
                        isTransmitting: isTransmitting,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Custom App Bar ──────────────────────────────────────────────────────

  Widget _buildCustomAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.85),
        border: const Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // LoRa icon
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.cell_tower_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          // Title & status
          Expanded(child: _buildAppBarTitle()),
          // Settings
          _buildIconButton(
            icon: Icons.settings_outlined,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
          // Connect / Disconnect
          _buildAppBarAction(),
        ],
      ),
    );
  }

  Widget _buildIconButton(
      {required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: AppDecorations.glassmorphism(
            opacity: 0.06,
            borderRadius: 12,
            borderOpacity: 0.08,
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    return Consumer<BleService>(
      builder: (context, bleService, child) {
        if (bleService.targetDevice != null) {
          final name =
              bleService.targetDevice?.platformName.isNotEmpty ?? false
                  ? bleService.targetDevice!.platformName
                  : "Unknown Device";
          final remoteId =
              bleService.targetDevice?.remoteId.toString() ?? '';
          final last4 = remoteId.length > 4
              ? remoteId.substring(remoteId.length - 4)
              : remoteId;

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const PulseDot(isActive: true, size: 7),
                        const SizedBox(width: 6),
                        Text(
                          "Connected · $last4",
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "LoRa Communicator",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const PulseDot(isActive: false, size: 7),
                  const SizedBox(width: 6),
                  Text(
                    "No device connected",
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildAppBarAction() {
    return Consumer<BleService>(
      builder: (context, bleService, _) {
        if (bleService.targetDevice != null) {
          return GestureDetector(
            key: const Key('disconnectButton'),
            onTap: () => bleService.disconnect(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withOpacity(0.25),
                  width: 0.5,
                ),
              ),
              child: Text(
                "Disconnect",
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
          );
        } else {
          return GestureDetector(
            key: const Key('selectDeviceButton'),
            onTap: () async {
              if (await FlutterBluePlus.adapterState.first !=
                  BluetoothAdapterState.on) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.bluetooth_disabled,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 10),
                          Text("Please turn on Bluetooth.",
                              style: GoogleFonts.inter()),
                        ],
                      ),
                    ),
                  );
                }
                return;
              }
              if (await _requestPermissions()) {
                if (mounted) _showDeviceSelectionSheet(context);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bluetooth_searching,
                      color: Colors.white, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    "Connect",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  // ─── Device Selection Bottom Sheet ─────────────────────────────────────

  void _showDeviceSelectionSheet(BuildContext context) {
    final bleService = context.read<BleService>()..startScan();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
              left: BorderSide(color: AppColors.divider, width: 0.5),
              right: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.cell_tower_rounded,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      "Select a LoRa Module",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        bleService.stopScan();
                        Navigator.of(sheetContext).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close,
                            color: AppColors.textSecondary, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              // Device list
              Expanded(
                child: Consumer<BleService>(
                  builder: (context, service, child) {
                    if (service.isScanning) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AnimatedScanIndicator(size: 90),
                          const SizedBox(height: 20),
                          Text(
                            "Scanning for devices...",
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      );
                    }

                    final loraDevices = service.scanResults
                        .where((r) =>
                            r.device.platformName.contains('Heltec-LoRa'))
                        .toList();

                    if (loraDevices.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bluetooth_disabled_rounded,
                                size: 40,
                                color: AppColors.textHint.withOpacity(0.5),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                "No LoRa devices found",
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Ensure the module is powered on\nand within Bluetooth range.",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textHint,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              GestureDetector(
                                onTap: () => service.startScan(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: AppGradients.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "Retry Scan",
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shrinkWrap: true,
                      itemCount: loraDevices.length,
                      itemBuilder: (context, index) {
                        ScanResult result = loraDevices[index];
                        final rssi = result.rssi;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                service.setTargetDevice(result.device);
                                Navigator.of(sheetContext).pop();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: AppDecorations.glassmorphism(
                                  opacity: 0.05,
                                  borderRadius: 14,
                                  borderOpacity: 0.1,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.primary.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.bluetooth,
                                        color: AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            result.device.platformName,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            result.device.remoteId.toString(),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.textHint,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Signal strength
                                    Column(
                                      children: [
                                        Icon(
                                          rssi > -60
                                              ? Icons.signal_wifi_4_bar
                                              : rssi > -80
                                                  ? Icons.network_wifi_3_bar
                                                  : Icons.network_wifi_1_bar,
                                          size: 18,
                                          color: rssi > -60
                                              ? AppColors.success
                                              : rssi > -80
                                                  ? AppColors.warning
                                                  : AppColors.error,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "$rssi dBm",
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: AppColors.textHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Transmission Progress Bar ─────────────────────────────────────────

  Widget _buildProgressBar({
    required String label,
    required int current,
    required int total,
    required double progress,
  }) {
    final percentage = (progress * 100).toInt();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.95),
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                      value: progress,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$label $current/$total chunks',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                '$percentage%',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  // Background
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Animated fill
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          gradient: AppGradients.primary,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Message Composer ──────────────────────────────────────────────────


  Widget _buildMessageComposer({required bool isEnabled, bool isTransmitting = false}) {
    String recipientId = _recipientController.text;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.92),
        border: const Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Recipient row
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_outlined,
                            size: 12,
                            color: AppColors.primary.withOpacity(0.7)),
                        const SizedBox(width: 5),
                        Text(
                          "To:",
                          style: GoogleFonts.inter(
                            color: AppColors.primary.withOpacity(0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    height: 30,
                    child: TextField(
                      controller: _recipientController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.divider, width: 0.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.divider, width: 0.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 1),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                      ),
                      onChanged: (value) {
                        recipientId = value;
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Message input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AnimatedOpacity(
                    opacity: isEnabled ? 1.0 : 0.4,
                    duration: AppAnimations.fast,
                    child: AbsorbPointer(
                      absorbing: !isEnabled,
                      child: TextField(
                        controller: _textController,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          hintText: isTransmitting
                              ? "Transmitting..."
                              : isEnabled
                                  ? "Type a message..."
                                  : "Connect to a device first",
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.textHint,
                            fontSize: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                                color: AppColors.divider, width: 0.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                                color: AppColors.divider, width: 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1),
                          ),
                        ),
                        onSubmitted:
                            isEnabled ? (_) => _sendMessage(recipientId) : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Mic button (hold to record)
                _buildMicButton(isEnabled, recipientId),
                const SizedBox(width: 4),
                // Camera/Image button
                _buildCameraButton(isEnabled, recipientId),
                const SizedBox(width: 4),
                // Send button
                ScaleTransition(
                  scale: _sendButtonScale,
                  child: GestureDetector(
                    onTap:
                        isEnabled ? () => _sendMessage(recipientId) : null,
                    child: AnimatedContainer(
                      duration: AppAnimations.fast,
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient:
                            isEnabled ? AppGradients.sendButton : null,
                        color: isEnabled ? null : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(23),
                        boxShadow: isEnabled
                            ? [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withOpacity(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        color: isEnabled
                            ? Colors.white
                            : AppColors.textHint,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Mic Button (hold to record) ────────────────────────────────────────

  Widget _buildMicButton(bool isEnabled, String recipientId) {
    return GestureDetector(
      onLongPressStart: isEnabled
          ? (_) async {
              final started = await _audioService.startRecording();
              if (started) {
                setState(() {
                  _isRecording = true;
                  _recordingStartTime = DateTime.now();
                  _recordingSeconds = 0;
                });
                // Update timer every second
                _updateRecordingTimer();
              }
            }
          : null,
      onLongPressEnd: isEnabled
          ? (_) async {
              if (!_isRecording) return;
              final duration = _recordingSeconds;
              final bytes = await _audioService.stopRecording();
              setState(() => _isRecording = false);
              if (bytes != null && duration > 0) {
                context
                    .read<ChatProvider>()
                    .sendVoiceNote(recipientId, bytes, duration);
              }
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _isRecording
              ? AppColors.error.withOpacity(0.15)
              : isEnabled
                  ? AppColors.surfaceLight
                  : AppColors.surfaceLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: _isRecording ? AppColors.error : AppColors.divider,
            width: _isRecording ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: _isRecording
                  ? AppColors.error
                  : isEnabled
                      ? AppColors.textSecondary
                      : AppColors.textHint,
              size: _isRecording ? 16 : 18,
            ),
            if (_isRecording)
              Text(
                '${_recordingSeconds}s',
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _updateRecordingTimer() async {
    while (_isRecording && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (_isRecording && mounted) {
        setState(() {
          _recordingSeconds =
              DateTime.now().difference(_recordingStartTime!).inSeconds;
        });
        // Auto-stop at 5 seconds
        if (_recordingSeconds >= 5) {
          final bytes = await _audioService.stopRecording();
          setState(() => _isRecording = false);
          if (bytes != null) {
            context
                .read<ChatProvider>()
                .sendVoiceNote(_recipientController.text, bytes, 5);
          }
          break;
        }
      }
    }
  }

  // ─── Camera/Image Button ────────────────────────────────────────────────

  Widget _buildCameraButton(bool isEnabled, String recipientId) {
    return GestureDetector(
      onTap: isEnabled ? () => _showImageOptions(recipientId) : null,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.surfaceLight
              : AppColors.surfaceLight.withOpacity(0.5),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Icon(
          Icons.camera_alt_rounded,
          color: isEnabled ? AppColors.textSecondary : AppColors.textHint,
          size: 18,
        ),
      ),
    );
  }

  void _showImageOptions(String recipientId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Send Image via LoRa',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose quality and source. Higher quality = longer transfer.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Row 1: Dithered options
            Row(
              children: [
                Expanded(
                  child: _imageOptionTile(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    sublabel: '64×64 Dithered',
                    badge: 'Fast',
                    onTap: () {
                      Navigator.pop(ctx);
                      _captureAndSendImage(
                          recipientId, ImageSource.camera, ImageQuality.dithered);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _imageOptionTile(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    sublabel: '32×32 Grayscale',
                    badge: 'Medium',
                    onTap: () {
                      Navigator.pop(ctx);
                      _captureAndSendImage(
                          recipientId, ImageSource.gallery, ImageQuality.grayscale);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 2: Color options (full quality)
            Row(
              children: [
                Expanded(
                  child: _imageOptionTile(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    sublabel: 'Full Color',
                    badge: 'HD',
                    badgeColor: AppColors.secondary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _captureAndSendImage(
                          recipientId, ImageSource.camera, ImageQuality.color);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _imageOptionTile(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    sublabel: 'Full Color',
                    badge: 'HD',
                    badgeColor: AppColors.secondary,
                    onTap: () {
                      Navigator.pop(ctx);
                      _captureAndSendImage(
                          recipientId, ImageSource.gallery, ImageQuality.color);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageOptionTile({
    required IconData icon,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
    String? badge,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                children: [
                  Icon(icon, color: AppColors.primary, size: 24),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: 0,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? AppColors.primary).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureAndSendImage(
      String recipientId, ImageSource source, ImageQuality quality) async {
    try {
      final rawBytes = await _imageService.pickImage(source: source);
      if (rawBytes == null) return;

      // Show processing indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Compressing image...', style: GoogleFonts.inter()),
              ],
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }

      final compressed = ImageService.compress(rawBytes, quality);
      debugPrint('📷 Compressed image: ${compressed.length} bytes ($quality)');

      context.read<ChatProvider>().sendImage(recipientId, compressed);
    } catch (e) {
      debugPrint('❌ Error capturing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: $e',
                style: GoogleFonts.inter()),
          ),
        );
      }
    }
  }
}
