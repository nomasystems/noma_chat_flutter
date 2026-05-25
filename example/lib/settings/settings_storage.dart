import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'example_settings.dart';

/// Persists [ExampleSettings] as JSON in SharedPreferences.
///
/// Single key ('noma_chat_example.settings_v1') so a schema bump simply
/// changes the key and old configs are discarded (acceptable for an example).
class SettingsStorage {
  static const _key = 'noma_chat_example.settings_v1';

  Future<ExampleSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const ExampleSettings();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ExampleSettings.fromJson(json);
    } catch (_) {
      // Corrupt or schema-mismatched payload — fall back to defaults so the
      // user is not stuck on an unrecoverable onboarding screen.
      return const ExampleSettings();
    }
  }

  Future<void> save(ExampleSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
