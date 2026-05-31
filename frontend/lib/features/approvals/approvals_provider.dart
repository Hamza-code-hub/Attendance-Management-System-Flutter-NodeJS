import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../authentication/presentation/auth_state.dart';
import '../overtime/overtime_provider.dart';
import '../adjustments/adjustments_provider.dart';

class ApprovalsState {
  final bool isLoading;
  final List<OvertimeRequest> pendingOvertime;
  final List<AdjustmentRequest> pendingAdjustments;
  final String? error;

  ApprovalsState({
    required this.isLoading,
    required this.pendingOvertime,
    required this.pendingAdjustments,
    this.error,
  });

  factory ApprovalsState.initial() => ApprovalsState(
        isLoading: false,
        pendingOvertime: [],
        pendingAdjustments: [],
      );

  ApprovalsState copyWith({
    bool? isLoading,
    List<OvertimeRequest>? pendingOvertime,
    List<AdjustmentRequest>? pendingAdjustments,
    String? error,
  }) {
    return ApprovalsState(
      isLoading: isLoading ?? this.isLoading,
      pendingOvertime: pendingOvertime ?? this.pendingOvertime,
      pendingAdjustments: pendingAdjustments ?? this.pendingAdjustments,
      error: error ?? this.error,
    );
  }
}

class ApprovalsNotifier extends StateNotifier<ApprovalsState> {
  final Ref<ApprovalsState> _ref;

  ApprovalsNotifier(this._ref) : super(ApprovalsState.initial()) {
    fetchPending();
  }

  Map<String, String> _getHeaders() {
    final authState = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${authState.accessToken ?? ''}',
    };
  }

  Future<void> fetchPending() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final otResponse = await http.get(
        Uri.parse('$ServerConfig.apiBase/overtime/pending'),
        headers: _getHeaders(),
      );
      final adjResponse = await http.get(
        Uri.parse('$ServerConfig.apiBase/adjustments/pending'),
        headers: _getHeaders(),
      );

      final otBody = jsonDecode(otResponse.body);
      final adjBody = jsonDecode(adjResponse.body);

      if (otResponse.statusCode == 200 && adjResponse.statusCode == 200) {
        final List<dynamic> otList = otBody['data'] ?? [];
        final List<dynamic> adjList = adjBody['data'] ?? [];

        state = ApprovalsState(
          isLoading: false,
          pendingOvertime: otList.map((x) => OvertimeRequest.fromJson(x)).toList(),
          pendingAdjustments: adjList.map((x) => AdjustmentRequest.fromJson(x)).toList(),
        );
      } else {
        final errMsg = otBody['error']?['message'] ?? adjBody['error']?['message'] ?? 'Failed to load queues.';
        state = state.copyWith(isLoading: false, error: errMsg);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Network request failed while loading approvals.',
      );
    }
  }

  Future<bool> reviewOvertime({
    required String id,
    required String status, // APPROVED, REJECTED, PARTIAL
    required int approvedMinutes,
    String? comment,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$ServerConfig.apiBase/overtime/review/$id'),
        headers: _getHeaders(),
        body: jsonEncode({
          'status': status,
          'approvedMinutes': approvedMinutes,
          'hrComment': comment,
        }),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchPending();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Review failed.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Network request failed.');
      return false;
    }
  }

  Future<bool> reviewAdjustment({
    required String id,
    required String status, // APPROVED, REJECTED
    String? comment,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$ServerConfig.apiBase/adjustments/review/$id'),
        headers: _getHeaders(),
        body: jsonEncode({
          'status': status,
          'hrComment': comment,
        }),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        await fetchPending();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Review failed.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Network request failed.');
      return false;
    }
  }
}

final approvalsProvider = StateNotifierProvider<ApprovalsNotifier, ApprovalsState>((ref) {
  return ApprovalsNotifier(ref);
});
