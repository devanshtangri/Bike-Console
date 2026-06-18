import 'dart:async';

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
  static final Guid _serviceUuid = Guid('7a8d0001-4f7a-4e6f-9a0b-1f2e3d4c5b6a');
  static const String _consoleName = 'Bike Console';

  final Map<String, ScanResult> _devicesById = {};
  StreamSubscription<List<ScanResult>>? scanSub;
  Timer? _scanTimer;
  bool _isScanning = false;

  List<ScanResult> get _visibleDevices {
    final next = _devicesById.values.toList();
    next.sort((a, b) => b.rssi.compareTo(a.rssi));
    return next;
  }

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
        _isScanning = true;
      });
    }

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      var changed = false;

      for (final result in results) {
        if (!_isMatchingConsole(result)) continue;

        final id = result.device.remoteId.str;
        final previous = _devicesById[id];

        if (previous == null ||
            previous.rssi != result.rssi ||
            _deviceName(previous) != _deviceName(result)) {
          _devicesById[id] = result;
          changed = true;
        }
      }

      if (mounted && changed) {
        setState(() {});
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 30));
    } catch (error) {
      debugPrint('Pairing scan failed: $error');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
      return;
    }

    _scanTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
    });
  }

  bool _isMatchingConsole(ScanResult result) {
    final platformName = result.device.platformName.trim();
    final advName = result.advertisementData.advName.trim();

    final nameMatches = platformName == _consoleName ||
        advName == _consoleName ||
        platformName.toLowerCase().contains('bike') ||
        advName.toLowerCase().contains('bike');

    final serviceMatches = result.advertisementData.serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase() == _serviceUuid.toString().toLowerCase(),
    );

    return nameMatches || serviceMatches;
  }

  String _deviceName(ScanResult result) {
    final platformName = result.device.platformName.trim();
    if (platformName.isNotEmpty) return platformName;

    final advName = result.advertisementData.advName.trim();
    if (advName.isNotEmpty) return advName;

    return _consoleName;
  }

  String _signalLabel(int rssi) {
    if (rssi >= -60) return 'Strong signal';
    if (rssi >= -75) return 'Good signal';
    return 'Weak signal';
  }

  @override
  Widget build(BuildContext context) {
    final visibleDevices = _visibleDevices;

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
                      'Nearby consoles',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Text(
                    _isScanning ? 'Scanning' : 'Scan complete',
                    style: TextStyle(
                      color: _isScanning ? AppColors.premiumGreen : Colors.white38,
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
                  child: visibleDevices.isEmpty
                      ? _EmptyScanState(isScanning: _isScanning)
                      : ListView.separated(
                          itemCount: visibleDevices.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final result = visibleDevices[index];
                            final name = _deviceName(result);

                            return _DeviceCard(
                              key: ValueKey(result.device.remoteId.str),
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
                'Pair a Console',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Choose your Bike Console',
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
                  'Looking for Bike Console',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Keep your Bike Console powered on and nearby. Tap it once it appears.',
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
    super.key,
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
                    '$signalLabel • RSSI $rssi dBm',
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
            isScanning ? 'Scanning for your console' : 'No console found',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Make sure your Bike Console is powered on and nearby.',
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
