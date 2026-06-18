import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/ride_models.dart';

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
