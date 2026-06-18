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


# ---------------------------------------------------------------------------
# RideStartGateService: denied location permission should not trap Smart Start.
# If Android refuses to show the permission dialog again or the user denies it,
# send them to the app settings page and return control cleanly.
# ---------------------------------------------------------------------------
gate_path = "lib/services/ride_start_gate_service.dart"
gate = read(gate_path)

gate = replace_once(
    gate,
    '''  Future<void> requestLocationPermission() async {
    await Permission.locationWhenInUse.request();
  }''',
    '''  Future<bool> requestLocationPermission() async {
    final before = await Permission.locationWhenInUse.status;

    if (before.isPermanentlyDenied || before.isRestricted) {
      await openAppSettings();
      return true;
    }

    final after = await Permission.locationWhenInUse.request();

    if (after.isGranted) {
      return false;
    }

    // On some Android builds, a second request after a denial may immediately
    // return denied without showing the dialog again. Open app settings instead
    // of looping the Smart Start sheet forever.
    await openAppSettings();
    return true;
  }''',
    "RideStartGateService denied location fallback",
)

write(gate_path, gate)


# ---------------------------------------------------------------------------
# Dashboard: if a setup action opens external settings, do not immediately
# re-open the setup sheet or start recursion. Let the user return and tap again.
# ---------------------------------------------------------------------------
dashboard_path = "lib/screens/dashboard_screen.dart"
dashboard = read(dashboard_path)

dashboard = replace_once(
    dashboard,
    '''      case RideStartRequirement.locationPermission:
        await _rideStartGateService.requestLocationPermission();
        break;''',
    '''      case RideStartRequirement.locationPermission:
        final openedSettings = await _rideStartGateService
            .requestLocationPermission();
        if (openedSettings) return;
        break;''',
    "dashboard location permission settings escape",
)

write(dashboard_path, dashboard)


# ---------------------------------------------------------------------------
# Pairing screen: replace the old Material-card screen with a premium dark
# screen matching Bike Console's visual language.
# ---------------------------------------------------------------------------
scan_screen = r'''import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/app_haptics.dart';
import '../theme/app_colors.dart';

class ScanForDevicesScreen extends StatefulWidget {
  const ScanForDevicesScreen({super.key});

  @override
  State<ScanForDevicesScreen> createState() => _ScanForDevicesScreenState();
}

class _ScanForDevicesScreenState extends State<ScanForDevicesScreen> {
  final List<ScanResult> devices = [];
  StreamSubscription<List<ScanResult>>? scanSub;
  Timer? _scanTimer;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> startScan() async {
    await FlutterBluePlus.stopScan();
    await scanSub?.cancel();
    _scanTimer?.cancel();

    if (mounted) {
      setState(() {
        devices.clear();
        _isScanning = true;
      });
    }

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) {
        final name = _deviceName(r);
        return name.toLowerCase().contains("bike");
      }).toList();

      filtered.sort((a, b) => b.rssi.compareTo(a.rssi));

      if (mounted) {
        setState(() {
          devices
            ..clear()
            ..addAll(filtered);
        });
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 30),
      androidUsesFineLocation: false,
    );

    _scanTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
    });
  }

  String _deviceName(ScanResult result) {
    return result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.advName;
  }

  String _signalLabel(int rssi) {
    if (rssi >= -60) return "Strong signal";
    if (rssi >= -75) return "Good signal";
    return "Weak signal";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScanHeader(
                isScanning: _isScanning,
                onRefresh: () {
                  AppHaptics.selectionClick();
                  startScan();
                },
              ),
              const SizedBox(height: 18),
              _ScanHero(isScanning: _isScanning),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Nearby consoles",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Text(
                    _isScanning ? "Scanning" : "Scan complete",
                    style: TextStyle(
                      color: _isScanning
                          ? AppColors.premiumGreen
                          : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: devices.isEmpty
                      ? _EmptyScanState(isScanning: _isScanning)
                      : ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final result = devices[index];
                            final name = _deviceName(result).isNotEmpty
                                ? _deviceName(result)
                                : "Bike Console";

                            return _DeviceCard(
                              name: name,
                              rssi: result.rssi,
                              signalLabel: _signalLabel(result.rssi),
                              onTap: () {
                                AppHaptics.selectionClick();
                                Navigator.pop(context, result.device);
                              },
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({required this.isScanning, required this.onRefresh});

  final bool isScanning;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Pair a Console",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Choose your ESP32 Bike Console",
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _HeaderButton(
          icon: isScanning ? Icons.radar_rounded : Icons.refresh_rounded,
          onTap: onRefresh,
          highlighted: isScanning,
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.premiumGreen.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: highlighted
                ? AppColors.premiumGreen.withValues(alpha: 0.36)
                : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Icon(
          icon,
          color: highlighted ? AppColors.premiumGreen : Colors.white70,
          size: 22,
        ),
      ),
    );
  }
}

class _ScanHero extends StatelessWidget {
  const _ScanHero({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.premiumGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.premiumGreen.withValues(alpha: 0.28),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isScanning)
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.premiumGreen.withValues(alpha: 0.70),
                    ),
                  ),
                const Icon(
                  Icons.bluetooth_searching_rounded,
                  color: AppColors.premiumGreen,
                  size: 28,
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Looking for Bike Console",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Keep your ESP32 powered on and nearby. Tap the console once it appears.",
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12.5,
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

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.name,
    required this.rssi,
    required this.signalLabel,
    required this.onTap,
  });

  final String name;
  final int rssi;
  final String signalLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.premiumGreen.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(
                Icons.memory_rounded,
                color: AppColors.premiumGreen,
                size: 24,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$signalLabel • RSSI $rssi dBm",
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white70,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScanState extends StatelessWidget {
  const _EmptyScanState({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: ValueKey(isScanning),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isScanning)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.premiumGreen,
              ),
            )
          else
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.bluetooth_disabled_rounded,
                color: Colors.white38,
                size: 26,
              ),
            ),
          const SizedBox(height: 16),
          Text(
            isScanning ? "Scanning for your console" : "No console found",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Make sure the ESP32 is powered on and advertising as Bike Console.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12.5,
              height: 1.28,
            ),
          ),
        ],
      ),
    );
  }
}
'''

write("lib/screens/scan_for_devices_screen.dart", scan_screen)

print("Batch 6A hotfix 2 applied.")
