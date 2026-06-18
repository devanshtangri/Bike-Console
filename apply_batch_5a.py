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

ride_path = "lib/controllers/ride_session_controller.dart"
dash_path = "lib/screens/dashboard_screen.dart"

ride = read(ride_path)
dash = read(dash_path)

ride = replace_once(
    ride,
    "import 'dart:async';\nimport 'package:flutter/foundation.dart';",
    "import 'dart:async';\nimport 'dart:math' as math;\n\nimport 'package:flutter/foundation.dart';",
    "ride_session_controller imports",
)

ride = replace_once(
    ride,
    "  static const int _indicatorCommandSettleMs = 450;\n",
    "  static const int _indicatorCommandSettleMs = 450;\n  static const double _gpsFallbackMinMovingSpeedMps = 0.6;\n  static const double _gpsFallbackMinDistanceMeters = 0.8;\n  static const double _gpsFallbackMaxReasonableSpeedKmph = 85.0;\n\n",
    "gps fallback constants",
)

ride = replace_once(
    ride,
    "  int? _lastIndicatorCommandEpochMs;\n\n  Timer? _durationTicker;\n",
    "  int? _lastIndicatorCommandEpochMs;\n  RideRoutePoint? _lastGpsFallbackDistancePoint;\n\n  Timer? _durationTicker;\n",
    "gps fallback field",
)

restore_reset_block = (
    "    _notMovingSinceEpochMs = null;\n"
    "    _lastAverageSpeedUpdateEpochMs = null;\n"
    "    _lastConsoleSyncEpochMs = null;\n\n"
    "    if (_state.rideState == RideState.running) {"
)

restore_from_snapshot_block = (
    "    _notMovingSinceEpochMs = null;\n"
    "    _lastAverageSpeedUpdateEpochMs = null;\n"
    "    _lastConsoleSyncEpochMs = null;\n"
    "    _lastGpsFallbackDistancePoint = _state.routePoints.isNotEmpty\n"
    "        ? _state.routePoints.last\n"
    "        : null;\n\n"
    "    if (_state.rideState == RideState.running) {"
)

restore_from_service_snapshot_block = (
    "    _notMovingSinceEpochMs = null;\n"
    "    _lastAverageSpeedUpdateEpochMs = null;\n"
    "    _lastConsoleSyncEpochMs = null;\n"
    "    _lastGpsFallbackDistancePoint = nextRoutePoints.isNotEmpty\n"
    "        ? nextRoutePoints.last\n"
    "        : null;\n\n"
    "    if (_state.rideState == RideState.running) {"
)

if ride.count(restore_reset_block) != 2:
    raise SystemExit(
        "Patch failed for restore gps fallback points: "
        f"expected 2 matches, found {ride.count(restore_reset_block)}"
    )

ride = ride.replace(restore_reset_block, restore_from_snapshot_block, 1)
ride = ride.replace(restore_reset_block, restore_from_service_snapshot_block, 1)

insert_after_handle_route = r'''  void handleGpsFallbackPoint(RideRoutePoint point) {
    if (!_state.isRouteRecordingActive || !point.isValid) {
      return;
    }

    if (isConsoleConnected) {
      _lastGpsFallbackDistancePoint = point;
      return;
    }

    if (!_state.isRunning) {
      _lastGpsFallbackDistancePoint = point;
      return;
    }

    final nowEpochMs = point.timestampMs > 0
        ? point.timestampMs
        : DateTime.now().millisecondsSinceEpoch;

    final lastPoint = _lastGpsFallbackDistancePoint;
    _lastGpsFallbackDistancePoint = point;

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

    final fallbackSpeedKmph = rawFallbackSpeedKmph.isFinite
        ? rawFallbackSpeedKmph.clamp(0.0, _gpsFallbackMaxReasonableSpeedKmph)
              .toDouble()
        : 0.0;

    final gpsMoving =
        gpsSpeedMps >= _gpsFallbackMinMovingSpeedMps || deltaMeters > 0;

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
    } else {
      _checkAutoPause(nowEpochMs);
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

    final fallbackRpm = _rpmFromSpeedKmph(fallbackSpeedKmph);

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

ride = replace_once(
    ride,
    "  void handleSensorPacket(BikeSensorPacket packet) {\n",
    insert_after_handle_route + "  void handleSensorPacket(BikeSensorPacket packet) {\n",
    "insert handleGpsFallbackPoint",
)

ride = replace_once(
    ride,
    "    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n\n    _state = _state.copyWith(\n",
    "    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n    _lastGpsFallbackDistancePoint = null;\n\n    _state = _state.copyWith(\n",
    "beginCountdown reset gps fallback",
)

ride = replace_once(
    ride,
    "    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = startMs;\n    _lastConsoleSyncEpochMs = null;\n\n    _state = _state.copyWith(\n",
    "    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = startMs;\n    _lastConsoleSyncEpochMs = null;\n    _lastGpsFallbackDistancePoint = null;\n\n    _state = _state.copyWith(\n",
    "finishCountdown reset gps fallback",
)

ride = replace_once(
    ride,
    "    _notMovingSinceEpochMs = null;\n    _lastSnapshotSaveEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n    _lastIndicatorCommandEpochMs = null;\n\n    onCommand?.call(BikeCommand.stop());\n",
    "    _notMovingSinceEpochMs = null;\n    _lastSnapshotSaveEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n    _lastIndicatorCommandEpochMs = null;\n    _lastGpsFallbackDistancePoint = null;\n\n    onCommand?.call(BikeCommand.stop());\n",
    "stopRide reset gps fallback",
)

ride = replace_once(
    ride,
    "  double _largerDistance(double appDistanceKm, double espDistanceKm) {\n    if (espDistanceKm > appDistanceKm) {\n      return espDistanceKm;\n    }\n\n    return appDistanceKm;\n  }\n\n  double _speedFromRpm(double rpm) {\n",
    "  double _largerDistance(double appDistanceKm, double espDistanceKm) {\n    if (espDistanceKm > appDistanceKm) {\n      return espDistanceKm;\n    }\n\n    return appDistanceKm;\n  }\n\n  double _distanceBetweenRoutePointsMeters(\n    RideRoutePoint from,\n    RideRoutePoint to,\n  ) {\n    const earthRadiusMeters = 6371000.0;\n\n    final fromLat = _degreesToRadians(from.latitude);\n    final toLat = _degreesToRadians(to.latitude);\n    final deltaLat = _degreesToRadians(to.latitude - from.latitude);\n    final deltaLng = _degreesToRadians(to.longitude - from.longitude);\n\n    final sinHalfLat = math.sin(deltaLat / 2);\n    final sinHalfLng = math.sin(deltaLng / 2);\n\n    final a = sinHalfLat * sinHalfLat +\n        math.cos(fromLat) * math.cos(toLat) * sinHalfLng * sinHalfLng;\n\n    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));\n\n    return earthRadiusMeters * c;\n  }\n\n  double _degreesToRadians(double degrees) {\n    return degrees * math.pi / 180.0;\n  }\n\n  double _rpmFromSpeedKmph(double speedKmph) {\n    if (speedKmph <= 0 || _settings.tyreCircumferenceMeters <= 0) return 0;\n\n    final speedMps = speedKmph * 1000.0 / 3600.0;\n    return speedMps / _settings.tyreCircumferenceMeters * 60.0;\n  }\n\n  double _speedFromRpm(double rpm) {\n",
    "insert gps distance helpers",
)

dash = replace_once(
    dash,
    "  void _handleRoutePoint(RideRoutePoint point) {\n    widget.bikeConsoleController.rideSessionController.handleRoutePoint(point);\n  }\n",
    "  void _handleRoutePoint(RideRoutePoint point) {\n    final rideController = widget.bikeConsoleController.rideSessionController;\n    rideController.handleRoutePoint(point);\n    rideController.handleGpsFallbackPoint(point);\n  }\n",
    "dashboard route point fallback hook",
)

write(ride_path, ride)
write(dash_path, dash)
print("Batch 5A patch applied successfully.")
