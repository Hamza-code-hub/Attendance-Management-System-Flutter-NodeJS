import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../authentication/presentation/auth_state.dart';

class TodayAttendanceState {
  final bool isLoading;
  final String status; // NOT_CHECKED_IN, CHECKED_IN, BREAK_ACTIVE, CHECKED_OUT
  final DateTime? checkInTime;
  final DateTime? activeBreakStart;
  final String? statusLabel; // ON_TIME, LATE, MISSED_CHECKOUT
  final int totalWorkedMinutes;
  final String? error;

  TodayAttendanceState({
    required this.isLoading,
    required this.status,
    this.checkInTime,
    this.activeBreakStart,
    this.statusLabel,
    this.totalWorkedMinutes = 0,
    this.error,
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
  }) {
    return TodayAttendanceState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      checkInTime: checkInTime ?? this.checkInTime,
      activeBreakStart: activeBreakStart ?? this.activeBreakStart,
      statusLabel: statusLabel ?? this.statusLabel,
      totalWorkedMinutes: totalWorkedMinutes ?? this.totalWorkedMinutes,
      error: error ?? this.error,
    );
  }
}

class AttendanceStateNotifier extends StateNotifier<TodayAttendanceState> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/attendance';

  AttendanceStateNotifier(this._ref) : super(TodayAttendanceState.initial()) {
    fetchToday();
  }

  Map<String, String> _getHeaders() {
    final auth = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${auth.accessToken ?? ''}',
    };
  }

  /**
   * 1. Fetch Today's state
   */
  Future<void> fetchToday() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/today'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final data = resBody['data'];
        final status = data['status'] as String;

        state = TodayAttendanceState(
          isLoading: false,
          status: status,
          checkInTime: data['checkInTime'] != null ? DateTime.parse(data['checkInTime']) : null,
          activeBreakStart: data['activeBreakStart'] != null ? DateTime.parse(data['activeBreakStart']) : null,
          statusLabel: data['statusLabel'] as String?,
          totalWorkedMinutes: data['totalWorkedMinutes'] ?? 0,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: resBody['error']?['message'] ?? 'Failed to load today logs.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load database. Please verify backend execution.',
      );
    }
  }

  /**
   * 2. Perform daily check-in
   */
  Future<bool> checkIn() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/check-in'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 201 && resBody['success'] == true) {
        await fetchToday(); // Reload states
        _ref.read(historyProvider.notifier).fetchHistory(); // Refresh history
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Failed to clock in.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Database network failed.');
      return false;
    }
  }

  /**
   * 3. Perform daily check-out
   */
  Future<bool> checkOut() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/check-out'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchToday();
        _ref.read(historyProvider.notifier).fetchHistory();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Failed to clock out.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Database network failed.');
      return false;
    }
  }

  /**
   * 4. Start active break
   */
  Future<bool> startBreak() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/break/start'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchToday();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Failed to start break.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Database network failed.');
      return false;
    }
  }

  /**
   * 5. End active break
   */
  Future<bool> endBreak() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/break/end'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchToday();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Failed to end break.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Database network failed.');
      return false;
    }
  }
}

// History States Provider
class HistoryNotifier extends StateNotifier<AsyncValue<List<dynamic>>> {
  final Ref _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/attendance/history';

  HistoryNotifier(this._ref) : super(const AsyncValue.loading()) {
    fetchHistory();
  }

  Future<void> fetchHistory({String? fromDate, String? toDate}) async {
    try {
      state = const AsyncValue.loading();
      final auth = _ref.read(authProvider);
      final params = <String, String>{};
      if (fromDate != null) params['from'] = fromDate;
      if (toDate != null) params['to'] = toDate;
      final uri = Uri.parse(_baseUrl).replace(queryParameters: params.isNotEmpty ? params : null);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.accessToken ?? ''}',
        },
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        state = AsyncValue.data(resBody['data'] as List<dynamic>);
      } else {
        state = AsyncValue.error(
          resBody['error']?['message'] ?? 'Failed to load history.',
          StackTrace.current,
        );
      }
    } catch (e, st) {
      state = AsyncValue.error('Network connection error.', st);
    }
  }
}

// Global Providers
final attendanceStateProvider = StateNotifierProvider<AttendanceStateNotifier, TodayAttendanceState>((ref) {
  return AttendanceStateNotifier(ref);
});

final historyProvider = StateNotifierProvider<HistoryNotifier, AsyncValue<List<dynamic>>>((ref) {
  return HistoryNotifier(ref);
});
