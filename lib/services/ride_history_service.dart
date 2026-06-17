import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_ride_session.dart';

class RideHistoryService {
  static const String _sessionsKey = "saved_ride_sessions";

  Future<List<SavedRideSession>> loadSessions() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_sessionsKey);

    if (raw == null) {
      return [];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return [];
      }

      final sessions = decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedRideSession.fromJson)
          .where((session) => session.id.isNotEmpty)
          .toList();

      sessions.sort((a, b) => b.endEpochMs.compareTo(a.endEpochMs));

      return sessions;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSession(SavedRideSession session) async {
    final sessions = await loadSessions();

    final updatedSessions = [
      session,
      ...sessions.where((existing) => existing.id != session.id),
    ];

    await _saveSessions(updatedSessions);
  }

  Future<void> deleteSessionsByIds(Set<String> ids) async {
    if (ids.isEmpty) return;

    final sessions = await loadSessions();
    final updatedSessions = sessions
        .where((session) => !ids.contains(session.id))
        .toList();

    await _saveSessions(updatedSessions);
  }

  Future<void> _saveSessions(List<SavedRideSession> sessions) async {
    final preferences = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      sessions.map((session) => session.toJson()).toList(),
    );

    await preferences.setString(_sessionsKey, encoded);
  }
}