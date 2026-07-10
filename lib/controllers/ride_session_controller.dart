import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ride_models.dart';
import '../models/ride_route_point.dart';
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
  static const double _gpsFallbackMinMovingSpeedMps = 0.6;
  static const double _gpsFallbackMinDistanceMeters = 0.8;
  static const double _gpsFallbackMaxReasonableSpeedKmph = 85.0;
  static const int _gpsFallbackStaleMs = 5000;
  static const int _gpsFallbackDisplayGraceMs = 7000;
  static const int _gpsFallbackSpeedHoldMs = 5000;
  static const double _distanceToleranceKm = 0.003;
  static const double _distanceJumpGraceKm = 0.03;
  static const double _maxPlausibleDistanceSpeedKmph = 95.0;
  static const int _manualDistanceCorrectionHoldMs = 7000;


  RideSessionState _state = RideSessionState.initial();
  RideSettings _settings = RideSettings.defaults();
  ConsoleConnectionState _connectionState = ConsoleConnectionState.disconnected;

  int? _notMovingSinceEpochMs;
  int? _lastSnapshotSaveEpochMs;
  int? _lastAverageSpeedUpdateEpochMs;
  int? _lastConsoleSyncEpochMs;
  int? _lastIndicatorCommandEpochMs;
  RideRoutePoint? _lastGpsFallbackDistancePoint;
  int? _lastGpsFallbackPointEpochMs;
  int? _lastGpsFallbackMotionEpochMs;
  int? _lastGpsFallbackValidSpeedEpochMs;
  double _lastGpsFallbackDisplaySpeedKmph = 0.0;
  double? _lastAcceptedWheelDistanceKm;
  int? _lastAcceptedWheelDistanceEpochMs;
  double? _manualDistanceCorrectionKm;
  int? _manualDistanceCorrectionEpochMs;

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

      final shouldHoldMotionUntilGps =
          _state.isRideActive && _state.currentSpeedKmph > 0;

      if (shouldHoldMotionUntilGps) {
        final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
        _lastGpsFallbackDisplaySpeedKmph = _state.currentSpeedKmph;
        _lastGpsFallbackValidSpeedEpochMs = nowEpochMs;
        _lastGpsFallbackMotionEpochMs = nowEpochMs;
      }

      _state = _state.copyWith(
        currentRpm: shouldHoldMotionUntilGps ? _state.currentRpm : 0,
        currentSpeedKmph:
            shouldHoldMotionUntilGps ? _state.currentSpeedKmph : 0,
        speedSource:
            shouldHoldMotionUntilGps ? _state.speedSource : SpeedSource.none,
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
    required double maxSpeedKmph,
    required int activeDurationMs,
  }) {
    if (_state.rideState != RideState.running &&
        _state.rideState != RideState.paused) {
      return;
    }

    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;

    final rawSafeDistanceKm = distanceKm.isFinite && distanceKm >= 0
        ? distanceKm
        : _state.distanceKm;

    final safeMaxSpeedKmph = maxSpeedKmph.isFinite && maxSpeedKmph >= 0
        ? math.max(maxSpeedKmph, _state.currentSpeedKmph)
        : _state.maxSpeedKmph;

    final safeActiveDurationMs = activeDurationMs
        .clamp(0, 99 * 60 * 60 * 1000)
        .toInt();

    final safeDistanceKm = _manualCorrectionDistanceIsPlausible(
      distanceKm: rawSafeDistanceKm,
      activeDurationMs: safeActiveDurationMs,
    )
        ? rawSafeDistanceKm
        : _state.distanceKm;

    final recalculatedAverageSpeedKmph = _calculatedAverageSpeedKmph(
      distanceKm: safeDistanceKm,
      activeDurationMs: safeActiveDurationMs,
    );

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
      averageSpeedKmph: recalculatedAverageSpeedKmph,
      maxSpeedKmph: safeMaxSpeedKmph,
    );

    _manualDistanceCorrectionKm = safeDistanceKm;
    _manualDistanceCorrectionEpochMs = nowEpochMs;
    _lastAcceptedWheelDistanceKm = safeDistanceKm;
    _lastAcceptedWheelDistanceEpochMs = nowEpochMs;

    _lastAverageSpeedUpdateEpochMs = nowEpochMs;
    _lastSnapshotSaveEpochMs = null;

    onCommand?.call(BikeCommand.setDistance(safeDistanceKm));
    _syncConsoleStateWithApp(force: true);
    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void restoreFromSnapshot(PersistedRideSnapshot snapshot) {
    _state = snapshot.toSessionState();

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;
    _lastGpsFallbackDistancePoint = _state.routePoints.isNotEmpty
        ? _state.routePoints.last
        : null;
    _lastGpsFallbackPointEpochMs = _lastGpsFallbackDistancePoint?.timestampMs;
    _lastGpsFallbackMotionEpochMs = _lastGpsFallbackPointEpochMs;
    _lastGpsFallbackValidSpeedEpochMs = null;
    _lastGpsFallbackDisplaySpeedKmph = 0.0;
    _lastAcceptedWheelDistanceKm = _state.distanceKm;
    _lastAcceptedWheelDistanceEpochMs = DateTime.now().millisecondsSinceEpoch;
    _manualDistanceCorrectionKm = null;
    _manualDistanceCorrectionEpochMs = null;

    if (_state.rideState == RideState.running) {
      _startDurationTicker();
    } else {
      _stopDurationTicker();
    }

    notifyListeners();
  }

  void restoreFromForegroundServiceSnapshot(PersistedRideSnapshot snapshot) {
    if (snapshot.rideState == RideState.stopped) return;

    final snapshotState = snapshot.toSessionState();
    final currentRoutePoints = _state.routePoints;
    final snapshotRoutePoints = snapshotState.routePoints;

    final shouldUseSnapshotRoute =
        snapshotRoutePoints.length > currentRoutePoints.length;

    final nextRoutePoints = shouldUseSnapshotRoute
        ? snapshotRoutePoints
        : currentRoutePoints;

    final nextDistanceKm = _resolveForegroundSnapshotDistance(
      snapshotState.distanceKm,
      DateTime.now().millisecondsSinceEpoch,
    );

    _state = _state.copyWith(
      rideState: snapshotState.rideState,
      pauseReason: snapshotState.pauseReason,
      rideStartEpochMs: snapshotState.rideStartEpochMs,
      currentPauseStartEpochMs: snapshotState.currentPauseStartEpochMs,
      accumulatedPausedMs: snapshotState.accumulatedPausedMs,
      distanceKm: nextDistanceKm,
      averageSpeedKmph: _state.averageSpeedKmph,
      maxSpeedKmph: _state.maxSpeedKmph,
      routePoints: nextRoutePoints,
      autoPauseSuppressedUntilMovement:
          _state.autoPauseSuppressedUntilMovement ||
          snapshotState.autoPauseSuppressedUntilMovement,
    );

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;
    _lastGpsFallbackDistancePoint = nextRoutePoints.isNotEmpty
        ? nextRoutePoints.last
        : null;
    _lastGpsFallbackPointEpochMs = _lastGpsFallbackDistancePoint?.timestampMs;
    _lastGpsFallbackMotionEpochMs = _lastGpsFallbackPointEpochMs;
    _lastGpsFallbackValidSpeedEpochMs = null;
    _lastGpsFallbackDisplaySpeedKmph = 0.0;
    _lastAcceptedWheelDistanceKm = nextDistanceKm;
    _lastAcceptedWheelDistanceEpochMs = DateTime.now().millisecondsSinceEpoch;

    if (_state.rideState == RideState.running) {
      _startDurationTicker();
    } else {
      _stopDurationTicker();
    }

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void handleRoutePoint(RideRoutePoint point) {
    if (!_state.isRouteRecordingActive || !point.isValid) {
      return;
    }

    final mode = _state.isPaused ? RideRouteMode.paused : RideRouteMode.running;
    final normalizedPoint = point.copyWith(rideMode: mode);
    final currentPoints = _state.routePoints;

    if (currentPoints.isNotEmpty) {
      final last = currentPoints.last;

      final isDuplicate = last.latitude == normalizedPoint.latitude &&
          last.longitude == normalizedPoint.longitude &&
          last.rideMode == normalizedPoint.rideMode;

      if (isDuplicate) {
        return;
      }
    }

    _state = _state.copyWith(
      routePoints: [...currentPoints, normalizedPoint],
    );

    _persistSnapshotFireAndForget();
    notifyListeners();
  }

  void handleGpsFallbackPoint(RideRoutePoint point) {
    if (!_state.isRouteRecordingActive || !point.isValid) {
      return;
    }

    final nowEpochMs = point.timestampMs > 0
        ? point.timestampMs
        : DateTime.now().millisecondsSinceEpoch;

    if (isConsoleConnected) {
      _lastGpsFallbackDistancePoint = point;
      _lastGpsFallbackPointEpochMs = nowEpochMs;
      return;
    }

    final lastPoint = _lastGpsFallbackDistancePoint;
    _lastGpsFallbackDistancePoint = point;
    _lastGpsFallbackPointEpochMs = nowEpochMs;

    var deltaMeters = 0.0;
    var rawDeltaMeters = 0.0;
    var impliedSpeedKmph = 0.0;

    if (lastPoint != null && lastPoint.isValid) {
      final elapsedMs = point.timestampMs - lastPoint.timestampMs;

      if (elapsedMs > 0) {
        rawDeltaMeters = _distanceBetweenRoutePointsMeters(lastPoint, point);
        impliedSpeedKmph = rawDeltaMeters / (elapsedMs / 1000.0) * 3.6;

        if (rawDeltaMeters >= _gpsFallbackMinDistanceMeters &&
            impliedSpeedKmph <= _gpsFallbackMaxReasonableSpeedKmph) {
          deltaMeters = rawDeltaMeters;
        }
      }
    }

    final gpsSpeedMps = point.gpsSpeedMps.isFinite && point.gpsSpeedMps > 0
        ? point.gpsSpeedMps
        : 0.0;

    final reportedGpsSpeedKmph = gpsSpeedMps * 3.6;
    final hasPlausibleReportedSpeed =
        reportedGpsSpeedKmph >= _gpsFallbackMinMovingSpeedMps * 3.6 &&
        reportedGpsSpeedKmph <= _gpsFallbackMaxReasonableSpeedKmph;
    final hasPlausibleDeltaSpeed =
        rawDeltaMeters >= 0.6 &&
        impliedSpeedKmph > 0 &&
        impliedSpeedKmph <= _gpsFallbackMaxReasonableSpeedKmph;

    final rawFallbackSpeedKmph = hasPlausibleReportedSpeed
        ? reportedGpsSpeedKmph
        : hasPlausibleDeltaSpeed
        ? impliedSpeedKmph
        : 0.0;

    final candidateFallbackSpeedKmph = rawFallbackSpeedKmph.isFinite
        ? rawFallbackSpeedKmph.clamp(0.0, _gpsFallbackMaxReasonableSpeedKmph)
              .toDouble()
        : 0.0;

    final gpsMoving =
        hasPlausibleReportedSpeed || hasPlausibleDeltaSpeed || deltaMeters > 0;

    if (gpsMoving) {
      _lastGpsFallbackMotionEpochMs = nowEpochMs;
    }

    final fallbackSpeedKmph = _stableGpsFallbackDisplaySpeedKmph(
      candidateFallbackSpeedKmph,
      gpsMoving: gpsMoving,
      nowEpochMs: nowEpochMs,
    );

    final fallbackRpm = _rpmFromSpeedKmph(fallbackSpeedKmph);

    final shouldClearAutoPauseSuppression =
        gpsMoving && _state.autoPauseSuppressedUntilMovement;

    if (gpsMoving) {
      _notMovingSinceEpochMs = null;

      if (_state.rideState == RideState.paused &&
          _state.pauseReason == PauseReason.auto) {
        resumeRide(
          resumeEpochMs: nowEpochMs,
          suppressAutoPauseUntilMovement: false,
        );
      }
    } else if (_state.rideState == RideState.running) {
      _checkAutoPause(nowEpochMs);
    }

    if (_state.rideState == RideState.paused) {
      _state = _state.copyWith(
        currentRpm: fallbackRpm,
        currentSpeedKmph: fallbackSpeedKmph,
        speedSource: SpeedSource.gpsFallback,
        autoPauseSuppressedUntilMovement: shouldClearAutoPauseSuppression
            ? false
            : _state.autoPauseSuppressedUntilMovement,
      );

      _persistSnapshotFireAndForget();
      notifyListeners();
      return;
    }

    if (!_state.isRunning) {
      return;
    }

    final fallbackDistanceKm = deltaMeters / 1000.0;
    final nextDistanceKm = _state.distanceKm + fallbackDistanceKm;
    final nextMaxSpeed = fallbackSpeedKmph > _state.maxSpeedKmph
        ? fallbackSpeedKmph
        : _state.maxSpeedKmph;

    final activeDurationMs = calculateActiveDurationMs(nowEpochMs: nowEpochMs);
    var nextAverageSpeed = _state.averageSpeedKmph;

    if (activeDurationMs > 0) {
      final calculatedAverageSpeed = _calculatedAverageSpeedKmph(
        distanceKm: nextDistanceKm,
        activeDurationMs: activeDurationMs,
      );

      final shouldRefreshAverage =
          _lastAverageSpeedUpdateEpochMs == null ||
          nowEpochMs - _lastAverageSpeedUpdateEpochMs! >=
              _averageSpeedDisplayRefreshMs;

      if (shouldRefreshAverage) {
        nextAverageSpeed = calculatedAverageSpeed;
        _lastAverageSpeedUpdateEpochMs = nowEpochMs;
      }
    }

    _state = _state.copyWith(
      currentRpm: fallbackRpm,
      currentSpeedKmph: fallbackSpeedKmph,
      speedSource: SpeedSource.gpsFallback,
      autoPauseSuppressedUntilMovement: shouldClearAutoPauseSuppression
          ? false
          : _state.autoPauseSuppressedUntilMovement,
      distanceKm: nextDistanceKm,
      maxSpeedKmph: nextMaxSpeed,
      averageSpeedKmph: nextAverageSpeed,
    );

    _persistSnapshotFireAndForget();
    notifyListeners();
  }

  void handleSensorPacket(BikeSensorPacket packet) {
    final speedKmph = _speedFromRpm(packet.rpm);
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final shouldClearAutoPauseSuppression =
        packet.isMoving && _state.autoPauseSuppressedUntilMovement;

    if (packet.isMoving) {
      _notMovingSinceEpochMs = null;

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

    final nextDistanceKm = _resolveConsolePacketDistance(
      packet,
      nowEpochMs,
    );

    final activeDurationMs = calculateActiveDurationMs(nowEpochMs: nowEpochMs);

    var nextAverageSpeed = _state.averageSpeedKmph;

    if (_state.rideState == RideState.running && activeDurationMs > 0) {
      final calculatedAverageSpeed = _calculatedAverageSpeedKmph(
        distanceKm: nextDistanceKm,
        activeDurationMs: activeDurationMs,
      );

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
      autoPauseSuppressedUntilMovement: shouldClearAutoPauseSuppression
          ? false
          : _state.autoPauseSuppressedUntilMovement,
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
    _resetGpsFallbackTracking();

    _state = _state.copyWith(
      autoPauseSuppressedUntilMovement: false,
      rideState: RideState.countdown,
      pauseReason: PauseReason.none,
      clearRideStartEpochMs: true,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs: 0,
      distanceKm: 0,
      averageSpeedKmph: 0,
      maxSpeedKmph: 0,
      speedSource: SpeedSource.wheel,
      routePoints: const [],
      leftOutputActive: false,
      rightOutputActive: false,
    );

    _resetDistanceAuthorityTracking(distanceKm: 0, epochMs: DateTime.now().millisecondsSinceEpoch);

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void finishCountdownAndStartRide({int? startEpochMs}) {
    if (_state.rideState != RideState.countdown) return;

    final startMs = startEpochMs ?? DateTime.now().millisecondsSinceEpoch;

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = startMs;
    _lastConsoleSyncEpochMs = null;
    _resetGpsFallbackTracking();

    _state = _state.copyWith(
      autoPauseSuppressedUntilMovement: false,
      rideState: RideState.running,
      pauseReason: PauseReason.none,
      rideStartEpochMs: startMs,
      clearCurrentPauseStartEpochMs: true,
      accumulatedPausedMs: 0,
      distanceKm: 0,
      averageSpeedKmph: 0,
      maxSpeedKmph: 0,
      routePoints: const [],
    );

    _resetDistanceAuthorityTracking(distanceKm: 0, epochMs: startMs);

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

    _state = _state.copyWith(
      autoPauseSuppressedUntilMovement: false,
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

    _state = _state.copyWith(
      autoPauseSuppressedUntilMovement: false,
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

    _state = _state.copyWith(
      autoPauseSuppressedUntilMovement: suppressAutoPauseUntilMovement,
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
          routePoints: completedState.routePoints,
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
    _resetGpsFallbackTracking();
    _resetDistanceAuthorityTracking(distanceKm: 0, epochMs: endEpochMs);

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
      final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
      _checkGpsFallbackInactivity(nowEpochMs);

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

    if (_state.autoPauseSuppressedUntilMovement) {
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

  double _resolveConsolePacketDistance(
    BikeSensorPacket packet,
    int nowEpochMs,
  ) {
    if (!_state.isRideActive) {
      _resetDistanceAuthorityTracking(distanceKm: 0, epochMs: nowEpochMs);
      return 0.0;
    }

    final incomingDistanceKm = packet.distanceKm;

    if (!incomingDistanceKm.isFinite || incomingDistanceKm < 0) {
      return _state.distanceKm;
    }

    final manualCorrectionEpochMs = _manualDistanceCorrectionEpochMs;
    final manualCorrectionKm = _manualDistanceCorrectionKm;
    final manualCorrectionActive =
        manualCorrectionEpochMs != null &&
        manualCorrectionKm != null &&
        nowEpochMs - manualCorrectionEpochMs <= _manualDistanceCorrectionHoldMs;

    if (manualCorrectionActive &&
        (incomingDistanceKm - manualCorrectionKm).abs() > _distanceToleranceKm) {
      onCommand?.call(BikeCommand.setDistance(manualCorrectionKm));
      _syncConsoleStateWithApp(force: true);
      return manualCorrectionKm;
    }

    if (manualCorrectionActive &&
        (incomingDistanceKm - manualCorrectionKm).abs() <= _distanceToleranceKm) {
      _manualDistanceCorrectionKm = null;
      _manualDistanceCorrectionEpochMs = null;
    }

    if (incomingDistanceKm + _distanceToleranceKm < _state.distanceKm) {
      _syncConsoleStateWithApp();
      return _state.distanceKm;
    }

    if (!_distanceIncreaseIsPlausible(
      currentDistanceKm: _state.distanceKm,
      incomingDistanceKm: incomingDistanceKm,
      nowEpochMs: nowEpochMs,
    )) {
      _syncConsoleStateWithApp(force: true);
      return _state.distanceKm;
    }

    final resolvedDistanceKm = incomingDistanceKm > _state.distanceKm
        ? incomingDistanceKm
        : _state.distanceKm;

    _lastAcceptedWheelDistanceKm = resolvedDistanceKm;
    _lastAcceptedWheelDistanceEpochMs = nowEpochMs;

    return resolvedDistanceKm;
  }

  double _resolveForegroundSnapshotDistance(
    double snapshotDistanceKm,
    int nowEpochMs,
  ) {
    if (!snapshotDistanceKm.isFinite || snapshotDistanceKm < 0) {
      return _state.distanceKm;
    }

    if (snapshotDistanceKm <= _state.distanceKm + _distanceToleranceKm) {
      return _state.distanceKm;
    }

    if (!_distanceIncreaseIsPlausible(
      currentDistanceKm: _state.distanceKm,
      incomingDistanceKm: snapshotDistanceKm,
      nowEpochMs: nowEpochMs,
    )) {
      return _state.distanceKm;
    }

    return snapshotDistanceKm;
  }

  bool _distanceIncreaseIsPlausible({
    required double currentDistanceKm,
    required double incomingDistanceKm,
    required int nowEpochMs,
  }) {
    if (incomingDistanceKm <= currentDistanceKm + _distanceToleranceKm) {
      return true;
    }

    final activeDurationMs = calculateActiveDurationMs(nowEpochMs: nowEpochMs);

    if (activeDurationMs > 0) {
      final maxTotalDistanceKm =
          (_maxPlausibleDistanceSpeedKmph * activeDurationMs / 3600000.0) +
          0.5;

      if (incomingDistanceKm > maxTotalDistanceKm) {
        return false;
      }
    }

    final lastDistanceKm = _lastAcceptedWheelDistanceKm;
    final lastEpochMs = _lastAcceptedWheelDistanceEpochMs;

    if (lastDistanceKm == null || lastEpochMs == null) {
      return true;
    }

    final elapsedMs = (nowEpochMs - lastEpochMs).clamp(1000, 15000).toInt();
    final baselineKm = math.max(currentDistanceKm, lastDistanceKm);
    final deltaKm = incomingDistanceKm - baselineKm;

    if (deltaKm <= _distanceToleranceKm) {
      return true;
    }

    final maxDeltaKm =
        (_maxPlausibleDistanceSpeedKmph * elapsedMs / 3600000.0) +
        _distanceJumpGraceKm;

    return deltaKm <= maxDeltaKm;
  }

  bool _manualCorrectionDistanceIsPlausible({
    required double distanceKm,
    required int activeDurationMs,
  }) {
    if (!distanceKm.isFinite || distanceKm < 0) return false;
    if (distanceKm <= _distanceToleranceKm) return true;

    if (activeDurationMs <= 0) {
      return distanceKm <= _distanceJumpGraceKm;
    }

    final maxDistanceKm =
        (_maxPlausibleDistanceSpeedKmph * activeDurationMs / 3600000.0) +
        0.5;

    return distanceKm <= maxDistanceKm;
  }

  double _calculatedAverageSpeedKmph({
    required double distanceKm,
    required int activeDurationMs,
  }) {
    if (activeDurationMs <= 0) return 0.0;
    return distanceKm / (activeDurationMs / 3600000.0);
  }

  void _resetDistanceAuthorityTracking({
    required double distanceKm,
    required int epochMs,
  }) {
    _lastAcceptedWheelDistanceKm = distanceKm;
    _lastAcceptedWheelDistanceEpochMs = epochMs;
    _manualDistanceCorrectionKm = null;
    _manualDistanceCorrectionEpochMs = null;
  }

  double _distanceBetweenRoutePointsMeters(
    RideRoutePoint from,
    RideRoutePoint to,
  ) {
    const earthRadiusMeters = 6371000.0;

    final fromLat = _degreesToRadians(from.latitude);
    final toLat = _degreesToRadians(to.latitude);
    final deltaLat = _degreesToRadians(to.latitude - from.latitude);
    final deltaLng = _degreesToRadians(to.longitude - from.longitude);

    final sinHalfLat = math.sin(deltaLat / 2);
    final sinHalfLng = math.sin(deltaLng / 2);

    final a = sinHalfLat * sinHalfLat +
        math.cos(fromLat) * math.cos(toLat) * sinHalfLng * sinHalfLng;

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  double _rpmFromSpeedKmph(double speedKmph) {
    if (speedKmph <= 0 || _settings.tyreCircumferenceMeters <= 0) return 0;

    final speedMps = speedKmph * 1000.0 / 3600.0;
    return speedMps / _settings.tyreCircumferenceMeters * 60.0;
  }

  void _checkGpsFallbackInactivity(int nowEpochMs) {
    if (isConsoleConnected) return;
    if (_state.rideState != RideState.running) return;

    final lastPointEpochMs = _lastGpsFallbackPointEpochMs;
    final pointIsStale = lastPointEpochMs == null ||
        nowEpochMs - lastPointEpochMs >= _gpsFallbackStaleMs;

    if (!pointIsStale) return;

    _checkAutoPause(nowEpochMs);

    if (_state.rideState != RideState.running) return;

    final shouldClearDisplay = _lastGpsFallbackMotionEpochMs == null ||
        nowEpochMs - _lastGpsFallbackMotionEpochMs! >=
            _gpsFallbackDisplayGraceMs;

    if (shouldClearDisplay &&
        _state.speedSource == SpeedSource.gpsFallback &&
        (_state.currentSpeedKmph != 0 || _state.currentRpm != 0)) {
      _lastGpsFallbackDisplaySpeedKmph = 0.0;

      _state = _state.copyWith(
        currentSpeedKmph: 0.0,
        currentRpm: 0.0,
        speedSource: SpeedSource.gpsFallback,
      );

      _persistSnapshotFireAndForget();
      notifyListeners();
    }
  }

  double _stableGpsFallbackDisplaySpeedKmph(
    double candidateSpeedKmph, {
    required bool gpsMoving,
    required int nowEpochMs,
  }) {
    if (candidateSpeedKmph > 0) {
      _lastGpsFallbackDisplaySpeedKmph = candidateSpeedKmph;
      _lastGpsFallbackValidSpeedEpochMs = nowEpochMs;
      return candidateSpeedKmph;
    }

    final lastValidSpeedEpochMs = _lastGpsFallbackValidSpeedEpochMs;

    if (lastValidSpeedEpochMs != null &&
        nowEpochMs - lastValidSpeedEpochMs <= _gpsFallbackSpeedHoldMs) {
      return _lastGpsFallbackDisplaySpeedKmph;
    }

    final lastMotionEpochMs = _lastGpsFallbackMotionEpochMs;

    if (!gpsMoving &&
        lastMotionEpochMs != null &&
        nowEpochMs - lastMotionEpochMs <= _gpsFallbackDisplayGraceMs) {
      return _lastGpsFallbackDisplaySpeedKmph;
    }

    _lastGpsFallbackDisplaySpeedKmph = 0.0;
    _lastGpsFallbackValidSpeedEpochMs = null;
    return 0.0;
  }

  void _resetGpsFallbackTracking() {
    _lastGpsFallbackDistancePoint = null;
    _lastGpsFallbackPointEpochMs = null;
    _lastGpsFallbackMotionEpochMs = null;
    _lastGpsFallbackValidSpeedEpochMs = null;
    _lastGpsFallbackDisplaySpeedKmph = 0.0;
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
