import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/ride_models.dart';
import '../models/saved_ride_session.dart';
import '../services/ride_history_service.dart';
import '../services/ride_persistence_service.dart';

class RideSessionController extends ChangeNotifier {
  RideSessionController({
    this.onCommand,
    RidePersistenceService? persistenceService,
    RideHistoryService? rideHistoryService,
  }) : _persistenceService = persistenceService ?? RidePersistenceService(),
       _rideHistoryService = rideHistoryService ?? RideHistoryService();

  void Function(BikeCommand command)? onCommand;

  final RidePersistenceService _persistenceService;
  final RideHistoryService _rideHistoryService;

  static const int _averageSpeedDisplayRefreshMs = 5000;
  static const int _consoleSyncThrottleMs = 1500;
  static const int _minimumSavedRideDurationMs = 60000;
  static const int _indicatorCommandSettleMs = 450;

  RideSessionState _state = RideSessionState.initial();
  RideSettings _settings = RideSettings.defaults();
  ConsoleConnectionState _connectionState = ConsoleConnectionState.disconnected;

  int? _notMovingSinceEpochMs;
  int? _lastSnapshotSaveEpochMs;
  int? _lastAverageSpeedUpdateEpochMs;
  int? _lastConsoleSyncEpochMs;
  int? _lastIndicatorCommandEpochMs;
  bool _autoPauseSuppressedUntilMovement = false;

  Timer? _durationTicker;

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

    if (isConsoleConnected) {
      _syncConsoleStateWithApp(force: true);
    } else {
      _lastIndicatorCommandEpochMs = null;
      _autoPauseSuppressedUntilMovement = false;
      _state = _state.copyWith(
        currentRpm: 0,
        currentSpeedKmph: 0,
        speedSource: SpeedSource.none,
        leftPhysicalIndicator: false,
        rightPhysicalIndicator: false,
        leftOutputActive: false,
        rightOutputActive: false,
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

    _syncConsoleStateWithApp(force: true);

    notifyListeners();
  }


  void editCurrentRideData({
    required double distanceKm,
    required double averageSpeedKmph,
    required double maxSpeedKmph,
    required int activeDurationMs,
  }) {
    if (_state.rideState != RideState.running &&
        _state.rideState != RideState.paused) {
      return;
    }

    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    final safeDistanceKm = distanceKm.isFinite && distanceKm >= 0
        ? distanceKm
        : _state.distanceKm;

    final safeAverageSpeedKmph =
        averageSpeedKmph.isFinite && averageSpeedKmph >= 0
        ? averageSpeedKmph
        : _state.averageSpeedKmph;

    final safeMaxSpeedKmph = maxSpeedKmph.isFinite && maxSpeedKmph >= 0
        ? maxSpeedKmph
        : _state.maxSpeedKmph;

    final safeActiveDurationMs = activeDurationMs
        .clamp(0, 99 * 60 * 60 * 1000)
        .toInt();

    final currentPauseDurationMs =
        _state.isPaused && _state.currentPauseStartEpochMs != null
        ? (nowEpochMs - _state.currentPauseStartEpochMs!)
              .clamp(0, 99 * 60 * 60 * 1000)
              .toInt()
        : 0;

    final nextRideStartEpochMs =
        nowEpochMs - safeActiveDurationMs - currentPauseDurationMs;

    _state = _state.copyWith(
      rideStartEpochMs: nextRideStartEpochMs,
      accumulatedPausedMs: 0,
      distanceKm: safeDistanceKm,
      averageSpeedKmph: safeAverageSpeedKmph,
      maxSpeedKmph: safeMaxSpeedKmph,
    );

    _lastAverageSpeedUpdateEpochMs = nowEpochMs;
    _lastSnapshotSaveEpochMs = null;

    _syncConsoleStateWithApp(force: true);
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void restoreFromSnapshot(PersistedRideSnapshot snapshot) {
    _state = snapshot.toSessionState();

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;
    _autoPauseSuppressedUntilMovement = false;

    if (_state.rideState == RideState.running) {
      _startDurationTicker();
    } else {
      _stopDurationTicker();
    }

    notifyListeners();
  }

  void handleSensorPacket(BikeSensorPacket packet) {
    final speedKmph = _speedFromRpm(packet.rpm);
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    if (packet.isMoving) {
      _notMovingSinceEpochMs = null;
      _autoPauseSuppressedUntilMovement = false;

      if (_state.rideState == RideState.paused &&
          _state.pauseReason == PauseReason.auto) {
        resumeRide(
          resumeEpochMs: nowEpochMs,
          suppressAutoPauseUntilMovement: false,
        );
      }
    } else {
      _checkAutoPause(nowEpochMs);
    }

    final nextMaxSpeed = _state.isRideActive && speedKmph > _state.maxSpeedKmph
        ? speedKmph
        : _state.maxSpeedKmph;

    final nextDistanceKm = _state.isRideActive
        ? _largerDistance(_state.distanceKm, packet.distanceKm)
        : 0.0;

    final activeDurationMs = calculateActiveDurationMs(nowEpochMs: nowEpochMs);

    var nextAverageSpeed = _state.averageSpeedKmph;

    if (_state.rideState == RideState.running && activeDurationMs > 0) {
      final calculatedAverageSpeed =
          nextDistanceKm / (activeDurationMs / 3600000.0);

      final shouldRefreshAverage =
          _lastAverageSpeedUpdateEpochMs == null ||
          nowEpochMs - _lastAverageSpeedUpdateEpochMs! >=
              _averageSpeedDisplayRefreshMs;

      if (shouldRefreshAverage) {
        nextAverageSpeed = calculatedAverageSpeed;
        _lastAverageSpeedUpdateEpochMs = nowEpochMs;
      }
    } else if (_state.rideState == RideState.paused) {
      nextAverageSpeed = _state.averageSpeedKmph;
    } else {
      nextAverageSpeed = 0.0;
      _lastAverageSpeedUpdateEpochMs = null;
    }

    final espDistanceWasLower =
        _state.isRideActive && packet.distanceKm + 0.00001 < nextDistanceKm;

    final physicalIndicatorActive = packet.leftPhysical || packet.rightPhysical;

    final indicatorPacketIsSettling =
        !physicalIndicatorActive &&
        _lastIndicatorCommandEpochMs != null &&
        nowEpochMs - _lastIndicatorCommandEpochMs! < _indicatorCommandSettleMs;

    if (!indicatorPacketIsSettling && _lastIndicatorCommandEpochMs != null) {
      _lastIndicatorCommandEpochMs = null;
    }

    final resolvedLeftOutput = indicatorPacketIsSettling
        ? _state.leftOutputActive
        : _resolveLeftOutputFromPacket(packet);

    final resolvedRightOutput = indicatorPacketIsSettling
        ? _state.rightOutputActive
        : _resolveRightOutputFromPacket(packet);

    _state = _state.copyWith(
      currentRpm: packet.rpm,
      currentSpeedKmph: speedKmph,
      speedSource: SpeedSource.wheel,
      distanceKm: nextDistanceKm,
      maxSpeedKmph: nextMaxSpeed,
      averageSpeedKmph: nextAverageSpeed,

      leftPhysicalIndicator: packet.leftPhysical,
      rightPhysicalIndicator: packet.rightPhysical,

      leftOutputActive: resolvedLeftOutput,
      rightOutputActive: resolvedRightOutput,

      appLeftIndicator: physicalIndicatorActive
          ? false
          : indicatorPacketIsSettling
          ? _state.appLeftIndicator
          : packet.appLeft,
      appRightIndicator: physicalIndicatorActive
          ? false
          : indicatorPacketIsSettling
          ? _state.appRightIndicator
          : packet.appRight,
    );

    if (espDistanceWasLower) {
      _syncConsoleStateWithApp();
    }

    _persistSnapshotFireAndForget();
    notifyListeners();
  }

  bool _resolveLeftOutputFromPacket(BikeSensorPacket packet) {
    if (packet.leftPhysical) return true;
    if (packet.rightPhysical) return false;

    return packet.leftOutput;
  }

  bool _resolveRightOutputFromPacket(BikeSensorPacket packet) {
    if (packet.leftPhysical) return false;
    if (packet.rightPhysical) return true;

    return packet.rightOutput;
  }

  void toggleHazard() {
    final nextHazardState = !_state.hazardEnabled;
    _lastIndicatorCommandEpochMs = DateTime.now().millisecondsSinceEpoch;
    final hasPhysicalOverride =
        _state.leftPhysicalIndicator || _state.rightPhysicalIndicator;

    final hasAppLeft = _state.appLeftIndicator;
    final hasAppRight = _state.appRightIndicator;

    _state = _state.copyWith(
      hazardEnabled: nextHazardState,

      // Do not visually override a physical switch.
      leftOutputActive: hasPhysicalOverride
          ? _state.leftOutputActive
          : isConsoleConnected
          ? hasAppLeft || (!hasAppRight && nextHazardState)
          : false,
      rightOutputActive: hasPhysicalOverride
          ? _state.rightOutputActive
          : isConsoleConnected
          ? hasAppRight || (!hasAppLeft && nextHazardState)
          : false,
    );

    onCommand?.call(BikeCommand.hazard(nextHazardState));
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void toggleAppLeftIndicator() {
    final hasPhysicalOverride =
        _state.leftPhysicalIndicator || _state.rightPhysicalIndicator;
    _lastIndicatorCommandEpochMs = DateTime.now().millisecondsSinceEpoch;

    final nextLeftState = !_state.appLeftIndicator;
    final nextRightState = nextLeftState ? false : _state.appRightIndicator;

    _state = _state.copyWith(
      appLeftIndicator: nextLeftState,
      appRightIndicator: nextRightState,

      // Optimistic UI only when no physical switch is active.
      leftOutputActive: hasPhysicalOverride
          ? _state.leftOutputActive
          : isConsoleConnected
          ? nextLeftState || (!nextRightState && _state.hazardEnabled)
          : false,
      rightOutputActive: hasPhysicalOverride
          ? _state.rightOutputActive
          : isConsoleConnected
          ? nextRightState || (!nextLeftState && _state.hazardEnabled)
          : false,
    );

    onCommand?.call(
      BikeCommand.indicator(
        appLeftIndicator: _state.appLeftIndicator,
        appRightIndicator: _state.appRightIndicator,
      ),
    );

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void toggleAppRightIndicator() {
    final hasPhysicalOverride =
        _state.leftPhysicalIndicator || _state.rightPhysicalIndicator;
    _lastIndicatorCommandEpochMs = DateTime.now().millisecondsSinceEpoch;

    final nextRightState = !_state.appRightIndicator;
    final nextLeftState = nextRightState ? false : _state.appLeftIndicator;

    _state = _state.copyWith(
      appRightIndicator: nextRightState,
      appLeftIndicator: nextLeftState,

      // Optimistic UI only when no physical switch is active.
      leftOutputActive: hasPhysicalOverride
          ? _state.leftOutputActive
          : isConsoleConnected
          ? nextLeftState || (!nextRightState && _state.hazardEnabled)
          : false,
      rightOutputActive: hasPhysicalOverride
          ? _state.rightOutputActive
          : isConsoleConnected
          ? nextRightState || (!nextLeftState && _state.hazardEnabled)
          : false,
    );

    onCommand?.call(
      BikeCommand.indicator(
        appLeftIndicator: _state.appLeftIndicator,
        appRightIndicator: _state.appRightIndicator,
      ),
    );

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void beginCountdown() {
    if (!canStartRide) return;

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;
    _autoPauseSuppressedUntilMovement = false;

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
      leftOutputActive: false,
      rightOutputActive: false,
    );

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void finishCountdownAndStartRide({int? startEpochMs}) {
    if (_state.rideState != RideState.countdown) return;

    final startMs = startEpochMs ?? DateTime.now().millisecondsSinceEpoch;

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = startMs;
    _lastConsoleSyncEpochMs = null;
    _autoPauseSuppressedUntilMovement = false;

    _state = _state.copyWith(
      rideState: RideState.running,
      pauseReason: PauseReason.none,
      rideStartEpochMs: startMs,
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
    _startDurationTicker();
    notifyListeners();
  }

  void manualPauseRide({int? pauseEpochMs}) {
    if (_state.rideState != RideState.running) return;

    _autoPauseSuppressedUntilMovement = false;

    _state = _state.copyWith(
      rideState: RideState.paused,
      pauseReason: PauseReason.manual,
      currentPauseStartEpochMs:
          pauseEpochMs ?? DateTime.now().millisecondsSinceEpoch,
    );

    onCommand?.call(BikeCommand.pause());
    _persistSnapshotFireAndForget(force: true);

    _stopDurationTicker();

    notifyListeners();
  }

  void autoPauseRide({int? pauseEpochMs}) {
    if (_state.rideState != RideState.running) return;

    _autoPauseSuppressedUntilMovement = false;

    _state = _state.copyWith(
      rideState: RideState.paused,
      pauseReason: PauseReason.auto,
      currentPauseStartEpochMs:
          pauseEpochMs ?? DateTime.now().millisecondsSinceEpoch,
    );

    onCommand?.call(BikeCommand.pause());
    _persistSnapshotFireAndForget(force: true);

    _stopDurationTicker();

    notifyListeners();
  }

  void resumeRide({
    int? resumeEpochMs,
    bool suppressAutoPauseUntilMovement = true,
  }) {
    if (_state.rideState != RideState.paused) return;

    final pauseStart = _state.currentPauseStartEpochMs;
    final now = resumeEpochMs ?? DateTime.now().millisecondsSinceEpoch;
    final completedPauseMs = pauseStart == null ? 0 : now - pauseStart;

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = now;
    _autoPauseSuppressedUntilMovement = suppressAutoPauseUntilMovement;

    _state = _state.copyWith(
      rideState: RideState.running,
      pauseReason: PauseReason.none,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs:
          _state.accumulatedPausedMs + completedPauseMs.clamp(0, 1 << 31),
    );

    onCommand?.call(BikeCommand.resume());
    _persistSnapshotFireAndForget(force: true);
    _startDurationTicker();
    notifyListeners();
  }

  bool stopRide() {
    final completedState = _state;
    final endEpochMs = DateTime.now().millisecondsSinceEpoch;
    final activeDurationMs = calculateActiveDurationMs(nowEpochMs: endEpochMs);

    final shouldSaveSession =
        completedState.rideStartEpochMs != null &&
        activeDurationMs >= _minimumSavedRideDurationMs;

    if (shouldSaveSession) {
      final calculatedAverageSpeed = activeDurationMs > 0
          ? completedState.distanceKm / (activeDurationMs / 3600000.0)
          : completedState.averageSpeedKmph;

      _rideHistoryService.saveSession(
        SavedRideSession(
          id: endEpochMs.toString(),
          startEpochMs: completedState.rideStartEpochMs!,
          endEpochMs: endEpochMs,
          activeDurationMs: activeDurationMs,
          distanceKm: completedState.distanceKm,
          averageSpeedKmph: calculatedAverageSpeed,
          maxSpeedKmph: completedState.maxSpeedKmph,
        ),
      );
    }

    final hazardShouldRemainOn = completedState.hazardEnabled;

    _state = RideSessionState.initial().copyWith(
      hazardEnabled: hazardShouldRemainOn,
      leftOutputActive: isConsoleConnected && hazardShouldRemainOn,
      rightOutputActive: isConsoleConnected && hazardShouldRemainOn,
    );

    _notMovingSinceEpochMs = null;
    _lastSnapshotSaveEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;
    _lastIndicatorCommandEpochMs = null;
    _autoPauseSuppressedUntilMovement = false;

    onCommand?.call(BikeCommand.stop());
    _syncConsoleStateWithApp(force: true);
    _persistSnapshotFireAndForget(force: true);

    _stopDurationTicker();

    notifyListeners();

    return shouldSaveSession;
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

  void _startDurationTicker() {
    _durationTicker?.cancel();

    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.rideState == RideState.running) {
        notifyListeners();
      }
    });
  }

  void _stopDurationTicker() {
    _durationTicker?.cancel();
    _durationTicker = null;
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

  void _syncConsoleStateWithApp({bool force = false}) {
    if (!isConsoleConnected) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    if (!force &&
        _lastConsoleSyncEpochMs != null &&
        now - _lastConsoleSyncEpochMs! < _consoleSyncThrottleMs) {
      return;
    }

    _lastConsoleSyncEpochMs = now;

    final rideActive =
        _state.rideState == RideState.running ||
        _state.rideState == RideState.paused;

    final paused = _state.rideState == RideState.paused;

    onCommand?.call(
      BikeCommand.sync(
        rideActive: rideActive,
        paused: paused,
        distanceKm: rideActive ? _state.distanceKm : 0,
        hazardEnabled: _state.hazardEnabled,
        appLeftIndicator: _state.appLeftIndicator,
        appRightIndicator: _state.appRightIndicator,
        tyreCircumferenceMeters: _settings.tyreCircumferenceMeters,
      ),
    );
  }

  void _checkAutoPause(int nowEpochMs) {
    if (!_settings.autoPauseEnabled) return;
    if (_state.rideState != RideState.running) return;

    if (_autoPauseSuppressedUntilMovement) {
      _notMovingSinceEpochMs = null;
      return;
    }

    _notMovingSinceEpochMs ??= nowEpochMs;

    final inactiveMs = nowEpochMs - _notMovingSinceEpochMs!;
    final requiredInactiveMs = _settings.autoPauseSeconds * 1000;

    if (inactiveMs >= requiredInactiveMs) {
      autoPauseRide(pauseEpochMs: nowEpochMs);
      _notMovingSinceEpochMs = null;
    }
  }

  double _largerDistance(double appDistanceKm, double espDistanceKm) {
    if (espDistanceKm > appDistanceKm) {
      return espDistanceKm;
    }

    return appDistanceKm;
  }

  double _speedFromRpm(double rpm) {
    if (rpm <= 0) return 0;

    return rpm * _settings.tyreCircumferenceMeters * 60.0 / 1000.0;
  }

  @override
  void dispose() {
    _stopDurationTicker();
    super.dispose();
  }
}
