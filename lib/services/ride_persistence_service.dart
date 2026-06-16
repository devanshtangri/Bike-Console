import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/ride_models.dart';

class RidePersistenceService {
  static const _settingsKey = 'ride_settings';
  static const _snapshotKey = 'active_ride_snapshot';

  Future<void> saveSettings(RideSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _settingsKey,
      jsonEncode(settings.toJson()),
    );
  }

  Future<RideSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);

    if (raw == null || raw.isEmpty) {
      return RideSettings.defaults();
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        return RideSettings.fromJson(decoded);
      }

      return RideSettings.defaults();
    } catch (_) {
      return RideSettings.defaults();
    }
  }

  Future<void> saveRideSnapshot(PersistedRideSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _snapshotKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<PersistedRideSnapshot?> loadRideSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);

    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map<String, dynamic>) {
        final snapshot = PersistedRideSnapshot.fromJson(decoded);

        if (snapshot.rideState == RideState.stopped) {
          return null;
        }

        return snapshot;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRideSnapshot() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_snapshotKey);
  }
}