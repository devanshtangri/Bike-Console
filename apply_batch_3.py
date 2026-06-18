from pathlib import Path

ROOT = Path.cwd()


def replace_exact(path: str, old: str, new: str) -> None:
    file_path = ROOT / path
    text = file_path.read_text(encoding='utf-8')
    if old not in text:
        raise RuntimeError(f"Expected block not found in {path}:\n{old[:500]}")
    file_path.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_all(path: str, old: str, new: str) -> None:
    file_path = ROOT / path
    text = file_path.read_text(encoding='utf-8')
    count = text.count(old)
    if count == 0:
        raise RuntimeError(f"Expected text not found in {path}: {old!r}")
    file_path.write_text(text.replace(old, new), encoding='utf-8')


def write_file(path: str, content: str) -> None:
    file_path = ROOT / path
    if not file_path.exists():
        raise RuntimeError(f"File does not exist: {path}")
    file_path.write_text(content, encoding='utf-8')


MAIN_ACTIVITY = r'''package com.example.bike_console

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val rideServiceChannelName = "bike_console/foreground_ride_service"
    private val rideServiceEventChannelName = "bike_console/foreground_ride_events"

    private var rideEventSink: EventChannel.EventSink? = null
    private var rideActionReceiverRegistered = false

    private val rideActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != RideTrackingService.ACTION_SERVICE_EVENT) return

            val serviceAction = intent.getStringExtra(
                RideTrackingService.EXTRA_SERVICE_EVENT_ACTION,
            ) ?: return

            rideEventSink?.success(serviceAction)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            rideServiceChannelName,
        ).setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *>

            try {
                when (call.method) {
                    "start" -> {
                        dispatchRideServiceAction(RideTrackingService.ACTION_START, args)
                        result.success(null)
                    }

                    "update" -> {
                        dispatchRideServiceAction(RideTrackingService.ACTION_UPDATE, args)
                        result.success(null)
                    }

                    "pause" -> {
                        dispatchRideServiceAction(RideTrackingService.ACTION_PAUSE, args)
                        result.success(null)
                    }

                    "resume" -> {
                        dispatchRideServiceAction(RideTrackingService.ACTION_RESUME, args)
                        result.success(null)
                    }

                    "stop" -> {
                        dispatchRideServiceAction(RideTrackingService.ACTION_STOP, args)
                        result.success(null)
                    }

                    "consumePendingAction" -> {
                        result.success(consumePendingRideAction())
                    }

                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error(
                    "ride_service_error",
                    error.message ?: "Ride service command failed",
                    null,
                )
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            rideServiceEventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    rideEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    rideEventSink = null
                }
            },
        )

        registerRideActionReceiver()
    }

    override fun onDestroy() {
        unregisterRideActionReceiver()
        super.onDestroy()
    }

    private fun dispatchRideServiceAction(action: String, args: Map<*, *>?) {
        val intent = Intent(this, RideTrackingService::class.java).apply {
            this.action = action
            putExtra(RideTrackingService.EXTRA_FROM_FLUTTER, true)
            putExtra(
                RideTrackingService.EXTRA_DISTANCE_KM,
                readDouble(args?.get("distanceKm")),
            )
            putExtra(
                RideTrackingService.EXTRA_ELAPSED_ACTIVE_MS,
                readLong(args?.get("elapsedActiveMs")),
            )
            putExtra(
                RideTrackingService.EXTRA_PAUSED,
                readBool(args?.get("paused")),
            )
        }

        if (action == RideTrackingService.ACTION_START &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
        ) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun registerRideActionReceiver() {
        if (rideActionReceiverRegistered) return

        val filter = IntentFilter(RideTrackingService.ACTION_SERVICE_EVENT)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                rideActionReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(rideActionReceiver, filter)
        }

        rideActionReceiverRegistered = true
    }

    private fun unregisterRideActionReceiver() {
        if (!rideActionReceiverRegistered) return

        try {
            unregisterReceiver(rideActionReceiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered by the framework.
        }

        rideActionReceiverRegistered = false
        rideEventSink = null
    }

    private fun consumePendingRideAction(): String? {
        val prefs = getSharedPreferences(
            RideTrackingService.PENDING_PREFS,
            Context.MODE_PRIVATE,
        )

        val pendingAction = prefs.getString(
            RideTrackingService.PENDING_ACTION_KEY,
            null,
        )

        if (pendingAction != null) {
            prefs.edit().remove(RideTrackingService.PENDING_ACTION_KEY).apply()
        }

        return pendingAction
    }

    private fun readDouble(value: Any?): Double {
        return when (value) {
            is Double -> value
            is Float -> value.toDouble()
            is Int -> value.toDouble()
            is Long -> value.toDouble()
            is String -> value.toDoubleOrNull() ?: 0.0
            else -> 0.0
        }
    }

    private fun readLong(value: Any?): Long {
        return when (value) {
            is Long -> value
            is Int -> value.toLong()
            is Double -> value.toLong()
            is Float -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun readBool(value: Any?): Boolean {
        return when (value) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            is String -> value.equals("true", ignoreCase = true) || value == "1"
            else -> false
        }
    }
}
'''

RIDE_TRACKING_SERVICE = r'''package com.example.bike_console

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
import android.os.IBinder
import android.os.Looper
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
    private var paused: Boolean = false
    private var foregroundStarted = false
    private var nativeLocationPointCount = 0

    private var locationManager: LocationManager? = null

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            // Batch 3 still keeps Flutter as the visible route renderer.
            // A later batch will persist native GPS points into active ride snapshots.
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

        updateStateFromIntent(intent)

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
        // The service is declared with stopWithTask=false. Keep the active ride service
        // alive when the Flutter activity is removed from Recents.
        updateForegroundNotification()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopLocationUpdates()
        super.onDestroy()
    }

    private fun updateStateFromIntent(intent: Intent?) {
        if (intent == null) return

        if (intent.hasExtra(EXTRA_DISTANCE_KM)) {
            distanceKm = intent.getDoubleExtra(EXTRA_DISTANCE_KM, distanceKm)
        }

        if (intent.hasExtra(EXTRA_ELAPSED_ACTIVE_MS)) {
            elapsedActiveMs = intent.getLongExtra(EXTRA_ELAPSED_ACTIVE_MS, elapsedActiveMs)
        }

        if (intent.hasExtra(EXTRA_PAUSED)) {
            paused = intent.getBooleanExtra(EXTRA_PAUSED, paused)
        }
    }

    private fun startRide() {
        paused = false
        startInForeground()
        startLocationUpdates()
    }

    private fun pauseRide() {
        paused = true
        startInForeground()
        startLocationUpdates()
    }

    private fun resumeRide() {
        paused = false
        startInForeground()
        startLocationUpdates()
    }

    private fun stopRide() {
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
        val text = "$status • ${formatDistance(distanceKm)} • ${formatElapsed(elapsedActiveMs)}"

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
            putExtra(EXTRA_ELAPSED_ACTIVE_MS, elapsedActiveMs)
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
'''

FOREGROUND_RIDE_SERVICE_DART = r'''import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ForegroundRideService {
  const ForegroundRideService();

  static const MethodChannel _channel = MethodChannel(
    'bike_console/foreground_ride_service',
  );

  static const EventChannel _events = EventChannel(
    'bike_console/foreground_ride_events',
  );

  Stream<String> notificationActions() {
    if (!Platform.isAndroid) return const Stream.empty();

    return _events.receiveBroadcastStream().where((event) {
      return event is String && event.trim().isNotEmpty;
    }).cast<String>();
  }

  Future<String?> consumePendingAction() async {
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
    required double distanceKm,
    required int elapsedActiveMs,
  }) {
    return _invoke(
      'start',
      distanceKm: distanceKm,
      elapsedActiveMs: elapsedActiveMs,
      paused: false,
    );
  }

  Future<void> update({
    required double distanceKm,
    required int elapsedActiveMs,
    required bool paused,
  }) {
    return _invoke(
      'update',
      distanceKm: distanceKm,
      elapsedActiveMs: elapsedActiveMs,
      paused: paused,
    );
  }

  Future<void> pause({
    required double distanceKm,
    required int elapsedActiveMs,
  }) {
    return _invoke(
      'pause',
      distanceKm: distanceKm,
      elapsedActiveMs: elapsedActiveMs,
      paused: true,
    );
  }

  Future<void> resume({
    required double distanceKm,
    required int elapsedActiveMs,
  }) {
    return _invoke(
      'resume',
      distanceKm: distanceKm,
      elapsedActiveMs: elapsedActiveMs,
      paused: false,
    );
  }

  Future<void> stop() {
    return _invoke(
      'stop',
      distanceKm: 0,
      elapsedActiveMs: 0,
      paused: false,
    );
  }

  Future<void> _invoke(
    String method, {
    required double distanceKm,
    required int elapsedActiveMs,
    required bool paused,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod<void>(method, {
        'distanceKm': distanceKm,
        'elapsedActiveMs': elapsedActiveMs,
        'paused': paused,
      });
    } on PlatformException catch (error) {
      debugPrint(
        'ForegroundRideService.$method failed: ${error.code} ${error.message}',
      );
    } catch (error) {
      debugPrint('ForegroundRideService.$method failed: $error');
    }
  }
}
'''

BIKE_CONSOLE_CONTROLLER_DART = r'''import 'dart:async';

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
    _displaySettings = await _appSettingsService.loadDisplaySettings();
    AppHaptics.setEnabled(_displaySettings.hapticFeedbackEnabled);

    _startForegroundRideActionListener();

    await rideSessionController.initialize();
    await connectionController.initialize();
    await _consumePendingForegroundRideAction();

    _syncForegroundRideService(force: true);
    notifyListeners();
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
'''

write_file('android/app/src/main/kotlin/com/example/bike_console/MainActivity.kt', MAIN_ACTIVITY)
write_file('android/app/src/main/kotlin/com/example/bike_console/RideTrackingService.kt', RIDE_TRACKING_SERVICE)
write_file('lib/services/foreground_ride_service.dart', FOREGROUND_RIDE_SERVICE_DART)
write_file('lib/controllers/bike_console_controller.dart', BIKE_CONSOLE_CONTROLLER_DART)

# ride_models.dart targeted updates
replace_exact(
    'lib/models/ride_models.dart',
    '''    required this.speedSource,\n    required this.routePoints,\n    required this.hazardEnabled,''',
    '''    required this.speedSource,\n    required this.routePoints,\n    required this.autoPauseSuppressedUntilMovement,\n    required this.hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''  final List<RideRoutePoint> routePoints;\n\n  /// Logical app-side hazard state.''',
    '''  final List<RideRoutePoint> routePoints;\n\n  /// When true, auto-pause is blocked until fresh movement is detected.\n  /// This preserves manual resume after auto-pause across UI recreation.\n  final bool autoPauseSuppressedUntilMovement;\n\n  /// Logical app-side hazard state.''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      speedSource: SpeedSource.none,\n      routePoints: [],\n      hazardEnabled: false,''',
    '''      speedSource: SpeedSource.none,\n      routePoints: [],\n      autoPauseSuppressedUntilMovement: false,\n      hazardEnabled: false,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''    SpeedSource? speedSource,\n    List<RideRoutePoint>? routePoints,\n    bool? hazardEnabled,''',
    '''    SpeedSource? speedSource,\n    List<RideRoutePoint>? routePoints,\n    bool? autoPauseSuppressedUntilMovement,\n    bool? hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      speedSource: speedSource ?? this.speedSource,\n      routePoints: routePoints ?? this.routePoints,\n      hazardEnabled: hazardEnabled ?? this.hazardEnabled,''',
    '''      speedSource: speedSource ?? this.speedSource,\n      routePoints: routePoints ?? this.routePoints,\n      autoPauseSuppressedUntilMovement:\n          autoPauseSuppressedUntilMovement ??\n          this.autoPauseSuppressedUntilMovement,\n      hazardEnabled: hazardEnabled ?? this.hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''    required this.routePoints,\n    required this.hazardEnabled,''',
    '''    required this.routePoints,\n    required this.autoPauseSuppressedUntilMovement,\n    required this.hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''  final List<RideRoutePoint> routePoints;\n  final bool hazardEnabled;''',
    '''  final List<RideRoutePoint> routePoints;\n  final bool autoPauseSuppressedUntilMovement;\n  final bool hazardEnabled;''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      routePoints: state.routePoints,\n      hazardEnabled: state.hazardEnabled,''',
    '''      routePoints: state.routePoints,\n      autoPauseSuppressedUntilMovement:\n          state.autoPauseSuppressedUntilMovement,\n      hazardEnabled: state.hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      routePoints: _readRoutePoints(json['routePoints']),\n      hazardEnabled: json['hazardEnabled'] == true,''',
    '''      routePoints: _readRoutePoints(json['routePoints']),\n      autoPauseSuppressedUntilMovement:\n          json['autoPauseSuppressedUntilMovement'] == true,\n      hazardEnabled: json['hazardEnabled'] == true,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      'routePoints': routePoints.map((point) => point.toJson()).toList(),\n      'hazardEnabled': hazardEnabled,''',
    '''      'routePoints': routePoints.map((point) => point.toJson()).toList(),\n      'autoPauseSuppressedUntilMovement': autoPauseSuppressedUntilMovement,\n      'hazardEnabled': hazardEnabled,''',
)
replace_exact(
    'lib/models/ride_models.dart',
    '''      routePoints: routePoints,\n      hazardEnabled: hazardEnabled,''',
    '''      routePoints: routePoints,\n      autoPauseSuppressedUntilMovement: autoPauseSuppressedUntilMovement,\n      hazardEnabled: hazardEnabled,''',
)

# ride_session_controller.dart targeted updates
replace_all(
    'lib/controllers/ride_session_controller.dart',
    '  bool _autoPauseSuppressedUntilMovement = false;\n',
    '',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''      _lastIndicatorCommandEpochMs = null;\n      _autoPauseSuppressedUntilMovement = false;\n      _state = _state.copyWith(''',
    '''      _lastIndicatorCommandEpochMs = null;\n      _state = _state.copyWith(\n        autoPauseSuppressedUntilMovement: false,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n    _autoPauseSuppressedUntilMovement = false;\n\n    if (_state.rideState == RideState.running) {''',
    '''    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n\n    if (_state.rideState == RideState.running) {''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    final speedKmph = _speedFromRpm(packet.rpm);\n    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;\n\n    if (packet.isMoving) {''',
    '''    final speedKmph = _speedFromRpm(packet.rpm);\n    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;\n    final shouldClearAutoPauseSuppression =\n        packet.isMoving && _state.autoPauseSuppressedUntilMovement;\n\n    if (packet.isMoving) {''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    if (packet.isMoving) {\n      _notMovingSinceEpochMs = null;\n      _autoPauseSuppressedUntilMovement = false;\n\n      if (_state.rideState == RideState.paused &&''',
    '''    if (packet.isMoving) {\n      _notMovingSinceEpochMs = null;\n\n      if (_state.rideState == RideState.paused &&''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''      currentRpm: packet.rpm,\n      currentSpeedKmph: speedKmph,\n      speedSource: SpeedSource.wheel,\n      distanceKm: nextDistanceKm,''',
    '''      currentRpm: packet.rpm,\n      currentSpeedKmph: speedKmph,\n      speedSource: SpeedSource.wheel,\n      autoPauseSuppressedUntilMovement: shouldClearAutoPauseSuppression\n          ? false\n          : _state.autoPauseSuppressedUntilMovement,\n      distanceKm: nextDistanceKm,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n    _autoPauseSuppressedUntilMovement = false;\n\n    _state = _state.copyWith(''',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = null;\n    _lastConsoleSyncEpochMs = null;\n\n    _state = _state.copyWith(\n      autoPauseSuppressedUntilMovement: false,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = startMs;\n    _lastConsoleSyncEpochMs = null;\n    _autoPauseSuppressedUntilMovement = false;\n\n    _state = _state.copyWith(''',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = startMs;\n    _lastConsoleSyncEpochMs = null;\n\n    _state = _state.copyWith(\n      autoPauseSuppressedUntilMovement: false,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    if (_state.rideState != RideState.running) return;\n\n    _autoPauseSuppressedUntilMovement = false;\n\n    _state = _state.copyWith(''',
    '''    if (_state.rideState != RideState.running) return;\n\n    _state = _state.copyWith(\n      autoPauseSuppressedUntilMovement: false,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    if (_state.rideState != RideState.running) return;\n\n    _autoPauseSuppressedUntilMovement = false;\n\n    _state = _state.copyWith(''',
    '''    if (_state.rideState != RideState.running) return;\n\n    _state = _state.copyWith(\n      autoPauseSuppressedUntilMovement: false,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = now;\n    _autoPauseSuppressedUntilMovement = suppressAutoPauseUntilMovement;\n\n    _state = _state.copyWith(''',
    '''    _notMovingSinceEpochMs = null;\n    _lastAverageSpeedUpdateEpochMs = now;\n\n    _state = _state.copyWith(\n      autoPauseSuppressedUntilMovement: suppressAutoPauseUntilMovement,''',
)
replace_exact(
    'lib/controllers/ride_session_controller.dart',
    '''    _lastConsoleSyncEpochMs = null;\n    _lastIndicatorCommandEpochMs = null;\n    _autoPauseSuppressedUntilMovement = false;\n\n    onCommand?.call(BikeCommand.stop());''',
    '''    _lastConsoleSyncEpochMs = null;\n    _lastIndicatorCommandEpochMs = null;\n\n    onCommand?.call(BikeCommand.stop());''',
)
replace_all(
    'lib/controllers/ride_session_controller.dart',
    '_autoPauseSuppressedUntilMovement',
    '_state.autoPauseSuppressedUntilMovement',
)

print('Batch 3 applied successfully.')
