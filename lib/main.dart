import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/providers/chat_provider.dart';
import 'package:lora_communicator/screens/chat_screen.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/encryption_service.dart';
import 'package:lora_communicator/services/packet_framer_service.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Set system UI overlay style for a fully immersive dark theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // The services are provided here to be available across the app.
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => EncryptionService()),
        ChangeNotifierProxyProvider2<BleService, EncryptionService,
            PacketFramerService>(
          create: (context) => PacketFramerService(
            bleService: context.read<BleService>(),
            encryptionService: context.read<EncryptionService>(),
          ),
          update: (_, bleService, encryptionService, previousFramer) =>
              previousFramer!
                ..updateBleService(bleService)
                ..updateEncryptionService(encryptionService),
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
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        // Conditionally show the correct screen.
        home: const ChatScreen(),
      ),
    );
  }
}
