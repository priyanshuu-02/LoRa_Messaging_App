import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lora_communicator/constants/app_constants.dart';

class BleService with ChangeNotifier {
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _rxCharacteristic; // For writing data to the device
  BluetoothCharacteristic?
      _txCharacteristic; // For receiving data from the device
  StreamSubscription<List<int>>? _valueSubscription;
  final StreamController<List<int>> _rawDataController =
      StreamController.broadcast();
  String _deviceUid = ''; // Permanent unique device identifier
  String _username = ""; // Human-readable display name
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  StreamSubscription<bool>? _isScanningSubscription;
  // Add connection state tracking
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  // Add this subscription
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // Public getters
  BluetoothDevice? get targetDevice => _targetDevice;
  Stream<List<int>> get rawDataStream => _rawDataController.stream;
  List<ScanResult> get scanResults => _scanResults;
  String get senderId => _deviceUid;
  String get deviceUid => _deviceUid;
  String get username => _username.isNotEmpty ? _username : _deviceUid;
  /// Returns "username#uid" for display, or just "Device {id}" as fallback.
  String get displayIdentity {
    final name = _username.isNotEmpty ? _username : 'Device';
    return '$name#$_deviceUid';
  }
  bool get isScanning => _isScanning;
  Future<bool> get isBluetoothAvailable => FlutterBluePlus.isSupported;
  BluetoothConnectionState get connectionState => _connectionState;

  /// Returns "Device {id}" as a fallback when no name is embedded.
  String resolveDisplayName(String loraId) {
    return 'Device $loraId';
  }

  /// Generate a permanent 4-char alphanumeric device UID.
  static String _generateDeviceUid() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(4, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
    );
  }

  BleService() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {}
    });
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      // If the underlying scanning state changes, update our own state
      // and notify listeners. This is crucial for when the scan times out.
      if (_isScanning != isScanning) {
        _isScanning = isScanning;
        notifyListeners();
      }
    });
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    // Ensure senderId is loaded before scanning.
    await _loadSenderId(); // This is now awaited

    try {
      _isScanning = true;
      _scanResults.clear();
      notifyListeners();

      // We remove the `withServices` filter to make scanning more reliable,
      // as some devices may not advertise the service UUID correctly.
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        _scanResults = results;
        notifyListeners();
      }, onError: (e) {
        debugPrint("Error during scan: $e");
        stopScan();
      });
    } catch (e) {
      debugPrint("Error starting scan: $e");
      stopScan();
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    // No need to cancel _scanSubscription, it's managed by the library
    _isScanning = false;
    notifyListeners();
  }

  // Modify setTargetDevice method
  void setTargetDevice(BluetoothDevice device) {
    _targetDevice = device;

    // Listen for connection state changes
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      _connectionState = state;
      debugPrint("Connection state changed to: $state");

      if (state == BluetoothConnectionState.disconnected) {
        _cleanupConnection();
      } else if (state == BluetoothConnectionState.connected) {
        // Automatically discover services when connected
        _discoverServices(device).then((success) {
          if (!success) {
            debugPrint("Failed to discover services after connection");
          }
        });
      }

      notifyListeners();
    });

    // Immediately connect so BLE notifications are active for receiving.
    // Without this, incoming LoRa messages forwarded by the ESP32 would be
    // lost until the user sends their first message.
    _connectToDevice(device);

    notifyListeners();
  }

  /// Initiates a BLE GATT connection to the selected device.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      debugPrint("Connecting to ${device.platformName}...");
      await device.connect(timeout: const Duration(seconds: 10));
      // The connection state listener will handle service discovery.
    } catch (e) {
      debugPrint("Error connecting to device: $e");
    }
  }

  // Add helper method to cleanup connection
  void _cleanupConnection() {
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _valueSubscription?.cancel();
    _valueSubscription = null;
    notifyListeners();
  }

  void disconnect() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _targetDevice?.disconnect();
    _cleanupConnection();
    _targetDevice = null;
    notifyListeners();
  }

  // Update the discoverServices method to be private and return Future<bool>
  Future<bool> _discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      debugPrint("Found ${services.length} services.");
      for (var service in services) {
        debugPrint("Service: ${service.uuid}");
        if (service.uuid == SERVICE_UUID) {
          debugPrint("Found our LoRa Service!");
          for (var c in service.characteristics) {
            if (c.uuid == RX_CHARACTERISTIC_UUID) {
              debugPrint("Found RX Characteristic (App -> Module).");
              _rxCharacteristic = c;
            } else if (c.uuid == TX_CHARACTERISTIC_UUID) {
              debugPrint(
                  "Found TX Characteristic (Module -> App). Subscribing...");
              _txCharacteristic = c;

              _valueSubscription?.cancel();
              await c.setNotifyValue(true, timeout: 10);
              _valueSubscription = c.onValueReceived.listen((value) {
                debugPrint("<- RAW BLE DATA: ${String.fromCharCodes(value)}");
                _rawDataController.add(value);
              });
              debugPrint("Subscribed to TX Characteristic.");
            }
          }
          if (_rxCharacteristic != null && _txCharacteristic != null) {
            debugPrint(
                "All required characteristics found. Warming up connection...");
            // Warm-up: send a lightweight ping to stabilize the BLE link
            // before any real data transfer. This prevents the initial
            // disconnection issue on fresh connections.
            await _warmUpConnection();
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint("Error discovering services: $e");
      return false;
    }
  }

  /// Stabilize the BLE connection before any real data transfer.
  /// Fresh BLE connections to ESP32 modules can be unstable; without
  /// this warm-up sequence the first real write often triggers a
  /// disconnect.  The strategy:
  ///   1. Negotiate a larger MTU (exercises the GATT layer).
  ///   2. Send multiple small pings to fully exercise the write path.
  ///   3. Allow a settling delay before returning control.
  Future<void> _warmUpConnection() async {
    try {
      // 1. MTU negotiation — also stabilizes the underlying L2CAP link.
      //    ESP32 NimBLE typically supports up to 512; the OS will
      //    negotiate down to whatever both sides support.
      if (_targetDevice != null) {
        try {
          final mtu = await _targetDevice!.requestMtu(512);
          debugPrint("📏 MTU negotiated: $mtu");
        } catch (e) {
          debugPrint("⚠️ MTU negotiation failed (non-fatal): $e");
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // 2. Send multiple warm-up pings with short delays between them.
      //    This exercises the BLE write path several times so the
      //    connection is fully stable before any real data.
      if (_rxCharacteristic != null) {
        for (int i = 1; i <= 3; i++) {
          try {
            final pingData = utf8.encode('PING');
            await _rxCharacteristic!.write(
              pingData,
              withoutResponse: false,
              timeout: 5,
            );
            debugPrint("🏓 Warm-up ping $i/3 sent.");
          } catch (e) {
            debugPrint("⚠️ Warm-up ping $i failed (non-fatal): $e");
          }
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // 3. Final settling delay
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint("✅ Connection warm-up complete.");
    } catch (e) {
      // Non-fatal: if the warm-up fails we still proceed
      debugPrint("⚠️ Warm-up failed (non-fatal): $e");
    }
  }

  /// Connects if not already connected, sends data, and manages a disconnect timer.
  Future<bool> sendToDevice(List<List<int>> dataFrames) async {
    if (_targetDevice == null) {
      debugPrint("Cannot send data: No target device selected.");
      return false;
    }

    // If we are not connected, connect and discover services.
    final currentState = await _targetDevice!.connectionState.first;
    if (currentState != BluetoothConnectionState.connected) {
      try {
        await _targetDevice!.connect(timeout: const Duration(seconds: 10));
        _connectionState = BluetoothConnectionState.connected;
        notifyListeners();

        // Only discover services if not already set up by the connection listener.
        if (_rxCharacteristic == null || _txCharacteristic == null) {
          bool servicesFound = await _discoverServices(_targetDevice!);
          if (!servicesFound) {
            debugPrint("Failed to find required services/characteristics.");
            disconnect();
            return false;
          }
        }
      } catch (e) {
        debugPrint("Error during initial connection: $e");
        disconnect();
        return false;
      }
    }

    // We are connected, so proceed to send data.
    try {
      if (_rxCharacteristic != null) {
        for (final frame in dataFrames) {
          await _rxCharacteristic!
              .write(frame, withoutResponse: false, timeout: 10);
          // A small delay between frames is good practice.
          await Future.delayed(const Duration(milliseconds: 50));
        }
        debugPrint("All data frames sent successfully.");
        return true;
      } else {
        debugPrint("RX Characteristic is null. Cannot send data.");
        return false;
      }
    } catch (e) {
      debugPrint("Error during sendToDevice: $e");
      return false;
    }
  }

  Future<void> _loadSenderId() async {
    final prefs = await SharedPreferences.getInstance();
    // Load or generate permanent device UID
    if (prefs.containsKey('device_uid')) {
      _deviceUid = prefs.getString('device_uid')!;
    } else {
      _deviceUid = _generateDeviceUid();
      await prefs.setString('device_uid', _deviceUid);
    }
    debugPrint('📱 Device UID: $_deviceUid');
    // Load username
    _username = prefs.getString('username') ?? '';
    notifyListeners();
  }

  Future<void> updateUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name.trim());
    _username = name.trim();
    notifyListeners();
  }


  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _valueSubscription?.cancel();
    _rawDataController.close();
    super.dispose();
  }
}
