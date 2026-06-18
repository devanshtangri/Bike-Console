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

        private const val SERVICE_ACTION_PAUSE = "pause"
        private const val SERVICE_ACTION_RESUME = "resume"
        private const val SERVICE_ACTION_STOP = "stop"

        private const val CHANNEL_ID = "bike_console_active_ride"
        private const val CHANNEL_NAME = "Active ride"
        private const val NOTIFICATION_ID = 1207
    }

    private var distanceKm: Double = 0.0
    private var elapsedActiveMs: Long = 0L
    private var activeElapsedBaseMs: Long = 0L
    private var activeRealtimeBaseMs: Long? = null
    private var paused: Boolean = false
    private var foregroundStarted = false
    private var nativeLocationPointCount = 0

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
            // Flutter still renders the visible route in this batch.
            // Native route persistence will be added in the next architecture batch.
            nativeLocationPointCount += 1
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
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
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = if (paused) null else SystemClock.elapsedRealtime()
    }

    private fun startRide() {
        paused = false
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
    }

    private fun pauseRide() {
        elapsedActiveMs = currentElapsedActiveMs()
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = null
        paused = true
        startInForeground()
        startLocationUpdates()
        stopNotificationTicker()
        updateForegroundNotification()
    }

    private fun resumeRide() {
        paused = false
        activeElapsedBaseMs = elapsedActiveMs
        activeRealtimeBaseMs = SystemClock.elapsedRealtime()
        startInForeground()
        startLocationUpdates()
        scheduleNotificationTickerIfNeeded()
    }

    private fun stopRide() {
        syncElapsedFromClock()
        stopNotificationTicker()
        stopLocationUpdates()
        foregroundStarted = false

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
