package com.example.bike_console

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val rideServiceChannelName = "bike_console/foreground_ride_service"

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
    }

    private fun dispatchRideServiceAction(action: String, args: Map<*, *>?) {
        val intent = Intent(this, RideTrackingService::class.java).apply {
            this.action = action
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
