from pathlib import Path

ROOT = Path.cwd()


def read(path: str) -> str:
    file_path = ROOT / path
    if not file_path.exists():
        raise FileNotFoundError(f"Missing file: {path}")
    return file_path.read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(content: str, old: str, new: str, path: str) -> str:
    count = content.count(old)
    if count != 1:
        raise RuntimeError(
            f"{path}: expected exactly 1 match, found {count} for:\n{old[:700]}"
        )
    return content.replace(old, new, 1)


# -----------------------------------------------------------------------------
# Android service: distance authority metadata + GPS fallback only when Flutter
# distance is stale. This keeps ESP/Flutter wheel distance primary while the UI
# is alive, and lets GPS advance distance only after Flutter updates stop.
# -----------------------------------------------------------------------------
path = "android/app/src/main/kotlin/com/example/bike_console/RideTrackingService.kt"
content = read(path)

content = replace_once(
    content,
    """        private const val MAX_NATIVE_ROUTE_POINTS = 20000
        private const val MAX_ACCEPTED_ACCURACY_METERS = 80.0
        private const val MAX_REASONABLE_GPS_SEGMENT_METERS = 140.0
    }
""",
    """        private const val MAX_NATIVE_ROUTE_POINTS = 20000
        private const val MAX_ACCEPTED_ACCURACY_METERS = 80.0
        private const val MAX_REASONABLE_GPS_SEGMENT_METERS = 140.0

        // If Flutter has not updated the service recently, assume the UI/engine
        // is detached and allow native GPS distance to act as the fallback.
        private const val FLUTTER_DISTANCE_FRESH_MS = 4500L
    }
""",
    path,
)

content = replace_once(
    content,
    """    private var currentPauseStartEpochMs: Long? = null
    private var accumulatedPausedMs: Long = 0L
    private var nativeGpsDistanceKm: Double = 0.0
    private var lastAcceptedNativeRoutePoint: NativeRoutePoint? = null
    private val nativeRoutePoints = mutableListOf<NativeRoutePoint>()

    private var locationManager: LocationManager? = null
""",
    """    private var currentPauseStartEpochMs: Long? = null
    private var accumulatedPausedMs: Long = 0L
    private var nativeGpsDistanceKm: Double = 0.0
    private var flutterDistanceKm: Double = 0.0
    private var lastFlutterUpdateRealtimeMs: Long? = null
    private var lastFlutterUpdateEpochMs: Long? = null
    private var lastAcceptedNativeRoutePoint: NativeRoutePoint? = null
    private val nativeRoutePoints = mutableListOf<NativeRoutePoint>()

    private var locationManager: LocationManager? = null
""",
    path,
)

content = replace_once(
    content,
    """        if (intent.hasExtra(EXTRA_DISTANCE_KM)) {
            distanceKm = intent.getDoubleExtra(EXTRA_DISTANCE_KM, distanceKm)
        }

        if (intent.hasExtra(EXTRA_ELAPSED_ACTIVE_MS)) {
""",
    """        if (intent.hasExtra(EXTRA_DISTANCE_KM)) {
            val reportedDistanceKm = intent
                .getDoubleExtra(EXTRA_DISTANCE_KM, distanceKm)
                .coerceAtLeast(0.0)

            flutterDistanceKm = reportedDistanceKm
            lastFlutterUpdateRealtimeMs = SystemClock.elapsedRealtime()
            lastFlutterUpdateEpochMs = System.currentTimeMillis()
            distanceKm = max(distanceKm, flutterDistanceKm)
        }

        if (intent.hasExtra(EXTRA_ELAPSED_ACTIVE_MS)) {
""",
    path,
)

content = replace_once(
    content,
    """        if (distanceKm > nativeGpsDistanceKm) {
            nativeGpsDistanceKm = distanceKm
        }
        activeElapsedBaseMs = elapsedActiveMs
""",
    """        if (flutterDistanceKm > nativeGpsDistanceKm) {
            nativeGpsDistanceKm = flutterDistanceKm
        }

        refreshDistanceAuthority()
        activeElapsedBaseMs = elapsedActiveMs
""",
    path,
)

content = replace_once(
    content,
    """            nativeRoutePoints.clear()
            lastAcceptedNativeRoutePoint = null
            nativeGpsDistanceKm = distanceKm
            accumulatedPausedMs = 0L
""",
    """            nativeRoutePoints.clear()
            lastAcceptedNativeRoutePoint = null
            flutterDistanceKm = distanceKm
            nativeGpsDistanceKm = distanceKm
            lastFlutterUpdateRealtimeMs = SystemClock.elapsedRealtime()
            lastFlutterUpdateEpochMs = System.currentTimeMillis()
            accumulatedPausedMs = 0L
""",
    path,
)

content = replace_once(
    content,
    """            if (segmentMeters in 0.0..MAX_REASONABLE_GPS_SEGMENT_METERS) {
                nativeGpsDistanceKm += segmentMeters / 1000.0
                distanceKm = max(distanceKm, nativeGpsDistanceKm)
            }
        }
""",
    """            if (segmentMeters in 0.0..MAX_REASONABLE_GPS_SEGMENT_METERS) {
                nativeGpsDistanceKm += segmentMeters / 1000.0
                refreshDistanceAuthority()
            }
        }
""",
    path,
)

content = replace_once(
    content,
    """    private fun persistActiveSnapshot() {
        if (!foregroundStarted) return

        val snapshotJson = buildActiveSnapshotJson()
""",
    """    private fun persistActiveSnapshot() {
        if (!foregroundStarted) return

        refreshDistanceAuthority()
        val snapshotJson = buildActiveSnapshotJson()
""",
    path,
)

content = replace_once(
    content,
    """            .put("accumulatedPausedMs", accumulatedPausedMs)
            .put("distanceKm", max(distanceKm, nativeGpsDistanceKm))
            .put("averageSpeedKmph", 0.0)
""",
    """            .put("accumulatedPausedMs", accumulatedPausedMs)
            .put("distanceKm", distanceKm)
            .put("distanceSource", currentDistanceSource())
            .put("flutterDistanceKm", flutterDistanceKm)
            .put("nativeGpsDistanceKm", nativeGpsDistanceKm)
            .put("nativeRoutePointCount", nativeRoutePoints.size)
            .put("snapshotUpdatedEpochMs", System.currentTimeMillis())
            .put("lastFlutterUpdateEpochMs", lastFlutterUpdateEpochMs)
            .put("averageSpeedKmph", 0.0)
""",
    path,
)

content = replace_once(
    content,
    """            accumulatedPausedMs = json.optLong("accumulatedPausedMs", 0L)
            distanceKm = json.optDouble("distanceKm", 0.0)
            nativeGpsDistanceKm = distanceKm
            elapsedActiveMs = currentElapsedFromWallClock()
""",
    """            accumulatedPausedMs = json.optLong("accumulatedPausedMs", 0L)
            distanceKm = json.optDouble("distanceKm", 0.0).coerceAtLeast(0.0)
            flutterDistanceKm = json.optDouble("flutterDistanceKm", distanceKm).coerceAtLeast(0.0)
            nativeGpsDistanceKm = json.optDouble("nativeGpsDistanceKm", distanceKm).coerceAtLeast(0.0)
            lastFlutterUpdateRealtimeMs = null
            lastFlutterUpdateEpochMs = if (json.isNull("lastFlutterUpdateEpochMs")) {
                null
            } else {
                json.optLong("lastFlutterUpdateEpochMs")
            }
            refreshDistanceAuthority()
            elapsedActiveMs = currentElapsedFromWallClock()
""",
    path,
)

content = replace_once(
    content,
    """        return (now - start - accumulatedPausedMs - livePauseMs).coerceAtLeast(0L)
    }

    private fun createNotificationChannel() {
""",
    """        return (now - start - accumulatedPausedMs - livePauseMs).coerceAtLeast(0L)
    }

    private fun refreshDistanceAuthority() {
        val currentDistance = distanceKm.coerceAtLeast(0.0)
        val flutterDistance = flutterDistanceKm.coerceAtLeast(0.0)
        val gpsDistance = nativeGpsDistanceKm.coerceAtLeast(0.0)

        distanceKm = if (paused) {
            max(currentDistance, flutterDistance)
        } else if (isFlutterDistanceFresh()) {
            max(currentDistance, flutterDistance)
        } else {
            max(max(currentDistance, flutterDistance), gpsDistance)
        }
    }

    private fun isFlutterDistanceFresh(): Boolean {
        val lastUpdate = lastFlutterUpdateRealtimeMs ?: return false
        val ageMs = SystemClock.elapsedRealtime() - lastUpdate
        return ageMs in 0L..FLUTTER_DISTANCE_FRESH_MS
    }

    private fun currentDistanceSource(): String {
        if (paused) return "paused"
        return if (isFlutterDistanceFresh()) "wheel" else "gpsFallback"
    }

    private fun createNotificationChannel() {
""",
    path,
)

write(path, content)


# -----------------------------------------------------------------------------
# Dart model: preserve service distance metadata for later ESP-vs-GPS
# reconciliation/debugging. Existing app logic can ignore these fields safely.
# -----------------------------------------------------------------------------
path = "lib/models/ride_models.dart"
content = read(path)

content = replace_once(
    content,
    """    required this.hazardEnabled,
    required this.appLeftIndicator,
    required this.appRightIndicator,
  });
""",
    """    required this.hazardEnabled,
    required this.appLeftIndicator,
    required this.appRightIndicator,
    this.distanceSource = 'unknown',
    this.flutterDistanceKm = 0,
    this.nativeGpsDistanceKm = 0,
    this.nativeRoutePointCount = 0,
    this.snapshotUpdatedEpochMs,
    this.lastFlutterUpdateEpochMs,
  });
""",
    path,
)

content = replace_once(
    content,
    """  final bool hazardEnabled;
  final bool appLeftIndicator;
  final bool appRightIndicator;

  factory PersistedRideSnapshot.fromSessionState(RideSessionState state) {
""",
    """  final bool hazardEnabled;
  final bool appLeftIndicator;
  final bool appRightIndicator;

  /// Distance metadata supplied by the Android foreground service.
  /// These fields prepare future ESP wheel-distance vs GPS fallback reconciliation.
  final String distanceSource;
  final double flutterDistanceKm;
  final double nativeGpsDistanceKm;
  final int nativeRoutePointCount;
  final int? snapshotUpdatedEpochMs;
  final int? lastFlutterUpdateEpochMs;

  factory PersistedRideSnapshot.fromSessionState(RideSessionState state) {
""",
    path,
)

content = replace_once(
    content,
    """      hazardEnabled: state.hazardEnabled,
      appLeftIndicator: state.appLeftIndicator,
      appRightIndicator: state.appRightIndicator,
    );
  }
""",
    """      hazardEnabled: state.hazardEnabled,
      appLeftIndicator: state.appLeftIndicator,
      appRightIndicator: state.appRightIndicator,
      distanceSource: state.speedSource.name,
      flutterDistanceKm: state.distanceKm,
      nativeGpsDistanceKm: state.distanceKm,
      nativeRoutePointCount: state.routePoints.length,
    );
  }
""",
    path,
)

content = replace_once(
    content,
    """      hazardEnabled: json['hazardEnabled'] == true,
      appLeftIndicator: json['appLeftIndicator'] == true,
      appRightIndicator: json['appRightIndicator'] == true,
    );
  }
""",
    """      hazardEnabled: json['hazardEnabled'] == true,
      appLeftIndicator: json['appLeftIndicator'] == true,
      appRightIndicator: json['appRightIndicator'] == true,
      distanceSource: _readString(json['distanceSource'], fallback: 'unknown'),
      flutterDistanceKm: BikeSensorPacket._readDouble(json['flutterDistanceKm']),
      nativeGpsDistanceKm: BikeSensorPacket._readDouble(json['nativeGpsDistanceKm']),
      nativeRoutePointCount: _readInt(json['nativeRoutePointCount']),
      snapshotUpdatedEpochMs: _readNullableInt(json['snapshotUpdatedEpochMs']),
      lastFlutterUpdateEpochMs: _readNullableInt(
        json['lastFlutterUpdateEpochMs'],
      ),
    );
  }
""",
    path,
)

content = replace_once(
    content,
    """      'hazardEnabled': hazardEnabled,
      'appLeftIndicator': appLeftIndicator,
      'appRightIndicator': appRightIndicator,
    };
  }
""",
    """      'hazardEnabled': hazardEnabled,
      'appLeftIndicator': appLeftIndicator,
      'appRightIndicator': appRightIndicator,
      'distanceSource': distanceSource,
      'flutterDistanceKm': flutterDistanceKm,
      'nativeGpsDistanceKm': nativeGpsDistanceKm,
      'nativeRoutePointCount': nativeRoutePointCount,
      'snapshotUpdatedEpochMs': snapshotUpdatedEpochMs,
      'lastFlutterUpdateEpochMs': lastFlutterUpdateEpochMs,
    };
  }
""",
    path,
)

content = replace_once(
    content,
    """  static RideState _readRideState(dynamic value) {
    return RideState.values.firstWhere(
""",
    """  static String _readString(dynamic value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  static RideState _readRideState(dynamic value) {
    return RideState.values.firstWhere(
""",
    path,
)

write(path, content)

print("Batch 4C applied successfully.")
