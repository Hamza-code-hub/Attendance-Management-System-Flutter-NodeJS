import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../authentication/presentation/auth_state.dart';

class AdjustmentRequest {
  final String id;
  final int userId;
  final String? attendanceId;
  final String adjustmentType; // MISSED_CHECKIN, MISSED_CHECKOUT, LATE_COMPENSATION, EARLY_LEAVE, CUSTOM
  final int requestedMinutes;
  final int approvedMinutes;
  final String? requestedCheckinTime;
  final String? requestedCheckoutTime;
  final String reason;
  final String status; // PENDING, APPROVED, REJECTED
  final String? hrComment;
  final int? reviewedBy;
  final String? reviewedAt;
  final String? managerApprovedAt;
  final String createdAt;
  final String updatedAt;
  // joined fields
  final String? username;
  final String? firstName;
  final String? lastName;

  AdjustmentRequest({
    required this.id,
    required this.userId,
    this.attendanceId,
    required this.adjustmentType,
    required this.requestedMinutes,
    required this.approvedMinutes,
    this.requestedCheckinTime,
    this.requestedCheckoutTime,
    required this.reason,
    required this.status,
    this.hrComment,
    this.reviewedBy,
    this.reviewedAt,
    this.managerApprovedAt,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.firstName,
    this.lastName,
  });

  factory AdjustmentRequest.fromJson(Map<String, dynamic> json) {
    return AdjustmentRequest(
      id: json['id'] ?? '',
      userId: json['userId'] ?? 0,
      attendanceId: json['attendanceId'],
      adjustmentType: json['adjustmentType'] ?? 'CUSTOM',
      requestedMinutes: json['requestedMinutes'] ?? 0,
      approvedMinutes: json['approvedMinutes'] ?? 0,
      requestedCheckinTime: json['requestedCheckinTime'],
      requestedCheckoutTime: json['requestedCheckoutTime'],
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'PENDING',
      hrComment: json['hrComment'],
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'],
      managerApprovedAt: json['managerApprovedAt'],
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
      username: json['username'],
      firstName: json['firstName'],
      lastName: json['lastName'],
    );
  }
}

class AdjustmentState {
  final bool isLoading;
  final List<AdjustmentRequest> history;
  final String? error;

  AdjustmentState({
    required this.isLoading,
    required this.history,
    this.error,
  });

  factory AdjustmentState.initial() => AdjustmentState(
        isLoading: false,
        history: [],
      );

  AdjustmentState copyWith({
    bool? isLoading,
    List<AdjustmentRequest>? history,
    String? error,
  }) {
    return AdjustmentState(
      isLoading: isLoading ?? this.isLoading,
      history: history ?? this.history,
      error: error ?? this.error,
    );
  }
}

class AdjustmentNotifier extends StateNotifier<AdjustmentState> {
  final Ref<AdjustmentState> _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/adjustments';

  AdjustmentNotifier(this._ref) : super(AdjustmentState.initial()) {
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
        state = AdjustmentState(
          isLoading: false,
          history: data.map((x) => AdjustmentRequest.fromJson(x)).toList(),
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

  Future<bool> createRequest({
    required String type,
    String? checkinTime,
    String? checkoutTime,
    required String reason,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/request'),
        headers: _getHeaders(),
        body: jsonEncode({
          'adjustmentType': type,
          'requestedCheckinTime': checkinTime,
          'requestedCheckoutTime': checkoutTime,
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

final adjustmentProvider = StateNotifierProvider<AdjustmentNotifier, AdjustmentState>((ref) {
  return AdjustmentNotifier(ref);
});
