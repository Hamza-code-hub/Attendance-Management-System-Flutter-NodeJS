import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

// ============================================================================
// USER ACCOUNTS SCREEN
// ============================================================================

class UserAccountsScreen extends ConsumerStatefulWidget {
  const UserAccountsScreen({super.key});

  @override
  ConsumerState<UserAccountsScreen> createState() => _UserAccountsScreenState();
}

class _UserAccountsScreenState extends ConsumerState<UserAccountsScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${ref.read(authProvider).accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  int? get _currentUserId => ref.read(authProvider).user?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        Uri.parse('$_base/admin/users'),
        headers: _headers,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        final raw = body['data'];
        final List list = raw is List
            ? raw
            : (raw is Map && raw['users'] is List)
                ? raw['users'] as List
                : [];
        setState(() {
          _users = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
        _applyFilter();
      } else {
        setState(() {
          _loading = false;
          _error = (body['error'] as Map?)?['message'] as String? ?? 'Failed to load user accounts';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_users);
      } else {
        _filtered = _users.where((u) {
          final username = (u['username'] as String? ?? '').toLowerCase();
          final email = (u['email'] as String? ?? '').toLowerCase();
          final roles = (u['roles'] as String? ?? '').toLowerCase();
          return username.contains(q) || email.contains(q) || roles.contains(q);
        }).toList();
      }
    });
  }

  // ── Snackbar helpers ───────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.brandSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.brandDanger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Dialog: Create User ────────────────────────────────────────────────────

  Future<void> _showCreateDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePass = true;
    bool obscureConfirm = true;
    final List<String> allRoles = ['Employee', 'Manager', 'HR', 'Admin'];
    final Set<String> selectedRoles = {'Employee'};
    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dialog title
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            'Create User Account',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkText : AppTheme.lightText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Set up a new standalone account',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                              fontSize: 12,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // Error banner
                    if (dialogError != null) ...[
                      _DialogErrorBanner(message: dialogError!),
                      const SizedBox(height: 14),
                    ],

                    // Username
                    _FieldLabel('Username *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: usernameCtrl,
                      autofocus: true,
                      decoration: _inputDecor('e.g. john_doe', isDark),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Username is required';
                        if (v.trim().length < 3) return 'Minimum 3 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Email
                    _FieldLabel('Email *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecor('e.g. john@office.local', isDark),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Password
                    _FieldLabel('Password *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: obscurePass,
                      decoration: _inputDecor('Min 6 characters', isDark).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                          onPressed: () => setS(() => obscurePass = !obscurePass),
                        ),
                      ),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 6) return 'Minimum 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Confirm password
                    _FieldLabel('Confirm Password *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: obscureConfirm,
                      decoration: _inputDecor('Re-enter password', isDark).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                          onPressed: () => setS(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm your password';
                        if (v != passwordCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Roles chip selector
                    _FieldLabel('Roles *', isDark: isDark),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: allRoles.map((role) {
                        final isSelected = selectedRoles.contains(role);
                        final roleColor = _roleColor(role);
                        return GestureDetector(
                          onTap: () => setS(() {
                            if (isSelected) {
                              selectedRoles.remove(role);
                            } else {
                              selectedRoles.add(role);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? roleColor.withOpacity(0.15) : (isDark ? AppTheme.darkInput : AppTheme.lightInput),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? roleColor.withOpacity(0.5) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (isSelected) ...[
                                Icon(Icons.check_rounded, size: 13, color: roleColor),
                                const SizedBox(width: 5),
                              ],
                              Text(
                                role,
                                style: TextStyle(
                                  color: isSelected ? roleColor : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedRoles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Select at least one role',
                          style: const TextStyle(color: AppTheme.brandDanger, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Info note
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accent.withOpacity(0.18)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Creates a standalone account not linked to an employee profile. To create employee accounts, use Employee Management.',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 22),

                    // Action buttons
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _GradientButton(
                        label: 'Create Account',
                        icon: Icons.person_add_rounded,
                        loading: saving,
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          if (selectedRoles.isEmpty) return;
                          setS(() { saving = true; dialogError = null; });
                          try {
                            final res = await http.post(
                              Uri.parse('$_base/admin/users'),
                              headers: _headers,
                              body: jsonEncode({
                                'username': usernameCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                                'password': passwordCtrl.text,
                                'roles': selectedRoles.toList(),
                              }),
                            );
                            final rb = jsonDecode(res.body) as Map<String, dynamic>;
                            if ((res.statusCode == 200 || res.statusCode == 201) && rb['success'] == true) {
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } else {
                              setS(() {
                                saving = false;
                                dialogError = (rb['error'] as Map?)?['message'] as String? ?? 'Failed to create user account';
                              });
                            }
                          } catch (e) {
                            setS(() { saving = false; dialogError = e.toString(); });
                          }
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    usernameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();
    _load();
  }

  // ── Dialog: Edit User ──────────────────────────────────────────────────────

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    final usernameCtrl = TextEditingController(text: user['username'] as String? ?? '');
    final emailCtrl = TextEditingController(text: user['email'] as String? ?? '');
    String selectedStatus = (user['status'] as String? ?? 'ACTIVE');
    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.edit_rounded, color: AppTheme.accent, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            'Edit User Account',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkText : AppTheme.lightText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            user['username'] as String? ?? '',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                              fontSize: 12,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    if (dialogError != null) ...[
                      _DialogErrorBanner(message: dialogError!),
                      const SizedBox(height: 14),
                    ],

                    // Username
                    _FieldLabel('Username *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: usernameCtrl,
                      autofocus: true,
                      decoration: _inputDecor('Username', isDark),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Username is required';
                        if (v.trim().length < 3) return 'Minimum 3 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Email
                    _FieldLabel('Email *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _inputDecor('Email address', isDark),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Status
                    _FieldLabel('Status', isDark: isDark),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      dropdownColor: isDark ? AppTheme.darkCard2 : Colors.white,
                      decoration: _inputDecor(null, isDark),
                      style: _inputStyle(isDark),
                      items: ['ACTIVE', 'SUSPENDED'].map((s) => DropdownMenuItem(
                        value: s,
                        child: Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: s == 'ACTIVE' ? AppTheme.brandSuccess : AppTheme.brandDanger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(s),
                        ]),
                      )).toList(),
                      onChanged: (v) => setS(() => selectedStatus = v ?? 'ACTIVE'),
                    ),
                    const SizedBox(height: 22),

                    // Actions
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _GradientButton(
                        label: 'Save Changes',
                        icon: Icons.save_rounded,
                        loading: saving,
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          setS(() { saving = true; dialogError = null; });
                          try {
                            final res = await http.put(
                              Uri.parse('$_base/admin/users/${user['id']}'),
                              headers: _headers,
                              body: jsonEncode({
                                'username': usernameCtrl.text.trim(),
                                'email': emailCtrl.text.trim(),
                                'status': selectedStatus,
                              }),
                            );
                            final rb = jsonDecode(res.body) as Map<String, dynamic>;
                            if (res.statusCode == 200 && rb['success'] == true) {
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } else {
                              setS(() {
                                saving = false;
                                dialogError = (rb['error'] as Map?)?['message'] as String? ?? 'Failed to update user';
                              });
                            }
                          } catch (e) {
                            setS(() { saving = false; dialogError = e.toString(); });
                          }
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    usernameCtrl.dispose();
    emailCtrl.dispose();
    _load();
  }

  // ── Dialog: Reset Password ─────────────────────────────────────────────────

  Future<void> _showResetPasswordDialog(Map<String, dynamic> user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePass = true;
    bool obscureConfirm = true;
    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.brandWarning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.key_rounded, color: AppTheme.brandWarning, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            'Reset Password',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkText : AppTheme.lightText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Resetting password for: ${user['username'] ?? ''}',
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                              fontSize: 12,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    if (dialogError != null) ...[
                      _DialogErrorBanner(message: dialogError!),
                      const SizedBox(height: 14),
                    ],

                    // New password
                    _FieldLabel('New Password *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: obscurePass,
                      autofocus: true,
                      decoration: _inputDecor('Min 6 characters', isDark).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                          onPressed: () => setS(() => obscurePass = !obscurePass),
                        ),
                      ),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 6) return 'Minimum 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Confirm password
                    _FieldLabel('Confirm Password *', isDark: isDark),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: obscureConfirm,
                      decoration: _inputDecor('Re-enter new password', isDark).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          ),
                          onPressed: () => setS(() => obscureConfirm = !obscureConfirm),
                        ),
                      ),
                      style: _inputStyle(isDark),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Please confirm password';
                        if (v != passwordCtrl.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),

                    // Actions
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ActionButton(
                        label: 'Reset Password',
                        icon: Icons.key_rounded,
                        color: AppTheme.brandWarning,
                        loading: saving,
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          setS(() { saving = true; dialogError = null; });
                          try {
                            final res = await http.post(
                              Uri.parse('$_base/admin/users/${user['id']}/reset-password'),
                              headers: _headers,
                              body: jsonEncode({'newPassword': passwordCtrl.text}),
                            );
                            final rb = jsonDecode(res.body) as Map<String, dynamic>;
                            if (res.statusCode == 200 && rb['success'] == true) {
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } else {
                              setS(() {
                                saving = false;
                                dialogError = (rb['error'] as Map?)?['message'] as String? ?? 'Failed to reset password';
                              });
                            }
                          } catch (e) {
                            setS(() { saving = false; dialogError = e.toString(); });
                          }
                        },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    passwordCtrl.dispose();
    confirmCtrl.dispose();
    _load();
  }

  // ── Dialog: Manage Roles ───────────────────────────────────────────────────

  Future<void> _showManageRolesDialog(Map<String, dynamic> user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Hardcoded fallback roles list
    final List<Map<String, dynamic>> allRoles = [
      {'id': 1, 'role_name': 'Admin'},
      {'id': 2, 'role_name': 'HR'},
      {'id': 3, 'role_name': 'Manager'},
      {'id': 4, 'role_name': 'Employee'},
    ];

    // Parse currently assigned roles
    final currentRolesRaw = (user['roles'] as String? ?? '');
    final currentRoleNames = currentRolesRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    // Try to fetch roles from backend if employee is linked
    List<Map<String, dynamic>> displayRoles = List.from(allRoles);
    if (user['employee_id'] != null) {
      try {
        final res = await http.get(
          Uri.parse('$_base/employees/${user['employee_id']}/roles'),
          headers: _headers,
        );
        if (res.statusCode == 200) {
          final rb = jsonDecode(res.body) as Map<String, dynamic>;
          if (rb['success'] == true) {
            final raw = rb['data'];
            final List list = raw is List
                ? raw
                : (raw is Map && raw['roles'] is List)
                    ? raw['roles'] as List
                    : allRoles;
            if (list.isNotEmpty) {
              displayRoles = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
          }
        }
      } catch (_) {
        // Use hardcoded fallback
      }
    }

    final Set<int> selectedIds = {};
    for (final role in displayRoles) {
      final name = role['role_name'] as String? ?? '';
      if (currentRoleNames.contains(name)) {
        selectedIds.add(role['id'] as int);
      }
    }

    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.brandInfo.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.shield_rounded, color: AppTheme.brandInfo, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          'Manage Roles',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkText : AppTheme.lightText,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          user['username'] as String? ?? '',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                            fontSize: 12,
                          ),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  if (dialogError != null) ...[
                    _DialogErrorBanner(message: dialogError!),
                    const SizedBox(height: 14),
                  ],

                  Text(
                    'Select roles to assign:',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role checkboxes
                  ...displayRoles.map((role) {
                    final id = role['id'] as int;
                    final name = role['role_name'] as String? ?? '';
                    final isChecked = selectedIds.contains(id);
                    final roleColor = _roleColor(name);
                    return GestureDetector(
                      onTap: () => setS(() {
                        if (isChecked) {
                          selectedIds.remove(id);
                        } else {
                          selectedIds.add(id);
                        }
                      }),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? roleColor.withOpacity(0.08)
                              : (isDark ? AppTheme.darkInput : AppTheme.lightInput),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isChecked
                                ? roleColor.withOpacity(0.4)
                                : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            width: isChecked ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: isChecked ? roleColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isChecked ? roleColor : (isDark ? AppTheme.darkBorderStrong : AppTheme.lightBorderStrong),
                                width: 1.5,
                              ),
                            ),
                            child: isChecked
                                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: roleColor),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: TextStyle(
                              color: isChecked ? roleColor : (isDark ? AppTheme.darkText : AppTheme.lightText),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 22),

                  // Actions
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActionButton(
                      label: 'Save Roles',
                      icon: Icons.shield_rounded,
                      color: AppTheme.brandInfo,
                      loading: saving,
                      onPressed: () async {
                        if (selectedIds.isEmpty) {
                          setS(() => dialogError = 'Select at least one role');
                          return;
                        }
                        setS(() { saving = true; dialogError = null; });
                        try {
                          final res = await http.put(
                            Uri.parse('$_base/admin/users/${user['id']}/roles'),
                            headers: _headers,
                            body: jsonEncode({'roleIds': selectedIds.toList()}),
                          );
                          final rb = jsonDecode(res.body) as Map<String, dynamic>;
                          if (res.statusCode == 200 && rb['success'] == true) {
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setS(() {
                              saving = false;
                              dialogError = (rb['error'] as Map?)?['message'] as String? ?? 'Failed to update roles';
                            });
                          }
                        } catch (e) {
                          setS(() { saving = false; dialogError = e.toString(); });
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    _load();
  }

  // ── Dialog: Delete Confirmation ────────────────────────────────────────────

  Future<void> _confirmDelete(Map<String, dynamic> user) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        title: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.brandDanger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppTheme.brandDanger, size: 17),
          ),
          const SizedBox(width: 10),
          Text(
            'Delete User Account',
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
        content: RichText(
          text: TextSpan(
            style: TextStyle(
              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              fontSize: 14,
            ),
            children: [
              const TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                text: '"${user['username'] ?? 'this user'}"',
                style: TextStyle(
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const TextSpan(text: '? This action cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brandDanger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final res = await http.delete(
        Uri.parse('$_base/admin/users/${user['id']}'),
        headers: _headers,
      );
      final rb = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && rb['success'] == true) {
        _showSuccess('User account deleted successfully');
        _load();
      } else {
        _showError((rb['error'] as Map?)?['message'] as String? ?? 'Failed to delete user');
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  // ── Shared input helpers ───────────────────────────────────────────────────

  InputDecoration _inputDecor(String? hint, bool isDark) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: AppTheme.brandDanger),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        hintStyle: TextStyle(
          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          fontSize: 14,
        ),
      );

  TextStyle _inputStyle(bool isDark) => TextStyle(
        color: isDark ? AppTheme.darkText : AppTheme.lightText,
        fontSize: 14,
      );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final displayList = _searchCtrl.text.isNotEmpty ? _filtered : _users;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon + title
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Accounts',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _loading
                          ? 'Loading...'
                          : '${_users.length} total account${_users.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),

              // Search field
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search users…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 17),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(9)),
                      borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    hintStyle: TextStyle(
                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                      fontSize: 13,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 15),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
                          )
                        : null,
                  ),
                  style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Refresh
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: _loading ? null : _load,
              ),
              const SizedBox(width: 10),

              // Create button
              GestureDetector(
                onTap: _showCreateDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_add_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 7),
                      Text(
                        'Create User Account',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Error banner ─────────────────────────────────────────────────
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.brandDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppTheme.brandDanger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!, style: const TextStyle(color: AppTheme.brandDanger, fontSize: 13)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 15, color: AppTheme.brandDanger),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

          // ── Table card ───────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column headers
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      border: Border(
                        bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                    ),
                    child: Row(children: [
                      _ColHeader('#', flex: 1, isDark: isDark),
                      _ColHeader('USERNAME', flex: 4, isDark: isDark),
                      _ColHeader('EMAIL', flex: 4, isDark: isDark),
                      _ColHeader('ROLES', flex: 4, isDark: isDark),
                      _ColHeader('LINKED EMPLOYEE', flex: 4, isDark: isDark),
                      _ColHeader('STATUS', flex: 2, isDark: isDark),
                      _ColHeader('LAST LOGIN', flex: 3, isDark: isDark),
                      _ColHeader('ACTIONS', flex: 3, isDark: isDark, center: true),
                    ]),
                  ),

                  // Body
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : displayList.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.manage_accounts_rounded,
                                      size: 44,
                                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchCtrl.text.isNotEmpty
                                          ? 'No users match your search'
                                          : 'No user accounts found',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (_searchCtrl.text.isEmpty) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        icon: const Icon(Icons.person_add_rounded, size: 15),
                                        label: const Text('Create first account'),
                                        onPressed: _showCreateDialog,
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: displayList.length,
                                itemBuilder: (context, index) {
                                  final user = displayList[index];
                                  return _UserRow(
                                    user: user,
                                    rowNumber: index + 1,
                                    isDark: isDark,
                                    isEven: index.isEven,
                                    isCurrentUser: user['id'] == _currentUserId,
                                    onEdit: () => _showEditDialog(user),
                                    onResetPassword: () => _showResetPasswordDialog(user),
                                    onManageRoles: () => _showManageRolesDialog(user),
                                    onDelete: () => _confirmDelete(user),
                                  );
                                },
                              ),
                  ),

                  // Footer
                  if (!_loading && _users.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                      ),
                      child: Row(children: [
                        Text(
                          '${displayList.length} of ${_users.length} account${_users.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                            fontSize: 12,
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Column header helper ───────────────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String label;
  final int flex;
  final bool isDark;
  final bool center;

  const _ColHeader(this.label, {required this.flex, required this.isDark, this.center = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: TextStyle(
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── User table row ─────────────────────────────────────────────────────────────

class _UserRow extends StatefulWidget {
  final Map<String, dynamic> user;
  final int rowNumber;
  final bool isDark;
  final bool isEven;
  final bool isCurrentUser;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onManageRoles;
  final VoidCallback onDelete;

  const _UserRow({
    required this.user,
    required this.rowNumber,
    required this.isDark,
    required this.isEven,
    required this.isCurrentUser,
    required this.onEdit,
    required this.onResetPassword,
    required this.onManageRoles,
    required this.onDelete,
  });

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isDark = widget.isDark;

    Color rowBg;
    if (_hovered) {
      rowBg = isDark ? const Color(0xFF1A2B47) : const Color(0xFFEDF2FB);
    } else if (widget.isEven) {
      rowBg = isDark ? AppTheme.darkCard : Colors.white;
    } else {
      rowBg = isDark ? const Color(0xFF0F1A2E) : const Color(0xFFF7FAFF);
    }

    final username = user['username'] as String? ?? '—';
    final email = user['email'] as String? ?? '—';
    final status = user['status'] as String? ?? 'ACTIVE';
    final rolesStr = user['roles'] as String? ?? '';
    final employeeId = user['employee_id'];
    final employeeName = user['employee_name'] as String?;
    final employeeCode = user['employee_code'] as String?;
    final lastLogin = user['last_login'] as String?;

    final roles = rolesStr
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Row(
          children: [
            // Row number
            Expanded(
              flex: 1,
              child: Text(
                '${widget.rowNumber}',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Username + avatar
            Expanded(
              flex: 4,
              child: Row(children: [
                // Avatar circle
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        username,
                        style: TextStyle(
                          color: isDark ? AppTheme.darkText : AppTheme.lightText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.isCurrentUser)
                        Text(
                          'You',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
            ),

            // Email
            Expanded(
              flex: 4,
              child: Text(
                email,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Roles badges
            Expanded(
              flex: 4,
              child: roles.isEmpty
                  ? Text(
                      '—',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        fontSize: 13,
                      ),
                    )
                  : Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: roles.map((r) {
                        final color = _roleColor(r);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: color.withOpacity(0.25)),
                          ),
                          child: Text(
                            r,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),

            // Linked employee
            Expanded(
              flex: 4,
              child: employeeId != null && employeeName != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          employeeName,
                          style: TextStyle(
                            color: isDark ? AppTheme.darkText : AppTheme.lightText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (employeeCode != null)
                          Text(
                            employeeCode,
                            style: TextStyle(
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: Text(
                        'Standalone',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            ),

            // Status badge
            Expanded(
              flex: 2,
              child: _StatusBadge(status: status),
            ),

            // Last login
            Expanded(
              flex: 3,
              child: Text(
                _formatLastLogin(lastLogin),
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 12,
                ),
              ),
            ),

            // Actions
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RowActionBtn(
                    icon: Icons.edit_rounded,
                    color: AppTheme.accent,
                    tooltip: 'Edit User',
                    onTap: widget.onEdit,
                  ),
                  const SizedBox(width: 6),
                  _RowActionBtn(
                    icon: Icons.key_rounded,
                    color: AppTheme.brandWarning,
                    tooltip: 'Reset Password',
                    onTap: widget.onResetPassword,
                  ),
                  const SizedBox(width: 6),
                  _RowActionBtn(
                    icon: Icons.shield_rounded,
                    color: AppTheme.brandInfo,
                    tooltip: 'Manage Roles',
                    onTap: widget.onManageRoles,
                  ),
                  const SizedBox(width: 6),
                  _RowActionBtn(
                    icon: Icons.delete_outline_rounded,
                    color: widget.isCurrentUser ? (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted) : AppTheme.brandDanger,
                    tooltip: widget.isCurrentUser ? 'Cannot delete own account' : 'Delete User',
                    onTap: widget.isCurrentUser ? null : widget.onDelete,
                    disabled: widget.isCurrentUser,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge widget ────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status.toUpperCase() == 'ACTIVE';
    final color = isActive ? AppTheme.brandSuccess : AppTheme.brandDanger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          status,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ]),
    );
  }
}

// ── Row action button ──────────────────────────────────────────────────────────

class _RowActionBtn extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final bool disabled;

  const _RowActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.disabled = false,
  });

  @override
  State<_RowActionBtn> createState() => _RowActionBtnState();
}

class _RowActionBtnState extends State<_RowActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.disabled ? widget.color.withOpacity(0.35) : widget.color;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.disabled ? null : widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered && !widget.disabled
                  ? effectiveColor.withOpacity(0.18)
                  : effectiveColor.withOpacity(0.09),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: effectiveColor.withOpacity(0.22)),
            ),
            child: Icon(widget.icon, color: effectiveColor, size: 14),
          ),
        ),
      ),
    );
  }
}

// ── Gradient primary button ────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: AnimatedOpacity(
        opacity: loading ? 0.7 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: loading
                ? [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Saving...',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ]
                : [
                    Icon(icon, color: Colors.white, size: 15),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── Colored action button (non-gradient) ──────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: AnimatedOpacity(
        opacity: loading ? 0.7 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: loading
                ? [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Saving...',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ]
                : [
                    Icon(icon, color: Colors.white, size: 15),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

// ── Dialog error banner ────────────────────────────────────────────────────────

class _DialogErrorBanner extends StatelessWidget {
  final String message;
  const _DialogErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.brandDanger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: AppTheme.brandDanger, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: AppTheme.brandDanger, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

// ── Field label helper ─────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _FieldLabel(this.label, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ── Role color helper ──────────────────────────────────────────────────────────

Color _roleColor(String roleName) {
  switch (roleName.trim().toLowerCase()) {
    case 'admin':
      return AppTheme.roleAdmin;
    case 'hr':
      return AppTheme.roleHR;
    case 'manager':
      return AppTheme.roleManager;
    case 'employee':
      return AppTheme.roleEmployee;
    default:
      return AppTheme.accent;
  }
}

// ── Date formatter ─────────────────────────────────────────────────────────────

String _formatLastLogin(String? iso) {
  if (iso == null || iso.isEmpty) return 'Never';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return DateFormat('dd MMM hh:mm a').format(dt);
  } catch (_) {
    return 'Invalid';
  }
}
