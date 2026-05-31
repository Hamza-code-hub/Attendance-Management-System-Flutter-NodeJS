import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../authentication/presentation/auth_state.dart';

// ── Today's attendance state ───────────────────────────────────────────────

class TodayAttendanceState {
  final bool isLoading;
  final String status; // NOT_CHECKED_IN, CHECKED_IN, BREAK_ACTIVE, CHECKED_OUT
  final DateTime? checkInTime;
  final DateTime? activeBreakStart;
  final String? statusLabel;
  final int totalWorkedMinutes;
  final String? error;
  final bool isOfflineCache;

  TodayAttendanceState({
    required this.isLoading,
    required this.status,
    this.checkInTime,
    this.activeBreakStart,
    this.statusLabel,
    this.totalWorkedMinutes = 0,
    this.error,
    this.isOfflineCache = false,
  });

  factory TodayAttendanceState.initial() => TodayAttendanceState(
        isLoading: false,
        status: 'NOT_CHECKED_IN',
      );

  TodayAttendanceState copyWith({
    bool? isLoading,
    String? status,
    DateTime? checkInTime,
    DateTime? activeBreakStart,
    String? statusLabel,
    int? totalWorkedMinutes,
    String? error,
    bool? isOfflineCache,
  }) {
    return TodayAttendanceState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      checkInTime: checkInTime ?? this.checkInTime,
      activeBreakStart: activeBreakStart ?? this.activeBreakStart,
      statusLabel: statusLabel ?? this.statusLabel,
      totalWorkedMinutes: totalWorkedMinutes ?? this.totalWorkedMinutes,
      error: error ?? this.error,
      isOfflineCache: isOfflineCache ?? this.isOfflineCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'checkInTime': checkInTime?.toIso8601String(),
    'activeBreakStart': activeBreakStart?.toIso8601String(),
    'statusLabel': statusLabel,
    'totalWorkedMinutes': totalWorkedMinutes,
  };

  factory TodayAttendanceState.fromCacheJson(Map<String, dynamic> j) =>
      TodayAttendanceState(
        isLoading: false,
        status: j['status'] ?? 'NOT_CHECKED_IN',
        checkInTime: j['checkInTime'] != null ? DateTime.parse(j['checkInTime']) : null,
        activeBreakStart: j['activeBreakStart'] != null ? DateTime.parse(j['activeBreakStart']) : null,
        statusLabel: j['statusLabel'],
        totalWorkedMinutes: j['totalWorkedMinutes'] ?? 0,
        isOfflineCache: true,
      );
}

// ── Today notifier ─────────────────────────────────────────────────────────

class AttendanceStateNotifier extends StateNotifier<TodayAttendanceState> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/attendance';
  String get _uid => _ref.read(authProvider).user?.id.toString() ?? '0';
  // Include date so yesterday's CHECKED_OUT never loads as today's state
  String get _cacheKey {
    final d = DateTime.now();
    final date = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    return 'att_today_${_uid}_$date';
  }

  AttendanceStateNotifier(this._ref) : super(TodayAttendanceState.initial()) {
    fetchToday();
  }

  Map<String, String> _headers() {
    final token = _ref.read(authProvider).accessToken ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> _saveCache(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(data));
  }

  Future<TodayAttendanceState?> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    return TodayAttendanceState.fromCacheJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> fetchToday() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/today'), headers: _headers())
          .timeout(const Duration(seconds: 6));

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final data = resBody['data'] as Map<String, dynamic>;
        await _saveCache(data);
        state = TodayAttendanceState(
          isLoading: false,
          status: data['status'] as String,
          checkInTime: data['checkInTime'] != null
              ? DateTime.parse(data['checkInTime'])
              : null,
          activeBreakStart: data['activeBreakStart'] != null
              ? DateTime.parse(data['activeBreakStart'])
              : null,
          statusLabel: data['statusLabel'] as String?,
          totalWorkedMinutes: data['totalWorkedMinutes'] ?? 0,
        );
      } else {
        final cached = await _loadCache();
        state = cached ??
            state.copyWith(
              isLoading: false,
              error: resBody['error']?['message'] ?? 'Failed to load today.',
            );
      }
    } catch (_) {
      final cached = await _loadCache();
      state = cached ??
          state.copyWith(
            isLoading: false,
            error: 'Office network unreachable.',
          );
    }
  }

  Future<bool> checkIn() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await http
          .post(Uri.parse('$_baseUrl/check-in'), headers: _headers())
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body);
      if (res.statusCode == 201 && body['success'] == true) {
        await fetchToday();
        _ref.read(historyProvider.notifier).fetchHistory();
        return true;
      }
      state = state.copyWith(
          isLoading: false,
          error: body['error']?['message'] ?? 'Failed to clock in.');
      return false;
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Office network unreachable.');
      return false;
    }
  }

  Future<bool> checkOut() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await http
          .post(Uri.parse('$_baseUrl/check-out'), headers: _headers())
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchToday();
        _ref.read(historyProvider.notifier).fetchHistory();
        return true;
      }
      state = state.copyWith(
          isLoading: false,
          error: body['error']?['message'] ?? 'Failed to clock out.');
      return false;
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Office network unreachable.');
      return false;
    }
  }

  Future<bool> startBreak() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await http
          .post(Uri.parse('$_baseUrl/break/start'), headers: _headers())
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchToday();
        return true;
      }
      state = state.copyWith(
          isLoading: false,
          error: body['error']?['message'] ?? 'Failed to start break.');
      return false;
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Office network unreachable.');
      return false;
    }
  }

  Future<bool> endBreak() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await http
          .post(Uri.parse('$_baseUrl/break/end'), headers: _headers())
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        await fetchToday();
        return true;
      }
      state = state.copyWith(
          isLoading: false,
          error: body['error']?['message'] ?? 'Failed to end break.');
      return false;
    } catch (_) {
      state = state.copyWith(
          isLoading: false, error: 'Office network unreachable.');
      return false;
    }
  }
}

// ── History state ──────────────────────────────────────────────────────────

class HistoryState {
  final List<dynamic> records;
  final bool isLoading;
  final String? error;
  final bool isOfflineCache;

  const HistoryState({
    this.records = const [],
    this.isLoading = false,
    this.error,
    this.isOfflineCache = false,
  });

  HistoryState copyWith({
    List<dynamic>? records,
    bool? isLoading,
    String? error,
    bool? isOfflineCache,
  }) =>
      HistoryState(
        records: records ?? this.records,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isOfflineCache: isOfflineCache ?? this.isOfflineCache,
      );
}

// ── History notifier ───────────────────────────────────────────────────────

class HistoryNotifier extends StateNotifier<HistoryState> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/attendance/history';
  String get _uid => _ref.read(authProvider).user?.id.toString() ?? '0';
  String get _cacheKey => 'att_history_$_uid';

  HistoryNotifier(this._ref) : super(const HistoryState(isLoading: true)) {
    fetchHistory();
  }

  Future<void> _saveCache(List<dynamic> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(records));
  }

  Future<List<dynamic>?> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    return raw != null ? jsonDecode(raw) as List<dynamic> : null;
  }

  Future<void> fetchHistory({String? fromDate, String? toDate}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final params = <String, String>{};
      if (fromDate != null) params['from'] = fromDate;
      if (toDate != null) params['to'] = toDate;
      final uri = Uri.parse(_baseUrl)
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final token = _ref.read(authProvider).accessToken ?? '';
      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 8));

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final records = resBody['data'] as List<dynamic>;
        // Only cache unfiltered fetches
        if (fromDate == null && toDate == null) await _saveCache(records);
        state = HistoryState(records: records);
      } else {
        final cached = fromDate == null ? await _loadCache() : null;
        if (cached != null) {
          state = HistoryState(records: cached, isOfflineCache: true);
        } else {
          state = state.copyWith(
            isLoading: false,
            error: resBody['error']?['message'] ?? 'Failed to load history.',
          );
        }
      }
    } catch (_) {
      final cached = fromDate == null ? await _loadCache() : null;
      if (cached != null) {
        state = HistoryState(records: cached, isOfflineCache: true);
      } else {
        state = state.copyWith(
            isLoading: false, error: 'Office network unreachable.');
      }
    }
  }
}

// ── Global providers ───────────────────────────────────────────────────────
// autoDispose: state is destroyed when the dashboard unmounts (e.g. on logout).
// This prevents a previous user's CHECKED_OUT from showing for the next login.

final attendanceStateProvider =
    StateNotifierProvider.autoDispose<AttendanceStateNotifier, TodayAttendanceState>(
        (ref) => AttendanceStateNotifier(ref));

final historyProvider =
    StateNotifierProvider.autoDispose<HistoryNotifier, HistoryState>(
        (ref) => HistoryNotifier(ref));
