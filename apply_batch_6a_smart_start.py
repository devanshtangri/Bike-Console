from pathlib import Path

ROOT = Path(__file__).resolve().parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    full = ROOT / path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Patch failed for {label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


ride_start_gate_service = '''import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/bike_console_controller.dart';

enum RideStartRequirement {
  locationPermission,
  locationServices,
  notificationPermission,
  bluetoothPermissions,
  bluetoothPower,
  pairConsole,
  connectConsole,
}

class RideStartGateItem {
  const RideStartGateItem({
    required this.requirement,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.isComplete,
  });

  final RideStartRequirement requirement;
  final String title;
  final String description;
  final String actionLabel;
  final bool isComplete;
}

class RideStartReadiness {
  const RideStartReadiness(this.items);

  final List<RideStartGateItem> items;

  List<RideStartGateItem> get missingItems =>
      items.where((item) => !item.isComplete).toList(growable: false);

  bool get canStart => missingItems.isEmpty;
}

class RideStartGateService {
  const RideStartGateService();

  Future<RideStartReadiness> check(BikeConsoleController controller) async {
    final locationPermission = await Permission.locationWhenInUse.status;
    final notificationPermission = await Permission.notification.status;
    final bluetoothScanPermission = await Permission.bluetoothScan.status;
    final bluetoothConnectPermission = await Permission.bluetoothConnect.status;

    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final bluetoothPoweredOn = await _isBluetoothPoweredOn();

    final connection = controller.connectionController;

    return RideStartReadiness([
      RideStartGateItem(
        requirement: RideStartRequirement.locationPermission,
        title: "Allow Location",
        description:
            "Needed for route tracking, GPS fallback, speed estimate, and the foreground ride service.",
        actionLabel: "Allow Location",
        isComplete: locationPermission.isGranted,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.locationServices,
        title: "Turn On Location",
        description: "Device location must be on before a ride can be tracked.",
        actionLabel: "Open Location Settings",
        isComplete: locationServiceEnabled,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.notificationPermission,
        title: "Allow Ride Notification",
        description:
            "Needed so the active ride controls stay visible while the app is backgrounded.",
        actionLabel: "Allow Notification",
        isComplete: notificationPermission.isGranted,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.bluetoothPermissions,
        title: "Allow Bluetooth",
        description: "Needed to find and connect to the ESP32 console.",
        actionLabel: "Allow Bluetooth",
        isComplete:
            bluetoothScanPermission.isGranted &&
            bluetoothConnectPermission.isGranted,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.bluetoothPower,
        title: "Turn On Bluetooth",
        description: "Bluetooth must be on to connect to the console.",
        actionLabel: "Turn On Bluetooth",
        isComplete: bluetoothPoweredOn,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.pairConsole,
        title: "Pair a Console",
        description:
            "Select your Bike Console once. The app will reconnect automatically after that.",
        actionLabel: "Pair Console",
        isComplete: connection.hasSavedConsole,
      ),
      RideStartGateItem(
        requirement: RideStartRequirement.connectConsole,
        title: "Connect Console",
        description:
            "The first ride start still requires the ESP32 console. GPS is used as fallback after a ride is active.",
        actionLabel: "Connect",
        isComplete: connection.isConnected,
      ),
    ]);
  }

  Future<void> requestLocationPermission() async {
    await Permission.locationWhenInUse.request();
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> requestNotificationPermission() async {
    await Permission.notification.request();
  }

  Future<void> requestBluetoothPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
  }

  Future<void> requestBluetoothPower() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      await openAppSettings();
    }
  }

  Future<bool> _isBluetoothPoweredOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(milliseconds: 800),
      );

      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }
}
'''

write("lib/services/ride_start_gate_service.dart", ride_start_gate_service)

ride_bar_path = "lib/widgets/ride_control_bar.dart"
ride_bar = read(ride_bar_path)

ride_bar = replace_once(
    ride_bar,
    "    required this.onStop,\n  });",
    "    required this.onStop,\n    this.onBlockedStart,\n  });",
    "RideControlBar constructor onBlockedStart",
)

ride_bar = replace_once(
    ride_bar,
    "  final VoidCallback onStop;\n",
    "  final VoidCallback onStop;\n  final VoidCallback? onBlockedStart;\n",
    "RideControlBar onBlockedStart field",
)

ride_bar = replace_once(
    ride_bar,
    "  VoidCallback get onStop => widget.onStop;\n",
    "  VoidCallback get onStop => widget.onStop;\n  VoidCallback? get onBlockedStart => widget.onBlockedStart;\n",
    "RideControlBar onBlockedStart getter",
)

ride_bar = replace_once(
    ride_bar,
    '''  void _handleBlockedStartTap() {
    AppHaptics.mediumImpact();
    _blockedTapController.forward(from: 0);
  }''',
    '''  void _handleBlockedStartTap() {
    AppHaptics.mediumImpact();

    final handler = onBlockedStart;
    if (handler != null) {
      handler();
      return;
    }

    _blockedTapController.forward(from: 0);
  }''',
    "RideControlBar blocked start handler",
)

ride_bar = ride_bar.replace('"Connect a Console"', '"Set Up Ride"', 1)

write(ride_bar_path, ride_bar)

dashboard_path = "lib/screens/dashboard_screen.dart"
dashboard = read(dashboard_path)

dashboard = replace_once(
    dashboard,
    "import 'package:flutter/material.dart';\nimport 'package:google_maps_flutter/google_maps_flutter.dart';",
    "import 'package:flutter/material.dart';\nimport 'package:flutter_blue_plus/flutter_blue_plus.dart';\nimport 'package:google_maps_flutter/google_maps_flutter.dart';",
    "dashboard flutter_blue_plus import",
)

dashboard = replace_once(
    dashboard,
    "import '../services/app_haptics.dart';\nimport '../theme/app_colors.dart';",
    "import '../services/app_haptics.dart';\nimport '../services/ride_start_gate_service.dart';\nimport '../theme/app_colors.dart';",
    "dashboard ride start gate import",
)

dashboard = replace_once(
    dashboard,
    "import 'settings_screen.dart';\nimport 'sessions_screen.dart';",
    "import 'settings_screen.dart';\nimport 'sessions_screen.dart';\nimport 'scan_for_devices_screen.dart';",
    "dashboard scan screen import",
)

dashboard = replace_once(
    dashboard,
    "  late final MapTrackingController _mapTrackingController;\n  late final AnimationController _recenterPulseController;",
    "  late final MapTrackingController _mapTrackingController;\n  final RideStartGateService _rideStartGateService = const RideStartGateService();\n  late final AnimationController _recenterPulseController;",
    "dashboard ride start gate field",
)

old_start = '''  Future<void> _startRideWithCountdown() async {
    final rideController = widget.bikeConsoleController.rideSessionController;

    if (!rideController.canStartRide) return;

    rideController.beginCountdown();

    for (final value in [3, 2, 1]) {
      if (!mounted) return;

      setState(() {
        _countdownValue = value;
      });

      AppHaptics.lightImpact();

      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (!mounted) return;

    setState(() {
      _countdownValue = null;
    });

    // Let Flutter render one clean frame with the overlay removed while the
    // control bar is still in its wide green "Starting" state.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;

    AppHaptics.mediumImpact();
    rideController.finishCountdownAndStartRide();
  }'''

new_start = '''  Future<void> _handleSmartStart() async {
    final readiness = await _rideStartGateService.check(
      widget.bikeConsoleController,
    );

    if (!mounted) return;

    if (readiness.canStart) {
      await _startRideWithCountdown();
      return;
    }

    AppHaptics.mediumImpact();

    final action = await _showRideSetupSheet(readiness);
    if (action == null || !mounted) return;

    await _handleRideSetupAction(action);
  }

  Future<void> _handleRideSetupAction(RideStartRequirement requirement) async {
    switch (requirement) {
      case RideStartRequirement.locationPermission:
        await _rideStartGateService.requestLocationPermission();
        break;
      case RideStartRequirement.locationServices:
        await _rideStartGateService.openLocationSettings();
        break;
      case RideStartRequirement.notificationPermission:
        await _rideStartGateService.requestNotificationPermission();
        break;
      case RideStartRequirement.bluetoothPermissions:
        await _rideStartGateService.requestBluetoothPermissions();
        break;
      case RideStartRequirement.bluetoothPower:
        await _rideStartGateService.requestBluetoothPower();
        break;
      case RideStartRequirement.pairConsole:
        final BluetoothDevice? selected = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScanForDevicesScreen()),
        );

        if (selected != null) {
          await widget.bikeConsoleController.connectionController
              .pairWithDevice(selected);
        }
        break;
      case RideStartRequirement.connectConsole:
        await widget.bikeConsoleController.connectionController.reconnectNow();
        break;
    }

    if (!mounted) return;

    // Let permission dialogs, Bluetooth state, and BLE callbacks settle before
    // deciding whether to start or show the next missing setup item.
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    final nextReadiness = await _rideStartGateService.check(
      widget.bikeConsoleController,
    );

    if (!mounted) return;

    if (nextReadiness.canStart) {
      await _startRideWithCountdown();
      return;
    }

    await _showRideSetupSheet(nextReadiness);
  }

  Future<RideStartRequirement?> _showRideSetupSheet(
    RideStartReadiness readiness,
  ) {
    return showModalBottomSheet<RideStartRequirement>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _RideSetupSheet(readiness: readiness);
      },
    );
  }

  Future<void> _startRideWithCountdown() async {
    final rideController = widget.bikeConsoleController.rideSessionController;

    if (!rideController.canStartRide) return;

    rideController.beginCountdown();

    for (final value in [3, 2, 1]) {
      if (!mounted) return;

      setState(() {
        _countdownValue = value;
      });

      AppHaptics.lightImpact();

      await Future.delayed(const Duration(milliseconds: 800));
    }

    if (!mounted) return;

    setState(() {
      _countdownValue = null;
    });

    // Let Flutter render one clean frame with the overlay removed while the
    // control bar is still in its wide green "Starting" state.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;

    AppHaptics.mediumImpact();
    rideController.finishCountdownAndStartRide();
  }'''

dashboard = replace_once(
    dashboard,
    old_start,
    new_start,
    "dashboard smart start flow",
)

dashboard = replace_once(
    dashboard,
    '''                          canStart: widget
                              .bikeConsoleController
                              .rideSessionController
                              .canStartRide,
''',
    '''                          canStart: rideState.rideState == RideState.stopped,
''',
    "dashboard RideControlBar canStart",
)

dashboard = replace_once(
    dashboard,
    "                          onStart: _startRideWithCountdown,\n",
    "                          onStart: _handleSmartStart,\n                          onBlockedStart: _handleSmartStart,\n",
    "dashboard RideControlBar onStart",
)

setup_sheet = r'''
class _RideSetupSheet extends StatelessWidget {
  const _RideSetupSheet({required this.readiness});

  final RideStartReadiness readiness;

  @override
  Widget build(BuildContext context) {
    final missingItems = readiness.missingItems;
    final firstMissing = missingItems.isNotEmpty ? missingItems.first : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.premiumGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.premiumGreen.withValues(alpha: 0.24),
                        ),
                      ),
                      child: const Icon(
                        Icons.directions_bike_rounded,
                        color: AppColors.premiumGreen,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Ready to Ride",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "Finish these one-time setup checks before starting.",
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
                const SizedBox(height: 18),
                for (final item in readiness.items) ...[
                  _RideSetupStepTile(
                    item: item,
                    isPrimaryAction: item == firstMissing,
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: firstMissing == null
                        ? () => Navigator.pop(context)
                        : () => Navigator.pop(context, firstMissing.requirement),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: firstMissing == null
                          ? AppColors.premiumGreen
                          : Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: Text(
                      firstMissing?.actionLabel ?? "Done",
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RideSetupStepTile extends StatelessWidget {
  const _RideSetupStepTile({
    required this.item,
    required this.isPrimaryAction,
  });

  final RideStartGateItem item;
  final bool isPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final complete = item.isComplete;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: complete
            ? AppColors.premiumGreen.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: isPrimaryAction ? 0.075 : 0.045),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: complete
              ? AppColors.premiumGreen.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: isPrimaryAction ? 0.16 : 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: complete
                  ? AppColors.premiumGreen
                  : Colors.white.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              complete ? Icons.check_rounded : Icons.arrow_forward_rounded,
              color: complete ? Colors.black : Colors.white70,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: complete
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.92),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12.2,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
'''

dashboard = dashboard.replace(
    "\nclass _HeaderSessionsButton extends StatelessWidget {",
    setup_sheet + "\nclass _HeaderSessionsButton extends StatelessWidget {",
    1,
)

write(dashboard_path, dashboard)

print("Batch 6A Smart Start patch applied.")
