import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/bike_console_controller.dart';
import '../models/ride_models.dart';
import 'scan_for_devices_screen.dart';
import 'sessions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.bikeConsoleController});

  final BikeConsoleController bikeConsoleController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _circumferenceController;
  late final TextEditingController _autoPauseSecondsController;

  bool _autoPauseEnabled = true;
  bool _savingRideSettings = false;

  RideSettings get _settings =>
      widget.bikeConsoleController.rideSessionController.settings;
  bool get _liteModeEnabled =>
      widget.bikeConsoleController.displaySettings.liteModeEnabled;

  @override
  void initState() {
    super.initState();

    _circumferenceController = TextEditingController(
      text: _settings.tyreCircumferenceMeters.toStringAsFixed(2),
    );

    _autoPauseSecondsController = TextEditingController(
      text: _settings.autoPauseSeconds.toString(),
    );

    _autoPauseEnabled = _settings.autoPauseEnabled;

    widget.bikeConsoleController.addListener(_onConsoleChanged);
  }

  @override
  void dispose() {
    widget.bikeConsoleController.removeListener(_onConsoleChanged);
    _circumferenceController.dispose();
    _autoPauseSecondsController.dispose();
    super.dispose();
  }

  void _onConsoleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveRideSettings() async {
    final circumferenceText = _circumferenceController.text.trim();
    final autoPauseSecondsText = _autoPauseSecondsController.text.trim();

    final circumference = double.tryParse(circumferenceText);
    final autoPauseSeconds = int.tryParse(autoPauseSecondsText);

    if (circumference == null || circumference <= 0) {
      _showSnackBar("Enter a valid tyre circumference");
      return;
    }

    if (circumference < 0.5 || circumference > 3.5) {
      _showSnackBar("Tyre circumference should be between 0.5 m and 3.5 m");
      return;
    }

    if (_autoPauseEnabled &&
        (autoPauseSeconds == null ||
            autoPauseSeconds < 1 ||
            autoPauseSeconds > 120)) {
      _showSnackBar("Auto-pause delay should be between 1 and 120 seconds");
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _savingRideSettings = true;
    });

    final nextSettings = _settings.copyWith(
      tyreCircumferenceMeters: circumference,
      autoPauseEnabled: _autoPauseEnabled,
      autoPauseSeconds: autoPauseSeconds ?? _settings.autoPauseSeconds,
    );

    await widget.bikeConsoleController.rideSessionController.updateSettings(
      nextSettings,
    );

    if (!mounted) return;

    setState(() {
      _savingRideSettings = false;
      _circumferenceController.text = nextSettings.tyreCircumferenceMeters
          .toStringAsFixed(2);
      _autoPauseSecondsController.text = nextSettings.autoPauseSeconds
          .toString();
    });

    _showSnackBar("Ride settings saved");
  }

  Future<void> _setLiteModeEnabled(bool value) async {
    await widget.bikeConsoleController.updateDisplaySettings(
      widget.bikeConsoleController.displaySettings.copyWith(
        liteModeEnabled: value,
      ),
    );

    if (!mounted) return;

    _showSnackBar(value ? "Lite Mode enabled" : "Lite Mode disabled");
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1000),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pairDevice() async {
    final BluetoothDevice? selected = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanForDevicesScreen()),
    );

    if (selected != null) {
      await widget.bikeConsoleController.connectionController.pairWithDevice(
        selected,
      );

      if (mounted) setState(() {});
    }
  }

  Future<void> _forgetDevice() async {
    await widget.bikeConsoleController.connectionController.forgetConsole();

    if (mounted) setState(() {});
  }

  String _consoleStatusText(ConsoleConnectionState state) {
    switch (state) {
      case ConsoleConnectionState.disconnected:
        return "No Console Paired";
      case ConsoleConnectionState.scanning:
        return "Offline";
      case ConsoleConnectionState.available:
        return "Available";
      case ConsoleConnectionState.connecting:
        return "Connecting";
      case ConsoleConnectionState.connected:
        return "Connected";
      case ConsoleConnectionState.lostDuringRide:
        return "Connection Lost";
      case ConsoleConnectionState.reconnecting:
        return "Reconnecting";
      case ConsoleConnectionState.offline:
        return "Offline";
    }
  }

  String _rssiText(int? rssi) {
    if (rssi == null) return "-";
    return "$rssi dBm";
  }

  @override
  Widget build(BuildContext context) {
    final connectionController =
        widget.bikeConsoleController.connectionController;

    final rideState = widget.bikeConsoleController.rideSessionController.state;

    final hasSavedDevice = connectionController.hasSavedConsole;
    final hasConnectedConsole = connectionController.connectedDeviceId != null;
    final shouldShowConsoleRows = hasSavedDevice || hasConnectedConsole;

    final consoleDeviceName =
        connectionController.consoleDisplayName ?? "Unknown Console";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Bike Console Settings"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SettingsCard(
            title: "Ride Settings",
            children: [
              const Text(
                "Tyre Circumference",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _circumferenceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(hintText: "2.00", suffixText: "m"),
              ),
              const SizedBox(height: 6),
              const Text(
                "Used by the app to calculate speed from wheel RPM. This value will sync to the console later.",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _autoPauseEnabled,
                activeThumbColor: Colors.greenAccent,
                activeTrackColor: Colors.greenAccent.withValues(alpha: 0.35),
                title: const Text(
                  "Auto Pause",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  "Pause the ride when no movement is detected.",
                  style: TextStyle(color: Colors.white38),
                ),
                onChanged: (value) {
                  setState(() {
                    _autoPauseEnabled = value;
                  });
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _autoPauseEnabled
                    ? Column(
                        key: const ValueKey("auto-pause-seconds"),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          const Text(
                            "Inactivity Delay",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _autoPauseSecondsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              hintText: "10",
                              suffixText: "seconds",
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: ValueKey("auto-pause-disabled"),
                      ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _savingRideSettings ? null : _saveRideSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _savingRideSettings ? "Saving..." : "Save Ride Settings",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: "Display & Performance",
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _liteModeEnabled,
                activeThumbColor: Colors.greenAccent,
                activeTrackColor: Colors.greenAccent.withValues(alpha: 0.35),
                title: const Text(
                  "Lite Mode",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  "Reduces blur, glow, and always-running visual effects for smoother performance and lower battery use.",
                  style: TextStyle(color: Colors.white38, height: 1.35),
                ),
                onChanged: _setLiteModeEnabled,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: "Ride History",
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Colors.greenAccent,
                    size: 22,
                  ),
                ),
                title: const Text(
                  "Ride Sessions",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  "View saved rides, route maps, and ride stats.",
                  style: TextStyle(color: Colors.white38, height: 1.35),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white38,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SessionsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: "Current Ride State",
            children: [
              _InfoRow(label: "Ride", value: rideState.rideState.name),
              _InfoRow(
                label: "Speed",
                value: "${rideState.currentSpeedKmph.toStringAsFixed(1)} km/h",
              ),
              _InfoRow(
                label: "RPM",
                value: rideState.currentRpm.toStringAsFixed(0),
              ),
              _InfoRow(
                label: "Distance",
                value: "${rideState.distanceKm.toStringAsFixed(2)} km",
              ),
              _InfoRow(
                label: "Hazard",
                value: rideState.hazardEnabled ? "On" : "Off",
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: "Console Device Status",
            children: [
              if (shouldShowConsoleRows) ...[
                _InfoRow(
                  label: "Status",
                  value: _consoleStatusText(
                    connectionController.connectionState,
                  ),
                ),
                _InfoRow(label: "Console", value: consoleDeviceName),
                if (connectionController.isConnected)
                  _InfoRow(
                    label: "RSSI",
                    value: _rssiText(connectionController.latestRssi),
                  ),
                const SizedBox(height: 14),
              ],
              if (!shouldShowConsoleRows)
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _pairDevice,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text("Pair a Console"),
                  ),
                ),
              if (shouldShowConsoleRows)
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: _forgetDevice,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text("Forget Console"),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required String suffixText,
  }) {
    return InputDecoration(
      hintText: hintText,
      suffixText: suffixText,
      hintStyle: const TextStyle(color: Colors.white24),
      suffixStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF101010),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Colors.greenAccent.withValues(alpha: 0.7),
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181818).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
