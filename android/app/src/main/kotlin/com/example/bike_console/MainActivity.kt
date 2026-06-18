package com.example.bike_console

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

                    "loadActiveRideSnapshotJson" -> {
                        result.success(RideTrackingService.loadActiveRideSnapshotJson(this))
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
