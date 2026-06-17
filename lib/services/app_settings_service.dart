import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class AppSettingsService {
  static const String _displaySettingsKey = "app_display_settings";

  Future<AppDisplaySettings> loadDisplaySettings() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_displaySettingsKey);

    if (raw == null) {
      return AppDisplaySettings.defaults();
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return AppDisplaySettings.defaults();
      }

      return AppDisplaySettings.fromJson(decoded);
    } catch (_) {
      return AppDisplaySettings.defaults();
    }
  }

  Future<void> saveDisplaySettings(AppDisplaySettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_displaySettingsKey, jsonEncode(settings.toJson()));
  }
}