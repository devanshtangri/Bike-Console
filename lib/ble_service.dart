import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bike_data.dart';

const String bikeName = "Bike Console";
const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

class BleService {
  static final BleService instance = BleService._internal();

  BleService._internal();

  final bikeData = BikeData.instance;

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? bikeCharacteristic;

  String? savedDeviceId;
  String? savedDeviceName;

  bool connecting = false;
  bool reconnecting = false;

  StreamSubscription<List<int>>? bikeDataSub;
  StreamSubscription<BluetoothConnectionState>? connectionSub;

  Timer? rssiTimer;

  Future<void> init() async {
    await requestBlePermissions();
    await loadSavedDevice();

    if (savedDeviceId != null) {
      startReconnectLoop();
    }
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

    savedDeviceId = prefs.getString("bike_device_id");
    savedDeviceName = prefs.getString("bike_device_name");
  }

  Future<void> saveDevice(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("bike_device_id", device.remoteId.str);
    await prefs.setString(
      "bike_device_name",
      device.platformName.isNotEmpty ? device.platformName : bikeName,
    );

    savedDeviceId = device.remoteId.str;
    savedDeviceName = device.platformName.isNotEmpty
        ? device.platformName
        : bikeName;
  }

  Future<void> reconnectSavedDevice() async {
    if (savedDeviceId == null) return;

    final device = BluetoothDevice.fromId(savedDeviceId!);
    await connectToDevice(device);
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connecting) return;

    connecting = true;
    bikeData.updateStatus("Connecting...");

    try {
      connectionSub?.cancel();

      connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          reconnecting = false;
          bikeData.updateStatus("Connected");
          return;
        }

        bikeData.updateStatus("Disconnected");
        bikeData.clearRideData();

        if (savedDeviceId != null) {
          startReconnectLoop();
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
          bikeData.updateRssi(value);
        } catch (_) {}
      });

      final services = await device.discoverServices();

      for (final service in services) {
        if (service.uuid.str.toLowerCase() == serviceUuid.toLowerCase()) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid.str.toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              bikeCharacteristic = characteristic;

              await characteristic.setNotifyValue(true);

              bikeDataSub?.cancel();

              bikeDataSub = characteristic.onValueReceived.listen((value) {
                try {
                  final text = utf8.decode(value).trim();
                  final data = jsonDecode(text);

                  bikeData.updateFromJson(data);
                } catch (e) {
                  // Ignore bad packets for now
                }
              });

              bikeData.updateStatus("Connected");
              return;
            }
          }
        }
      }

      bikeData.updateStatus("Connected, but characteristic not found");
    } catch (_) {
      bikeData.updateStatus("Connection failed");
    } finally {
      connecting = false;
    }
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

  Future<void> startReconnectLoop() async {
    if (reconnecting) return;
    if (savedDeviceId == null) return;

    reconnecting = true;

    while (reconnecting && savedDeviceId != null) {
      final visible = await isSavedDeviceVisible();

      if (!visible) {
        bikeData.updateStatus("Offline");

        await Future.delayed(const Duration(seconds: 3));
        continue;
      }

      bikeData.updateStatus("Reconnecting...");

      try {
        final device = BluetoothDevice.fromId(savedDeviceId!);

        await connectToDevice(device);

        if (connectedDevice?.isConnected == true) {
          reconnecting = false;
          return;
        }
      } catch (_) {
        bikeData.updateStatus("Disconnected");
      }

      await Future.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> forgetDevice() async {
    await connectedDevice?.disconnect();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("bike_device_id");
    await prefs.remove("bike_device_name");

    await bikeDataSub?.cancel();
    await connectionSub?.cancel();

    rssiTimer?.cancel();

    connectedDevice = null;
    bikeCharacteristic = null;
    savedDeviceId = null;
    savedDeviceName = null;

    bikeData.clearRideData();
    bikeData.updateStatus("No paired device");
  }
}
