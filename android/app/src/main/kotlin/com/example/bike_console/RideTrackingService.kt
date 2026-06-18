package com.example.bike_console

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.roundToInt

class RideTrackingService : Service() {
    companion object {
        const val ACTION_START = "com.example.bike_console.ride.START"
        const val ACTION_UPDATE = "com.example.bike_console.ride.UPDATE"
        const val ACTION_PAUSE = "com.example.bike_console.ride.PAUSE"
        const val ACTION_RESUME = "com.example.bike_console.ride.RESUME"
        const val ACTION_STOP = "com.example.bike_console.ride.STOP"
        const val ACTION_SERVICE_EVENT = "com.example.bike_console.ride.SERVICE_EVENT"

        const val EXTRA_DISTANCE_KM = "distanceKm"
        const val EXTRA_ELAPSED_ACTIVE_MS = "elapsedActiveMs"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_FROM_FLUTTER = "fromFlutter"
        const val EXTRA_SERVICE_EVENT_ACTION = "serviceEventAction"

        const val PENDING_PREFS = "bike_console_ride_service_pending"
        const val PENDING_ACTION_KEY = "pendingAction"

        const val SNAPSHOT_PREFS = "bike_console_ride_service_snapshot"
        const val SNAPSHOT_JSON_KEY = "activeRideSnapshotJson"

        fun loadActiveRideSnapshotJson(context: Context): String? {
            return context
                .getSharedPreferences(SNAPSHOT_PREFS, Context.MODE_PRIVATE)
                .getString(SNAPSHOT_JSON_KEY, null)
        }

        private const val SERVICE_ACTION_PAUSE = "pause"
        private const val SERVICE_ACTION_RESUME = "resume"
        private const val SERVICE_ACTION_STOP = "stop"

        private const val CHANNEL_ID = "bike_console_active_ride"
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
    private var elapsedActiveMs: Long = 0L
    private var activeElapsedBaseMs: Long = 0L
    private var activeRealtimeBaseMs: Long? = null
    private var paused: Boolean = false
    private var foregroundStarted = false
    private var nativeLocationPointCount = 0

    private var rideStartEpochMs: Long? = null
    private var currentPauseStartEpochMs: Long? = null
    private var accumulatedPausedMs: Long = 0L
    private var nativeGpsDistanceKm: Double = 0.0
    private var lastAcceptedNativeRoutePoint: NativeRoutePoint? = null
    private val nativeRoutePoints = mutableListOf<NativeRoutePoint>()

    private var locationManager: LocationManager? = null
    private val notificationHandler = Handler(Looper.getMainLooper())

    private val notificationTick = object : Runnable {
        override fun run() {
            if (!foregroundStarted) return

            updateForegroundNotification()

            if (!paused) {
                notificationHandler.postDelayed(this, 1000L)
            }
        }
    }

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            nativeLocationPointCount += 1
            appendNativeRoutePoint(location)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        restoreRuntimeFromSnapshotIfPossible()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val fromFlutter = intent?.getBooleanExtra(EXTRA_FROM_FLUTTER, false) ?: false

        if (fromFlutter || action == ACTION_START || action == ACTION_UPDATE) {
            updateStateFromIntent(intent)
        } else {
            // Notification actions are handled by the already-running service.
            // Do not trust old PendingIntent extras for elapsed time.
            syncElapsedFromClock()
        }

        when (action) {
            ACTION_START -> startRide()
            ACTION_UPDATE -> updateForegroundNotification()
            ACTION_PAUSE -> {
                pauseRide()
                publishServiceActionIfNeeded(SERVICE_ACTION_PAUSE, fromFlutter)
            }
            ACTION_RESUME -> {
                resumeRide()
                publishServiceActionIfNeeded(SERVICE_ACTION_RESUME, fromFlutter)
            }
            ACTION_STOP -> {
                publishServiceActionIfNeeded(SERVICE_ACTION_STOP, fromFlutter)
                stopRide()
            }
            else -> startRide()
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep the foreground ride alive when the Flutter activity is removed from Recents.
        updateForegroundNotification()
        scheduleNotificationTickerIfNeeded()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopNotificationTicker()
        stopLocationUpdates()
        super.onDestroy()
    }

    private fun updateStateFromIntent(intent: Intent?) {
        if (intent == null) return

        val nextPaused = if (intent.hasExtra(EXTRA_PAUSED)) {
            intent.getBooleanExtra(EXTRA_PAUSED, paused)
        } else {
            paused
        }

        if (intent.hasExtra(EXTRA_DISTANCE_KM)) {
            distanceKm = intent.getDoubleExtra(EXTRA_DISTANCE_KM, distanceKm)
        }

        if (intent.hasExtra(EXTRA_ELAPSED_ACTIVE_MS)) {
            elapsedActiveMs = intent.getLongExtra(
                EXTRA_ELAPSED_ACTIVE_MS,
                currentElapsedActiveMs(),
            )
        } else {
            elapsedActiveMs = currentElapsedActiveMs()
        }

        paused = nextPaused
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
        activeElapsedBaseMs = elapsedActiveMs
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
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = null
        paused = true
        currentPauseStartEpochMs = System.currentTimeMillis()
        startInForeground()
        startLocationUpdates()
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
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        currentPauseStartEpochMs = null
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
        persistActiveSnapshot()
    }

    private fun stopRide() {
        syncElapsedFromClock()
        stopNotificationTicker()
        stopLocationUpdates()
        foregroundStarted = false
        clearActiveSnapshot()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        stopSelf()
    }

    private fun publishServiceActionIfNeeded(serviceAction: String, fromFlutter: Boolean) {
        if (fromFlutter) return

        savePendingAction(serviceAction)

        val eventIntent = Intent(ACTION_SERVICE_EVENT).apply {
            setPackage(packageName)
            putExtra(EXTRA_SERVICE_EVENT_ACTION, serviceAction)
        }

        sendBroadcast(eventIntent)
    }

    private fun savePendingAction(serviceAction: String) {
        getSharedPreferences(PENDING_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(PENDING_ACTION_KEY, serviceAction)
            .apply()
    }

    private fun startInForeground() {
        val notification = buildNotification()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: SecurityException) {
            // If a test build starts before location permission is ready, keep the
            // service alive as a normal foreground service instead of crashing.
            startForeground(NOTIFICATION_ID, notification)
        }

        foregroundStarted = true
    }

    private fun updateForegroundNotification() {
        if (!foregroundStarted) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val status = if (paused) "Ride paused" else "Ride active"
        val text = "$status • ${formatDistance(distanceKm)} • ${formatElapsed(currentElapsedActiveMs())}"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle("Bike Console")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(openAppPendingIntent())
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setShowWhen(false)

        if (paused) {
            builder.addAction(
                android.R.drawable.ic_media_play,
                "Resume",
                servicePendingIntent(ACTION_RESUME, 2),
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                servicePendingIntent(ACTION_STOP, 3),
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                servicePendingIntent(ACTION_PAUSE, 1),
            )
        }

        return builder.build()
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: Intent(this, MainActivity::class.java)

        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, RideTrackingService::class.java).apply {
            this.action = action
            putExtra(EXTRA_DISTANCE_KM, distanceKm)
            putExtra(EXTRA_ELAPSED_ACTIVE_MS, currentElapsedActiveMs())
            putExtra(EXTRA_PAUSED, paused)
            putExtra(EXTRA_FROM_FLUTTER, false)
        }

        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun appendNativeRoutePoint(location: Location) {
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

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows active Bike Console ride tracking."
            setShowBadge(false)
        }

        manager.createNotificationChannel(channel)
    }

    private fun startLocationUpdates() {
        val manager = locationManager ?: return

        val hasFineLocation = checkSelfPermissionCompat(Manifest.permission.ACCESS_FINE_LOCATION)
        val hasCoarseLocation = checkSelfPermissionCompat(Manifest.permission.ACCESS_COARSE_LOCATION)

        if (!hasFineLocation && !hasCoarseLocation) return

        try {
            if (manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER,
                    1000L,
                    0f,
                    locationListener,
                    Looper.getMainLooper(),
                )
            }

            if (manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    1500L,
                    0f,
                    locationListener,
                    Looper.getMainLooper(),
                )
            }
        } catch (_: SecurityException) {
            // Permission changed while service was running.
        } catch (_: IllegalArgumentException) {
            // Provider disappeared or is unavailable on this device.
        }
    }

    private fun stopLocationUpdates() {
        try {
            locationManager?.removeUpdates(locationListener)
        } catch (_: SecurityException) {
            // Permission changed while service was running.
        }
    }

    private fun scheduleNotificationTickerIfNeeded() {
        stopNotificationTicker()

        if (foregroundStarted && !paused) {
            notificationHandler.postDelayed(notificationTick, 1000L)
        }
    }

    private fun stopNotificationTicker() {
        notificationHandler.removeCallbacks(notificationTick)
    }

    private fun currentElapsedActiveMs(): Long {
        if (paused) return elapsedActiveMs.coerceAtLeast(0L)

        val baseRealtime = activeRealtimeBaseMs ?: return elapsedActiveMs.coerceAtLeast(0L)
        val delta = SystemClock.elapsedRealtime() - baseRealtime

        return (activeElapsedBaseMs + delta).coerceAtLeast(0L)
    }

    private fun Float.isFinite(): Boolean {
        return !isNaN() && !isInfinite()
    }

    private fun syncElapsedFromClock() {
        elapsedActiveMs = currentElapsedActiveMs()
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = if (paused) null else SystemClock.elapsedRealtime()
    }

    private fun checkSelfPermissionCompat(permission: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun formatDistance(value: Double): String {
        return "${(value * 100.0).roundToInt() / 100.0} km"
    }

    private fun formatElapsed(valueMs: Long): String {
        val totalSeconds = (valueMs / 1000L).coerceAtLeast(0L)
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L

        return if (hours > 0L) {
            "%02d:%02d:%02d".format(hours, minutes, seconds)
        } else {
            "%02d:%02d".format(minutes, seconds)
        }
    }
}
