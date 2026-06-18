from pathlib import Path

ROOT = Path.cwd()


def read(path: str) -> str:
    full = ROOT / path
    if not full.exists():
        raise SystemExit(f"Missing file: {path}")
    return full.read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(content: str, old: str, new: str, label: str) -> str:
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"Patch failed for {label}: expected 1 match, found {count}")
    return content.replace(old, new, 1)


def replace_between(content: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    start = content.find(start_marker)
    if start < 0:
        raise SystemExit(f"Patch failed for {label}: start marker not found")
    end = content.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"Patch failed for {label}: end marker not found")
    return content[:start] + replacement + content[end:]

ride_path = "lib/controllers/ride_session_controller.dart"
ride = read(ride_path)

# 1) Add fallback display/watchdog constants.
ride = replace_once(
    ride,
    "  static const double _gpsFallbackMaxReasonableSpeedKmph = 85.0;\n\n",
    "  static const double _gpsFallbackMaxReasonableSpeedKmph = 85.0;\n"
    "  static const int _gpsFallbackStaleMs = 2500;\n"
    "  static const int _gpsFallbackDisplayGraceMs = 3500;\n\n",
    "gps fallback hotfix constants",
)

# 2) Add fallback display/watchdog fields.
ride = replace_once(
    ride,
    "  RideRoutePoint? _lastGpsFallbackDistancePoint;\n\n  Timer? _durationTicker;\n",
    "  RideRoutePoint? _lastGpsFallbackDistancePoint;\n"
    "  int? _lastGpsFallbackPointEpochMs;\n"
    "  int? _lastGpsFallbackMotionEpochMs;\n"
    "  double _lastGpsFallbackDisplaySpeedKmph = 0.0;\n\n"
    "  Timer? _durationTicker;\n",
    "gps fallback hotfix fields",
)

# 3) Make restore points seed the watchdog fields.
ride = replace_once(
    ride,
    "    _lastGpsFallbackDistancePoint = _state.routePoints.isNotEmpty\n"
    "        ? _state.routePoints.last\n"
    "        : null;\n\n"
    "    if (_state.rideState == RideState.running) {",
    "    _lastGpsFallbackDistancePoint = _state.routePoints.isNotEmpty\n"
    "        ? _state.routePoints.last\n"
    "        : null;\n"
    "    _lastGpsFallbackPointEpochMs = _lastGpsFallbackDistancePoint?.timestampMs;\n"
    "    _lastGpsFallbackMotionEpochMs = _lastGpsFallbackPointEpochMs;\n"
    "    _lastGpsFallbackDisplaySpeedKmph = 0.0;\n\n"
    "    if (_state.rideState == RideState.running) {",
    "restoreFromSnapshot gps fallback watchdog seed",
)

ride = replace_once(
    ride,
    "    _lastGpsFallbackDistancePoint = nextRoutePoints.isNotEmpty\n"
    "        ? nextRoutePoints.last\n"
    "        : null;\n\n"
    "    if (_state.rideState == RideState.running) {",
    "    _lastGpsFallbackDistancePoint = nextRoutePoints.isNotEmpty\n"
    "        ? nextRoutePoints.last\n"
    "        : null;\n"
    "    _lastGpsFallbackPointEpochMs = _lastGpsFallbackDistancePoint?.timestampMs;\n"
    "    _lastGpsFallbackMotionEpochMs = _lastGpsFallbackPointEpochMs;\n"
    "    _lastGpsFallbackDisplaySpeedKmph = 0.0;\n\n"
    "    if (_state.rideState == RideState.running) {",
    "restoreFromForegroundServiceSnapshot gps fallback watchdog seed",
)

# 4) Replace the whole 5A GPS fallback method with the hotfixed version.
new_handle_gps_fallback = r'''  void handleGpsFallbackPoint(RideRoutePoint point) {
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
    var impliedSpeedKmph = 0.0;

    if (lastPoint != null && lastPoint.isValid) {
      final elapsedMs = point.timestampMs - lastPoint.timestampMs;

      if (elapsedMs > 0) {
        final rawDeltaMeters = _distanceBetweenRoutePointsMeters(
          lastPoint,
          point,
        );
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

    final rawFallbackSpeedKmph = gpsSpeedMps > 0
        ? gpsSpeedMps * 3.6
        : impliedSpeedKmph;

    final candidateFallbackSpeedKmph = rawFallbackSpeedKmph.isFinite
        ? rawFallbackSpeedKmph.clamp(0.0, _gpsFallbackMaxReasonableSpeedKmph)
              .toDouble()
        : 0.0;

    final gpsMoving =
        gpsSpeedMps >= _gpsFallbackMinMovingSpeedMps || deltaMeters > 0;

    final fallbackSpeedKmph = _stableGpsFallbackDisplaySpeedKmph(
      candidateFallbackSpeedKmph,
      gpsMoving: gpsMoving,
      nowEpochMs: nowEpochMs,
    );

    final fallbackRpm = _rpmFromSpeedKmph(fallbackSpeedKmph);

    final shouldClearAutoPauseSuppression =
        gpsMoving && _state.autoPauseSuppressedUntilMovement;

    if (gpsMoving) {
      _lastGpsFallbackMotionEpochMs = nowEpochMs;
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

'''

ride = replace_between(
    ride,
    "  void handleGpsFallbackPoint(RideRoutePoint point) {\n",
    "  void handleSensorPacket(BikeSensorPacket packet) {\n",
    new_handle_gps_fallback,
    "replace handleGpsFallbackPoint hotfix",
)

# 5) Reset all fallback watchdog/display fields wherever 5A reset only the point.
reset_count = ride.count("    _lastGpsFallbackDistancePoint = null;\n")
if reset_count < 3:
    raise SystemExit(
        "Patch failed for gps fallback resets: "
        f"expected at least 3 matches, found {reset_count}"
    )
ride = ride.replace(
    "    _lastGpsFallbackDistancePoint = null;\n",
    "    _resetGpsFallbackTracking();\n",
)

# 6) Add ticker watchdog so auto-pause can happen even after GPS/mock updates stop.
ride = replace_once(
    ride,
    "    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {\n"
    "      if (_state.rideState == RideState.running) {\n"
    "        notifyListeners();\n"
    "      }\n"
    "    });",
    "    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {\n"
    "      final nowEpochMs = DateTime.now().millisecondsSinceEpoch;\n"
    "      _checkGpsFallbackInactivity(nowEpochMs);\n\n"
    "      if (_state.rideState == RideState.running) {\n"
    "        notifyListeners();\n"
    "      }\n"
    "    });",
    "duration ticker gps fallback watchdog",
)

# 7) Add helper methods before _speedFromRpm.
helpers = r'''  void _checkGpsFallbackInactivity(int nowEpochMs) {
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
      return candidateSpeedKmph;
    }

    final lastMotionEpochMs = _lastGpsFallbackMotionEpochMs;

    if (!gpsMoving &&
        lastMotionEpochMs != null &&
        nowEpochMs - lastMotionEpochMs <= _gpsFallbackDisplayGraceMs) {
      return _lastGpsFallbackDisplaySpeedKmph;
    }

    _lastGpsFallbackDisplaySpeedKmph = 0.0;
    return 0.0;
  }

  void _resetGpsFallbackTracking() {
    _lastGpsFallbackDistancePoint = null;
    _lastGpsFallbackPointEpochMs = null;
    _lastGpsFallbackMotionEpochMs = null;
    _lastGpsFallbackDisplaySpeedKmph = 0.0;
  }

'''

ride = replace_once(
    ride,
    "  double _speedFromRpm(double rpm) {\n",
    helpers + "  double _speedFromRpm(double rpm) {\n",
    "insert gps fallback hotfix helpers",
)

write(ride_path, ride)
print("Batch 5A hotfix patch applied successfully.")
