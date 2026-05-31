import 'dart:convert';
import '../../core/config/server_config.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../authentication/presentation/auth_state.dart';
import '../../core/theme/app_theme.dart';

String get _apiBase => ServerConfig.apiBase;

// ---------------------------------------------------------------------------
// ProfileSheet — CyberZeus AMS profile panel
// ---------------------------------------------------------------------------

class ProfileSheet extends ConsumerStatefulWidget {
  const ProfileSheet({super.key});

  /// Convenience launcher via [showModalBottomSheet].
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const ProfileSheet(),
      ),
    );
  }

  @override
  ConsumerState<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<ProfileSheet> {
  // ── persisted profile fields ──────────────────────────────────────────────
  String _displayName = '';
  String _bio = '';
  Uint8List? _photoBytes;

  // ── tab: 0 = Profile, 1 = Change Password ─────────────────────────────────
  int _tab = 0;

  // ── profile tab ───────────────────────────────────────────────────────────
  bool _editingName = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _bioCtrl;
  bool _saving = false;

  // ── employee info (fetched from /employees/me) ────────────────────────────
  String? _employeeCode;
  String? _department;
  String? _shift;
  bool _loadingEmployee = false;

  // ── change-password tab ───────────────────────────────────────────────────
  late TextEditingController _oldPwdCtrl;
  late TextEditingController _newPwdCtrl;
  late TextEditingController _confirmCtrl;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _pwdError;
  bool _pwdSuccess = false;
  bool _changingPwd = false;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _oldPwdCtrl = TextEditingController();
    _newPwdCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
    _loadPrefs();
    _fetchEmployeeInfo();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _oldPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── data loading ──────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final displayName = prefs.getString('profile_display_name') ?? '';
    final bio = prefs.getString('profile_bio') ?? '';
    final photob64 = prefs.getString('profile_photo_b64');
    Uint8List? photo;
    if (photob64 != null && photob64.isNotEmpty) {
      try {
        photo = base64Decode(photob64);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _displayName = displayName;
        _bio = bio;
        _photoBytes = photo;
        _nameCtrl.text = displayName;
        _bioCtrl.text = bio;
      });
    }
  }

  Future<void> _fetchEmployeeInfo() async {
    final token = ref.read(authProvider).accessToken;
    if (token == null) return;
    setState(() => _loadingEmployee = true);
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/employees/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? body;
        if (mounted) {
          setState(() {
            _employeeCode = data['employeeCode']?.toString();
            _department = data['departmentName']?.toString() ??
                data['department']?['name']?.toString();
            _shift = data['shiftName']?.toString() ??
                data['shift']?['name']?.toString();
          });
        }
      }
    } catch (_) {
      // silently ignore — employee info is non-critical
    } finally {
      if (mounted) setState(() => _loadingEmployee = false);
    }
  }

  // ── photo picker (web only — image_picker not used on mobile) ───────────────

  Future<void> _pickPhoto() async {
    if (!kIsWeb) {
      _showSnack('Photo upload is available on the web portal only.', isError: false);
      return;
    }
    // Web: no image_picker needed — keep this stub for future web-specific implementation
    _showSnack('Photo picker coming soon on web.', isError: false);
  }

  // ── save personal info ────────────────────────────────────────────────────

  Future<void> _savePersonalInfo() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_display_name', _nameCtrl.text.trim());
    await prefs.setString('profile_bio', _bioCtrl.text.trim());
    if (mounted) {
      setState(() {
        _displayName = _nameCtrl.text.trim();
        _bio = _bioCtrl.text.trim();
        _editingName = false;
        _saving = false;
      });
      _showSnack('Profile saved', isError: false);
    }
  }

  // ── change password ───────────────────────────────────────────────────────

  Future<void> _submitChangePassword() async {
    setState(() {
      _pwdError = null;
      _pwdSuccess = false;
    });

    final old = _oldPwdCtrl.text.trim();
    final next = _newPwdCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (old.isEmpty || next.isEmpty || confirm.isEmpty) {
      setState(() => _pwdError = 'All fields are required.');
      return;
    }
    if (next.length < 6) {
      setState(() => _pwdError = 'New password must be at least 6 characters.');
      return;
    }
    if (next != confirm) {
      setState(() => _pwdError = 'New password and confirmation do not match.');
      return;
    }

    setState(() => _changingPwd = true);

    final token = ref.read(authProvider).accessToken;
    if (token == null) {
      setState(() {
        _pwdError = 'You are not authenticated. Please log in again.';
        _changingPwd = false;
      });
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$_apiBase/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'oldPassword': old, 'newPassword': next}),
      ).timeout(const Duration(seconds: 10));

      final body = jsonDecode(res.body);

      if (res.statusCode == 200 && body['success'] == true) {
        if (mounted) {
          setState(() {
            _pwdSuccess = true;
            _changingPwd = false;
          });
          _oldPwdCtrl.clear();
          _newPwdCtrl.clear();
          _confirmCtrl.clear();
        }
      } else {
        final msg = body['error']?['message'] ??
            body['message'] ??
            'Failed to change password.';
        if (mounted) setState(() {
          _pwdError = msg.toString();
          _changingPwd = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _pwdError = 'Could not reach the server. Please try again.';
        _changingPwd = false;
      });
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.brandDanger : AppTheme.brandSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  Color _roleColor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return AppTheme.roleAdmin;
      case 'HR':
        return AppTheme.roleHR;
      case 'MANAGER':
        return AppTheme.roleManager;
      default:
        return AppTheme.roleEmployee;
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final username = user?.username ?? 'User';
    final email = user?.email ?? '';
    final roles = user?.roles ?? [];

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppTheme.darkBorderStrong : AppTheme.lightBorderStrong,
              ),
            ),
          ),
          child: Column(
            children: [
              // ── Drag handle + header ──────────────────────────────────────
              _buildHeader(isDark),

              // ── Scrollable content ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // avatar section
                      _buildAvatarSection(isDark, username, email, roles),
                      const SizedBox(height: 20),

                      // tab selector
                      _buildTabSelector(isDark),
                      const SizedBox(height: 20),

                      // tab body
                      if (_tab == 0)
                        _buildProfileTab(isDark, username)
                      else
                        _buildChangePasswordTab(isDark),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 10),
        // drag pill
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Text(
                'My Profile',
                style: TextStyle(
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                ),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── avatar section ────────────────────────────────────────────────────────

  Widget _buildAvatarSection(
    bool isDark,
    String username,
    String email,
    List<String> roles,
  ) {
    final initial = username.isNotEmpty ? username[0].toUpperCase() : 'U';

    return Column(
      children: [
        const SizedBox(height: 12),
        // avatar with edit overlay
        GestureDetector(
          onTap: _pickPhoto,
          child: Stack(
            children: [
              // circle avatar
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _photoBytes == null ? AppTheme.primaryGradient : null,
                  border: Border.all(
                    color: isDark
                        ? AppTheme.darkBorderStrong
                        : AppTheme.lightBorderStrong,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _photoBytes != null
                      ? Image.memory(
                          _photoBytes!,
                          fit: BoxFit.cover,
                          width: 140,
                          height: 140,
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
              // edit icon badge
              Positioned(
                bottom: 4,
                right: 4,
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      border: Border.all(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // username
        Text(
          _displayName.isNotEmpty ? _displayName : username,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),

        // email
        Text(
          email,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),

        // role chips
        if (roles.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: roles.map((r) {
              final color = _roleColor(r);
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  r,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ── tab selector ──────────────────────────────────────────────────────────

  Widget _buildTabSelector(bool isDark) {
    final labels = ['Profile Info', 'Change Password'];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _tab = i;
                _pwdError = null;
                _pwdSuccess = false;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: active ? AppTheme.primaryGradient : null,
                  color: active ? null : Colors.transparent,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active
                        ? Colors.white
                        : (isDark
                            ? AppTheme.darkTextSub
                            : AppTheme.lightTextSub),
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── profile info tab ──────────────────────────────────────────────────────

  Widget _buildProfileTab(bool isDark, String username) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // display name
        _sectionLabel('Display Name', isDark),
        const SizedBox(height: 6),
        _buildNameField(isDark, username),
        const SizedBox(height: 16),

        // bio
        _sectionLabel('Bio / Note', isDark),
        const SizedBox(height: 6),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 3,
          minLines: 2,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 14,
          ),
          decoration: _inputDecor(
            isDark,
            hint: 'Write a short note about yourself...',
          ),
        ),
        const SizedBox(height: 20),

        // employee info chips
        _buildEmployeeInfoSection(isDark),
        const SizedBox(height: 24),

        // save button
        _buildGradientButton(
          label: _saving ? 'Saving...' : 'Save Personal Info',
          onTap: _saving ? null : _savePersonalInfo,
          isDark: isDark,
          icon: Icons.save_rounded,
        ),
      ],
    );
  }

  Widget _buildNameField(bool isDark, String username) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _nameCtrl,
            enabled: _editingName,
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 14,
            ),
            decoration: _inputDecor(
              isDark,
              hint: username,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _editingName
              ? Row(
                  key: const ValueKey('editing'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBtn(
                      icon: Icons.check_rounded,
                      color: AppTheme.brandSuccess,
                      onTap: () => setState(() => _editingName = false),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 4),
                    _iconBtn(
                      icon: Icons.close_rounded,
                      color: AppTheme.brandDanger,
                      onTap: () {
                        _nameCtrl.text = _displayName;
                        setState(() => _editingName = false);
                      },
                      isDark: isDark,
                    ),
                  ],
                )
              : _iconBtn(
                  key: const ValueKey('view'),
                  icon: Icons.edit_rounded,
                  color: AppTheme.accent,
                  onTap: () => setState(() => _editingName = true),
                  isDark: isDark,
                ),
        ),
      ],
    );
  }

  Widget _buildEmployeeInfoSection(bool isDark) {
    if (_loadingEmployee) {
      return Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
      );
    }

    final hasInfo =
        _employeeCode != null || _department != null || _shift != null;
    if (!hasInfo) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Employee Details', isDark),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_employeeCode != null)
              _infoChip(
                label: 'Code',
                value: _employeeCode!,
                icon: Icons.badge_rounded,
                color: AppTheme.brandInfo,
                isDark: isDark,
              ),
            if (_department != null)
              _infoChip(
                label: 'Dept',
                value: _department!,
                icon: Icons.business_rounded,
                color: AppTheme.accent,
                isDark: isDark,
              ),
            if (_shift != null)
              _infoChip(
                label: 'Shift',
                value: _shift!,
                icon: Icons.schedule_rounded,
                color: AppTheme.brandSuccess,
                isDark: isDark,
              ),
          ],
        ),
      ],
    );
  }

  Widget _infoChip({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── change password tab ───────────────────────────────────────────────────

  Widget _buildChangePasswordTab(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // success banner
        if (_pwdSuccess)
          _buildBanner(
            message: 'Password changed successfully!',
            isError: false,
            isDark: isDark,
          ),

        // error banner
        if (_pwdError != null)
          _buildBanner(
            message: _pwdError!,
            isError: true,
            isDark: isDark,
          ),

        // current password
        _sectionLabel('Current Password', isDark),
        const SizedBox(height: 6),
        TextFormField(
          controller: _oldPwdCtrl,
          obscureText: _obscureOld,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 14,
          ),
          decoration: _inputDecor(
            isDark,
            hint: 'Enter current password',
            suffixIcon: _pwdToggleIcon(
              obscure: _obscureOld,
              onToggle: () => setState(() => _obscureOld = !_obscureOld),
              isDark: isDark,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // new password
        _sectionLabel('New Password', isDark),
        const SizedBox(height: 6),
        TextFormField(
          controller: _newPwdCtrl,
          obscureText: _obscureNew,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 14,
          ),
          decoration: _inputDecor(
            isDark,
            hint: 'Min. 6 characters',
            suffixIcon: _pwdToggleIcon(
              obscure: _obscureNew,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
              isDark: isDark,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // confirm new password
        _sectionLabel('Confirm New Password', isDark),
        const SizedBox(height: 6),
        TextFormField(
          controller: _confirmCtrl,
          obscureText: _obscureConfirm,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 14,
          ),
          decoration: _inputDecor(
            isDark,
            hint: 'Re-enter new password',
            suffixIcon: _pwdToggleIcon(
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              isDark: isDark,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // submit button
        _buildGradientButton(
          label: _changingPwd ? 'Updating...' : 'Update Password',
          onTap: _changingPwd ? null : _submitChangePassword,
          isDark: isDark,
          icon: Icons.lock_reset_rounded,
        ),
      ],
    );
  }

  // ── shared small widgets ──────────────────────────────────────────────────

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }

  InputDecoration _inputDecor(
    bool isDark, {
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
      hintStyle: TextStyle(
        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
        fontSize: 14,
      ),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)
              .withOpacity(0.5),
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _pwdToggleIcon({
    required bool obscure,
    required VoidCallback onToggle,
    required bool isDark,
  }) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        size: 18,
        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
      ),
      onPressed: onToggle,
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildBanner({
    required String message,
    required bool isError,
    required bool isDark,
  }) {
    final color = isError ? AppTheme.brandDanger : AppTheme.brandSuccess;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required VoidCallback? onTap,
    required bool isDark,
    required IconData icon,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 48,
        decoration: BoxDecoration(
          gradient: disabled ? null : AppTheme.primaryGradient,
          color: disabled
              ? (isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated)
              : null,
          borderRadius: BorderRadius.circular(10),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppTheme.accent.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (disabled)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                ),
              )
            else
              Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: disabled
                    ? (isDark
                        ? AppTheme.darkTextSub
                        : AppTheme.lightTextSub)
                    : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
