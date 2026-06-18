import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
            "Needed for route tracking, speed estimate, and active ride protection.",
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
        description: "Needed to find and connect to your Bike Console.",
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
            "Your Bike Console must be connected before starting a ride.",
        actionLabel: "Connect",
        isComplete: connection.isConnected,
      ),
    ]);
  }

  Future<bool> requestLocationPermission() async {
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
