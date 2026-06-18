import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/ride_models.dart';
import '../services/app_haptics.dart';
import '../services/app_settings_service.dart';
import '../services/foreground_ride_service.dart';
import 'bike_connection_controller.dart';
import 'ride_session_controller.dart';

class BikeConsoleController extends ChangeNotifier {
  BikeConsoleController({ForegroundRideService? foregroundRideService})
    : connectionController = BikeConnectionController(),
      rideSessionController = RideSessionController(),
      _foregroundRideService =
          foregroundRideService ?? const ForegroundRideService() {
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

  final ForegroundRideService _foregroundRideService;
  final AppSettingsService _appSettingsService = AppSettingsService();

  static const int _foregroundNotificationUpdateThrottleMs = 1000;

  AppDisplaySettings _displaySettings = AppDisplaySettings.defaults();
  RideState _lastForegroundRideState = RideState.stopped;
  bool _foregroundRideServiceActive = false;
  int? _lastForegroundNotificationUpdateEpochMs;

  AppDisplaySettings get displaySettings => _displaySettings;

  Future<void> initialize() async {
    _displaySettings = await _appSettingsService.loadDisplaySettings();
    AppHaptics.setEnabled(_displaySettings.hapticFeedbackEnabled);

    await rideSessionController.initialize();
    await connectionController.initialize();
    _syncForegroundRideService(force: true);
    notifyListeners();
  }

  Future<void> updateDisplaySettings(AppDisplaySettings nextSettings) async {
    _displaySettings = nextSettings;
    AppHaptics.setEnabled(nextSettings.hapticFeedbackEnabled);
    notifyListeners();

    await _appSettingsService.saveDisplaySettings(nextSettings);
  }

  void _notify() {
    _syncForegroundRideService();
    notifyListeners();
  }

  void _syncForegroundRideService({bool force = false}) {
    final state = rideSessionController.state;
    final currentRideState = state.rideState;

    if (currentRideState == RideState.countdown) {
      _lastForegroundRideState = currentRideState;
      return;
    }

    final stateChanged = currentRideState != _lastForegroundRideState;
    final shouldForce = force || stateChanged;
    final elapsedActiveMs = rideSessionController.calculateActiveDurationMs();

    if (currentRideState == RideState.running) {
      if (!_foregroundRideServiceActive || shouldForce) {
        _foregroundRideService.start(
          distanceKm: state.distanceKm,
          elapsedActiveMs: elapsedActiveMs,
        );
        _foregroundRideServiceActive = true;
        _markForegroundNotificationUpdated();
      } else {
        _updateForegroundRideNotificationIfNeeded(
          distanceKm: state.distanceKm,
          elapsedActiveMs: elapsedActiveMs,
          paused: false,
          force: shouldForce,
        );
      }
    } else if (currentRideState == RideState.paused) {
      if (!_foregroundRideServiceActive || shouldForce) {
        _foregroundRideService.pause(
          distanceKm: state.distanceKm,
          elapsedActiveMs: elapsedActiveMs,
        );
        _foregroundRideServiceActive = true;
        _markForegroundNotificationUpdated();
      } else {
        _updateForegroundRideNotificationIfNeeded(
          distanceKm: state.distanceKm,
          elapsedActiveMs: elapsedActiveMs,
          paused: true,
          force: shouldForce,
        );
      }
    } else if (currentRideState == RideState.stopped) {
      if (_foregroundRideServiceActive ||
          _lastForegroundRideState != RideState.stopped) {
        _foregroundRideService.stop();
      }

      _foregroundRideServiceActive = false;
      _lastForegroundNotificationUpdateEpochMs = null;
    }

    _lastForegroundRideState = currentRideState;
  }

  void _updateForegroundRideNotificationIfNeeded({
    required double distanceKm,
    required int elapsedActiveMs,
    required bool paused,
    required bool force,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force &&
        _lastForegroundNotificationUpdateEpochMs != null &&
        now - _lastForegroundNotificationUpdateEpochMs! <
            _foregroundNotificationUpdateThrottleMs) {
      return;
    }

    _foregroundRideService.update(
      distanceKm: distanceKm,
      elapsedActiveMs: elapsedActiveMs,
      paused: paused,
    );

    _markForegroundNotificationUpdated(nowEpochMs: now);
  }

  void _markForegroundNotificationUpdated({int? nowEpochMs}) {
    _lastForegroundNotificationUpdateEpochMs =
        nowEpochMs ?? DateTime.now().millisecondsSinceEpoch;
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
