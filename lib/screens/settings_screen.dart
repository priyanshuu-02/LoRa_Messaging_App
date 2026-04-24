import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lora_communicator/constants/app_theme.dart';
import 'package:lora_communicator/services/ble_service.dart';
import 'package:lora_communicator/services/encryption_service.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _passphraseController;
  bool _obscurePassphrase = true;
  bool _isLoadingPassphrase = true;

  @override
  void initState() {
    super.initState();
    final bleService = context.read<BleService>();
    _usernameController = TextEditingController(
        text: bleService.username == bleService.deviceUid
            ? ''
            : bleService.username);
    _passphraseController = TextEditingController();
    _loadPassphrase();
  }

  Future<void> _loadPassphrase() async {
    final encryptionService = context.read<EncryptionService>();
    final saved = await encryptionService.getSavedPassphrase();
    if (mounted) {
      setState(() {
        _passphraseController.text = saved ?? '';
        _isLoadingPassphrase = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final bleService = context.read<BleService>();
    bleService.updateUsername(_usernameController.text);

    // Save encryption passphrase
    final encryptionService = context.read<EncryptionService>();
    final passphrase = _passphraseController.text.trim();
    if (passphrase.isNotEmpty) {
      encryptionService.setPassphrase(passphrase);
    } else {
      encryptionService.clearPassphrase();
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 18),
            const SizedBox(width: 10),
            Text("Settings saved!", style: GoogleFonts.inter()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              _buildAppBar(),
              // Content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Identity Section
                    _buildSectionHeader(
                      icon: Icons.person_outline_rounded,
                      title: "Identity",
                    ),
                    const SizedBox(height: 12),
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Display Name field
                          Text(
                            "Your Display Name",
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _usernameController,
                            maxLength: 10,
                            style: GoogleFonts.inter(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: "e.g. Rahul, Alice...",
                              prefixIcon: const Icon(
                                Icons.badge_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: AppColors.surfaceLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.divider, width: 0.5),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.divider, width: 0.5),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 14),
                          // Device UID (read-only)
                          Row(
                            children: [
                              Text(
                                "Device UID",
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Consumer<BleService>(
                                builder: (context, ble, _) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#${ble.deviceUid}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Auto-generated unique ID. Others see you as DisplayName#UID.",
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Encryption Section
                    _buildSectionHeader(
                      icon: Icons.lock_rounded,
                      title: "End-to-End Encryption",
                    ),
                    const SizedBox(height: 12),
                    _buildEncryptionCard(),
                    const SizedBox(height: 28),

                    // Device Info Section
                    _buildSectionHeader(
                      icon: Icons.bluetooth_rounded,
                      title: "Device Info",
                    ),
                    const SizedBox(height: 12),
                    Consumer<BleService>(
                      builder: (context, bleService, _) {
                        final device = bleService.targetDevice;
                        return _buildCard(
                          child: Column(
                            children: [
                              _buildInfoRow(
                                "Status",
                                device != null ? "Connected" : "Disconnected",
                                valueColor: device != null
                                    ? AppColors.success
                                    : AppColors.textHint,
                              ),
                              if (device != null) ...[
                                const Divider(height: 20),
                                _buildInfoRow(
                                  "Device Name",
                                  device.platformName.isNotEmpty
                                      ? device.platformName
                                      : "Unknown",
                                ),
                                const Divider(height: 20),
                                _buildInfoRow(
                                  "Remote ID",
                                  device.remoteId.toString(),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // Save Button
                    GestureDetector(
                      onTap: _saveSettings,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: AppGradients.primary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            "Save Changes",
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Version footer
                    Center(
                      child: Text(
                        "LoRa Communicator v1.0.0",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Encryption Card ─────────────────────────────────────────────────

  Widget _buildEncryptionCard() {
    return Consumer<EncryptionService>(
      builder: (context, encryptionService, _) {
        return _buildCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: encryptionService.isEnabled
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.textHint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: encryptionService.isEnabled
                        ? AppColors.success.withOpacity(0.25)
                        : AppColors.textHint.withOpacity(0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      encryptionService.isEnabled
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 13,
                      color: encryptionService.isEnabled
                          ? AppColors.success
                          : AppColors.textHint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      encryptionService.isEnabled
                          ? "AES-256-GCM Active"
                          : "No passphrase set",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: encryptionService.isEnabled
                            ? AppColors.success
                            : AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Passphrase field
              Text(
                "Shared Passphrase",
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoadingPassphrase)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12.0),
                    child:
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              else
                TextField(
                  controller: _passphraseController,
                  obscureText: _obscurePassphrase,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: "Enter a shared secret",
                    prefixIcon: const Icon(
                      Icons.key_rounded,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassphrase
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassphrase = !_obscurePassphrase;
                        });
                      },
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.divider, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.divider, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppColors.secondary, width: 1.5),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                "Both devices must use the same passphrase. Leave empty to disable encryption.",
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textHint,
                  height: 1.4,
                ),
              ),

              // Clear passphrase button
              if (encryptionService.hasPassphrase) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    _passphraseController.clear();
                    encryptionService.clearPassphrase();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.error.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "Clear Passphrase",
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─── Shared Widgets ──────────────────────────────────────────────────

  Widget _buildAppBar() {
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
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: AppDecorations.glassmorphism(
                  opacity: 0.06,
                  borderRadius: 12,
                  borderOpacity: 0.08,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textSecondary, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            "Settings",
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      {required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(),
      child: child,
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
