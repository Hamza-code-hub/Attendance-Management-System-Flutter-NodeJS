import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../authentication/presentation/auth_state.dart';

class Shift {
  final int id;
  final String shiftName;
  final String shiftStart;
  final String shiftEnd;
  final int graceMinutes;
  final bool nightShiftEnabled;
  final bool allowOvertime;
  final bool active;

  Shift({
    required this.id,
    required this.shiftName,
    required this.shiftStart,
    required this.shiftEnd,
    required this.graceMinutes,
    required this.nightShiftEnabled,
    required this.allowOvertime,
    required this.active,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'] as int,
      shiftName: json['shiftName'] as String,
      shiftStart: json['shiftStart'] as String,
      shiftEnd: json['shiftEnd'] as String,
      graceMinutes: json['graceMinutes'] as int,
      nightShiftEnabled: json['nightShiftEnabled'] == true,
      allowOvertime: json['allowOvertime'] == true,
      active: json['active'] == true,
    );
  }
}

class ShiftNotifier extends StateNotifier<AsyncValue<List<Shift>>> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/shifts';

  ShiftNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchShifts();
  }

  Map<String, String> _getHeaders() {
    final auth = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${auth.accessToken ?? ''}',
    };
  }

  /**
   * Fetch shift list
   */
  Future<void> fetchShifts() async {
    try {
      state = const AsyncValue.loading();
      final response = await http.get(Uri.parse(_baseUrl), headers: _getHeaders());

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final list = (resBody['data'] as List).map((x) => Shift.fromJson(x)).toList();
        state = AsyncValue.data(list);
      } else {
        state = AsyncValue.error(resBody['error']?['message'] ?? 'Failed to load shifts', StackTrace.current);
      }
    } catch (e, st) {
      state = AsyncValue.error('Network connection error.', st);
    }
  }

  /**
   * Create new shift
   */
  Future<bool> createShift(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: _getHeaders(),
        body: jsonEncode(data),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 201 && resBody['success'] == true) {
        await fetchShifts();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /**
   * Update shift details
   */
  Future<bool> updateShift(int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/$id'),
        headers: _getHeaders(),
        body: jsonEncode(data),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchShifts();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

// Global Provider
final shiftsProvider = StateNotifierProvider<ShiftNotifier, AsyncValue<List<Shift>>>((ref) {
  return ShiftNotifier(ref);
});
