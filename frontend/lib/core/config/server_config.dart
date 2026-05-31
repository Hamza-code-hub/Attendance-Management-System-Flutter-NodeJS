import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Auto-detects the backend on the local WiFi subnet at startup.
/// Falls back to a saved URL (czeus remote mode) or the hardcoded default.
class ServerConfig {
  static const int _serverLastOctet = 15;
  static const int _serverPort = 5000;
  static const String _defaultBaseUrl = 'http://192.168.100.15:5000';
  static const String _prefsKey = 'server_base_url_override';

  static String _baseUrl = _defaultBaseUrl;

  static String get apiBase => '$_baseUrl/api';
  static String get baseUrl => _baseUrl;

  /// Called once during the splash screen (runs in parallel with the delay).
  static Future<void> init() async {
    // 1. Auto-detect: find the device's WiFi subnet and ping the backend
    final subnet = await _detectWifiSubnet();
    if (subnet != null) {
      final candidate = 'http://$subnet.$_serverLastOctet:$_serverPort';
      if (await _isReachable(candidate)) {
        _baseUrl = candidate;
        return;
      }
    }
    // 2. Fall back to a URL saved by the czeus remote-access dialog
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) {
      _baseUrl = saved;
      return;
    }
    // 3. Hard default
    _baseUrl = _defaultBaseUrl;
  }

  /// Saves a custom URL (used only by the czeus remote-access dialog).
  static Future<void> save(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
    _baseUrl = normalized;
  }

  static Future<void> clearOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _baseUrl = _defaultBaseUrl;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the 3-octet subnet prefix of the device's WiFi IP, e.g. "192.168.100".
  static Future<String?> _detectWifiSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      // Prefer the wlan interface (Android WiFi)
      for (final iface in interfaces) {
        if (iface.name.toLowerCase().contains('wlan') ||
            iface.name.toLowerCase().contains('wifi')) {
          final ip = _pickPrivateIp(iface);
          if (ip != null) return _subnetOf(ip);
        }
      }
      // Fallback: any non-loopback private IPv4
      for (final iface in interfaces) {
        final ip = _pickPrivateIp(iface);
        if (ip != null) return _subnetOf(ip);
      }
    } catch (_) {}
    return null;
  }

  static String? _pickPrivateIp(NetworkInterface iface) {
    for (final addr in iface.addresses) {
      final ip = addr.address;
      if (!ip.startsWith('127.') && !ip.startsWith('169.254.')) return ip;
    }
    return null;
  }

  static String _subnetOf(String ip) {
    final p = ip.split('.');
    return '${p[0]}.${p[1]}.${p[2]}';
  }

  static Future<bool> _isReachable(String baseUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
