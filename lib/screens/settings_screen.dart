import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bike_data.dart';
import '../ble_service.dart';
import 'scan_for_devices_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? rpmCharacteristic;

  final bikeData = BikeData.instance;
  final bleService = BleService.instance;

  String status = "Disconnected";
  String? savedDeviceId;
  String? savedDeviceName;
  int? speed;
  int? rpm;
  double? distance;
  double? avgSpeed;
  int? maxSpeed;

  bool leftIndicator = false;
  bool rightIndicator = false;
  bool hazard = false;

  int? rssi;

  bool connecting = false;
  bool reconnecting = false;

  StreamSubscription<List<ScanResult>>? scanSub;
  StreamSubscription<List<int>>? rpmSub;
  StreamSubscription<BluetoothConnectionState>? connectionSub;
  StreamSubscription<BluetoothBondState>? bondSub;

  Timer? rssiTimer;

  @override
  void initState() {
    super.initState();

    final bike = BikeData.instance;

    speed = bike.speed;
    rpm = bike.rpm;
    distance = bike.distance;
    avgSpeed = bike.avgSpeed;
    maxSpeed = bike.maxSpeed;

    leftIndicator = bike.leftIndicator;
    rightIndicator = bike.rightIndicator;
    hazard = bike.hazard;

    rssi = bike.rssi;
    status = bike.status;

    bike.addListener(_bikeDataListener);
  }

  @override
  void dispose() {
    BikeData.instance.removeListener(_bikeDataListener);
    super.dispose();
  }

  Future<void> requestBlePermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> loadSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();

    final deviceId = prefs.getString("bike_device_id");
    final deviceName = prefs.getString("bike_device_name");

    setState(() {
      savedDeviceId = deviceId;
      savedDeviceName = deviceName;
    });

    if (deviceId != null) {
      setState(() {
        status = "Reconnecting...";
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        reconnectSavedDevice();
      });
    }
  }

  Future<void> saveDevice(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("bike_device_id", device.remoteId.str);
    await prefs.setString(
      "bike_device_name",
      device.platformName.isNotEmpty ? device.platformName : bikeName,
    );

    setState(() {
      savedDeviceId = device.remoteId.str;
      savedDeviceName = device.platformName.isNotEmpty
          ? device.platformName
          : bikeName;
    });
  }

  Future<void> forgetDevice() async {
    await connectedDevice?.disconnect();
    reconnecting = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("bike_device_id");
    await prefs.remove("bike_device_name");

    await rpmSub?.cancel();
    await connectionSub?.cancel();
    await bondSub?.cancel();

    setState(() {
      connectedDevice = null;
      rpmCharacteristic = null;
      savedDeviceId = null;
      savedDeviceName = null;

      speed = null;
      rpm = null;
      distance = null;
      avgSpeed = null;
      maxSpeed = null;

      leftIndicator = false;
      rightIndicator = false;
      hazard = false;

      rssi = null;
      status = "No paired device";
    });
  }

  Future<bool> isSavedDeviceVisible() async {
    if (savedDeviceId == null) return false;

    final completer = Completer<bool>();

    StreamSubscription<List<ScanResult>>? tempSub;

    tempSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (result.device.remoteId.str == savedDeviceId) {
          tempSub?.cancel();

          if (!completer.isCompleted) {
            completer.complete(true);
          }
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 3),
      androidUsesFineLocation: false,
    );

    await Future.delayed(const Duration(seconds: 3));

    await tempSub.cancel();
    await FlutterBluePlus.stopScan();

    if (!completer.isCompleted) {
      completer.complete(false);
    }

    return completer.future;
  }

  Future<void> reconnectSavedDevice() async {
    if (savedDeviceId == null) return;

    await requestBlePermissions();

    final device = BluetoothDevice.fromId(savedDeviceId!);
    await connectToDevice(device);
  }

  Future<void> startReconnectLoop() async {
    if (reconnecting) return;
    if (savedDeviceId == null) return;

    reconnecting = true;

    while (reconnecting && mounted) {
      if (status == "Connected") {
        reconnecting = false;
        return;
      }
      final visible = await isSavedDeviceVisible();

      if (!visible) {
        if (status == "Connected") {
          reconnecting = false;
          return;
        }

        setState(() {
          status = "Offline";
        });

        await Future.delayed(const Duration(seconds: 2));
        continue;
      }

      setState(() {
        status = "Disconnected";
      });

      await Future.delayed(const Duration(seconds: 1));

      try {
        setState(() {
          status = "Reconnecting...";
        });

        await reconnectSavedDevice();

        if (connectedDevice?.isConnected == true) {
          reconnecting = false;
          return;
        }

        setState(() {
          status = "Reconnection Failed";
        });
      } catch (_) {
        setState(() {
          status = "Reconnection Failed";
        });
      }

      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connecting) return;

    setState(() {
      connecting = true;
      status = "Connecting...";
    });

    try {
      connectionSub?.cancel();
      connectionSub = device.connectionState.listen((state) async {
        if (!mounted) return;

        if (state == BluetoothConnectionState.connected) {
          reconnecting = false;

          setState(() {
            status = "Connected";
          });

          bikeData.updateStatus("Connected");

          return;
        }

        setState(() {
          status = "Disconnected";
          rssi = null;

          speed = null;
          rpm = null;
          distance = null;
          avgSpeed = null;
          maxSpeed = null;

          leftIndicator = false;
          rightIndicator = false;
          hazard = false;
        });

        bikeData.updateStatus("Disconnected");
        bikeData.clearRideData();

        if (savedDeviceId != null) {
          startReconnectLoop();
        }
      });

      bondSub?.cancel();
      bondSub = device.bondState.listen((bondState) async {
        if (bondState == BluetoothBondState.none && savedDeviceId != null) {
          // This only matters if ESP32 bonding/security is enabled later.
          // For your current BLE code, Android usually will not create a bond.
        }
      });

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );

      connectedDevice = device;
      await saveDevice(device);

      rssiTimer?.cancel();

      rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final value = await device.readRssi();

          if (mounted) {
            setState(() {
              rssi = value;
            });

            bikeData.updateRssi(value);
          }
        } catch (_) {}
      });

      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.str.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.str.toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              rpmCharacteristic = characteristic;

              await characteristic.setNotifyValue(true);

              rpmSub?.cancel();
              rpmSub = characteristic.onValueReceived.listen((value) {
                try {
                  final text = utf8.decode(value).trim();

                  final data = jsonDecode(text);

                  if (!mounted) return;

                  setState(() {
                    speed = data["speed"];
                    rpm = data["rpm"];

                    distance = (data["distance"] as num).toDouble();
                    avgSpeed = (data["avgSpeed"] as num).toDouble();

                    maxSpeed = data["maxSpeed"];

                    leftIndicator = data["left"] ?? false;
                    rightIndicator = data["right"] ?? false;
                    hazard = data["hazard"] ?? false;
                  });

                  bikeData.updateFromJson(data);
                } catch (e) {
                  debugPrint("JSON Error: $e");
                }
              });

              setState(() {
                status = "Connected";
              });

              return;
            }
          }
        }
      }

      setState(() {
        status = "Connected, but RPM characteristic not found";
      });
    } catch (e) {
      setState(() {
        status = "Connection failed";
      });
    } finally {
      setState(() {
        connecting = false;
      });
    }
  }

  Future<void> disconnect() async {
    await connectedDevice?.disconnect();

    setState(() {
      connectedDevice = null;
      rpmCharacteristic = null;

      speed = null;
      rpm = null;
      distance = null;
      avgSpeed = null;
      maxSpeed = null;

      leftIndicator = false;
      rightIndicator = false;
      hazard = false;

      rssi = null;
      status = "Disconnected";
    });
  }

  void _bikeDataListener() {
    if (!mounted) return;

    final bike = BikeData.instance;

    setState(() {
      speed = bike.speed;
      rpm = bike.rpm;
      distance = bike.distance;
      avgSpeed = bike.avgSpeed;
      maxSpeed = bike.maxSpeed;

      leftIndicator = bike.leftIndicator;
      rightIndicator = bike.rightIndicator;
      hazard = bike.hazard;

      rssi = bike.rssi;
      status = bike.status;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSavedDevice = BleService.instance.savedDeviceId != null;

    return Scaffold(
      appBar: AppBar(title: const Text("Bike Console Settings")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Bluetooth Device",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text("Status: $status"),
                    const SizedBox(height: 8),
                    Text("Signal: ${rssi != null ? "$rssi dBm" : "-"}"),
                    const SizedBox(height: 8),
                    Text(
                      "Device: ${BleService.instance.savedDeviceName ?? "None"}",
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "RPM: ${rpm ?? "-"}",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("Speed: ${speed ?? "-"} km/h"),

                    const SizedBox(height: 8),
                    Text("Distance: ${distance?.toStringAsFixed(2) ?? "-"} km"),

                    const SizedBox(height: 8),
                    Text(
                      "Avg Speed: ${avgSpeed?.toStringAsFixed(1) ?? "-"} km/h",
                    ),

                    const SizedBox(height: 8),
                    Text("Max Speed: ${maxSpeed ?? "-"} km/h"),

                    const SizedBox(height: 8),
                    Text("Left Indicator: $leftIndicator"),

                    const SizedBox(height: 8),
                    Text("Right Indicator: $rightIndicator"),

                    const SizedBox(height: 8),
                    Text("Hazard: $hazard"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (!hasSavedDevice)
              ElevatedButton(
                onPressed: () async {
                  final BluetoothDevice? selected = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScanForDevicesScreen(),
                    ),
                  );

                  if (selected != null) {
                    await BleService.instance.connectToDevice(selected);
                  }
                },
                child: const Text("Pair a Device"),
              ),

            if (hasSavedDevice)
              OutlinedButton(
                onPressed: BleService.instance.forgetDevice,
                child: const Text("Forget Device"),
              ),
          ],
        ),
      ),
    );
  }
}
