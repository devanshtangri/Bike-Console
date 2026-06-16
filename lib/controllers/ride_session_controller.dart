import 'package:flutter/foundation.dart';

import '../models/ride_models.dart';
import '../services/ride_persistence_service.dart';

class RideSessionController extends ChangeNotifier {
  RideSessionController({
    this.onCommand,
    RidePersistenceService? persistenceService,
  }) : _persistenceService = persistenceService ?? RidePersistenceService();

  void Function(BikeCommand command)? onCommand;
  final RidePersistenceService _persistenceService;

  RideSessionState _state = RideSessionState.initial();
  RideSettings _settings = RideSettings.defaults();
  ConsoleConnectionState _connectionState = ConsoleConnectionState.disconnected;
  int? _lastMovingEpochMs;
  int? _lastSnapshotSaveEpochMs;

  RideSessionState get state => _state;
  RideSettings get settings => _settings;
  ConsoleConnectionState get connectionState => _connectionState;

  bool get isConsoleConnected =>
      _connectionState == ConsoleConnectionState.connected;

  bool get canStartRide =>
      isConsoleConnected && _state.rideState == RideState.stopped;

  Future<void> initialize() async {
    _settings = await _persistenceService.loadSettings();

    final snapshot = await _persistenceService.loadRideSnapshot();

    if (snapshot != null) {
      restoreFromSnapshot(snapshot);
      return;
    }

    notifyListeners();
  }

  void setConnectionState(ConsoleConnectionState value) {
    if (_connectionState == value) return;

    _connectionState = value;

    if (!isConsoleConnected) {
      _state = _state.copyWith(
        currentRpm: 0,
        currentSpeedKmph: 0,
        speedSource: SpeedSource.none,
      );
    }

    notifyListeners();
  }

  Future<void> updateSettings(RideSettings value) async {
    _settings = value;

    _state = _state.copyWith(
      currentSpeedKmph: _speedFromRpm(_state.currentRpm),
    );

    await _persistenceService.saveSettings(_settings);

    onCommand?.call(
      BikeCommand.setCircumference(_settings.tyreCircumferenceMeters),
    );

    notifyListeners();
  }

  void restoreFromSnapshot(PersistedRideSnapshot snapshot) {
    _state = snapshot.toSessionState();

    if (_state.rideState == RideState.running) {
      _lastMovingEpochMs = DateTime.now().millisecondsSinceEpoch;
    } else {
      _lastMovingEpochMs = null;
    }

    notifyListeners();
  }

  void handleSensorPacket(BikeSensorPacket packet) {
    final speedKmph = _speedFromRpm(packet.rpm);
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    if (packet.isMoving) {
      _lastMovingEpochMs = nowEpochMs;

      if (_state.rideState == RideState.paused &&
          _state.pauseReason == PauseReason.auto) {
        resumeRide(resumeEpochMs: nowEpochMs);
      }
    } else {
      _checkAutoPause(nowEpochMs);
    }

    final nextMaxSpeed = _state.isRideActive && speedKmph > _state.maxSpeedKmph
        ? speedKmph
        : _state.maxSpeedKmph;

    final nextDistanceKm = _state.isRideActive ? packet.distanceKm : 0.0;

    final activeDurationMs = calculateActiveDurationMs();

    final nextAverageSpeed = _state.isRideActive && activeDurationMs > 0
        ? nextDistanceKm / (activeDurationMs / 3600000.0)
        : 0.0;

    _state = _state.copyWith(
      currentRpm: packet.rpm,
      currentSpeedKmph: speedKmph,
      speedSource: SpeedSource.wheel,
      distanceKm: nextDistanceKm,
      maxSpeedKmph: nextMaxSpeed,
      averageSpeedKmph: nextAverageSpeed,
    );
    _persistSnapshotFireAndForget();
    notifyListeners();
  }

  void toggleHazard() {
    final nextHazardState = !_state.hazardEnabled;

    _state = _state.copyWith(hazardEnabled: nextHazardState);

    onCommand?.call(BikeCommand.hazard(nextHazardState));
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void beginCountdown() {
    if (!canStartRide) return;

    _state = _state.copyWith(
      rideState: RideState.countdown,
      pauseReason: PauseReason.none,
      clearRideStartEpochMs: true,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs: 0,
      distanceKm: 0,
      averageSpeedKmph: 0,
      maxSpeedKmph: 0,
      speedSource: SpeedSource.wheel,
    );
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void finishCountdownAndStartRide({int? startEpochMs}) {
    if (_state.rideState != RideState.countdown) return;

    _state = _state.copyWith(
      rideState: RideState.running,
      pauseReason: PauseReason.none,
      rideStartEpochMs: startEpochMs ?? DateTime.now().millisecondsSinceEpoch,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs: 0,
      distanceKm: 0,
      averageSpeedKmph: 0,
      maxSpeedKmph: 0,
    );

    onCommand?.call(
      BikeCommand.start(
        tyreCircumferenceMeters: _settings.tyreCircumferenceMeters,
        distanceKm: 0,
      ),
    );
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void manualPauseRide({int? pauseEpochMs}) {
    if (_state.rideState != RideState.running) return;

    _state = _state.copyWith(
      rideState: RideState.paused,
      pauseReason: PauseReason.manual,
      currentPauseStartEpochMs:
          pauseEpochMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    onCommand?.call(BikeCommand.pause());
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void autoPauseRide({int? pauseEpochMs}) {
    if (_state.rideState != RideState.running) return;

    _state = _state.copyWith(
      rideState: RideState.paused,
      pauseReason: PauseReason.auto,
      currentPauseStartEpochMs:
          pauseEpochMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    onCommand?.call(BikeCommand.pause());
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void resumeRide({int? resumeEpochMs}) {
    if (_state.rideState != RideState.paused) return;

    final pauseStart = _state.currentPauseStartEpochMs;
    final now = resumeEpochMs ?? DateTime.now().millisecondsSinceEpoch;

    final completedPauseMs = pauseStart == null ? 0 : now - pauseStart;

    _state = _state.copyWith(
      rideState: RideState.running,
      pauseReason: PauseReason.none,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs:
          _state.accumulatedPausedMs + completedPauseMs.clamp(0, 1 << 31),
    );
    onCommand?.call(BikeCommand.resume());
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void stopRide() {
    _state = RideSessionState.initial();
    _lastMovingEpochMs = null;
    _lastSnapshotSaveEpochMs = null;

    onCommand?.call(BikeCommand.stop());
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  int calculateActiveDurationMs({int? nowEpochMs}) {
    final start = _state.rideStartEpochMs;
    if (start == null) return 0;

    final now = nowEpochMs ?? DateTime.now().millisecondsSinceEpoch;

    final currentPauseDurationMs =
        _state.isPaused && _state.currentPauseStartEpochMs != null
        ? now - _state.currentPauseStartEpochMs!
        : 0;

    final activeMs =
        now - start - _state.accumulatedPausedMs - currentPauseDurationMs;

    if (activeMs < 0) return 0;
    return activeMs;
  }

  String formattedActiveDuration({int? nowEpochMs}) {
    final totalSeconds =
        calculateActiveDurationMs(nowEpochMs: nowEpochMs) ~/ 1000;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _persistSnapshotIfNeeded() async {
    if (_state.rideState == RideState.stopped) {
      await _persistenceService.clearRideSnapshot();
      return;
    }

    await _persistenceService.saveRideSnapshot(
      PersistedRideSnapshot.fromSessionState(_state),
    );
  }

  void _persistSnapshotFireAndForget({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force &&
        _lastSnapshotSaveEpochMs != null &&
        now - _lastSnapshotSaveEpochMs! < 2000) {
      return;
    }

    _lastSnapshotSaveEpochMs = now;
    _persistSnapshotIfNeeded();
  }

  void _checkAutoPause(int nowEpochMs) {
    if (!_settings.autoPauseEnabled) return;
    if (_state.rideState != RideState.running) return;

    final lastMoving = _lastMovingEpochMs;
    if (lastMoving == null) return;

    final inactiveMs = nowEpochMs - lastMoving;
    final requiredInactiveMs = _settings.autoPauseSeconds * 1000;

    if (inactiveMs >= requiredInactiveMs) {
      autoPauseRide(pauseEpochMs: nowEpochMs);
    }
  }

  double _speedFromRpm(double rpm) {
    if (rpm <= 0) return 0;

    // rpm * circumference gives meters per minute.
    // multiply by 60 = meters per hour.
    // divide by 1000 = km/h.
    return rpm * _settings.tyreCircumferenceMeters * 60.0 / 1000.0;
  }
}
