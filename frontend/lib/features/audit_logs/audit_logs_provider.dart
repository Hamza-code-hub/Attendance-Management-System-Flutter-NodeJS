import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../authentication/presentation/auth_state.dart';

class AuditLogItem {
  final int id;
  final int? actorId;
  final String action;
  final String entityName;
  final int? entityId;
  final String description;
  final String ipAddress;
  final String? userAgent;
  final String createdAt;
  final String? username;

  AuditLogItem({
    required this.id,
    this.actorId,
    required this.action,
    required this.entityName,
    this.entityId,
    required this.description,
    required this.ipAddress,
    this.userAgent,
    required this.createdAt,
    this.username,
  });

  factory AuditLogItem.fromJson(Map<String, dynamic> json) {
    return AuditLogItem(
      id: json['id'] ?? 0,
      actorId: json['actor_id'],
      action: json['action'] ?? '',
      entityName: json['entity_name'] ?? '',
      entityId: json['entity_id'],
      description: json['description'] ?? '',
      ipAddress: json['ip_address'] ?? '',
      userAgent: json['user_agent'],
      createdAt: json['created_at'] ?? '',
      username: json['username'],
    );
  }
}

class AuditLogsState {
  final bool isLoading;
  final List<AuditLogItem> logs;
  final String? error;

  AuditLogsState({
    required this.isLoading,
    required this.logs,
    this.error,
  });

  factory AuditLogsState.initial() => AuditLogsState(
        isLoading: false,
        logs: [],
      );

  AuditLogsState copyWith({
    bool? isLoading,
    List<AuditLogItem>? logs,
    String? error,
  }) {
    return AuditLogsState(
      isLoading: isLoading ?? this.isLoading,
      logs: logs ?? this.logs,
      error: error ?? this.error,
    );
  }
}

class AuditLogsNotifier extends StateNotifier<AuditLogsState> {
  final Ref<AuditLogsState> _ref;
  String get _baseUrl => '${ServerConfig.apiBase}/audit-logs';

  AuditLogsNotifier(this._ref) : super(AuditLogsState.initial()) {
    fetchLogs();
  }

  Map<String, String> _getHeaders() {
    final authState = _ref.read(authProvider);
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${authState.accessToken ?? ''}',
    };
  }

  Future<void> fetchLogs() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: _getHeaders(),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        final List<dynamic> data = resBody['data'] ?? [];
        state = AuditLogsState(
          isLoading: false,
          logs: data.map((x) => AuditLogItem.fromJson(x)).toList(),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: resBody['error']?['message'] ?? 'Failed to load audit logs.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Network connection failed.',
      );
    }
  }
}

final auditLogsProvider = StateNotifierProvider<AuditLogsNotifier, AuditLogsState>((ref) {
  return AuditLogsNotifier(ref);
});
