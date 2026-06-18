import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../services/app_haptics.dart';
import '../services/app_settings_service.dart';
import 'bike_connection_controller.dart';
import 'ride_session_controller.dart';

class BikeConsoleController extends ChangeNotifier {
  BikeConsoleController()
    : connectionController = BikeConnectionController(),
      rideSessionController = RideSessionController() {
    rideSessionController.onCommand = (command) {
      connectionController.sendCommand(command);
    };

    connectionController.onPacket = rideSessionController.handleSensorPacket;
    connectionController.onConnectionStateChanged =
        rideSessionController.setConnectionState;

    connectionController.addListener(_notify);
    rideSessionController.addListener(_notify);
  }

  final BikeConnectionController connectionController;
  final RideSessionController rideSessionController;

  final AppSettingsService _appSettingsService = AppSettingsService();

  AppDisplaySettings _displaySettings = AppDisplaySettings.defaults();

  AppDisplaySettings get displaySettings => _displaySettings;

  Future<void> initialize() async {
    _displaySettings = await _appSettingsService.loadDisplaySettings();
    AppHaptics.setEnabled(_displaySettings.hapticFeedbackEnabled);

    await rideSessionController.initialize();
    await connectionController.initialize();
    notifyListeners();
  }

  Future<void> updateDisplaySettings(AppDisplaySettings nextSettings) async {
    _displaySettings = nextSettings;
    AppHaptics.setEnabled(nextSettings.hapticFeedbackEnabled);
    notifyListeners();

    await _appSettingsService.saveDisplaySettings(nextSettings);
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
