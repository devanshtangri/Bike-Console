import 'package:flutter/foundation.dart';

import 'bike_connection_controller.dart';
import 'ride_session_controller.dart';

class BikeConsoleController extends ChangeNotifier {
  BikeConsoleController()
    : connectionController = BikeConnectionController(),
      rideSessionController = RideSessionController() {
    rideSessionController.onCommand = connectionController.sendCommand;

    connectionController.onPacket = rideSessionController.handleSensorPacket;
    connectionController.onConnectionStateChanged =
        rideSessionController.setConnectionState;

    connectionController.addListener(_notify);
    rideSessionController.addListener(_notify);
  }

  final BikeConnectionController connectionController;
  final RideSessionController rideSessionController;

  Future<void> initialize() async {
    await rideSessionController.initialize();
  }

  void injectDebugSensorPacket({
    double rpm = 90,
    double distanceKm = 0.25,
    bool isMoving = true,
    bool leftPhysical = false,
    bool rightPhysical = false,
    bool hazardOutput = false,
    bool consoleRideActive = true,
  }) {
    final raw =
        '''
{
  "rpm": $rpm,
  "distance": $distanceKm,
  "moving": $isMoving,
  "leftPhysical": $leftPhysical,
  "rightPhysical": $rightPhysical,
  "hazardOutput": $hazardOutput,
  "consoleActive": $consoleRideActive
}
''';

    connectionController.handleIncomingJson(raw);
  }

  void _notify() {
    notifyListeners();
  }

  @override
  void dispose() {
    connectionController.removeListener(_notify);
    rideSessionController.removeListener(_notify);

    connectionController.dispose();
    rideSessionController.dispose();

    super.dispose();
  }
}
