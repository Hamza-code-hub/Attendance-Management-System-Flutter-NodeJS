import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../features/authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

// ── Models ────────────────────────────────────────────────────────────────

class DashboardSummary {
  final int presentCount;
  final int checkedOutCount;
  final int activeBreaks;
  final int lateCount;
  final int missingCheckouts;
  final int pendingOvertimeRequests;
  final int pendingAdjustmentRequests;
  final int totalPendingApprovals;
  final int totalActiveEmployees;
  final int absentCount;
  final String date;

  DashboardSummary({
    required this.presentCount, required this.checkedOutCount,
    required this.activeBreaks, required this.lateCount,
    required this.missingCheckouts, required this.pendingOvertimeRequests,
    required this.pendingAdjustmentRequests, required this.totalPendingApprovals,
    required this.totalActiveEmployees, required this.absentCount,
    required this.date,
  });

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  factory DashboardSummary.fromJson(Map<String, dynamic> j) => DashboardSummary(
    presentCount: _asInt(j['presentCount']),
    checkedOutCount: _asInt(j['checkedOutCount']),
    activeBreaks: _asInt(j['activeBreaks']),
    lateCount: _asInt(j['lateCount']),
    missingCheckouts: _asInt(j['missingCheckouts']),
    pendingOvertimeRequests: _asInt(j['pendingOvertimeRequests']),
    pendingAdjustmentRequests: _asInt(j['pendingAdjustmentRequests']),
    totalPendingApprovals: _asInt(j['totalPendingApprovals']),
    totalActiveEmployees: _asInt(j['totalActiveEmployees']),
    absentCount: _asInt(j['absentCount']),
    date: j['date'] ?? '',
  );
}

class PagedResult<T> {
  final List<T> data;
  final int total;
  final int page;
  PagedResult({required this.data, required this.total, required this.page});
}

// ── State ─────────────────────────────────────────────────────────────────

class DashboardState {
  final DashboardSummary? summary;
  final bool loading;
  final String? error;
  final String selectedDate;

  DashboardState({this.summary, this.loading = false, this.error, required this.selectedDate});

  DashboardState copyWith({
    DashboardSummary? summary, bool? loading, String? error, String? selectedDate,
  }) => DashboardState(
    summary: summary ?? this.summary,
    loading: loading ?? this.loading,
    error: error,
    selectedDate: selectedDate ?? this.selectedDate,
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────

class DashboardNotifier extends StateNotifier<DashboardState> {
  final Ref _ref;

  DashboardNotifier(this._ref)
      : super(DashboardState(selectedDate: _today()));

  static String _today() => DateTime.now().toIso8601String().split('T')[0];

  Map<String, String> get _headers {
    final token = _ref.read(authProvider).accessToken ?? '';
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  Future<void> loadSummary({String? date}) async {
    final d = date ?? state.selectedDate;
    state = state.copyWith(loading: true, error: null, selectedDate: d);
    try {
      final res = await http.get(
        Uri.parse('$_base/dashboard/summary?date=$d'),
        headers: _headers,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        state = state.copyWith(loading: false, summary: DashboardSummary.fromJson(body['data']));
      } else {
        state = state.copyWith(loading: false, error: body['error']?['message'] ?? 'Failed to load');
      }
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<PagedResult<Map<String, dynamic>>> fetchPresent({
    String? date, int? employeeId, int? departmentId, int page = 1,
  }) => _paged('/dashboard/present', {
    'date': date ?? state.selectedDate, 'page': '$page', 'limit': '20',
    if (employeeId != null) 'employeeId': '$employeeId',
    if (departmentId != null) 'departmentId': '$departmentId',
  });

  Future<PagedResult<Map<String, dynamic>>> fetchLate({
    String? date, int? employeeId, int? departmentId, int page = 1,
  }) => _paged('/dashboard/late', {
    'date': date ?? state.selectedDate, 'page': '$page', 'limit': '20',
    if (employeeId != null) 'employeeId': '$employeeId',
    if (departmentId != null) 'departmentId': '$departmentId',
  });

  Future<PagedResult<Map<String, dynamic>>> fetchPendingApprovals({
    String? type, int? employeeId, int? departmentId,
    String? dateFrom, String? dateTo, int page = 1,
  }) => _paged('/dashboard/pending-approvals', {
    'page': '$page', 'limit': '20',
    if (type != null) 'type': type,
    if (employeeId != null) 'employeeId': '$employeeId',
    if (departmentId != null) 'departmentId': '$departmentId',
    if (dateFrom != null) 'dateFrom': dateFrom,
    if (dateTo != null) 'dateTo': dateTo,
  });

  Future<PagedResult<Map<String, dynamic>>> fetchAttendanceMonitor({
    String? date, int? employeeId, int? departmentId, String? status, int page = 1,
  }) => _paged('/dashboard/attendance-monitor', {
    'date': date ?? state.selectedDate, 'page': '$page', 'limit': '25',
    if (employeeId != null) 'employeeId': '$employeeId',
    if (departmentId != null) 'departmentId': '$departmentId',
    if (status != null && status.isNotEmpty) 'status': status,
  });

  Future<List<Map<String, dynamic>>> fetchDepartments() async {
    try {
      final res = await http.get(Uri.parse('$_base/settings/departments'), headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        final raw = body['data'];
        final list = raw is List ? raw : (raw is Map && raw['departments'] is List ? raw['departments'] as List : []);
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchShiftMonitor({String? date}) async {
    final d = date ?? state.selectedDate;
    try {
      final res = await http.get(
        Uri.parse('$_base/dashboard/shift-monitor?date=$d'),
        headers: _headers,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        return List<Map<String, dynamic>>.from(body['data'] ?? []);
      }
    } catch (_) {}
    return [];
  }

  Future<PagedResult<Map<String, dynamic>>> fetchEmployeeDirectory({
    String? search, int? departmentId, int? shiftId,
    String status = 'ACTIVE', int page = 1,
  }) => _paged('/dashboard/employee-directory', {
    'status': status, 'page': '$page', 'limit': '25',
    if (search != null && search.isNotEmpty) 'search': search,
    if (departmentId != null) 'departmentId': '$departmentId',
    if (shiftId != null) 'shiftId': '$shiftId',
  });

  Future<PagedResult<Map<String, dynamic>>> _paged(
    String path, Map<String, String> params,
  ) async {
    try {
      final uri = Uri.parse('$_base$path').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        return PagedResult(
          data: List<Map<String, dynamic>>.from(body['data'] ?? []),
          total: (body['total'] ?? 0) as int,
          page: (body['page'] ?? 1) as int,
        );
      }
    } catch (_) {}
    return PagedResult(data: [], total: 0, page: 1);
  }
}

final dashboardProvider = StateNotifierProvider<DashboardNotifier, DashboardState>(
  (ref) => DashboardNotifier(ref),
);
