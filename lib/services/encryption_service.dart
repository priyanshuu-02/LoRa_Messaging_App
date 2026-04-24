import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for AES-256-GCM end-to-end encryption of LoRa messages.
///
/// Uses a pre-shared passphrase which is hashed via PBKDF2 to derive
/// a 256-bit AES key. Each message gets a unique 12-byte random nonce.
///
/// Encrypted format: "ENC:" + base64(nonce[12] + ciphertext + mac[16])
class EncryptionService with ChangeNotifier {
  static const String _passphraseKey = 'encryption_passphrase';
  static const String _saltKey = 'encryption_salt';
  static const String _enabledKey = 'encryption_enabled';
  static const String encryptedPrefix = 'ENC:';

  final AesGcm _algorithm = AesGcm.with256bits();

  SecretKey? _secretKey;
  bool _isEnabled = false;
  bool _hasPassphrase = false;

  bool get isEnabled => _isEnabled && _hasPassphrase;
  bool get hasPassphrase => _hasPassphrase;

  EncryptionService() {
    _loadFromPrefs();
  }

  /// Load saved encryption settings from SharedPreferences.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_enabledKey) ?? false;
    final savedPassphrase = prefs.getString(_passphraseKey);
    final savedSalt = prefs.getString(_saltKey);

    if (savedPassphrase != null &&
        savedPassphrase.isNotEmpty &&
        savedSalt != null) {
      final salt = base64Decode(savedSalt);
      _secretKey = await _deriveKey(savedPassphrase, salt);
      _hasPassphrase = true;
    }
    notifyListeners();
  }

  /// Set a new passphrase and derive the AES-256 key via PBKDF2.
  Future<void> setPassphrase(String passphrase) async {
    if (passphrase.trim().isEmpty) {
      await clearPassphrase();
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // Use a fixed, deterministic salt so both devices derive the
    // same key from the same passphrase. In a PSK system the salt
    // must be identical on both sides — a unique app-specific
    // constant still protects against generic rainbow tables.
    final salt = utf8.encode('LoRaCommunicator_E2E_v1');

    _secretKey = await _deriveKey(passphrase, salt);
    _hasPassphrase = true;
    _isEnabled = true;

    await prefs.setString(_passphraseKey, passphrase);
    await prefs.setString(_saltKey, base64Encode(salt));
    await prefs.setBool(_enabledKey, true);

    notifyListeners();
    debugPrint('🔐 Encryption passphrase set and key derived.');
  }

  /// Derive a 256-bit key from a passphrase using PBKDF2.
  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    return secretKey;
  }

  /// Toggle encryption on/off (passphrase must be set first).
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    notifyListeners();
  }

  /// Clear the passphrase and disable encryption.
  Future<void> clearPassphrase() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passphraseKey);
    await prefs.remove(_saltKey);
    await prefs.setBool(_enabledKey, false);

    _secretKey = null;
    _hasPassphrase = false;
    _isEnabled = false;
    notifyListeners();
    debugPrint('🔓 Encryption passphrase cleared.');
  }

  /// Encrypt a plaintext message.
  /// Returns: "ENC:" + base64(nonce[12] + ciphertext + mac[16])
  Future<String?> encrypt(String plaintext) async {
    if (_secretKey == null) return null;

    try {
      final nonce = _algorithm.newNonce();

      final secretBox = await _algorithm.encrypt(
        utf8.encode(plaintext),
        secretKey: _secretKey!,
        nonce: nonce,
      );

      // Pack: nonce + ciphertext + mac into a single byte array
      final packed = <int>[
        ...secretBox.nonce,
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ];

      return encryptedPrefix + base64Encode(packed);
    } catch (e) {
      debugPrint('❌ Encryption error: $e');
      return null;
    }
  }

  /// Decrypt a message that starts with "ENC:".
  /// Returns the plaintext, or null if decryption fails (wrong key, tampered).
  Future<String?> decrypt(String encryptedMessage) async {
    if (_secretKey == null) return null;

    try {
      if (!encryptedMessage.startsWith(encryptedPrefix)) {
        return null;
      }

      final base64Data = encryptedMessage.substring(encryptedPrefix.length);
      final packed = base64Decode(base64Data);

      // Unpack: nonce[12] + ciphertext[...] + mac[16]
      const nonceLength = 12;
      const macLength = 16;

      if (packed.length < nonceLength + macLength) {
        debugPrint('❌ Encrypted message too short.');
        return null;
      }

      final nonce = packed.sublist(0, nonceLength);
      final cipherText =
          packed.sublist(nonceLength, packed.length - macLength);
      final mac = packed.sublist(packed.length - macLength);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );

      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: _secretKey!,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      debugPrint('❌ Decryption failed (wrong key?): $e');
      return null;
    }
  }

  /// Check if a message string is encrypted.
  static bool isEncryptedMessage(String message) {
    return message.startsWith(encryptedPrefix);
  }

  /// Get the saved passphrase for display (obscured in UI).
  Future<String?> getSavedPassphrase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passphraseKey);
  }
}
