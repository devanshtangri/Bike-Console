import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../controllers/bike_console_controller.dart';
import '../models/ride_models.dart';
import 'scan_for_devices_screen.dart';

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


  bool get _rideDataEditingAvailable {
    final rideState = widget.bikeConsoleController.rideSessionController.state;

    return rideState.rideState == RideState.running ||
        rideState.rideState == RideState.paused;
  }

  Future<void> _showEditRideDataSheet() async {
    final rideController = widget.bikeConsoleController.rideSessionController;
    final rideState = rideController.state;

    if (!_rideDataEditingAvailable) {
      return;
    }

    final elapsedMs = rideController.calculateActiveDurationMs();
    final totalSeconds = elapsedMs ~/ 1000;

    final distanceController = TextEditingController(
      text: rideState.distanceKm.toStringAsFixed(2),
    );

    final averageSpeedController = TextEditingController(
      text: rideState.averageSpeedKmph.toStringAsFixed(1),
    );

    final maxSpeedController = TextEditingController(
      text: rideState.maxSpeedKmph.toStringAsFixed(1),
    );

    final hoursController = TextEditingController(
      text: (totalSeconds ~/ 3600).toString(),
    );

    final minutesController = TextEditingController(
      text: ((totalSeconds % 3600) ~/ 60).toString(),
    );

    final secondsController = TextEditingController(
      text: (totalSeconds % 60).toString(),
    );

    var saved = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
          ),
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Colors.greenAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 13),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Edit Ride Data",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "Adjust the active ride values.",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _RideDataInputField(
                      label: "Distance",
                      controller: distanceController,
                      suffixText: "km",
                      hintText: "0.00",
                      decimal: true,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _RideDataInputField(
                            label: "Average Speed",
                            controller: averageSpeedController,
                            suffixText: "km/h",
                            hintText: "0.0",
                            decimal: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RideDataInputField(
                            label: "Max Speed",
                            controller: maxSpeedController,
                            suffixText: "km/h",
                            hintText: "0.0",
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Elapsed Time",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _RideDataInputField(
                            label: "Hours",
                            controller: hoursController,
                            suffixText: "h",
                            hintText: "0",
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RideDataInputField(
                            label: "Minutes",
                            controller: minutesController,
                            suffixText: "m",
                            hintText: "0",
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RideDataInputField(
                            label: "Seconds",
                            controller: secondsController,
                            suffixText: "s",
                            hintText: "0",
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(sheetContext);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text("Cancel"),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () {
                                final distance = double.tryParse(
                                  distanceController.text.trim(),
                                );

                                final averageSpeed = double.tryParse(
                                  averageSpeedController.text.trim(),
                                );

                                final maxSpeed = double.tryParse(
                                  maxSpeedController.text.trim(),
                                );

                                final hours = int.tryParse(
                                  hoursController.text.trim(),
                                );

                                final minutes = int.tryParse(
                                  minutesController.text.trim(),
                                );

                                final seconds = int.tryParse(
                                  secondsController.text.trim(),
                                );

                                if (distance == null ||
                                    distance < 0 ||
                                    averageSpeed == null ||
                                    averageSpeed < 0 ||
                                    maxSpeed == null ||
                                    maxSpeed < 0 ||
                                    hours == null ||
                                    hours < 0 ||
                                    minutes == null ||
                                    minutes < 0 ||
                                    minutes > 59 ||
                                    seconds == null ||
                                    seconds < 0 ||
                                    seconds > 59) {
                                  _showSnackBar("Enter valid ride data");
                                  return;
                                }

                                if (maxSpeed < averageSpeed) {
                                  _showSnackBar(
                                    "Max speed should be at least average speed",
                                  );
                                  return;
                                }

                                final activeDurationMs =
                                    (((hours * 60) + minutes) * 60 + seconds) *
                                    1000;

                                rideController.editCurrentRideData(
                                  distanceKm: distance,
                                  averageSpeedKmph: averageSpeed,
                                  maxSpeedKmph: maxSpeed,
                                  activeDurationMs: activeDurationMs,
                                );

                                saved = true;
                                Navigator.pop(sheetContext);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.greenAccent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                "Save",
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
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

    distanceController.dispose();
    averageSpeedController.dispose();
    maxSpeedController.dispose();
    hoursController.dispose();
    minutesController.dispose();
    secondsController.dispose();

    if (!mounted || !saved) return;

    _showSnackBar("Ride data updated");
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
    final showEditRideData =
        rideState.rideState == RideState.running ||
        rideState.rideState == RideState.paused;

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
          if (showEditRideData) ...[
            const SizedBox(height: 16),
            _SettingsCard(
              title: "Active Ride",
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
                      Icons.tune_rounded,
                      color: Colors.greenAccent,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    "Edit Ride Data",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                  onTap: _showEditRideDataSheet,
                ),
              ],
            ),
          ],
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


class _RideDataInputField extends StatelessWidget {
  const _RideDataInputField({
    required this.label,
    required this.controller,
    required this.suffixText,
    required this.hintText,
    this.decimal = false,
  });

  final String label;
  final TextEditingController controller;
  final String suffixText;
  final String hintText;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            decimal
                ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            suffixText: suffixText,
            hintStyle: const TextStyle(color: Colors.white24),
            suffixStyle: const TextStyle(color: Colors.white54, fontSize: 12),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.30),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.greenAccent.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),
      ],
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
