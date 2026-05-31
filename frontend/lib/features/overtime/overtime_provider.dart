import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../authentication/presentation/auth_state.dart';

class OvertimeRequest {
  final String id;
  final int userId;
  final String? attendanceId;
  final String requestDate;
  final int requestedMinutes;
  final int approvedMinutes;
  final String reason;
  final String status; // PENDING, APPROVED, REJECTED, PARTIAL
  final String? hrComment;
  final int? reviewedBy;
  final String? reviewedAt;
  final String createdAt;
  final String updatedAt;
  // joined fields
  final String? username;
  final String? firstName;
  final String? lastName;

  OvertimeRequest({
    required this.id,
    required this.userId,
    this.attendanceId,
    required this.requestDate,
    required this.requestedMinutes,
    required this.approvedMinutes,
    required this.reason,
    required this.status,
    this.hrComment,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.firstName,
    this.lastName,
  });

  factory OvertimeRequest.fromJson(Map<String, dynamic> json) {
    return OvertimeRequest(
      id: json['id'] ?? '',
      userId: json['userId'] ?? 0,
      attendanceId: json['attendanceId'],
      requestDate: json['requestDate'] ?? '',
      requestedMinutes: json['requestedMinutes'] ?? 0,
      approvedMinutes: json['approvedMinutes'] ?? 0,
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'PENDING',
      hrComment: json['hrComment'],
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
      username: json['username'],
      firstName: json['firstName'],
      lastName: json['lastName'],
    );
  }
}

class OvertimeState {
  final bool isLoading;
  final List<OvertimeRequest> history;
  final String? error;

  OvertimeState({
    required this.isLoading,
    required this.history,
    this.error,
  });

  factory OvertimeState.initial() => OvertimeState(
        isLoading: false,
        history: [],
      );

  OvertimeState copyWith({
    bool? isLoading,
    List<OvertimeRequest>? history,
    String? error,
  }) {
    return OvertimeState(
      isLoading: isLoading ?? this.isLoading,
      history: history ?? this.history,
      error: error ?? this.error,
    );
  }
}

class OvertimeNotifier extends StateNotifier<OvertimeState> {
  final Ref<OvertimeState> _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/overtime';

  OvertimeNotifier(this._ref) : super(OvertimeState.initial()) {
    fetchHistory();
  }

  Map<String, String> _getHeaders() {
    final authState = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${authState.accessToken ?? ''}',
    };
  }

  Future<void> fetchHistory() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/history'),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final List<dynamic> data = resBody['data'];
        state = OvertimeState(
          isLoading: false,
          history: data.map((x) => OvertimeRequest.fromJson(x)).toList(),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: resBody['error']?['message'] ?? 'Failed to load history.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load history. Please verify connection.',
      );
    }
  }

  Future<bool> createRequest(String date, int minutes, String reason) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/request'),
        headers: _getHeaders(),
        body: jsonEncode({
          'requestDate': date,
          'requestedMinutes': minutes,
          'reason': reason,
        }),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 201 && resBody['success'] == true) {
        await fetchHistory();
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Failed to submit request.';
        state = state.copyWith(isLoading: false, error: errorMsg);
        return false;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Network request failed.');
      return false;
    }
  }
}

final overtimeProvider = StateNotifierProvider<OvertimeNotifier, OvertimeState>((ref) {
  return OvertimeNotifier(ref);
});
