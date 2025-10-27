import 'package:flutter/material.dart';
import 'package:lora_communicator/providers/chat_provider.dart';
import 'package:lora_communicator/screens/blocked_screen.dart';
import 'package:lora_communicator/screens/loading_screen.dart';
import 'package:lora_communicator/screens/chat_screen.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/packet_framer_service.dart';
import 'package:lora_communicator/services/remote_config_service.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Use a nullable bool to represent the three states: loading, enabled, disabled.
  bool? _isAppEnabled;

  @override
  void initState() {
    super.initState();
    _checkAppStatus();
  }

  Future<void> _checkAppStatus() async {
    final remoteConfigService = RemoteConfigService();
    final enabled = await remoteConfigService.isAppEnabled();
    if (mounted) {
      setState(() {
        _isAppEnabled = enabled;
      });
    }
  }

  Widget _getHomeScreen() {
    if (_isAppEnabled == null) {
      return const LoadingScreen();
    }
    return _isAppEnabled! ? const ChatScreen() : const BlockedScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // The services are provided here to be available across the app.
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProxyProvider<BleService, PacketFramerService>(
          create: (context) => PacketFramerService(
            bleService: context.read<BleService>(),
          ),
          update: (_, bleService, previousFramer) =>
              previousFramer!..updateBleService(bleService),
        ),
        ChangeNotifierProxyProvider<PacketFramerService, ChatProvider>(
          create: (context) => ChatProvider(
            framerService: context.read<PacketFramerService>(),
          ),
          update: (_, framerService, previousChatProvider) =>
              previousChatProvider!..updateFramerService(framerService),
        ),
      ],
      child: MaterialApp(
        title: 'LoRa Communicator',
        theme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.cyan,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: Colors.black,
        ),
        debugShowCheckedModeBanner: false,
        // Conditionally show the correct screen.
        home: _getHomeScreen(),
      ),
    );
  }
}
