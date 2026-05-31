import 'package:shared_preferences/shared_preferences.dart';

/// Runtime-configurable server URL.
/// Call [init] once at app startup (before runApp) to restore the saved URL.
/// Call [save] when the user changes the URL in settings.
class ServerConfig {
  static const String _defaultBaseUrl = 'http://192.168.100.15:5000';
  static const String _prefsKey = 'server_base_url';

  static String _baseUrl = _defaultBaseUrl;

  /// e.g. http://192.168.100.15:5000/api
  static String get apiBase => '$_baseUrl/api';

  /// e.g. http://192.168.100.15:5000
  static String get baseUrl => _baseUrl;

  static bool get isDefault => _baseUrl == _defaultBaseUrl;

  /// Load saved URL from SharedPreferences. Safe to call before runApp.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) {
      _baseUrl = saved;
    }
  }

  /// Persist and activate a new URL immediately.
  static Future<void> save(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
    _baseUrl = normalized;
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _baseUrl = _defaultBaseUrl;
  }
}
