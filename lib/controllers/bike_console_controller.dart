import 'dart:async';

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
  StreamSubscription<String>? _foregroundRideActionSubscription;

  AppDisplaySettings get displaySettings => _displaySettings;

  Future<void> initialize() async {
    try {
      _displaySettings = await _appSettingsService.loadDisplaySettings();
      AppHaptics.setEnabled(_displaySettings.hapticFeedbackEnabled);

      _startForegroundRideActionListener();

      await rideSessionController.initialize();
      await _restoreForegroundRideSnapshotIfAvailable();
      await _consumePendingForegroundRideAction();
    } catch (error, stackTrace) {
      debugPrint('Bike Console core initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    _syncForegroundRideService(force: true);
    notifyListeners();

    // A saved-console scan can take several seconds. It should update the
    // connection state in the background, never hold the launch screen.
    unawaited(_initializeConnection());
  }

  Future<void> _initializeConnection() async {
    try {
      await connectionController.initialize();
    } catch (error, stackTrace) {
      debugPrint('Bike Console connection initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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

  void _startForegroundRideActionListener() {
    _foregroundRideActionSubscription?.cancel();

    _foregroundRideActionSubscription = _foregroundRideService
        .notificationActions()
        .listen(
          _handleForegroundRideAction,
          onError: (Object error) {
            debugPrint('Foreground ride action listener failed: $error');
          },
        );
  }

  Future<void> _restoreForegroundRideSnapshotIfAvailable() async {
    final snapshot = await _foregroundRideService.loadActiveRideSnapshot();
    if (snapshot == null) return;

    rideSessionController.restoreFromForegroundServiceSnapshot(snapshot);
  }

  Future<void> _consumePendingForegroundRideAction() async {
    final pendingAction = await _foregroundRideService.consumePendingAction();
    if (pendingAction == null) return;

    _handleForegroundRideAction(pendingAction);
  }

  void _handleForegroundRideAction(String action) {
    switch (action) {
      case 'pause':
        rideSessionController.manualPauseRide();
        break;
      case 'resume':
        rideSessionController.resumeRide(
          suppressAutoPauseUntilMovement: true,
        );
        break;
      case 'stop':
        rideSessionController.stopRide();
        break;
      default:
        debugPrint('Unknown foreground ride action: $action');
    }
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
    _foregroundRideActionSubscription?.cancel();

    connectionController.dispose();
    rideSessionController.dispose();

    super.dispose();
  }
}
