
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
        raise RuntimeError(f"{path}: expected exactly 1 match, found {count} for:\n{old[:500]}")
    return content.replace(old, new, 1)

path = "android/app/src/main/kotlin/com/example/bike_console/RideTrackingService.kt"
content = read(path)

content = replace_once(
    content,
    """import android.os.SystemClock
import kotlin.math.roundToInt
""",
    """import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToInt
""",
    path,
)

content = replace_once(
    content,
    """        const val PENDING_PREFS = "bike_console_ride_service_pending"
        const val PENDING_ACTION_KEY = "pendingAction"

        private const val SERVICE_ACTION_PAUSE = "pause"
""",
    """        const val PENDING_PREFS = "bike_console_ride_service_pending"
        const val PENDING_ACTION_KEY = "pendingAction"

        const val SNAPSHOT_PREFS = "bike_console_ride_service_snapshot"
        const val SNAPSHOT_JSON_KEY = "activeRideSnapshotJson"

        fun loadActiveRideSnapshotJson(context: Context): String? {
            return context
                .getSharedPreferences(SNAPSHOT_PREFS, Context.MODE_PRIVATE)
                .getString(SNAPSHOT_JSON_KEY, null)
        }

        private const val SERVICE_ACTION_PAUSE = "pause"
""",
    path,
)

content = replace_once(
    content,
    """        private const val CHANNEL_ID = "bike_console_active_ride"
        private const val CHANNEL_NAME = "Active ride"
        private const val NOTIFICATION_ID = 1207
    }

    private var distanceKm: Double = 0.0
""",
    """        private const val CHANNEL_ID = "bike_console_active_ride"
        private const val CHANNEL_NAME = "Active ride"
        private const val NOTIFICATION_ID = 1207

        private const val MAX_NATIVE_ROUTE_POINTS = 20000
        private const val MAX_ACCEPTED_ACCURACY_METERS = 80.0
        private const val MAX_REASONABLE_GPS_SEGMENT_METERS = 140.0
    }

    private data class NativeRoutePoint(
        val latitude: Double,
        val longitude: Double,
        val timestampMs: Long,
        val accuracyMeters: Double,
        val gpsSpeedMps: Double,
        val rideMode: String,
    )

    private var distanceKm: Double = 0.0
""",
    path,
)

content = replace_once(
    content,
    """    private var paused: Boolean = false
    private var foregroundStarted = false
    private var nativeLocationPointCount = 0

    private var locationManager: LocationManager? = null
""",
    """    private var paused: Boolean = false
    private var foregroundStarted = false
    private var nativeLocationPointCount = 0

    private var rideStartEpochMs: Long? = null
    private var currentPauseStartEpochMs: Long? = null
    private var accumulatedPausedMs: Long = 0L
    private var nativeGpsDistanceKm: Double = 0.0
    private var lastAcceptedNativeRoutePoint: NativeRoutePoint? = null
    private val nativeRoutePoints = mutableListOf<NativeRoutePoint>()

    private var locationManager: LocationManager? = null
""",
    path,
)

content = replace_once(
    content,
    """    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            // Flutter still renders the visible route in this batch.
            // Native route persistence will be added in the next architecture batch.
            nativeLocationPointCount += 1
        }
    }
""",
    """    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            nativeLocationPointCount += 1
            appendNativeRoutePoint(location)
        }
    }
""",
    path,
)

content = replace_once(
    content,
    """    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    }
""",
    """    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        restoreRuntimeFromSnapshotIfPossible()
    }
""",
    path,
)

content = replace_once(
    content,
    """        paused = nextPaused
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = if (paused) null else SystemClock.elapsedRealtime()
    }

    private fun startRide() {
        paused = false
""",
    """        paused = nextPaused
        if (distanceKm > nativeGpsDistanceKm) {
            nativeGpsDistanceKm = distanceKm
        }
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = if (paused) null else SystemClock.elapsedRealtime()

        if (rideStartEpochMs == null) {
            rideStartEpochMs = System.currentTimeMillis() - elapsedActiveMs
        }

        if (paused && currentPauseStartEpochMs == null) {
            currentPauseStartEpochMs = System.currentTimeMillis()
        } else if (!paused) {
            currentPauseStartEpochMs = null
        }

        persistActiveSnapshot()
    }

    private fun startRide() {
        if (!foregroundStarted) {
            nativeRoutePoints.clear()
            lastAcceptedNativeRoutePoint = null
            nativeGpsDistanceKm = distanceKm
            accumulatedPausedMs = 0L
            currentPauseStartEpochMs = null
            rideStartEpochMs = System.currentTimeMillis() - elapsedActiveMs
        }

        paused = false
""",
    path,
)

content = replace_once(
    content,
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
    }

    private fun pauseRide() {
        elapsedActiveMs = currentElapsedActiveMs()
""",
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        if (rideStartEpochMs == null) {
            rideStartEpochMs = System.currentTimeMillis() - elapsedActiveMs
        }
        currentPauseStartEpochMs = null
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
        persistActiveSnapshot()
    }

    private fun pauseRide() {
        elapsedActiveMs = currentElapsedActiveMs()
""",
    path,
)

content = replace_once(
    content,
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = null
        paused = true
        startInForeground()
""",
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = null
        paused = true
        currentPauseStartEpochMs = System.currentTimeMillis()
        startInForeground()
""",
    path,
)

content = replace_once(
    content,
    """        startLocationUpdates()
        stopNotificationTicker()
        updateForegroundNotification()
    }

    private fun resumeRide() {
        paused = false
""",
    """        startLocationUpdates()
        stopNotificationTicker()
        updateForegroundNotification()
        persistActiveSnapshot()
    }

    private fun resumeRide() {
        val now = System.currentTimeMillis()
        val pauseStart = currentPauseStartEpochMs
        if (pauseStart != null) {
            accumulatedPausedMs += (now - pauseStart).coerceAtLeast(0L)
        }

        paused = false
""",
    path,
)

content = replace_once(
    content,
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
    }

    private fun stopRide() {
""",
    """        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        currentPauseStartEpochMs = null
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
        persistActiveSnapshot()
    }

    private fun stopRide() {
""",
    path,
)

content = replace_once(
    content,
    """        foregroundStarted = false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
""",
    """        foregroundStarted = false
        clearActiveSnapshot()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
""",
    path,
)

content = replace_once(
    content,
    """    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
""",
    """    private fun appendNativeRoutePoint(location: Location) {
        if (!foregroundStarted) return
        if (location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0) return

        val accuracy = if (location.hasAccuracy()) {
            location.accuracy.toDouble().coerceAtLeast(0.0)
        } else {
            0.0
        }

        if (accuracy > MAX_ACCEPTED_ACCURACY_METERS) {
            return
        }

        val gpsSpeed = if (location.hasSpeed() && location.speed.isFinite() && location.speed > 0f) {
            location.speed.toDouble()
        } else {
            0.0
        }

        val mode = if (paused) "paused" else "running"
        val point = NativeRoutePoint(
            latitude = location.latitude,
            longitude = location.longitude,
            timestampMs = System.currentTimeMillis(),
            accuracyMeters = accuracy,
            gpsSpeedMps = gpsSpeed,
            rideMode = mode,
        )

        val last = lastAcceptedNativeRoutePoint

        if (last != null &&
            last.latitude == point.latitude &&
            last.longitude == point.longitude &&
            last.rideMode == point.rideMode
        ) {
            return
        }

        if (last != null && !paused) {
            val segmentMeters = distanceBetweenMeters(last, point)

            if (segmentMeters in 0.0..MAX_REASONABLE_GPS_SEGMENT_METERS) {
                nativeGpsDistanceKm += segmentMeters / 1000.0
                distanceKm = max(distanceKm, nativeGpsDistanceKm)
            }
        }

        nativeRoutePoints.add(point)

        if (nativeRoutePoints.size > MAX_NATIVE_ROUTE_POINTS) {
            nativeRoutePoints.removeAt(0)
        }

        lastAcceptedNativeRoutePoint = point

        persistActiveSnapshot()
        updateForegroundNotification()
    }

    private fun distanceBetweenMeters(from: NativeRoutePoint, to: NativeRoutePoint): Double {
        val result = FloatArray(1)

        Location.distanceBetween(
            from.latitude,
            from.longitude,
            to.latitude,
            to.longitude,
            result,
        )

        return result.firstOrNull()?.toDouble() ?: 0.0
    }

    private fun persistActiveSnapshot() {
        if (!foregroundStarted) return

        val snapshotJson = buildActiveSnapshotJson()

        getSharedPreferences(SNAPSHOT_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(SNAPSHOT_JSON_KEY, snapshotJson)
            .apply()
    }

    private fun clearActiveSnapshot() {
        getSharedPreferences(SNAPSHOT_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(SNAPSHOT_JSON_KEY)
            .apply()
    }

    private fun buildActiveSnapshotJson(): String {
        val routePointsJson = JSONArray()

        nativeRoutePoints.forEach { point ->
            routePointsJson.put(
                JSONObject()
                    .put("lat", point.latitude)
                    .put("lng", point.longitude)
                    .put("timestampMs", point.timestampMs)
                    .put("accuracyMeters", point.accuracyMeters)
                    .put("gpsSpeedMps", point.gpsSpeedMps)
                    .put("rideMode", point.rideMode)
                    .put("source", "gps"),
            )
        }

        val currentRideState = if (paused) "paused" else "running"
        val currentPauseReason = if (paused) "manual" else "none"

        return JSONObject()
            .put("rideState", currentRideState)
            .put("pauseReason", currentPauseReason)
            .put("rideStartEpochMs", rideStartEpochMs)
            .put("currentPauseStartEpochMs", currentPauseStartEpochMs)
            .put("accumulatedPausedMs", accumulatedPausedMs)
            .put("distanceKm", max(distanceKm, nativeGpsDistanceKm))
            .put("averageSpeedKmph", 0.0)
            .put("maxSpeedKmph", 0.0)
            .put("routePoints", routePointsJson)
            .put("autoPauseSuppressedUntilMovement", false)
            .put("hazardEnabled", false)
            .put("appLeftIndicator", false)
            .put("appRightIndicator", false)
            .toString()
    }

    private fun restoreRuntimeFromSnapshotIfPossible() {
        val rawSnapshot = loadActiveRideSnapshotJson(this) ?: return

        try {
            val json = JSONObject(rawSnapshot)
            val rideState = json.optString("rideState", "stopped")
            if (rideState == "stopped") return

            paused = rideState == "paused"
            rideStartEpochMs = if (json.isNull("rideStartEpochMs")) {
                null
            } else {
                json.optLong("rideStartEpochMs")
            }
            currentPauseStartEpochMs = if (json.isNull("currentPauseStartEpochMs")) {
                null
            } else {
                json.optLong("currentPauseStartEpochMs")
            }
            accumulatedPausedMs = json.optLong("accumulatedPausedMs", 0L)
            distanceKm = json.optDouble("distanceKm", 0.0)
            nativeGpsDistanceKm = distanceKm
            elapsedActiveMs = currentElapsedFromWallClock()
            activeElapsedBaseMs = elapsedActiveMs
            activeRealtimeBaseMs = if (paused) null else SystemClock.elapsedRealtime()

            nativeRoutePoints.clear()
            val routeArray = json.optJSONArray("routePoints") ?: JSONArray()

            for (index in 0 until routeArray.length()) {
                val pointJson = routeArray.optJSONObject(index) ?: continue
                val point = NativeRoutePoint(
                    latitude = pointJson.optDouble("lat", 0.0),
                    longitude = pointJson.optDouble("lng", 0.0),
                    timestampMs = pointJson.optLong("timestampMs", 0L),
                    accuracyMeters = pointJson.optDouble("accuracyMeters", 0.0),
                    gpsSpeedMps = pointJson.optDouble("gpsSpeedMps", 0.0),
                    rideMode = pointJson.optString("rideMode", "running"),
                )

                if (point.latitude in -90.0..90.0 && point.longitude in -180.0..180.0) {
                    nativeRoutePoints.add(point)
                    lastAcceptedNativeRoutePoint = point
                }
            }
        } catch (_: Throwable) {
            clearActiveSnapshot()
        }
    }

    private fun currentElapsedFromWallClock(): Long {
        val start = rideStartEpochMs ?: return elapsedActiveMs
        val now = System.currentTimeMillis()
        val livePauseMs = if (paused && currentPauseStartEpochMs != null) {
            now - currentPauseStartEpochMs!!
        } else {
            0L
        }

        return (now - start - accumulatedPausedMs - livePauseMs).coerceAtLeast(0L)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
""",
    path,
)

content = replace_once(
    content,
    """        return (activeElapsedBaseMs + delta).coerceAtLeast(0L)
    }

    private fun syncElapsedFromClock() {
""",
    """        return (activeElapsedBaseMs + delta).coerceAtLeast(0L)
    }

    private fun Float.isFinite(): Boolean {
        return !isNaN() && !isInfinite()
    }

    private fun syncElapsedFromClock() {
""",
    path,
)

write(path, content)

path = "android/app/src/main/kotlin/com/example/bike_console/MainActivity.kt"
content = read(path)

content = replace_once(
    content,
    """                    "consumePendingAction" -> {
                        result.success(consumePendingRideAction())
                    }

                    else -> result.notImplemented()
""",
    """                    "consumePendingAction" -> {
                        result.success(consumePendingRideAction())
                    }

                    "loadActiveRideSnapshotJson" -> {
                        result.success(RideTrackingService.loadActiveRideSnapshotJson(this))
                    }

                    else -> result.notImplemented()
""",
    path,
)

write(path, content)

path = "lib/services/foreground_ride_service.dart"
content = read(path)

content = replace_once(
    content,
    """import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
""",
    """import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ride_models.dart';
""",
    path,
)

content = replace_once(
    content,
    """  Future<String?> consumePendingAction() async {
    if (!Platform.isAndroid) return null;

    try {
      final value = await _channel.invokeMethod<String>('consumePendingAction');
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } on PlatformException catch (error) {
      debugPrint(
        'ForegroundRideService.consumePendingAction failed: ${error.code} ${error.message}',
      );
      return null;
    } catch (error) {
      debugPrint('ForegroundRideService.consumePendingAction failed: $error');
      return null;
    }
  }

  Future<void> start({
""",
    """  Future<String?> consumePendingAction() async {
    if (!Platform.isAndroid) return null;

    try {
      final value = await _channel.invokeMethod<String>('consumePendingAction');
      if (value == null || value.trim().isEmpty) return null;
      return value;
    } on PlatformException catch (error) {
      debugPrint(
        'ForegroundRideService.consumePendingAction failed: ${error.code} ${error.message}',
      );
      return null;
    } catch (error) {
      debugPrint('ForegroundRideService.consumePendingAction failed: $error');
      return null;
    }
  }

  Future<PersistedRideSnapshot?> loadActiveRideSnapshot() async {
    if (!Platform.isAndroid) return null;

    try {
      final raw = await _channel.invokeMethod<String>(
        'loadActiveRideSnapshotJson',
      );

      if (raw == null || raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) return null;

      final snapshot = PersistedRideSnapshot.fromJson(decoded);

      if (snapshot.rideState == RideState.stopped) return null;

      return snapshot;
    } on PlatformException catch (error) {
      debugPrint(
        'ForegroundRideService.loadActiveRideSnapshot failed: ${error.code} ${error.message}',
      );
      return null;
    } catch (error) {
      debugPrint('ForegroundRideService.loadActiveRideSnapshot failed: $error');
      return null;
    }
  }

  Future<void> start({
""",
    path,
)

write(path, content)

path = "lib/controllers/ride_session_controller.dart"
content = read(path)

content = replace_once(
    content,
    """  void restoreFromSnapshot(PersistedRideSnapshot snapshot) {
    _state = snapshot.toSessionState();

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;

    if (_state.rideState == RideState.running) {
      _startDurationTicker();
    } else {
      _stopDurationTicker();
    }

    notifyListeners();
  }

  void handleRoutePoint(RideRoutePoint point) {
""",
    """  void restoreFromSnapshot(PersistedRideSnapshot snapshot) {
    _state = snapshot.toSessionState();

    _notMovingSinceEpochMs = null;
    _lastAverageSpeedUpdateEpochMs = null;
    _lastConsoleSyncEpochMs = null;

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

    final nextDistanceKm = snapshotState.distanceKm > _state.distanceKm
        ? snapshotState.distanceKm
        : _state.distanceKm;

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

    if (_state.rideState == RideState.running) {
      _startDurationTicker();
    } else {
      _stopDurationTicker();
    }

    _persistSnapshotFireAndForget(force: true);
    notifyListeners();
  }

  void handleRoutePoint(RideRoutePoint point) {
""",
    path,
)

write(path, content)

path = "lib/controllers/bike_console_controller.dart"
content = read(path)

content = replace_once(
    content,
    """    await rideSessionController.initialize();
    await connectionController.initialize();
    await _consumePendingForegroundRideAction();

    _syncForegroundRideService(force: true);
""",
    """    await rideSessionController.initialize();
    await _restoreForegroundRideSnapshotIfAvailable();
    await connectionController.initialize();
    await _consumePendingForegroundRideAction();

    _syncForegroundRideService(force: true);
""",
    path,
)

content = replace_once(
    content,
    """  Future<void> _consumePendingForegroundRideAction() async {
    final pendingAction = await _foregroundRideService.consumePendingAction();
    if (pendingAction == null) return;

    _handleForegroundRideAction(pendingAction);
  }

  void _handleForegroundRideAction(String action) {
""",
    """  Future<void> _restoreForegroundRideSnapshotIfAvailable() async {
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
""",
    path,
)

write(path, content)

print("Batch 4B applied successfully.")
