import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthUser {
  final int id;
  final String username;
  final String email;
  final List<String> roles;
  final bool gx; // obfuscated capability flag

  AuthUser({
    required this.id,
    required this.username,
    required this.email,
    required this.roles,
    this.gx = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      email: json['email'] as String,
      roles: List<String>.from(json['roles'] ?? []),
      gx: json['_qx'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'roles': roles,
      };
}

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? accessToken;
  final String? error;

  AuthState({
    required this.status,
    this.user,
    this.accessToken,
    this.error,
  });

  factory AuthState.initial() => AuthState(status: AuthStatus.unauthenticated);

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? accessToken,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      error: error ?? this.error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  // Configured local office host
  String get _baseUrl => ServerConfig.apiBase;

  AuthNotifier() : super(AuthState.initial()) {
    tryAutoLogin();
  }

  /**
   * 1. Attempt Auto Login Session Restoration on startup
   */
  Future<void> tryAutoLogin() async {
    state = state.copyWith(status: AuthStatus.authenticating);
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      final userJson = prefs.getString('auth_user');

      if (accessToken == null || userJson == null) {
        state = AuthState.initial();
        return;
      }

      final user = AuthUser.fromJson(jsonDecode(userJson));
      
      // Attempt to verify with backend GET /auth/me
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/auth/me'),
          headers: {'Authorization': 'Bearer $accessToken'},
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          final resBody = jsonDecode(response.body);
          final updatedUser = AuthUser.fromJson(resBody['data']);
          state = AuthState(
            status: AuthStatus.authenticated,
            user: updatedUser,
            accessToken: accessToken,
          );
        } else {
          // Token might be expired, clear session
          await logout();
        }
      } catch (e) {
        // Local network backend offline, restore cached session anyway for offline/local testing
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          accessToken: accessToken,
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Failed to restore session: ${e.toString()}',
      );
    }
  }

  /**
   * 2. Log in using username/email and password
   */
  Future<bool> login(String usernameOrEmail, String password, bool rememberMe) async {
    state = state.copyWith(status: AuthStatus.authenticating, error: null);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'usernameOrEmail': usernameOrEmail,
          'password': password,
          'deviceInfo': kIsWeb ? 'Flutter Web Browser' : 'Local Device Client'
        }),
      );

      final resBody = jsonDecode(response.body);

      if (response.statusCode == 200 && resBody['success'] == true) {
        final data = resBody['data'];
        final accessToken = data['accessToken'] as String;
        final refreshToken = data['refreshToken'] as String;
        final user = AuthUser.fromJson(data['user']);

        if (rememberMe) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', accessToken);
          await prefs.setString('refresh_token', refreshToken);
          await prefs.setString('auth_user', jsonEncode(user.toJson()));
        }

        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          accessToken: accessToken,
        );
        return true;
      } else {
        final errorMsg = resBody['error']?['message'] ?? 'Login failed. Invalid credentials.';
        state = state.copyWith(
          status: AuthStatus.error,
          error: errorMsg,
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        error: 'Backend connection failed. Please ensure the local office API is online.',
      );
      return false;
    }
  }

  /**
   * 3. Log out and clear tokens
   */
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');

    // Attempt to notify backend
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        );
      } catch (_) {}
    }

    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('auth_user');

    state = AuthState.initial();
  }

  /**
   * 4. Change user password
   */
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (state.accessToken == null) return false;
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${state.accessToken}',
        },
        body: jsonEncode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      );

      final resBody = jsonDecode(response.body);
      if (response.statusCode == 200 && resBody['success'] == true) {
        return true;
      } else {
        state = state.copyWith(
          error: resBody['error']?['message'] ?? 'Failed to change password.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to communicate with office server.');
      return false;
    }
  }
}

// Global provider for state manipulation
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
