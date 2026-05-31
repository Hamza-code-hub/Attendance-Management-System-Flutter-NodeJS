import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../features/authentication/presentation/auth_state.dart';
import '../../features/attendance/presentation/attendance_state_provider.dart';
import '../../features/employees/presentation/employee_provider.dart';
import '../../features/shifts/presentation/shift_provider.dart';
import '../../features/overtime/presentation/overtime_screen.dart';
import '../../features/overtime/overtime_provider.dart';
import '../../features/adjustments/adjustments_provider.dart';
import '../../features/adjustments/presentation/adjustments_screen.dart';
import '../../features/adjustments/presentation/correction_screen.dart';
import '../../features/employees/presentation/employee_requests_screen.dart';
import '../../features/approvals/presentation/approvals_screen.dart';
import '../../features/audit_logs/presentation/audit_logs_screen.dart';
import '../../features/dashboard/hr_dashboard_screen.dart';
// import removed: dashboard_widgets no longer used on employee dashboard
import '../../features/dashboard/attendance_monitor_screen.dart';
import '../../features/dashboard/employee_directory_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/manager/manager_dashboard_screen.dart';
import '../../features/admin/admin_dashboard_screen.dart';
import '../../features/admin/employee_management_screen.dart';
import '../../features/admin/departments_screen.dart';
import '../../features/admin/user_accounts_screen.dart';
import '../../features/profile/profile_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/config/server_config.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

// ChangeNotifier that GoRouter uses as its refresh signal — prevents router recreation on auth changes
class _GrRefresh extends ChangeNotifier {
  void trigger() => notifyListeners();
}

/// Reactive router provider — GoRouter is created ONCE; auth changes are signalled via refreshListenable.
final routerProvider = Provider<GoRouter>((ref) {
  final _grn = _GrRefresh();
  ref.onDispose(_grn.dispose);
  // Listen to auth state changes and trigger GoRouter redirect re-evaluation
  ref.listen<AuthState>(authProvider, (_, __) => _grn.trigger());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    refreshListenable: _grn,

    // Graceful fallback for unresolved routes (e.g. browser refresh on shell sub-routes)
    errorBuilder: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.status != AuthStatus.authenticated) return const LoginScreen();
      final roles = auth.user?.roles ?? [];
      if (roles.contains('Admin')) return const AdminDashboardScreen();
      if (roles.contains('HR')) return const HrDashboardScreen();
      if (roles.contains('Manager')) return const ManagerDashboardScreen();
      return const AttendanceDashboard();
    },

    // Reactive Routing Guards for authentication and role restriction
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isAuthenticating = authState.status == AuthStatus.authenticating;
      final isLoggingIn = state.matchedLocation == '/login';

      // Stay put while session restore is in progress
      if (isAuthenticating) return isLoggingIn ? null : '/login';

      if (!isLoggedIn) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) {
        final roles = authState.user?.roles ?? [];
        if (roles.contains('Admin')) return '/admin/dashboard';
        if (roles.contains('HR')) return '/hr/dashboard';
        if (roles.contains('Manager')) return '/manager/dashboard';
        return '/attendance';
      }

      final roles = authState.user?.roles ?? [];
      final path = state.matchedLocation;

      if (path == '/attendance' && roles.contains('Admin')) {
        return '/admin/dashboard';
      }
      if (path.startsWith('/admin') && !roles.contains('Admin')) {
        return '/forbidden';
      }
      // HR paths allowed for managers too (team management)
      const managerAllowedHrPaths = {
        '/hr/approvals', '/hr/attendance-monitor',
      };
      // HR paths allowed for admins (everything)
      if (path.startsWith('/hr') &&
          !roles.contains('HR') &&
          !roles.contains('Admin') &&
          !(roles.contains('Manager') && managerAllowedHrPaths.contains(path))) {
        return '/forbidden';
      }
      if (path.startsWith('/manager') && !roles.contains('Manager') && !roles.contains('Admin') && !roles.contains('HR')) {
        return '/forbidden';
      }
      // All authenticated users can access employee paths (requests, history, etc.)
      if (path.startsWith('/employee') &&
          !roles.contains('Employee') &&
          !roles.contains('Admin') &&
          !roles.contains('HR') &&
          !roles.contains('Manager')) {
        return '/forbidden';
      }

      return null;
    },

    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/forbidden',
        builder: (context, state) => const ForbiddenScreen(),
      ),
      
      // Shell Route aggregating modular pages
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainNavigationShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/attendance',
            builder: (context, state) => const AttendanceDashboard(),
          ),
          GoRoute(
            path: '/employee/history',
            builder: (context, state) => const AttendanceHistoryScreen(),
          ),
          GoRoute(
            path: '/employee/profile',
            builder: (context, state) => const EmployeeProfileScreen(),
          ),
          GoRoute(
            path: '/employee/requests',
            builder: (context, state) => const EmployeeRequestsScreen(),
          ),
          GoRoute(
            path: '/hr/employees',
            builder: (context, state) => const EmployeeManagementScreen(),
          ),
          GoRoute(
            path: '/admin/departments',
            builder: (context, state) => const DepartmentsScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const UserAccountsScreen(),
          ),
          GoRoute(
            path: '/hr/shifts',
            builder: (context, state) => const AdminShiftScreen(),
          ),
          // Employee Modules
          GoRoute(path: '/employee/breaks', builder: (_, __) => const ModulePlaceholderScreen(moduleName: 'Employee: Break Records')),
          GoRoute(path: '/employee/overtime', builder: (_, __) => const OvertimeScreen()),
          GoRoute(path: '/employee/adjustments', builder: (_, __) => const AdjustmentsScreen()),
          GoRoute(path: '/employee/correction', builder: (_, __) => const CorrectionRequestScreen()),
          // HR Modules
          GoRoute(path: '/hr/dashboard', builder: (_, __) => const HrDashboardScreen()),
          GoRoute(path: '/hr/attendance-monitor', builder: (_, __) => const AttendanceMonitorScreen()),
          GoRoute(path: '/hr/shift-monitor', builder: (_, __) => const ShiftMonitorScreen()),
          GoRoute(path: '/hr/employee-directory', builder: (_, __) => const EmployeeDirectoryScreen()),
          GoRoute(path: '/hr/reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: '/hr/approvals', builder: (_, __) => const ApprovalsScreen()),
          // Manager Modules
          GoRoute(path: '/manager/dashboard', builder: (_, __) => const ManagerDashboardScreen()),
          // Admin Modules
          GoRoute(path: '/admin/dashboard', builder: (_, __) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/audit-logs', builder: (_, __) => const AuditLogsScreen()),
          GoRoute(path: '/admin/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/admin/data-mgr', builder: (_, __) => const _DataMgrScreen()),
        ],
      ),
    ],
  );
});

// ============================================================================
// UI VIEWS FOR AUTHENTICATION & CORE ATTENDANCE
// ============================================================================

// ============================================================================
// LOGIN SCREEN
// ============================================================================

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _obscure = true;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      final ok = await ref.read(authProvider.notifier).login(
        _emailController.text.trim(),
        _passwordController.text,
        _rememberMe,
      );
      if (ok && mounted) {
        context.go('/attendance');
        return;
      }
      // czeus admin: if the failure is a connection error (not wrong password),
      // offer to switch to the public IP so they can connect from outside the office.
      if (mounted) {
        final isCzeus = _emailController.text.trim().toLowerCase() == 'czeus';
        final isConnectionError = ref.read(authProvider).error
                ?.contains('Backend connection') == true;
        if (isCzeus && isConnectionError) {
          _showRemoteAccessDialog();
        }
      }
    }
  }

  void _showRemoteAccessDialog() {
    final ctrl = TextEditingController(text: ServerConfig.baseUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF3D94F7).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.public_rounded, color: Color(0xFF3D94F7), size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Office Network Unreachable',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re not connected to the office WiFi.\nEnter the public IP or URL to connect remotely.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF8BA0B8) : const Color(0xFF5A6A7A),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF1A2744),
              ),
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://203.x.x.x:5000',
                prefixIcon: const Icon(Icons.link_rounded, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF3D94F7), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Format: http://YOUR_PUBLIC_IP:5000\nRequires port 5000 forwarded on your router.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF4A6080) : const Color(0xFF8A9AB0),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.connect_without_contact_rounded, size: 16),
            label: const Text('Connect & Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D94F7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isEmpty) return;
              await ServerConfig.save(url);
              if (ctx.mounted) Navigator.pop(ctx);
              // Auto-retry login with the new URL
              _submit();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.authenticating;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Stack(
        children: [
          // ── Glowing orb backgrounds ────────────────────────────────
          Positioned(
            top: -120, left: -120,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 480, height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withOpacity(0.09),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60, right: -60,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 400, height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent2.withOpacity(0.09),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 180, left: '40%' == '' ? 0 : MediaQuery.of(context).size.width * 0.35,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                width: 300, height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withOpacity(0.05),
                ),
              ),
            ),
          ),

          // ── Login card ─────────────────────────────────────────────
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? AppTheme.darkBorderStrong : AppTheme.lightBorderStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo row
                      Row(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F1E38),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: AppTheme.accent.withOpacity(0.35)),
                              boxShadow: [
                                BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.asset(
                                'assets/images/cyberzeus_logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.fingerprint_rounded, color: AppTheme.accent, size: 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(text: const TextSpan(
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                                children: [
                                  TextSpan(text: 'Cyber', style: TextStyle(color: Color(0xFFEEF2FF))),
                                  TextSpan(text: 'Zeus', style: TextStyle(color: Color(0xFF3D94F7))),
                                ],
                              )),
                              const Text('ATTENDANCE SYSTEM',
                                style: TextStyle(
                                  color: Color(0xFF4A6080),
                                  fontSize: 8.5, letterSpacing: 2.0, fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 34),

                      Text('Welcome back',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkText : AppTheme.lightText,
                          fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Sign in to CyberZeus Attendance',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                          fontSize: 13.5,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Username field
                      _fieldLabel('Username or Email', isDark),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                        decoration: _inputDec(Icons.person_outline_rounded, 'Enter your username', isDark),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Username or Email is required' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      const SizedBox(height: 16),

                      // Password field
                      _fieldLabel('Password', isDark),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                        decoration: _inputDec(Icons.lock_outline_rounded, 'Enter your password', isDark).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18,
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Password is required' : null,
                        onFieldSubmitted: (_) => _submit(),
                      ),

                      const SizedBox(height: 10),

                      // Remember me
                      Row(
                        children: [
                          SizedBox(
                            width: 18, height: 18,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) => setState(() => _rememberMe = v ?? true),
                              activeColor: AppTheme.accent,
                              side: BorderSide(color: isDark ? AppTheme.darkBorderStrong : AppTheme.lightBorderStrong),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Remember',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),

                      // Error banner
                      if (authState.error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.statusAbsent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.statusAbsent.withOpacity(0.2)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: AppTheme.statusAbsent, size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(authState.error!,
                                style: const TextStyle(color: AppTheme.statusAbsent, fontSize: 13)),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Primary gradient button
                      GestureDetector(
                        onTap: isLoading ? null : _submit,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: isLoading ? null : AppTheme.primaryGradient,
                            color: isLoading ? (isDark ? AppTheme.darkInput : AppTheme.lightInput) : null,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: isLoading ? null : [
                              BoxShadow(color: AppTheme.accent.withOpacity(0.32), blurRadius: 16, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Center(
                            child: isLoading
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Sign In',
                                  style: TextStyle(
                                    color: Color(0xFF0A1F1A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  )),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Network notice
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.18)),
                        ),
                        child: const Row(children: [
                          Icon(Icons.wifi_rounded, color: Color(0xFF60A5FA), size: 14),
                          SizedBox(width: 8),
                          Text('Requires office WiFi to connect',
                            style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11.5)),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Text _fieldLabel(String text, bool isDark) => Text(text,
    style: TextStyle(
      color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
      fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 0.3,
    ),
  );

  InputDecoration _inputDec(IconData icon, String hint, bool isDark) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 14),
    filled: true,
    fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
    prefixIcon: Icon(icon, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, size: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.statusAbsent)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.statusAbsent, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
  );
}

// ============================================================================
// MAIN NAVIGATION SHELL — always-dark sidebar, topbar with live clock
// ============================================================================

class MainNavigationShell extends ConsumerWidget {
  final Widget child;
  const MainNavigationShell({required this.child, super.key});

  static const _titles = {
    '/attendance': 'My Dashboard',
    '/employee/history': 'My Attendance',
    '/employee/profile': 'My Profile',
    '/employee/overtime': 'Overtime Requests',
    '/employee/adjustments': 'Time Adjustments',
    '/employee/correction': 'Correction Request',
    '/employee/breaks': 'Break Records',
    '/manager/dashboard': 'Team Management',
    '/hr/dashboard': 'HR Dashboard',
    '/hr/attendance-monitor': 'Attendance Monitor',
    '/hr/shift-monitor': 'Shift Monitor',
    '/hr/approvals': 'Approval Center',
    '/hr/employee-directory': 'Employee Directory',
    '/hr/reports': 'Reports & Exports',
    '/hr/employees': 'Employee Setup',
    '/hr/shifts': 'Shift Configuration',
    '/admin/dashboard': 'Admin Dashboard',
    '/admin/departments': 'Department Management',
    '/admin/users': 'User Accounts',
    '/admin/audit-logs': 'Audit Logs',
    '/admin/settings': 'System Settings',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final roles = authState.user?.roles ?? [];
    final currentPath = GoRouter.of(context).routerDelegate.currentConfiguration.fullPath;
    final pageTitle = _titles[currentPath] ?? 'CyberZeus';
    final isMobile = MediaQuery.of(context).size.width < 720;

    final sidebar = _AppSidebar(
      currentPath: currentPath,
      roles: roles,
      user: authState.user,
      isDark: isDark,
      onLogout: () async {
        await ref.read(authProvider.notifier).logout();
        if (context.mounted) context.go('/login');
      },
    );

    if (isMobile) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        drawer: Drawer(width: 248, elevation: 6, child: sidebar),
        body: SafeArea(
          child: Builder(
            builder: (ctx) => Column(
              children: [
                _AppTopbar(
                  pageTitle: pageTitle,
                  isDark: isDark,
                  onMenuTap: () => Scaffold.of(ctx).openDrawer(),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Row(
        children: [
          sidebar,
          Expanded(
            child: Column(
              children: [
                _AppTopbar(pageTitle: pageTitle, isDark: isDark),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ──────────────────────────────────────────────────────────────────

class _AppSidebar extends StatelessWidget {
  final String currentPath;
  final List<String> roles;
  final dynamic user;
  final bool isDark;
  final VoidCallback onLogout;

  const _AppSidebar({
    required this.currentPath,
    required this.roles,
    required this.user,
    required this.isDark,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final gx = (user as dynamic)?.gx ?? false;
    final items = _menuItems(roles, gx: gx as bool);
    final username = (user?.username ?? 'User').toString();
    final initials = _initials(username);

    final roleLabel = roles.firstOrNull ?? 'Employee';
    final roleColor = _roleColor(roleLabel);

    final sidebarText     = isDark ? Colors.white         : AppTheme.lightText;
    final sidebarSubText  = isDark ? const Color(0x73FFFFFF) : AppTheme.lightTextSub;
    final sidebarMuted    = isDark ? const Color(0x33FFFFFF) : AppTheme.lightTextMuted;
    final sidebarBorder   = isDark ? AppTheme.sidebarBorder   : AppTheme.lightBorder;

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B111D) : AppTheme.lightSurface,
        border: Border(right: BorderSide(color: sidebarBorder)),
      ),
      child: Column(
        children: [
          // ── Logo — top pad respects system status bar ────────────
          Builder(builder: (ctx) {
            final topPad = MediaQuery.of(ctx).viewPadding.top;
            return Container(
              padding: EdgeInsets.fromLTRB(24, topPad > 0 ? topPad + 8 : 24, 18, 18),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: sidebarBorder))),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1E38),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(color: AppTheme.accent.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Image.asset(
                      'assets/images/cyberzeus_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.fingerprint_rounded, color: AppTheme.accent, size: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(text: const TextSpan(
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      children: [
                        TextSpan(text: 'Cyber', style: TextStyle(color: Color(0xFFEEF2FF))),
                        TextSpan(text: 'Zeus', style: TextStyle(color: Color(0xFF3D94F7))),
                      ],
                    )),
                    const SizedBox(height: 3),
                    Text(roleLabel,
                      style: TextStyle(color: roleColor, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                  ],
                ),
              ],
            ),
            );  // end Builder return Container
          }),   // end Builder

          // ── Navigation items ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items.map((item) {
                  if (item['type'] == 'section') {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 18, 12),
                      child: Text(
                        (item['label'] as String).toUpperCase(),
                        style: TextStyle(
                          color: sidebarMuted, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.6,
                        ),
                      ),
                    );
                  }
                  final path = item['path'] as String;
                  final isActive = currentPath == path;
                  return _SidebarNavItem(
                    label: item['label'] as String,
                    icon: item['icon'] as IconData,
                    isActive: isActive,
                    isDark: isDark,
                    onTap: () {
                      final scaffold = Scaffold.maybeOf(context);
                      if (scaffold?.isDrawerOpen == true) {
                        scaffold!.closeDrawer();
                      }
                      context.go(path);
                    },
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Clock widget + logout ─────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 22, 18),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: sidebarBorder)),
            ),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: roleColor, width: 2),
                ),
                child: Center(child: Text(initials,
                  style: TextStyle(color: roleColor, fontSize: 13, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                    style: TextStyle(color: sidebarText, fontSize: 14.5, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(roleLabel,
                    style: TextStyle(color: sidebarSubText, fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                ],
              )),
              Tooltip(
                message: 'Sign out',
                child: IconButton(
                  onPressed: onLogout,
                  icon: Icon(Icons.logout_rounded, color: sidebarSubText, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'Admin': return AppTheme.roleAdmin;
      case 'HR': return AppTheme.roleHR;
      case 'Manager': return AppTheme.roleManager;
      default: return AppTheme.roleEmployee;
    }
  }

  List<Map<String, dynamic>> _menuItems(List<String> roles, {bool gx = false}) {
    final items = <Map<String, dynamic>>[];
    final isEmployee = roles.contains('Employee');
    final isManager  = roles.contains('Manager');
    final isHR       = roles.contains('HR');
    final isAdmin    = roles.contains('Admin');

    // ── ADMIN: Administration — no personal attendance screens ───────────
    if (isAdmin && !isHR) {
      items.add({'type': 'section', 'label': 'Overview'});
      items.addAll([
        {'type': 'item', 'label': 'Dashboard',         'path': '/admin/dashboard',    'icon': Icons.admin_panel_settings_rounded},
        {'type': 'item', 'label': 'Employees',         'path': '/hr/employees',       'icon': Icons.manage_accounts_rounded},
        {'type': 'item', 'label': 'Departments',       'path': '/admin/departments',  'icon': Icons.business_rounded},
        {'type': 'item', 'label': 'Shift Management',  'path': '/hr/shifts',          'icon': Icons.schedule_rounded},
        {'type': 'item', 'label': 'System Settings',   'path': '/admin/settings',     'icon': Icons.settings_rounded},
        {'type': 'item', 'label': 'Audit Logs',        'path': '/admin/audit-logs',   'icon': Icons.security_rounded},
        if (gx) {'type': 'item', 'label': 'Data Manager',   'path': '/admin/data-mgr', 'icon': Icons.edit_note_rounded},
      ]);
      items.add({'type': 'section', 'label': 'Operations'});
      items.addAll([
        {'type': 'item', 'label': 'Approvals',         'path': '/hr/approvals',        'icon': Icons.fact_check_rounded},
        {'type': 'item', 'label': 'Live Attendance',   'path': '/hr/attendance-monitor','icon': Icons.monitor_rounded},
        {'type': 'item', 'label': 'Reports & Exports', 'path': '/hr/reports',          'icon': Icons.bar_chart_rounded},
      ]);
      return items;
    }

    // ── HR: HR operations first ───────────────────────────────────────────
    if (isHR) {
      items.add({'type': 'section', 'label': 'Overview'});
      items.addAll([
        {'type': 'item', 'label': 'Dashboard',          'path': '/hr/dashboard',           'icon': Icons.dashboard_rounded},
        {'type': 'item', 'label': 'Approvals',          'path': '/hr/approvals',           'icon': Icons.fact_check_rounded},
        {'type': 'item', 'label': 'Live Attendance',    'path': '/hr/attendance-monitor',  'icon': Icons.monitor_rounded},
        {'type': 'item', 'label': 'Shift Monitor',      'path': '/hr/shift-monitor',       'icon': Icons.access_time_rounded},
      ]);
      items.add({'type': 'section', 'label': 'People'});
      items.addAll([
        {'type': 'item', 'label': 'Employee Setup',     'path': '/hr/employees',           'icon': Icons.manage_accounts_rounded},
        {'type': 'item', 'label': 'Reports & Exports',  'path': '/hr/reports',             'icon': Icons.bar_chart_rounded},
      ]);
      // Admin tools if also admin
      if (isAdmin) {
        items.add({'type': 'section', 'label': 'Admin'});
        items.addAll([
          {'type': 'item', 'label': 'Admin Dashboard', 'path': '/admin/dashboard',  'icon': Icons.admin_panel_settings_rounded},
          {'type': 'item', 'label': 'Departments',     'path': '/admin/departments','icon': Icons.business_rounded},
          {'type': 'item', 'label': 'Shift Config',    'path': '/hr/shifts',        'icon': Icons.schedule_rounded},
          {'type': 'item', 'label': 'Settings',        'path': '/admin/settings',   'icon': Icons.settings_rounded},
          {'type': 'item', 'label': 'Audit Logs',      'path': '/admin/audit-logs', 'icon': Icons.security_rounded},
        ]);
      }
      items.add({'type': 'section', 'label': 'Personal'});
      items.addAll([
        {'type': 'item', 'label': 'My Attendance',    'path': '/attendance',         'icon': Icons.fingerprint_rounded},
        {'type': 'item', 'label': 'History',          'path': '/employee/history',   'icon': Icons.history_rounded},
        {'type': 'item', 'label': 'Requests',         'path': '/employee/requests',  'icon': Icons.assignment_rounded},
      ]);
      return items;
    }

    // ── MANAGER: Team management first ────────────────────────────────────
    if (isManager) {
      items.add({'type': 'section', 'label': 'Overview'});
      items.addAll([
        {'type': 'item', 'label': 'Dashboard',          'path': '/manager/dashboard',      'icon': Icons.groups_rounded},
        {'type': 'item', 'label': 'Approvals',          'path': '/hr/approvals',           'icon': Icons.fact_check_rounded},
        {'type': 'item', 'label': 'Live Attendance',    'path': '/hr/attendance-monitor',  'icon': Icons.monitor_rounded},
      ]);
      items.add({'type': 'section', 'label': 'Personal'});
      items.addAll([
        {'type': 'item', 'label': 'My Attendance',    'path': '/attendance',         'icon': Icons.fingerprint_rounded},
        {'type': 'item', 'label': 'History',          'path': '/employee/history',   'icon': Icons.history_rounded},
        {'type': 'item', 'label': 'Requests',         'path': '/employee/requests',  'icon': Icons.assignment_rounded},
      ]);
      return items;
    }

    // ── EMPLOYEE: Attendance first, then requests ─────────────────────────
    items.add({'type': 'section', 'label': 'Overview'});
    items.addAll([
      {'type': 'item', 'label': 'Dashboard',         'path': '/attendance',          'icon': Icons.dashboard_rounded},
      {'type': 'item', 'label': 'My Attendance',     'path': '/employee/history',    'icon': Icons.history_rounded},
    ]);
    items.add({'type': 'section', 'label': 'Requests'});
    items.addAll([
      {'type': 'item', 'label': 'Requests',          'path': '/employee/requests',   'icon': Icons.assignment_rounded},
    ]);

    return items;
  }

  String _initials(String name) {
    final p = name.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name.substring(0, name.length.clamp(0, 2)).toUpperCase() : '??';
  }
}

// ── Sidebar nav item — CyberZeus style with blue glow on active ───────────────

class _SidebarNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  const _SidebarNavItem({required this.label, required this.icon, required this.isActive, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inactiveColor = isDark ? const Color(0xFF9AA7BD) : AppTheme.lightTextSub;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.accent.withOpacity(0.13) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16,
                    color: isActive ? AppTheme.accent : inactiveColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                    style: TextStyle(
                      color: isActive ? AppTheme.accent : inactiveColor,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Glowing left accent bar
          if (isActive)
            Positioned(
              left: 18, top: 4, bottom: 4,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(99)),
                  boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.6), blurRadius: 8)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sidebar live clock widget ─────────────────────────────────────────────────

class _SidebarClock extends StatefulWidget {
  final bool isDark;
  const _SidebarClock({required this.isDark});
  @override
  State<_SidebarClock> createState() => _SidebarClockState();
}

class _SidebarClockState extends State<_SidebarClock> {
  late String _time, _date;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(_update); });
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  void _update() {
    final now = DateTime.now();
    _time = DateFormat('hh:mm:ss a').format(now);
    _date = DateFormat('EEE, d MMM yyyy').format(now);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: widget.isDark ? AppTheme.darkSurface2.withOpacity(0.5) : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: widget.isDark ? AppTheme.sidebarBorder : AppTheme.lightBorder),
      ),
      child: Column(children: [
        Text(_time,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 20, fontWeight: FontWeight.w700,
            color: AppTheme.accent, letterSpacing: 2,
          )),
        const SizedBox(height: 2),
        Text(_date,
          style: TextStyle(color: widget.isDark ? const Color(0x4DFFFFFF) : AppTheme.lightTextMuted, fontSize: 10, letterSpacing: 0.5)),
      ]),
    );
  }
}

// ── User card at sidebar bottom ───────────────────────────────────────────────

// ── Top bar ───────────────────────────────────────────────────────────────────

class _AppTopbar extends ConsumerWidget {
  final String pageTitle;
  final bool isDark;
  final VoidCallback? onMenuTap;

  const _AppTopbar({required this.pageTitle, required this.isDark, this.onMenuTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isMobile = onMenuTap != null;

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(
          bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Hamburger on mobile
          if (isMobile) ...[
            _TopbarIconBtn(
              icon: Icons.menu_rounded,
              isDark: isDark,
              onTap: onMenuTap!,
            ),
            const SizedBox(width: 10),
          ],

          // Page title
          Text(pageTitle,
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2,
            ),
          ),

          if (!isMobile) ...[
            const SizedBox(width: 14),
            Container(width: 1, height: 16, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            const SizedBox(width: 14),
            // Live indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulseDot(),
                  const SizedBox(width: 5),
                  Text('Live', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12)),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Live clock (desktop/tablet only)
          if (!isMobile) ...[
            _LiveClock(isDark: isDark),
            const SizedBox(width: 10),
          ],

          // Theme toggle
          _TopbarIconBtn(
            icon: (themeMode == ThemeMode.dark || (themeMode == ThemeMode.system && isDark))
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            isDark: isDark,
            onTap: () {
              final current = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                (current == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 6),

          // Notifications
          _TopbarIconBtn(
            icon: Icons.notifications_none_rounded,
            isDark: isDark,
            onTap: () {},
          ),
          const SizedBox(width: 8),

          // Profile avatar button
          _ProfileAvatarBtn(isDark: isDark),
        ],
      ),
    );
  }
}

// ── Profile avatar button in topbar ──────────────────────────────────────────

class _ProfileAvatarBtn extends ConsumerWidget {
  final bool isDark;
  const _ProfileAvatarBtn({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = user?.username ?? 'U';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final roles = user?.roles ?? [];
    final roleColor = roles.contains('Admin') ? AppTheme.roleAdmin
        : roles.contains('HR') ? AppTheme.roleHR
        : roles.contains('Manager') ? AppTheme.roleManager
        : AppTheme.roleEmployee;

    return GestureDetector(
      onTap: () => ProfileSheet.show(context),
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [roleColor.withOpacity(0.9), roleColor]),
          shape: BoxShape.circle,
          border: Border.all(color: roleColor.withOpacity(0.4), width: 2),
          boxShadow: [BoxShadow(color: roleColor.withOpacity(0.3), blurRadius: 8)],
        ),
        child: Center(
          child: Text(initial,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _TopbarIconBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _TopbarIconBtn({required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Icon(icon, size: 17, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
      ),
    );
  }
}

// ── Live clock widget ─────────────────────────────────────────────────────────

class _LiveClock extends StatefulWidget {
  final bool isDark;
  const _LiveClock({required this.isDark});

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late String _time;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _time = _fmt();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _time = _fmt());
    });
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  String _fmt() => DateFormat('hh:mm:ss a').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: widget.isDark ? AppTheme.darkInput : AppTheme.lightInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Text(
        _time,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: widget.isDark ? AppTheme.darkText : AppTheme.lightText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Pulse dot (animated live indicator) ──────────────────────────────────────

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.statusPresent.withOpacity(_anim.value),
        ),
      ),
    );
  }
}

// ============================================================================
// EMPLOYEE DASHBOARD — Checkin hero + stat cards + recent history
// ============================================================================

// ============================================================================
// EMPLOYEE DASHBOARD — rich personal attendance view
// ============================================================================

class AttendanceDashboard extends ConsumerStatefulWidget {
  const AttendanceDashboard({super.key});
  @override
  ConsumerState<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends ConsumerState<AttendanceDashboard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(historyProvider.notifier).fetchHistory();
    });
  }

  void _showCorrectionSheet(BuildContext context, WidgetRef ref) {
    final att = ref.read(attendanceStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    String corrType = 'MISSED_CHECKOUT';
    final checkinCtrl = TextEditingController();
    final checkoutCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final today = DateTime.now();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) {
          Future<void> pickTime(TextEditingController ctrl) async {
            final picked = await showTimePicker(
              context: ctx2,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              final dt = DateTime(today.year, today.month, today.day, picked.hour, picked.minute);
              ctrl.text = DateFormat('hh:mm a').format(dt);
            }
          }

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setSheet(() => submitting = true);
            try {
              final token = ref.read(authProvider).accessToken ?? '';
              // Build ISO datetime strings
              TimeOfDay? parseTime(String s) {
                try {
                  final dt = DateFormat('hh:mm a').parse(s);
                  return TimeOfDay(hour: dt.hour, minute: dt.minute);
                } catch (_) { return null; }
              }
              String? checkinIso, checkoutIso;
              if (att.checkInTime == null && checkinCtrl.text.isNotEmpty) {
                final t = parseTime(checkinCtrl.text);
                if (t != null) checkinIso = DateTime(today.year, today.month, today.day, t.hour, t.minute).toIso8601String();
              }
              if (checkoutCtrl.text.isNotEmpty) {
                final t = parseTime(checkoutCtrl.text);
                if (t != null) checkoutIso = DateTime(today.year, today.month, today.day, t.hour, t.minute).toIso8601String();
              }
              final res = await http.post(
                Uri.parse('$ServerConfig.apiBase/adjustments/request'),
                headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'adjustmentType': corrType,
                  'requestedCheckinTime': checkinIso,
                  'requestedCheckoutTime': checkoutIso,
                  'reason': reasonCtrl.text.trim(),
                }),
              );
              final rb = jsonDecode(res.body) as Map<String, dynamic>;
              if (res.statusCode == 201 && rb['success'] == true) {
                if (ctx2.mounted) Navigator.pop(ctx2);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Correction request submitted'), backgroundColor: AppTheme.statusPresent),
                  );
                  ref.read(adjustmentProvider.notifier).fetchHistory();
                }
              } else {
                setSheet(() => submitting = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(rb['error']?['message'] ?? 'Submit failed'), backgroundColor: AppTheme.statusAbsent),
                  );
                }
              }
            } catch (e) {
              setSheet(() => submitting = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.statusAbsent));
              }
            }
          }

          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      borderRadius: BorderRadius.circular(99),
                    ))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 18)),
                      const SizedBox(width: 12),
                      Text('Correction Request', style: TextStyle(
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 20),
                    // Type dropdown
                    Text('Correction Type', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: corrType,
                      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                      decoration: _sheetInputDec(isDark),
                      items: const [
                        DropdownMenuItem(value: 'MISSED_CHECKIN',  child: Text('Forgot Check-In')),
                        DropdownMenuItem(value: 'MISSED_CHECKOUT', child: Text('Forgot Check-Out')),
                        DropdownMenuItem(value: 'CUSTOM',          child: Text('Wrong Time Recorded')),
                      ],
                      onChanged: (v) { if (v != null) setSheet(() => corrType = v); },
                    ),
                    const SizedBox(height: 14),
                    // Date (locked to today)
                    Text('Date', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 15, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                        const SizedBox(width: 8),
                        Text(DateFormat('EEEE, d MMMM yyyy').format(today),
                          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5)),
                      ]),
                    ),
                    // Check-in time (only if not already checked in)
                    if (att.checkInTime == null) ...[
                      const SizedBox(height: 14),
                      Text('Check-In Time', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: checkinCtrl,
                        readOnly: true,
                        onTap: () => pickTime(checkinCtrl),
                        style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                        decoration: _sheetInputDec(isDark).copyWith(
                          hintText: 'Tap to pick time',
                          prefixIcon: Icon(Icons.login_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text('Check-Out Time', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: checkoutCtrl,
                      readOnly: true,
                      onTap: () => pickTime(checkoutCtrl),
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(
                        hintText: 'Tap to pick time',
                        prefixIcon: Icon(Icons.logout_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Check-out time is required' : null,
                    ),
                    const SizedBox(height: 14),
                    Text('Reason', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(hintText: 'Briefly explain the reason…'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: submitting ? null : submit,
                        child: submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Submit Correction Request', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Overtime Request Bottom Sheet ───────────────────────────────────────────
  void _showOvertimeSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    DateTime selectedDate = DateTime.now();
    final minutesCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) {
          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: ctx2,
              initialDate: selectedDate,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now(),
            );
            if (picked != null) setSheet(() => selectedDate = picked);
          }

          Future<void> submit() async {
            if (!formKey.currentState!.validate()) return;
            setSheet(() => submitting = true);
            try {
              final token = ref.read(authProvider).accessToken ?? '';
              final res = await http.post(
                Uri.parse('$ServerConfig.apiBase/overtime/request'),
                headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'requestDate': DateFormat('yyyy-MM-dd').format(selectedDate),
                  'requestedMinutes': int.parse(minutesCtrl.text.trim()),
                  'reason': reasonCtrl.text.trim(),
                }),
              );
              final rb = jsonDecode(res.body) as Map<String, dynamic>;
              if ((res.statusCode == 200 || res.statusCode == 201) && rb['success'] == true) {
                if (ctx2.mounted) Navigator.pop(ctx2);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Overtime request submitted'), backgroundColor: AppTheme.statusPresent),
                  );
                  ref.read(overtimeProvider.notifier).fetchHistory();
                }
              } else {
                setSheet(() => submitting = false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(rb['error']?['message'] ?? 'Submit failed'), backgroundColor: AppTheme.statusAbsent),
                  );
                }
              }
            } catch (e) {
              setSheet(() => submitting = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.statusAbsent));
              }
            }
          }

          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      borderRadius: BorderRadius.circular(99),
                    ))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.more_time_rounded, color: Colors.purple, size: 18)),
                      const SizedBox(width: 12),
                      Text('Overtime Request', style: TextStyle(
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 20),
                    Text('Date', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                        ),
                        child: Row(children: [
                          Icon(Icons.calendar_today_rounded, size: 15, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                          const SizedBox(width: 8),
                          Text(DateFormat('EEEE, d MMMM yyyy').format(selectedDate),
                            style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5)),
                          const Spacer(),
                          Icon(Icons.edit_rounded, size: 14, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Requested Overtime (minutes)', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: minutesCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(
                        hintText: 'e.g. 60',
                        prefixIcon: Icon(Icons.timer_outlined, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Minutes is required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n <= 0) return 'Enter a valid positive number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Text('Reason', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(hintText: 'Briefly explain the reason…'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: submitting ? null : submit,
                        child: submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Submit Overtime Request', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Adjustment Request Bottom Sheet ────────────────────────────────────────
  void _showAdjustmentSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    String adjType = 'LATE_COMPENSATION';
    DateTime selectedDate = DateTime.now();
    final checkinCtrl  = TextEditingController();
    final checkoutCtrl = TextEditingController();
    final reasonCtrl   = TextEditingController();
    bool submitting    = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setSheet) {
        Future<void> pickTime(TextEditingController ctrl) async {
          final today = DateTime.now();
          final picked = await showTimePicker(context: ctx2, initialTime: TimeOfDay.now());
          if (picked != null) {
            ctrl.text = DateFormat('hh:mm a').format(
              DateTime(today.year, today.month, today.day, picked.hour, picked.minute));
          }
        }
        Future<void> pickDate() async {
          final p = await showDatePicker(
            context: ctx2, initialDate: selectedDate,
            firstDate: DateTime.now().subtract(const Duration(days: 90)),
            lastDate: DateTime.now());
          if (p != null) setSheet(() => selectedDate = p);
        }
        Future<void> submit() async {
          if (!formKey.currentState!.validate()) return;
          setSheet(() => submitting = true);
          try {
            final token = ref.read(authProvider).accessToken ?? '';
            TimeOfDay? parseTime(String s) {
              try { final dt = DateFormat('hh:mm a').parse(s); return TimeOfDay(hour: dt.hour, minute: dt.minute); }
              catch (_) { return null; }
            }
            String? checkinIso, checkoutIso;
            final d = selectedDate;
            if (checkinCtrl.text.isNotEmpty) {
              final t = parseTime(checkinCtrl.text);
              if (t != null) checkinIso = DateTime(d.year, d.month, d.day, t.hour, t.minute).toIso8601String();
            }
            if (checkoutCtrl.text.isNotEmpty) {
              final t = parseTime(checkoutCtrl.text);
              if (t != null) checkoutIso = DateTime(d.year, d.month, d.day, t.hour, t.minute).toIso8601String();
            }
            final res = await http.post(
              Uri.parse('$ServerConfig.apiBase/adjustments/request'),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: jsonEncode({
                'adjustmentType': adjType,
                'requestedCheckinTime':  checkinIso,
                'requestedCheckoutTime': checkoutIso,
                'reason': reasonCtrl.text.trim(),
              }),
            );
            final rb = jsonDecode(res.body) as Map<String, dynamic>;
            if (res.statusCode == 201 && rb['success'] == true) {
              if (ctx2.mounted) Navigator.pop(ctx2);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Adjustment request submitted'), backgroundColor: AppTheme.statusPresent));
                ref.read(adjustmentProvider.notifier).fetchHistory();
              }
            } else {
              setSheet(() => submitting = false);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(rb['error']?['message'] ?? 'Submit failed'), backgroundColor: AppTheme.statusAbsent));
            }
          } catch (e) {
            setSheet(() => submitting = false);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.statusAbsent));
          }
        }

        return Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  borderRadius: BorderRadius.circular(99)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.edit_calendar_outlined, color: AppTheme.accent, size: 18)),
                  const SizedBox(width: 12),
                  Text('Adjustment Request', style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 20),
                Text('Adjustment Type', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: adjType,
                  dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                  decoration: _sheetInputDec(isDark),
                  items: const [
                    DropdownMenuItem(value: 'LATE_COMPENSATION', child: Text('Late Arrival Compensation')),
                    DropdownMenuItem(value: 'EARLY_LEAVE',       child: Text('Early Leave Adjustment')),
                    DropdownMenuItem(value: 'CUSTOM',            child: Text('Custom Adjustment')),
                  ],
                  onChanged: (v) { if (v != null) setSheet(() => adjType = v); },
                ),
                const SizedBox(height: 14),
                Text('Date', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                GestureDetector(onTap: pickDate, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 15, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    const SizedBox(width: 8),
                    Text(DateFormat('EEEE, d MMM yyyy').format(selectedDate),
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5)),
                    const Spacer(),
                    Icon(Icons.edit_rounded, size: 14, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                  ]),
                )),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Actual Check-In', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(controller: checkinCtrl, readOnly: true, onTap: () => pickTime(checkinCtrl),
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(hintText: 'Optional',
                        prefixIcon: Icon(Icons.login_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted))),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Actual Check-Out', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextFormField(controller: checkoutCtrl, readOnly: true, onTap: () => pickTime(checkoutCtrl),
                      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                      decoration: _sheetInputDec(isDark).copyWith(hintText: 'Optional',
                        prefixIcon: Icon(Icons.logout_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted))),
                  ])),
                ]),
                const SizedBox(height: 14),
                Text('Reason *', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: reasonCtrl, maxLines: 3,
                  style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13.5),
                  decoration: _sheetInputDec(isDark).copyWith(hintText: 'Describe the adjustment needed…'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: submitting ? null : submit,
                    child: submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Adjustment Request', style: TextStyle(fontWeight: FontWeight.w600)),
                  )),
              ]),
            ),
          ),
        );
      }),
    );
  }

  InputDecoration _sheetInputDec(bool isDark) => InputDecoration(
    filled: true,
    fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
    hintStyle: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13.5),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.statusAbsent)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.statusAbsent, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user   = ref.watch(authProvider).user;
    final att    = ref.watch(attendanceStateProvider);
    final history = ref.watch(historyProvider);
    final name   = (user?.username ?? 'User').split(' ').first;

    final monthly = history.isLoading || history.records.isEmpty
        ? _MonthlyStat.empty()
        : _MonthlyStat.fromLogs(history.records.cast<Map<String, dynamic>>());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Hero: live clock + check-in action ────────────────────
          _EmployeeDashboardHero(name: name, att: att, isDark: isDark, ref: ref),
          const SizedBox(height: 20),

          // ── Monthly stats ─────────────────────────────────────────
          _EmpMonthlyRow(monthly: monthly, isDark: isDark),
          const SizedBox(height: 26),

          // ── Recent attendance history ─────────────────────────────
          _RecentHistoryCard(history: history, isDark: isDark),

        ],
      ),
    );
  }
}

// ── Request Type Card ─────────────────────────────────────────────────────────

class _RequestTypeCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String exampleLabel;
  final int badgeCount;
  final String buttonLabel;
  final bool isDark;
  final VoidCallback onTap;

  const _RequestTypeCard({
    required this.icon, required this.color, required this.title,
    required this.description, required this.exampleLabel,
    required this.badgeCount, required this.buttonLabel,
    required this.isDark, required this.onTap,
  });

  @override
  State<_RequestTypeCard> createState() => _RequestTypeCardState();
}

class _RequestTypeCardState extends State<_RequestTypeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final d = widget.isDark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: d ? (const Color(0xFF111D33)) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? c.withOpacity(0.55) : (d ? AppTheme.darkBorder : AppTheme.lightBorder),
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: c.withOpacity(0.18), blurRadius: 20, offset: const Offset(0, 8))]
              : [BoxShadow(color: Colors.black.withOpacity(d ? 0.12 : 0.04), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + badge row ─────────────────────────────────
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.withOpacity(0.25)),
                ),
                child: Icon(widget.icon, color: c, size: 22),
              ),
              const Spacer(),
              if (widget.badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: c.withOpacity(0.3)),
                  ),
                  child: Text('${widget.badgeCount} pending',
                    style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 14),

            // ── Title ─────────────────────────────────────────────
            Text(widget.title,
              style: TextStyle(
                color: d ? AppTheme.darkText : AppTheme.lightText,
                fontSize: 15, fontWeight: FontWeight.w700,
              )),
            const SizedBox(height: 8),

            // ── Description ───────────────────────────────────────
            Text(widget.description,
              style: TextStyle(
                color: d ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                fontSize: 12.5, height: 1.55,
              )),
            const SizedBox(height: 10),

            // ── Example chip ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: c.withOpacity(0.07),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.withOpacity(0.18)),
              ),
              child: Text(widget.exampleLabel,
                style: TextStyle(color: c.withOpacity(0.9), fontSize: 10.5,
                  fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 16),

            // ── Action button ─────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _hovered ? c : c.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.withOpacity(_hovered ? 0 : 0.35)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(widget.icon, size: 14,
                      color: _hovered ? Colors.white : c),
                    const SizedBox(width: 7),
                    Text(widget.buttonLabel,
                      style: TextStyle(
                        color: _hovered ? Colors.white : c,
                        fontSize: 13, fontWeight: FontWeight.w600,
                      )),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 12,
                      color: _hovered ? Colors.white.withOpacity(0.7) : c.withOpacity(0.6)),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Request data model ────────────────────────────────────────────────────────

class _RequestItem {
  final String type;
  final String subType;
  final String status;
  final String date;
  final String kind; // 'ot' | 'correction' | 'adjustment'
  const _RequestItem({required this.type, required this.subType, required this.status, required this.date, required this.kind});

  bool get isOT => kind == 'ot';
  bool get isCorrection => kind == 'correction';
}

// ── Request row widget ────────────────────────────────────────────────────────

class _RequestRow extends StatelessWidget {
  final _RequestItem item;
  final bool isDark;
  const _RequestRow({required this.item, required this.isDark});

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED': return AppTheme.statusPresent;
      case 'REJECTED': return AppTheme.statusAbsent;
      case 'PARTIAL':  return AppTheme.statusLate;
      default:         return AppTheme.statusBreak;
    }
  }

  Color _kindColor(String k) {
    switch (k) {
      case 'ot':         return Colors.purple;
      case 'correction': return Colors.amber;
      default:           return AppTheme.accent;
    }
  }

  IconData _kindIcon(String k) {
    switch (k) {
      case 'ot':         return Icons.more_time_rounded;
      case 'correction': return Icons.edit_note_rounded;
      default:           return Icons.edit_calendar_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(item.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _kindColor(item.kind).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(_kindIcon(item.kind), size: 15, color: _kindColor(item.kind)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.type, style: TextStyle(
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
                fontSize: 13, fontWeight: FontWeight.w600)),
              Text(item.subType, style: TextStyle(
                color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11.5)),
            ],
          ),
        ),
        Text(item.date, style: TextStyle(
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12)),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Text(item.status, style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ── Big quick-action button ───────────────────────────────────────────────────

class _RequestsPreviewCard extends StatelessWidget {
  final List<_RequestItem> requests;
  final bool isDark;
  final String title;
  final String? trailing;

  const _RequestsPreviewCard({
    required this.requests,
    required this.isDark,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(children: [
              Icon(Icons.assignment_outlined, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              const SizedBox(width: 8),
              Text(title,
                style: TextStyle(
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                )),
              const Spacer(),
              if (trailing != null)
                Text(trailing!,
                  style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 12)),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text('No requests found',
                  style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
              ),
            )
          else
            ...requests.map((r) => _RequestRow(item: r, isDark: isDark)).toList(),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  const _QuickActionButton({required this.label, required this.icon, required this.color, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color.withOpacity(0.6)),
        ]),
      ),
    );
  }
}

// ── Monthly stats model ───────────────────────────────────────────────────────

class _MonthlyStat {
  final int presentDays;
  final int lateDays;
  final int onTimeDays;
  final int totalHours;
  final int streak;
  final int missedCheckouts;

  const _MonthlyStat({
    required this.presentDays, required this.lateDays, required this.onTimeDays,
    required this.totalHours, required this.streak, required this.missedCheckouts,
  });

  factory _MonthlyStat.empty() => const _MonthlyStat(
    presentDays: 0, lateDays: 0, onTimeDays: 0,
    totalHours: 0, streak: 0, missedCheckouts: 0,
  );

  factory _MonthlyStat.fromLogs(List<Map<String, dynamic>> logs) {
    final prefix = DateFormat('yyyy-MM').format(DateTime.now());
    final month  = logs.where((l) => '${l['date']}'.startsWith(prefix)).toList();

    int late = 0, onTime = 0, missed = 0, mins = 0;
    for (final l in month) {
      final s = '${l['status']}';
      if (s == 'LATE') late++;
      if (s == 'ON_TIME') onTime++;
      if (s == 'MISSED_CHECKOUT') missed++;
      mins += (l['totalWorkedMinutes'] ?? 0) as int;
    }

    int streak = 0;
    for (final l in logs) {
      final s = '${l['status']}';
      if (s == 'ON_TIME' || s == 'LATE' || s == 'CHECKED_OUT') streak++;
      else break;
    }

    return _MonthlyStat(
      presentDays: month.length,
      lateDays: late,
      onTimeDays: onTime,
      totalHours: mins ~/ 60,
      streak: streak,
      missedCheckouts: missed,
    );
  }
}

// ── Welcome banner with gradient ──────────────────────────────────────────────

class _EmpWelcomeBanner extends StatelessWidget {
  final String name, greeting;
  final TodayAttendanceState att;
  final _MonthlyStat monthly;
  final bool isDark;

  const _EmpWelcomeBanner({
    required this.name, required this.greeting, required this.att,
    required this.monthly, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
            ? [const Color(0xFF0A2520), const Color(0xFF0D1A3A)]
            : [const Color(0xFF00574A), const Color(0xFF1E3A8A)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.2), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, $name!',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text(DateFormat('EEEE, d MMMM yyyy').format(now),
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 14),
                Row(children: [
                  _bannerChip(_statusLabel(att.status), _statusColor(att.status)),
                  const SizedBox(width: 8),
                  if (monthly.streak > 0)
                    _bannerChip('🔥 ${monthly.streak} day streak', AppTheme.statusLate),
                ]),
              ],
            ),
          ),
          // Right side: quick month summary
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bannerStat('${monthly.presentDays}', 'Days Present'),
              const SizedBox(height: 8),
              _bannerStat('${monthly.totalHours}h', 'Hours Worked'),
              const SizedBox(height: 8),
              _bannerStat('${monthly.onTimeDays}', 'On-Time Days'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withOpacity(0.4))),
    child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
  );

  Widget _bannerStat(String val, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.5)),
    ],
  );

  Color _statusColor(String s) {
    switch (s) {
      case 'CHECKED_IN': return AppTheme.statusPresent;
      case 'BREAK_ACTIVE': return AppTheme.statusBreak;
      case 'CHECKED_OUT': return AppTheme.accent2;
      default: return const Color(0xFF94A3B8);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'CHECKED_IN': return '● Active';
      case 'BREAK_ACTIVE': return '☕ On Break';
      case 'CHECKED_OUT': return '✓ Done for Today';
      default: return '○ Not Checked In';
    }
  }
}

// ── Monthly summary row (4 cards) ────────────────────────────────────────────

class _EmployeeDashboardHero extends StatelessWidget {
  final String name;
  final TodayAttendanceState att;
  final bool isDark;
  final WidgetRef ref;

  const _EmployeeDashboardHero({
    required this.name,
    required this.att,
    required this.isDark,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = att.status == 'CHECKED_IN'
        ? AppTheme.statusPresent
        : att.status == 'BREAK_ACTIVE'
            ? AppTheme.statusBreak
            : att.status == 'CHECKED_OUT'
                ? AppTheme.accent2
                : const Color(0xFF94A3B8);
    final statusLabel = att.status == 'CHECKED_IN'
        ? 'On duty'
        : att.status == 'BREAK_ACTIVE'
            ? 'On break'
            : att.status == 'CHECKED_OUT'
                ? 'Completed'
                : 'Not checked in';
    final checkIn = att.checkInTime == null
        ? '--:--'
        : DateFormat('hh:mm a').format(att.checkInTime!.toLocal());

    return LayoutBuilder(builder: (context, constraints) {
      final wide   = constraints.maxWidth >= 900;
      final mobile = constraints.maxWidth < 500;
      final worked = att.totalWorkedMinutes > 0
          ? '${att.totalWorkedMinutes ~/ 60}h ${att.totalWorkedMinutes % 60}m'
          : '--';

      // ── Mobile hero: compact stacked card ─────────────────────────────────
      if (mobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hi, $name 👋',
                  style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(DateFormat('EEEE, d MMM').format(DateTime.now()),
                  style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
              ])),
              _HeroClock(isDark: isDark, compact: true),
            ]),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B273C) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 16, offset: const Offset(0, 8))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Status + check-in time row
                Row(children: [
                  AppTheme.statusBadge(statusLabel, statusColor),
                  const Spacer(),
                  if (att.checkInTime != null) ...[
                    Icon(Icons.login_rounded, size: 13, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    const SizedBox(width: 4),
                    Text(checkIn,
                      style: TextStyle(color: AppTheme.accent, fontSize: 13.5, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  ],
                ]),
                const SizedBox(height: 10),
                // Status badges row
                Wrap(spacing: 8, runSpacing: 6, children: [
                  AppTheme.statusBadge('Shift 09:00 – 18:00', AppTheme.accent),
                  AppTheme.statusBadge('Worked: $worked', const Color(0xFF94A3B8)),
                ]),
                const SizedBox(height: 16),
                // Full-width action buttons
                ..._actions(filled: true, fullWidth: true),
              ]),
            ),
          ],
        );
      }

      // ── Desktop/tablet hero (unchanged) ───────────────────────────────────
      final clockPanel = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroClock(isDark: isDark),
          const SizedBox(height: 8),
          Text(DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 14)),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: [
            AppTheme.statusBadge(statusLabel, statusColor),
            AppTheme.statusBadge('Shift: 09:00 - 18:00', AppTheme.accent),
            AppTheme.statusBadge('Worked: $worked', const Color(0xFF94A3B8)),
          ]),
        ],
      );

      final actionPanel = Column(
        crossAxisAlignment: wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: _actions(filled: true),
      );

      final checkInPanel = Container(
        constraints: const BoxConstraints(minWidth: 170),
        padding: wide ? const EdgeInsets.only(left: 28) : EdgeInsets.zero,
        decoration: wide
            ? BoxDecoration(border: Border(left: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)))
            : null,
        child: Column(
          crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text('CHECKED IN',
              style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(checkIn,
              style: TextStyle(
                color: att.checkInTime == null ? (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted) : AppTheme.accent,
                fontSize: 26, fontWeight: FontWeight.w800, fontFamily: 'monospace',
              )),
          ],
        ),
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Good morning, $name',
            style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text('${DateFormat('EEEE, d MMMM yyyy').format(DateTime.now())} - Office Network: Connected',
            style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 14.5)),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(wide ? 32 : 22),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1B273C) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.05), blurRadius: 22, offset: const Offset(0, 12))],
            ),
            child: wide
                ? Row(children: [
                    Expanded(child: clockPanel),
                    const SizedBox(width: 28), actionPanel,
                    const SizedBox(width: 28), checkInPanel,
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    clockPanel,
                    const SizedBox(height: 22), actionPanel,
                    const SizedBox(height: 22), checkInPanel,
                  ]),
          ),
        ],
      );
    });
  }

  List<Widget> _actions({bool filled = false, bool fullWidth = false}) {
    if (att.isLoading) {
      return [const SizedBox(width: 120, child: LinearProgressIndicator())];
    }
    if (att.status == 'NOT_CHECKED_IN') {
      return [_AttBtn('Check In', AppTheme.statusLate, Icons.login_rounded,
          () => ref.read(attendanceStateProvider.notifier).checkIn(), filled: filled, fullWidth: fullWidth)];
    }
    if (att.status == 'CHECKED_IN') {
      return [
        _AttBtn('Check Out', AppTheme.statusAbsent, Icons.logout_rounded,
            () => ref.read(attendanceStateProvider.notifier).checkOut(), filled: filled, fullWidth: fullWidth),
        SizedBox(height: fullWidth ? 8 : 10),
        _AttBtn('Start Break', AppTheme.statusBreak, Icons.free_breakfast_rounded,
            () => ref.read(attendanceStateProvider.notifier).startBreak(), filled: filled, fullWidth: fullWidth),
      ];
    }
    if (att.status == 'BREAK_ACTIVE') {
      return [_AttBtn('End Break', AppTheme.statusPresent, Icons.check_circle_outline_rounded,
          () => ref.read(attendanceStateProvider.notifier).endBreak(), filled: filled, fullWidth: fullWidth)];
    }
    return [AppTheme.statusBadge('Workday complete', AppTheme.statusPresent, fontSize: 13)];
  }
}

class _EmpMonthlyRow extends StatelessWidget {
  final _MonthlyStat monthly;
  final bool isDark;
  const _EmpMonthlyRow({required this.monthly, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _EmpStatCard(value: '${monthly.totalHours}h', label: 'This Month', sub: 'hours worked', color: AppTheme.accent, icon: Icons.alarm_rounded, isDark: isDark),
      _EmpStatCard(value: '${monthly.presentDays}', label: 'Days Present', sub: DateFormat('MMMM').format(DateTime.now()), color: AppTheme.statusBreak, icon: Icons.calendar_month_rounded, isDark: isDark),
      _EmpStatCard(value: '${monthly.lateDays}', label: 'Late Arrivals', sub: monthly.lateDays == 0 ? 'on schedule' : '${monthly.lateDays} this month', color: monthly.lateDays > 3 ? AppTheme.statusAbsent : AppTheme.statusLate, icon: Icons.flash_on_rounded, isDark: isDark),
      _EmpStatCard(value: '${monthly.onTimeDays}', label: 'On Time', sub: '${monthly.missedCheckouts} missed checkout', color: AppTheme.accent2, icon: Icons.assignment_turned_in_rounded, isDark: isDark),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Always 2 columns on mobile, 4 on wide desktop
      final columns = constraints.maxWidth >= 980 ? 4 : 2;
      const gap = 14.0;
      final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
      final isMobile = constraints.maxWidth < 600;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: cards
            .map((card) => SizedBox(width: width, child: _EmpStatCardWrap(compact: isMobile, child: card)))
            .toList(),
      );
    });
  }
}

// Wraps stat card to clamp height on mobile
class _EmpStatCardWrap extends StatelessWidget {
  final bool compact;
  final Widget child;
  const _EmpStatCardWrap({required this.compact, required this.child});
  @override
  Widget build(BuildContext context) => compact
      ? SizedBox(height: 120, child: child)
      : SizedBox(height: 200, child: child);
}

class _EmpStatCard extends StatelessWidget {
  final String value, label, sub;
  final Color color;
  final IconData icon;
  final bool isDark;
  const _EmpStatCard({required this.value, required this.label, required this.sub, required this.color, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final compact = box.maxHeight < 160;
      return Container(
        padding: EdgeInsets.all(compact ? 12 : 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B273C) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: compact
            ? Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(value, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                )),
                Container(width: 3, height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, color.withOpacity(0.1)]),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const Spacer(),
                    Container(width: 4, height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color, color.withOpacity(0.1)]),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(value, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const SizedBox(height: 3),
                  Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(sub, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ],
              ),
      );
    });
  }
}

// ── Streak card ───────────────────────────────────────────────────────────────

class _EmpStreakCard extends StatelessWidget {
  final int streak;
  final bool isDark;
  const _EmpStreakCard({required this.streak, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: streak >= 5
            ? [const Color(0xFF92400E), const Color(0xFF78350F)]
            : [isDark ? AppTheme.darkCard : Colors.white, isDark ? AppTheme.darkCard : Colors.white],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: streak >= 5 ? AppTheme.statusLate.withOpacity(0.4) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Row(children: [
        Text(streak > 0 ? '🔥' : '💤', style: const TextStyle(fontSize: 32)),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$streak day${streak == 1 ? '' : 's'}',
              style: TextStyle(
                color: streak >= 5 ? Colors.white : (isDark ? AppTheme.darkText : AppTheme.lightText),
                fontSize: 22, fontWeight: FontWeight.w700,
              )),
            Text('attendance streak',
              style: TextStyle(
                color: streak >= 5 ? Colors.white.withOpacity(0.7) : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                fontSize: 12,
              )),
          ],
        ),
      ]),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String greeting;
  final bool isDark;
  const _PageHeader({required this.greeting, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(DateFormat('EEEE, d MMMM yyyy').format(now),
          style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13.5),
        ),
      ],
    );
  }
}

// ── Compact check-in bar (replaces hero on dashboard) ────────────────────────

class _CompactCheckinBar extends StatelessWidget {
  final TodayAttendanceState att;
  final bool isDark;
  final WidgetRef ref;
  const _CompactCheckinBar({required this.att, required this.isDark, required this.ref});

  @override
  Widget build(BuildContext context) {
    final statusColor = att.status == 'CHECKED_IN' ? AppTheme.statusPresent
        : att.status == 'BREAK_ACTIVE' ? AppTheme.statusBreak
        : att.status == 'CHECKED_OUT' ? AppTheme.accent2
        : AppTheme.darkTextMuted;
    final statusLabel = att.status == 'CHECKED_IN' ? '● Checked In'
        : att.status == 'BREAK_ACTIVE' ? '☕ On Break'
        : att.status == 'CHECKED_OUT' ? '✓ Workday Complete'
        : '○ Not Checked In';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.fingerprint_rounded, color: statusColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Today's Status",
            style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11)),
          Text(statusLabel,
            style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600)),
        ])),
        if (att.isLoading) const SizedBox(width: 80, child: LinearProgressIndicator())
        else if (att.status == 'NOT_CHECKED_IN')
          _AttBtn('Check In', AppTheme.statusLate, Icons.login_rounded,
            () => ref.read(attendanceStateProvider.notifier).checkIn())
        else if (att.status == 'CHECKED_IN') ...[
          _AttBtn('Start Break', AppTheme.statusBreak, Icons.free_breakfast_rounded,
            () => ref.read(attendanceStateProvider.notifier).startBreak()),
          const SizedBox(width: 8),
          _AttBtn('Check Out', AppTheme.statusAbsent, Icons.logout_rounded,
            () => ref.read(attendanceStateProvider.notifier).checkOut()),
        ] else if (att.status == 'BREAK_ACTIVE')
          _AttBtn('End Break', AppTheme.statusPresent, Icons.check_circle_outline_rounded,
            () => ref.read(attendanceStateProvider.notifier).endBreak()),
        if (att.checkInTime != null) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: Text(
              DateFormat('hh:mm a').format(att.checkInTime!.toLocal()),
              style: TextStyle(
                fontFamily: 'monospace', fontSize: 12,
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Checkin hero ──────────────────────────────────────────────────────────────

class _CheckinHero extends StatelessWidget {
  final TodayAttendanceState att;
  final bool isDark;
  final WidgetRef ref;
  const _CheckinHero({required this.att, required this.isDark, required this.ref});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(att.status);
    final statusLabel = _statusLabel(att);
    final checkInStr  = att.checkInTime != null
        ? DateFormat('hh:mm a').format(att.checkInTime!.toLocal())
        : '--:--';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          // Clock + date + status badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroClock(isDark: isDark),
                const SizedBox(height: 4),
                Text(DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                  style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: [
                    AppTheme.statusBadge(statusLabel, statusColor),
                    if (att.checkInTime != null)
                      AppTheme.statusBadge('In: $checkInStr', AppTheme.statusBreak),
                    if (att.status == 'CHECKED_IN' || att.status == 'BREAK_ACTIVE')
                      AppTheme.statusBadge('Shift: 09:00 – 18:00', const Color(0xFF64748B)),
                  ],
                ),
              ],
            ),
          ),

          // Vertical divider
          Container(width: 1, height: 80, margin: const EdgeInsets.symmetric(horizontal: 20),
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Action buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (att.isLoading)
                const SizedBox(width: 120, child: LinearProgressIndicator())
              else ...[
                if (att.status == 'NOT_CHECKED_IN')
                  _AttBtn('Check In', AppTheme.statusLate, Icons.login_rounded,
                    () => ref.read(attendanceStateProvider.notifier).checkIn()),
                if (att.status == 'CHECKED_IN') ...[
                  _AttBtn('Check Out', AppTheme.statusAbsent, Icons.logout_rounded,
                    () => ref.read(attendanceStateProvider.notifier).checkOut()),
                  const SizedBox(height: 8),
                  _AttBtn('Start Break', AppTheme.statusBreak, Icons.free_breakfast_rounded,
                    () => ref.read(attendanceStateProvider.notifier).startBreak()),
                ],
                if (att.status == 'BREAK_ACTIVE')
                  _AttBtn('End Break', AppTheme.statusPresent, Icons.check_circle_outline_rounded,
                    () => ref.read(attendanceStateProvider.notifier).endBreak()),
                if (att.status == 'CHECKED_OUT')
                  AppTheme.statusBadge('Workday Complete', AppTheme.statusPresent, fontSize: 13),
              ],
              if (att.error != null) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.statusAbsent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.statusAbsent.withOpacity(0.2)),
                  ),
                  child: Text(att.error!, style: const TextStyle(color: AppTheme.statusAbsent, fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'CHECKED_IN': return AppTheme.statusPresent;
      case 'BREAK_ACTIVE': return AppTheme.statusBreak;
      case 'CHECKED_OUT': return AppTheme.accent2;
      default: return AppTheme.darkTextSub;
    }
  }

  String _statusLabel(TodayAttendanceState att) {
    switch (att.status) {
      case 'CHECKED_IN': return att.statusLabel != null ? '● ${att.statusLabel}' : '● Checked In';
      case 'BREAK_ACTIVE': return '☕ On Break';
      case 'CHECKED_OUT': return '✓ Completed';
      default: return '○ Not Checked In';
    }
  }
}

class _AttBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool fullWidth;
  const _AttBtn(this.label, this.color, this.icon, this.onTap, {this.filled = false, this.fullWidth = false});

  @override
  Widget build(BuildContext context) {
    final textColor = filled ? const Color(0xFF06141F) : color;
    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: textColor, size: filled ? 19 : 16),
        SizedBox(width: filled ? 10 : 7),
        Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: filled ? 15 : 13.5)),
      ],
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        constraints: (!fullWidth && filled) ? const BoxConstraints(minWidth: 170, minHeight: 52) : null,
        padding: EdgeInsets.symmetric(horizontal: filled ? 20 : 16, vertical: filled ? 14 : 9),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(filled ? 13 : 10),
          border: Border.all(color: filled ? color.withOpacity(0.9) : color.withOpacity(0.25)),
          boxShadow: filled ? [BoxShadow(color: color.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: child,
      ),
    );
  }
}

// ── Big live clock inside the hero ────────────────────────────────────────────

class _HeroClock extends StatefulWidget {
  final bool isDark;
  final bool compact;
  const _HeroClock({required this.isDark, this.compact = false});
  @override
  State<_HeroClock> createState() => _HeroClockState();
}

class _HeroClockState extends State<_HeroClock> {
  late String _t;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _t = _fmt();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _t = _fmt()); });
  }

  @override
  void dispose() { _timer.cancel(); super.dispose(); }

  String _fmt() => DateFormat('hh:mm:ss a').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Text(_t,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: widget.compact ? 18 : 44,
        fontWeight: FontWeight.w700,
        letterSpacing: widget.compact ? -0.5 : -1.5,
        color: widget.isDark ? AppTheme.darkText : AppTheme.lightText,
      ),
    );
  }
}

// ── 4 stat cards ──────────────────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final TodayAttendanceState att;
  final bool isDark;
  const _StatRow({required this.att, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final workedMins = att.totalWorkedMinutes;
    final workedStr = workedMins > 0 ? '${workedMins ~/ 60}h ${workedMins % 60}m' : '--';
    final isCheckedIn = att.status == 'CHECKED_IN' || att.status == 'BREAK_ACTIVE';

    return Row(children: [
      _StatCard(
        label: 'Today\'s Status',
        value: _statusShort(att.status),
        icon: Icons.circle_rounded,
        color: AppTheme.accent,
        isDark: isDark,
        accentLine: true,
      ),
      const SizedBox(width: 12),
      _StatCard(
        label: 'Check-in Time',
        value: att.checkInTime != null ? DateFormat('hh:mm a').format(att.checkInTime!.toLocal()) : '--:--',
        icon: Icons.login_rounded,
        color: AppTheme.accent2,
        isDark: isDark,
        accentLine: true,
      ),
      const SizedBox(width: 12),
      _StatCard(
        label: isCheckedIn ? 'Worked So Far' : 'Total Worked',
        value: workedStr,
        icon: Icons.timer_outlined,
        color: AppTheme.statusLate,
        isDark: isDark,
        accentLine: true,
      ),
      const SizedBox(width: 12),
      _StatCard(
        label: 'Break Status',
        value: att.status == 'BREAK_ACTIVE' ? 'Active' : 'Inactive',
        icon: Icons.free_breakfast_rounded,
        color: AppTheme.statusBreak,
        isDark: isDark,
        accentLine: true,
      ),
    ]);
  }

  String _statusShort(String s) {
    switch (s) {
      case 'CHECKED_IN': return 'Active';
      case 'BREAK_ACTIVE': return 'On Break';
      case 'CHECKED_OUT': return 'Done';
      default: return 'Offline';
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool isDark;
  final bool accentLine;

  const _StatCard({
    required this.label, required this.value, required this.icon,
    required this.color, required this.isDark, this.accentLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(height: 12),
                Text(value,
                  style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12)),
                const SizedBox(height: 10),
              ],
            ),
            // Bottom accent line
            if (accentLine)
              Positioned(
                left: -18, right: -18, bottom: -16,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, Colors.transparent]),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Recent history card ───────────────────────────────────────────────────────

class _RecentHistoryCard extends StatelessWidget {
  final HistoryState history;
  final bool isDark;
  const _RecentHistoryCard({required this.history, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(children: [
              Icon(Icons.history_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              const SizedBox(width: 8),
              Text('Recent Attendance',
                style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/employee/history'),
                child: Text('View All →',
                  style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Rows
          if (history.isLoading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (history.error != null && history.records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Could not load history',
                style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
            )
          else if (history.records.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No attendance records yet',
                style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
            )
          else
            Column(children: [
              if (history.isOfflineCache)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: Colors.orange.withOpacity(0.10),
                  child: const Row(children: [
                    Icon(Icons.cloud_off_rounded, size: 12, color: Colors.orange),
                    SizedBox(width: 6),
                    Text('Showing cached data — offline', style: TextStyle(color: Colors.orange, fontSize: 11)),
                  ]),
                ),
              ...history.records.take(5).cast<Map<String, dynamic>>()
                  .map((log) => _HistoryRow(log: log, isDark: isDark)),
            ]),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> log;
  final bool isDark;
  const _HistoryRow({required this.log, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final status = (log['status'] ?? '') as String;
    final statusColor = AppTheme.statusColor(status);
    final inTime  = _fmtTime(log['checkInTime'] as String?);
    final outTime = _fmtTime(log['checkOutTime'] as String?);
    final worked  = (log['totalWorkedMinutes'] ?? 0) as int;
    final workedStr = worked > 0 ? '${worked ~/ 60}h ${worked % 60}m' : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
        SizedBox(
          width: 90,
          child: Text(log['date'] ?? '', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5)),
        ),
        Expanded(
          child: Text('$inTime → $outTime',
            style: TextStyle(fontFamily: 'monospace', color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 12)),
        ),
        Text(workedStr, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w500, fontSize: 12.5)),
        const SizedBox(width: 10),
        AppTheme.statusBadge(status, statusColor, fontSize: 10.5),
      ]),
    );
  }

  String _fmtTime(String? dt) {
    if (dt == null) return '--:--';
    try { return DateFormat('hh:mm a').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return '--:--'; }
  }
}

// ── Quick actions card ────────────────────────────────────────────────────────

class _QuickActionsCard extends StatelessWidget {
  final bool isDark;
  const _QuickActionsCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(children: [
              Icon(Icons.bolt_rounded, size: 16, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              const SizedBox(width: 8),
              Text('Quick Actions',
                style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontWeight: FontWeight.w600, fontSize: 14)),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _QuickBtn('Submit Overtime Request', AppTheme.accent, Icons.more_time_rounded, () => context.go('/employee/overtime'), isDark),
              const SizedBox(height: 8),
              _QuickBtn('Time Correction', AppTheme.accent2, Icons.edit_calendar_outlined, () => context.go('/employee/adjustments'), isDark),
              const SizedBox(height: 8),
              _QuickBtn('My Attendance History', AppTheme.statusBreak, Icons.history_rounded, () => context.go('/employee/history'), isDark),
              const SizedBox(height: 8),
              _QuickBtn('My Profile', const Color(0xFF64748B), Icons.account_circle_outlined, () => context.go('/employee/profile'), isDark),
            ]),
          ),
        ],
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  const _QuickBtn(this.label, this.color, this.icon, this.onTap, this.isDark);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 13)),
        ]),
      ),
    );
  }
}
class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends ConsumerState<AttendanceHistoryScreen> {
  DateTime? _fromDate;
  DateTime? _toDate;

  String _fmt(String? dtStr) {
    if (dtStr == null) return '--:--';
    try { return DateFormat('hh:mm a').format(DateTime.parse(dtStr).toLocal()); } catch (_) { return '--:--'; }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _applyFilter() {
    ref.read(historyProvider.notifier).fetchHistory(
      fromDate: _fromDate != null ? _fmtDate(_fromDate!) : null,
      toDate:   _toDate   != null ? _fmtDate(_toDate!)   : null,
    );
  }

  void _clearFilter() {
    setState(() { _fromDate = null; _toDate = null; });
    ref.read(historyProvider.notifier).fetchHistory();
  }

  Future<void> _pickDate(bool isFrom) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final initial = isFrom ? (_fromDate ?? now) : (_toDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.accent,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) _fromDate = picked;
      else        _toDate   = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFilter = _fromDate != null || _toDate != null;

    Widget _dateChip(String label, DateTime? date, bool isFrom) {
      return InkWell(
        onTap: () => _pickDate(isFrom),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: date != null
                ? AppTheme.accent.withOpacity(0.12)
                : (isDark ? AppTheme.darkInput : AppTheme.lightInput),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: date != null
                  ? AppTheme.accent.withOpacity(0.4)
                  : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_rounded, size: 14,
                color: date != null ? AppTheme.accent : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted)),
            const SizedBox(width: 6),
            Text(
              date != null ? _fmtDate(date) : label,
              style: TextStyle(
                fontSize: 13,
                color: date != null ? AppTheme.accent : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final isMobileW = constraints.maxWidth < 600;
        final pad = isMobileW ? 14.0 : 24.0;

        return Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: isMobileW
                    ? Text('My Attendance',
                        style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 18, fontWeight: FontWeight.w700))
                    : _EmployeePageTitle(title: 'My Attendance', subtitle: 'Attendance logs and history', icon: Icons.history_rounded, isDark: isDark)),
                IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _applyFilter),
              ]),
              const SizedBox(height: 10),

              // ── Filter row ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                ),
                child: Wrap(
                  spacing: 8, runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dateChip('From', _fromDate, true),
                    Icon(Icons.arrow_forward_rounded, size: 12,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    _dateChip('To', _toDate, false),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _applyFilter,
                      child: const Text('Apply'),
                    ),
                    if (hasFilter)
                      GestureDetector(
                        onTap: _clearFilter,
                        child: Text('Clear', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Records ─────────────────────────────────────────────────────
              Expanded(
                child: Builder(builder: (context) {
                  if (history.isLoading) return const Center(child: CircularProgressIndicator());
                  if (history.error != null && history.records.isEmpty) {
                    return Center(child: Text(history.error!,
                        style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)));
                  }
                  final logs = history.records;
                  return Column(children: [
                    if (history.isOfflineCache)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        color: Colors.orange.withOpacity(0.10),
                        child: const Row(children: [
                          Icon(Icons.cloud_off_rounded, size: 13, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('Offline — showing last cached records',
                              style: TextStyle(color: Colors.orange, fontSize: 12)),
                        ]),
                      ),
                    Expanded(child: Builder(builder: (context) {
                  if (logs.isEmpty) {
                    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.history_toggle_off_rounded, size: 48, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                        const SizedBox(height: 12),
                        Text('No attendance records found', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 14)),
                        if (hasFilter) ...[const SizedBox(height: 6), TextButton(onPressed: _clearFilter, child: const Text('Clear filter'))],
                      ]));
                    }

                    // helper
                    String workedStr(String? ci, String? co, int stored) {
                      int wm = stored;
                      if (wm == 0 && ci != null && co != null) {
                        try { final d = DateTime.parse(co).difference(DateTime.parse(ci)).inMinutes; if (d > 0) wm = d; } catch (_) {}
                      }
                      if (co == null) return '--';
                      return wm > 0 ? '${wm ~/ 60}h ${(wm % 60).toString().padLeft(2,'0')}m' : '0h 00m';
                    }

                    // Mobile: card list
                    if (isMobileW) {
                      return ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final log = logs[i] as Map<String, dynamic>;
                          final status = (log['status'] as String?) ?? '--';
                          final ci = log['checkInTime'] as String?;
                          final co = log['checkOutTime'] as String?;
                          final wm = (log['totalWorkedMinutes'] as num? ?? 0).toInt();
                          final ws = workedStr(ci, co, wm);
                          final sc = AppTheme.statusColor(status);
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            ),
                            child: Row(children: [
                              // Date + shift
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(log['date']?.toString() ?? '--',
                                    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w700, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text(log['shiftName']?.toString() ?? '--',
                                    style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11.5)),
                              ])),
                              // CI → CO
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('${_fmt(ci)} → ${_fmt(co)}',
                                    style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5)),
                                const SizedBox(height: 4),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text(ws, style: TextStyle(color: AppTheme.statusPresent, fontWeight: FontWeight.w700, fontSize: 12.5)),
                                  const SizedBox(width: 8),
                                  AppTheme.statusBadge(status, sc),
                                ]),
                              ]),
                            ]),
                          );
                        },
                      );
                    }

                    // Desktop: DataTable
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: SingleChildScrollView(child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStatePropertyAll(isDark ? AppTheme.darkInput : AppTheme.lightInput),
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('Check In')),
                            DataColumn(label: Text('Check Out')),
                            DataColumn(label: Text('Worked Hours')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Shift')),
                          ],
                          rows: logs.map((raw) {
                            final log = raw as Map<String, dynamic>;
                            final status = (log['status'] as String?) ?? '--';
                            final ci = log['checkInTime'] as String?;
                            final co = log['checkOutTime'] as String?;
                            final wm = (log['totalWorkedMinutes'] as num? ?? 0).toInt();
                            final ws = workedStr(ci, co, wm);
                            return DataRow(cells: [
                              DataCell(Text(log['date']?.toString() ?? '--')),
                              DataCell(Text(_fmt(ci))),
                              DataCell(Text(_fmt(co))),
                              DataCell(Text(ws,
                                  style: TextStyle(
                                      color: wm > 0 ? AppTheme.statusPresent : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                                      fontWeight: wm > 0 ? FontWeight.w600 : FontWeight.normal))),
                              DataCell(AppTheme.statusBadge(status, AppTheme.statusColor(status))),
                              DataCell(Text(log['shiftName']?.toString() ?? '--')),
                            ]);
                          }).toList(),
                        ),
                      )),
                    );
                    })),      // end inner Builder + Expanded
                  ]);         // end Column children + return statement
                }),           // end outer Builder
              ),              // end outer Expanded
            ],
          ),
        );
      }),
    );
  }
}

/// 4. Employee Profile & Shift Information Screen
class EmployeeProfileScreen extends ConsumerWidget {
  const EmployeeProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Employee Profile & Shift'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(myProfileProvider.notifier).fetchProfile(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (emp) {
          if (emp == null) {
            return const Center(child: Text('Profile details not found.'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(36),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Details Card
                Expanded(
                  flex: 3,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                child: Icon(Icons.person, size: 40, color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${emp.firstName} ${emp.lastName}',
                                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(emp.designation, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 40),
                          _buildProfileRow('Employee Code', emp.employeeCode, theme),
                          _buildProfileRow('Email Address', ref.read(authProvider).user?.email ?? '--', theme),
                          _buildProfileRow('Phone', emp.phone.isNotEmpty ? emp.phone : 'Not Registered', theme),
                          _buildProfileRow('Department', emp.departmentName ?? 'Not Assigned', theme),
                          _buildProfileRow('Joining Date', emp.joiningDate, theme),
                          _buildProfileRow('Employment Status', emp.employmentStatus, theme),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                // Shift Information Card
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule, color: theme.colorScheme.secondary, size: 28),
                              const SizedBox(width: 12),
                              Text('Assigned Shift Info', style: theme.textTheme.titleLarge),
                            ],
                          ),
                          const Divider(height: 40),
                          _buildProfileRow('Shift Name', emp.shiftName ?? 'No Shift Assigned', theme),
                          if (emp.shiftName != null) ...[
                            _buildProfileRow('Shift Schedule', 'Standard Intranet Hours', theme),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondary.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.1)),
                              ),
                              child: const Text(
                                'Shift evaluations verify presence deadlines automatically. Late clocks are recorded with a 10-minute grace period.',
                                style: TextStyle(fontSize: 13, height: 1.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileRow(String label, String val, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// 5. Admin Employee List & Creation Screen
class AdminEmployeeScreen extends ConsumerWidget {
  const AdminEmployeeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emps = ref.watch(employeesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin: Employees Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(employeesProvider.notifier).fetchEmployees(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: emps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (list) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Registered Employees (${list.length})', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Employee'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Code')),
                      DataColumn(label: Text('Full Name')),
                      DataColumn(label: Text('Designation')),
                      DataColumn(label: Text('Department')),
                      DataColumn(label: Text('Assigned Shift')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: list.map((emp) {
                      return DataRow(cells: [
                        DataCell(Text(emp.employeeCode)),
                        DataCell(Text('${emp.firstName} ${emp.lastName}')),
                        DataCell(Text(emp.designation)),
                        DataCell(Text(emp.departmentName ?? 'Not Assigned')),
                        DataCell(Text(emp.shiftName ?? 'Not Assigned')),
                        DataCell(
                          Chip(
                            label: Text(emp.employmentStatus),
                            backgroundColor: emp.employmentStatus == 'ACTIVE' ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController();
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final desCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Employee Profile'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Employee Code (e.g. EMP005)'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: firstCtrl,
                  decoration: const InputDecoration(labelText: 'First Name'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: lastCtrl,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: desCtrl,
                  decoration: const InputDecoration(labelText: 'Designation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final ok = await ref.read(employeesProvider.notifier).createEmployee({
                    'employeeCode': codeCtrl.text.trim(),
                    'firstName': firstCtrl.text.trim(),
                    'lastName': lastCtrl.text.trim(),
                    'designation': desCtrl.text.trim(),
                    'joiningDate': DateTime.now().toIso8601String().split('T')[0],
                    'employmentStatus': 'ACTIVE',
                  });
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Save Profile'),
            ),
          ],
        );
      },
    );
  }
}

/// 6. Admin Shifts List & Creation Screen
class AdminShiftScreen extends ConsumerWidget {
  const AdminShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shifts = ref.watch(shiftsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin: Shifts Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(shiftsProvider.notifier).fetchShifts(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: shifts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (list) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Upstream Shifts Schedules (${list.length})', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Create Shift'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Shift Name')),
                      DataColumn(label: Text('Start Time')),
                      DataColumn(label: Text('End Time')),
                      DataColumn(label: Text('Grace Period')),
                      DataColumn(label: Text('Night Shift')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: list.map((s) {
                      return DataRow(cells: [
                        DataCell(Text(s.shiftName)),
                        DataCell(Text(s.shiftStart)),
                        DataCell(Text(s.shiftEnd)),
                        DataCell(Text('${s.graceMinutes} minutes')),
                        DataCell(Icon(s.nightShiftEnabled ? Icons.check_circle : Icons.cancel_outlined, size: 20)),
                        DataCell(
                          Chip(
                            label: Text(s.active ? 'ACTIVE' : 'INACTIVE'),
                            backgroundColor: s.active ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final graceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add New Shift Schedule'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Shift Name (e.g. Morning Shift)'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: startCtrl,
                  decoration: const InputDecoration(labelText: 'Start Time (e.g. 09:00:00)'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: endCtrl,
                  decoration: const InputDecoration(labelText: 'End Time (e.g. 18:00:00)'),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: graceCtrl,
                  decoration: const InputDecoration(labelText: 'Grace period (minutes)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final ok = await ref.read(shiftsProvider.notifier).createShift({
                    'shiftName': nameCtrl.text.trim(),
                    'shiftStart': startCtrl.text.trim(),
                    'shiftEnd': endCtrl.text.trim(),
                    'graceMinutes': graceCtrl.text.isNotEmpty ? int.parse(graceCtrl.text) : 10,
                    'nightShiftEnabled': false,
                    'allowOvertime': true,
                    'active': true,
                  });
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Save Shift'),
            ),
          ],
        );
      },
    );
  }
}

class ForbiddenScreen extends StatelessWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.statusAbsent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.gpp_bad_rounded, size: 40, color: AppTheme.statusAbsent),
              ),
              const SizedBox(height: 22),
              Text('Access Denied',
                style: TextStyle(
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontSize: 22, fontWeight: FontWeight.w700,
                )),
              const SizedBox(height: 10),
              Text(
                '403 Forbidden — You do not have the required role permissions to access this module.',
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () => context.go('/attendance'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: const Text('Return to Dashboard',
                    style: TextStyle(color: Color(0xFF0A1F1A), fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data Manager Screen (czeus only) ─────────────────────────────────────────

class _DataMgrScreen extends ConsumerStatefulWidget {
  const _DataMgrScreen();
  @override
  ConsumerState<_DataMgrScreen> createState() => _DataMgrScreenState();
}

class _DataMgrScreenState extends ConsumerState<_DataMgrScreen> {
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _logs = [];
  bool _loadingEmps = true;
  bool _loadingLogs = false;
  String? _error;

  Map<String, String> get _hdrs => {
    'Authorization': 'Bearer ${ref.read(authProvider).accessToken ?? ''}',
    'Content-Type': 'application/json',
  };

  @override
  void initState() { super.initState(); _fetchEmployees(); }

  Future<void> _fetchEmployees() async {
    try {
      final r = await http.get(Uri.parse('$ServerConfig.apiBase/employees'), headers: _hdrs);
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && b['success'] == true) {
        final raw = b['data'];
        final list = raw is List ? raw : (raw is Map && raw['employees'] is List ? raw['employees'] as List : []);
        setState(() { _employees = list.map((e) => Map<String, dynamic>.from(e as Map)).toList(); _loadingEmps = false; });
      }
    } catch (e) { setState(() { _loadingEmps = false; _error = e.toString(); }); }
  }

  Future<void> _fetchLogs(Map<String, dynamic> emp) async {
    final uid = emp['userId'] ?? emp['user_id'];
    if (uid == null) { setState(() { _logs = []; _selected = emp; }); return; }
    setState(() { _loadingLogs = true; _selected = emp; _error = null; });
    try {
      final r = await http.get(Uri.parse('$ServerConfig.apiBase/attendance/records/$uid'), headers: _hdrs);
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode == 200 && b['success'] == true) {
        setState(() { _logs = (b['data'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList(); _loadingLogs = false; });
      } else { setState(() { _loadingLogs = false; _error = 'Failed to load records'; }); }
    } catch (e) { setState(() { _loadingLogs = false; _error = e.toString(); }); }
  }

  Future<void> _delete(String id) async {
    await http.delete(Uri.parse('$ServerConfig.apiBase/attendance/records/$id'), headers: _hdrs);
    if (_selected != null) _fetchLogs(_selected!);
  }

  Future<void> _edit(Map<String, dynamic> rec) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ciCtrl = TextEditingController(text: rec['check_in_time']?.toString() ?? '');
    final coCtrl = TextEditingController(text: rec['check_out_time']?.toString() ?? '');
    final wmCtrl = TextEditingController(text: '${rec['total_worked_minutes'] ?? 0}');
    String selStatus = rec['status']?.toString() ?? 'ON_TIME';
    bool saving = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        title: Text('Edit Record — ${rec['date']}'),
        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
          _TF('Check-In (YYYY-MM-DD HH:MM:SS)', ciCtrl, isDark),
          const SizedBox(height: 8),
          _TF('Check-Out', coCtrl, isDark),
          const SizedBox(height: 8),
          _TF('Worked Minutes', wmCtrl, isDark, number: true),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selStatus,
            decoration: const InputDecoration(labelText: 'Status', isDense: true),
            items: ['ON_TIME','EARLY','LATE','ABSENT','MISSED_CHECKOUT','PRESENT']
                .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => ss(() => selStatus = v ?? selStatus),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
            onPressed: saving ? null : () async {
              ss(() => saving = true);
              final body = <String, dynamic>{
                'status': selStatus,
                'totalWorkedMinutes': int.tryParse(wmCtrl.text) ?? 0,
                if (ciCtrl.text.trim().isNotEmpty) 'checkInTime': ciCtrl.text.trim(),
                if (coCtrl.text.trim().isNotEmpty) 'checkOutTime': coCtrl.text.trim(),
              };
              final res = await http.put(Uri.parse('$ServerConfig.apiBase/attendance/records/${rec['id']}'), headers: _hdrs, body: jsonEncode(body));
              if (res.statusCode == 200 && ctx.mounted) { Navigator.pop(ctx); _fetchLogs(_selected!); }
              else ss(() => saving = false);
            },
            child: const Text('Save'),
          ),
        ],
      )),
    );
    ciCtrl.dispose(); coCtrl.dispose(); wmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Employee list
        SizedBox(
          width: 230,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Employees', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Expanded(
              child: _loadingEmps
                  ? const Center(child: CircularProgressIndicator())
                  : Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: ListView.builder(
                        itemCount: _employees.length,
                        itemBuilder: (ctx, i) {
                          final e = _employees[i];
                          final name = '${e['firstName'] ?? ''} ${e['lastName'] ?? ''}'.trim();
                          final selected = _selected?['id'] == e['id'];
                          return InkWell(
                            onTap: () => _fetchLogs(e),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              color: selected ? AppTheme.accent.withOpacity(0.12) : null,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: TextStyle(color: selected ? AppTheme.accent : (isDark ? AppTheme.darkText : AppTheme.lightText), fontWeight: FontWeight.w600, fontSize: 13)),
                                Text(e['employeeCode'] as String? ?? '', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ]),
        ),
        const SizedBox(width: 16),
        // Records
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(
              _selected == null ? 'Select an employee' : 'Attendance: ${_selected!['firstName']} ${_selected!['lastName']}',
              style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            if (_selected != null)
              IconButton(icon: const Icon(Icons.refresh_rounded, size: 18), onPressed: () => _fetchLogs(_selected!)),
          ]),
          const SizedBox(height: 10),
          if (_error != null)
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppTheme.brandDanger.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(_error!, style: const TextStyle(color: AppTheme.brandDanger, fontSize: 13))),
          if (_selected != null && ((_selected!['userId'] ?? _selected!['user_id']) == null))
            Padding(padding: const EdgeInsets.all(12), child: Text('No login account linked — cannot load attendance.', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted))),
          if (_loadingLogs)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_logs.isEmpty && _selected != null)
            Expanded(child: Center(child: Text('No attendance records.', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted))))
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: isDark ? AppTheme.darkCard : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                child: SingleChildScrollView(child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Check-In')),
                    DataColumn(label: Text('Check-Out')),
                    DataColumn(label: Text('Worked')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _logs.map((rec) {
                    final wm = (rec['total_worked_minutes'] as num? ?? 0).toInt();
                    final ci = rec['check_in_time'] as String?;
                    final co = rec['check_out_time'] as String?;
                    int displayMins = wm;
                    if (displayMins == 0 && ci != null && co != null) {
                      try { displayMins = DateTime.parse(co).difference(DateTime.parse(ci)).inMinutes.clamp(0, 9999); } catch (_) {}
                    }
                    final wStr = displayMins > 0 ? '${displayMins ~/ 60}h ${displayMins % 60}m' : '--';
                    String fmtT(String? t) {
                      if (t == null) return '--';
                      try { return DateFormat('hh:mm a').format(DateTime.parse(t).toLocal()); } catch (_) { return t; }
                    }
                    return DataRow(cells: [
                      DataCell(Text(rec['date']?.toString() ?? '--')),
                      DataCell(Text(fmtT(ci))),
                      DataCell(Text(fmtT(co))),
                      DataCell(Text(wStr, style: TextStyle(color: displayMins > 0 ? AppTheme.statusPresent : null, fontWeight: displayMins > 0 ? FontWeight.w600 : null))),
                      DataCell(AppTheme.statusBadge(rec['status']?.toString() ?? '--', AppTheme.statusColor(rec['status']?.toString()))),
                      DataCell(Row(children: [
                        IconButton(icon: const Icon(Icons.edit_rounded, size: 16, color: AppTheme.accent), tooltip: 'Edit', onPressed: () => _edit(rec), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.statusAbsent), tooltip: 'Delete', onPressed: () async {
                          final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                            title: const Text('Delete?'), content: Text('Delete record for ${rec['date']}?'),
                            actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAbsent, foregroundColor: Colors.white), onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
                          ));
                          if (ok == true) _delete(rec['id']?.toString() ?? '');
                        }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                      ])),
                    ]);
                  }).toList(),
                )),
              ),
            ),
        ])),
      ]),
    );
  }
}

class _TF extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isDark;
  final bool number;
  const _TF(this.label, this.ctrl, this.isDark, {this.number = false});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13),
    decoration: InputDecoration(labelText: label, isDense: true, filled: true,
      fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class ModulePlaceholderScreen extends StatelessWidget {
  final String moduleName;

  const ModulePlaceholderScreen({required this.moduleName, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(36.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.construction_rounded, size: 64, color: theme.colorScheme.secondary.withOpacity(0.8)),
            const SizedBox(height: 24),
            Text(
              moduleName,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Authorized Role Cleared. Business logic for this component will follow in future phases.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page title widget used by attendance history and other screens ─────────────
class _EmployeePageTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDark;

  const _EmployeePageTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: AppTheme.accent, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4,
          )),
        const SizedBox(height: 3),
        Text(subtitle,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
            fontSize: 13.5,
          )),
      ])),
    ]);
  }
}
