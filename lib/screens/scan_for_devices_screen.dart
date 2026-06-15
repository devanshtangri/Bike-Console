import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class ScanForDevicesScreen extends StatefulWidget {
  const ScanForDevicesScreen({super.key});

  @override
  State<ScanForDevicesScreen> createState() => _ScanForDevicesScreenState();
}

class _ScanForDevicesScreenState extends State<ScanForDevicesScreen> {
  List<ScanResult> devices = [];
  StreamSubscription<List<ScanResult>>? scanSub;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  void dispose() {
    scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> startScan() async {
    await FlutterBluePlus.stopScan();

    scanSub?.cancel();

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;

        return name.toLowerCase().contains("bike");
      }).toList();

      if (mounted) {
        setState(() {
          devices = filtered;
        });
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 30),
      androidUsesFineLocation: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pair a Device")),
      body: devices.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final result = devices[index];

                final name = result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : result.advertisementData.advName;

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text("RSSI: ${result.rssi} dBm"),
                    trailing: const Icon(Icons.bluetooth),
                    onTap: () {
                      Navigator.pop(context, result.device);
                    },
                  ),
                );
              },
            ),
    );
  }
}