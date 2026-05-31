import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../authentication/presentation/auth_state.dart';
import '../shifts/presentation/shift_provider.dart';

String get _base => ServerConfig.apiBase;

// ============================================================================
// EMPLOYEE MANAGEMENT SCREEN
// ============================================================================

class EmployeeManagementScreen extends ConsumerStatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  ConsumerState<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState
    extends ConsumerState<EmployeeManagementScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _departments = [];
  List<Shift> _shifts = [];
  bool _loading = true;
  String _search = '';
  String? _statusFilter; // null = all
  String? _error;

  // ── Headers ────────────────────────────────────────────────────────────────
  Map<String, String> get _headers => {
        'Authorization':
            'Bearer ${ref.read(authProvider).accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ── Data fetching ──────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_base/employees'), headers: _headers),
        http.get(Uri.parse('$_base/settings/departments'), headers: _headers),
        http.get(Uri.parse('$_base/shifts'), headers: _headers),
      ]);

      // Employees
      final empBody =
          jsonDecode(results[0].body) as Map<String, dynamic>;
      List<Map<String, dynamic>> employees = [];
      if (results[0].statusCode == 200 && empBody['success'] == true) {
        final raw = empBody['data'];
        final List list = raw is List
            ? raw
            : (raw is Map && raw['employees'] is List)
                ? raw['employees'] as List
                : [];
        employees =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // Departments
      final deptBody =
          jsonDecode(results[1].body) as Map<String, dynamic>;
      List<Map<String, dynamic>> departments = [];
      if (results[1].statusCode == 200 && deptBody['success'] == true) {
        final raw = deptBody['data'];
        final List list = raw is List
            ? raw
            : (raw is Map && raw['departments'] is List)
                ? raw['departments'] as List
                : [];
        departments =
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // Shifts
      final shiftBody =
          jsonDecode(results[2].body) as Map<String, dynamic>;
      List<Shift> shifts = [];
      if (results[2].statusCode == 200 && shiftBody['success'] == true) {
        final raw = shiftBody['data'];
        final List list = raw is List ? raw : [];
        shifts = list.map((e) => Shift.fromJson(e as Map<String, dynamic>)).toList();
      }

      setState(() {
        _employees = employees;
        _departments = departments;
        _shifts = shifts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Filtered list ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    var list = _employees;
    if (_statusFilter != null) {
      list = list.where((e) =>
          (e['employmentStatus'] as String? ?? '').toUpperCase() == _statusFilter).toList();
    }
    if (_search.trim().isEmpty) return list;
    final q = _search.trim().toLowerCase();
    return list.where((e) {
      final name =
          '${e['first_name'] ?? ''} ${e['last_name'] ?? ''}'.toLowerCase();
      final code = '${e['employee_code'] ?? ''}'.toLowerCase();
      final dept = '${e['department_name'] ?? ''}'.toLowerCase();
      return name.contains(q) || code.contains(q) || dept.contains(q);
    }).toList();
  }

  // ── Snackbar helpers ───────────────────────────────────────────────────────
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.statusPresent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.brandDanger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ── Status badge for employee status ──────────────────────────────────────
  Widget _statusBadge(String? status) {
    final s = (status ?? 'INACTIVE').toUpperCase();
    Color color;
    switch (s) {
      case 'ACTIVE':
        color = AppTheme.statusPresent;
        break;
      case 'SUSPENDED':
        color = AppTheme.statusAbsent;
        break;
      default:
        color = AppTheme.darkTextMuted;
    }
    return AppTheme.statusBadge(s, color);
  }

  // ============================================================================
  // DIALOG: ADD EMPLOYEE
  // ============================================================================
  Future<void> _showAddEmployeeDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();

    final codeCtrl    = TextEditingController();
    final firstCtrl   = TextEditingController();
    final lastCtrl    = TextEditingController();
    final designCtrl  = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final userCtrl    = TextEditingController();
    final emailCtrl   = TextEditingController();
    final passCtrl    = TextEditingController();
    final pass2Ctrl   = TextEditingController();
    DateTime joiningDate   = DateTime.now();
    int? selectedDeptId;
    int? selectedShiftId;
    String selectedStatus  = 'ACTIVE';
    Set<String> selectedRoles = {'Employee'};
    bool obscurePass   = true;
    bool obscurePass2  = true;
    bool saving        = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          InputDecoration fieldDecoration(String label, {String? hint}) =>
              InputDecoration(
                labelText: label,
                hintText: hint,
                filled: true,
                fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppTheme.accent, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                labelStyle: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSub
                        : AppTheme.lightTextSub,
                    fontSize: 13),
                hintStyle: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextMuted
                        : AppTheme.lightTextMuted,
                    fontSize: 13),
              );

          return Dialog(
            backgroundColor:
                isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: isDark
                      ? AppTheme.darkBorder
                      : AppTheme.lightBorder),
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
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.person_add_rounded,
                              size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Add Employee',
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              size: 18),
                          onPressed:
                              saving ? null : () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // Error banner
                      if (dialogError != null) ...[
                        _DialogErrorBanner(message: dialogError!),
                        const SizedBox(height: 14),
                      ],

                      // Section divider: Profile
                      _SectionDivider(label: 'Employee Profile', isDark: isDark),
                      const SizedBox(height: 12),

                      // Employee Code
                      TextFormField(
                        controller: codeCtrl,
                        decoration: fieldDecoration('Employee Code *',
                            hint: 'e.g. EMP001'),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Employee code is required'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // First Name + Last Name
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: firstCtrl,
                            decoration:
                                fieldDecoration('First Name *'),
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: lastCtrl,
                            decoration:
                                fieldDecoration('Last Name *'),
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Designation
                      TextFormField(
                        controller: designCtrl,
                        decoration: fieldDecoration('Designation',
                            hint: 'e.g. Software Engineer'),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: fieldDecoration('Phone',
                            hint: 'e.g. +92 300 1234567'),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 12),

                      // Joining Date
                      _FieldLabel('Joining Date', isDark: isDark),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: joiningDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setS(() => joiningDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.darkInput
                                : AppTheme.lightInput,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isDark
                                    ? AppTheme.darkBorder
                                    : AppTheme.lightBorder),
                          ),
                          child: Row(children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 15,
                                color: isDark
                                    ? AppTheme.darkTextSub
                                    : AppTheme.lightTextSub),
                            const SizedBox(width: 8),
                            Text(
                              '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Department
                      _FieldLabel('Department', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<int?>(
                        value: selectedDeptId,
                        isDark: isDark,
                        hint: 'Select department',
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ..._departments.map((d) =>
                              DropdownMenuItem<int?>(
                                value: d['id'] as int?,
                                child:
                                    Text(d['department_name'] as String? ?? ''),
                              )),
                        ],
                        onChanged: (v) =>
                            setS(() => selectedDeptId = v),
                      ),
                      const SizedBox(height: 12),

                      // Shift
                      _FieldLabel('Shift', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<int?>(
                        value: selectedShiftId,
                        isDark: isDark,
                        hint: 'Select shift',
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ..._shifts.map((s) => DropdownMenuItem<int?>(
                                value: s.id,
                                child: Text(s.shiftName),
                              )),
                        ],
                        onChanged: (v) =>
                            setS(() => selectedShiftId = v),
                      ),
                      const SizedBox(height: 12),

                      // Employment Status
                      _FieldLabel('Employment Status', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<String>(
                        value: selectedStatus,
                        isDark: isDark,
                        hint: 'Select status',
                        items: const [
                          DropdownMenuItem(value: 'ACTIVE',   child: Text('ACTIVE')),
                          DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE')),
                        ],
                        onChanged: (v) => setS(() => selectedStatus = v ?? 'ACTIVE'),
                      ),
                      const SizedBox(height: 20),

                      // ── Login Account Section ────────────────────────────
                      _SectionDivider(label: 'Login Account (Optional)', isDark: isDark),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.accent.withOpacity(0.18)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.info_outline, color: AppTheme.accent, size: 14),
                          const SizedBox(width: 7),
                          Expanded(child: Text(
                            'Fill username, email and password to create a login account now. Leave blank to set it up later via "Reset Password" & "Roles" actions.',
                            style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // Username + Email
                      Row(children: [
                        Expanded(child: TextFormField(
                          controller: userCtrl,
                          decoration: fieldDecoration('Username', hint: 'e.g. john.doe'),
                          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                          validator: (v) {
                            if (v != null && v.isNotEmpty && v.trim().length < 3) return 'Min 3 characters';
                            return null;
                          },
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(
                          controller: emailCtrl,
                          decoration: fieldDecoration('Email', hint: 'john@company.com'),
                          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v != null && v.isNotEmpty && !v.contains('@')) return 'Enter valid email';
                            return null;
                          },
                        )),
                      ]),
                      const SizedBox(height: 12),

                      // Password + Confirm
                      Row(children: [
                        Expanded(child: TextFormField(
                          controller: passCtrl,
                          obscureText: obscurePass,
                          decoration: fieldDecoration('Password', hint: 'Min 6 chars').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility,
                                  size: 18, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                              onPressed: () => setS(() => obscurePass = !obscurePass),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                          validator: (v) {
                            if (userCtrl.text.trim().isNotEmpty && (v == null || v.length < 6)) return 'Min 6 characters';
                            return null;
                          },
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(
                          controller: pass2Ctrl,
                          obscureText: obscurePass2,
                          decoration: fieldDecoration('Confirm Password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(obscurePass2 ? Icons.visibility_off : Icons.visibility,
                                  size: 18, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                              onPressed: () => setS(() => obscurePass2 = !obscurePass2),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                          validator: (v) {
                            if (userCtrl.text.trim().isNotEmpty && v != passCtrl.text) return 'Passwords do not match';
                            return null;
                          },
                        )),
                      ]),
                      const SizedBox(height: 12),

                      // Roles
                      _FieldLabel('Assign Roles', isDark: isDark),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final entry in [
                          ('Employee', AppTheme.roleEmployee),
                          ('Manager',  AppTheme.roleManager),
                          ('HR',       AppTheme.roleHR),
                          ('Admin',    AppTheme.roleAdmin),
                        ])
                          GestureDetector(
                            onTap: () => setS(() {
                              if (selectedRoles.contains(entry.$1)) {
                                if (selectedRoles.length > 1) selectedRoles.remove(entry.$1);
                              } else {
                                selectedRoles.add(entry.$1);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selectedRoles.contains(entry.$1)
                                    ? entry.$2.withOpacity(0.15)
                                    : (isDark ? AppTheme.darkInput : AppTheme.lightInput),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedRoles.contains(entry.$1) ? entry.$2 : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                                  width: selectedRoles.contains(entry.$1) ? 1.5 : 1,
                                ),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (selectedRoles.contains(entry.$1))
                                  Icon(Icons.check_circle_rounded, size: 13, color: entry.$2),
                                if (selectedRoles.contains(entry.$1))
                                  const SizedBox(width: 5),
                                Text(entry.$1, style: TextStyle(
                                  color: selectedRoles.contains(entry.$1) ? entry.$2 : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                                  fontSize: 12.5, fontWeight: selectedRoles.contains(entry.$1) ? FontWeight.w600 : FontWeight.w400,
                                )),
                              ]),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextSub
                                      : AppTheme.lightTextSub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _GradientButton(
                            label: 'Add Employee',
                            icon: Icons.person_add_rounded,
                            loading: saving,
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              setS(() {
                                saving = true;
                                dialogError = null;
                              });
                              try {
                                final hasLogin = userCtrl.text.trim().isNotEmpty &&
                                    emailCtrl.text.trim().isNotEmpty &&
                                    passCtrl.text.isNotEmpty;
                                final payload = {
                                  'employeeCode': codeCtrl.text.trim(),
                                  'firstName': firstCtrl.text.trim(),
                                  'lastName': lastCtrl.text.trim(),
                                  if (designCtrl.text.trim().isNotEmpty) 'designation': designCtrl.text.trim(),
                                  if (phoneCtrl.text.trim().isNotEmpty)  'phone': phoneCtrl.text.trim(),
                                  'joiningDate': '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                                  if (selectedDeptId != null)  'departmentId': selectedDeptId,
                                  if (selectedShiftId != null) 'shiftId': selectedShiftId,
                                  'employmentStatus': selectedStatus,
                                  if (hasLogin) 'username': userCtrl.text.trim(),
                                  if (hasLogin) 'email':    emailCtrl.text.trim(),
                                  if (hasLogin) 'password': passCtrl.text,
                                  if (hasLogin) 'roles': selectedRoles.toList(),
                                };
                                final res = await http.post(
                                  Uri.parse('$_base/employees'),
                                  headers: _headers,
                                  body: jsonEncode(payload),
                                );
                                final rb = jsonDecode(res.body)
                                    as Map<String, dynamic>;
                                if ((res.statusCode == 200 ||
                                        res.statusCode == 201) &&
                                    rb['success'] == true) {
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } else {
                                  setS(() {
                                    saving = false;
                                    dialogError =
                                        (rb['error'] as Map?)?['message']
                                                as String? ??
                                            'Failed to create employee';
                                  });
                                }
                              } catch (e) {
                                setS(() {
                                  saving = false;
                                  dialogError = e.toString();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    codeCtrl.dispose();
    firstCtrl.dispose();
    lastCtrl.dispose();
    designCtrl.dispose();
    phoneCtrl.dispose();
    userCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    pass2Ctrl.dispose();
    _loadAll();
  }

  // ============================================================================
  // DIALOG: EDIT EMPLOYEE
  // ============================================================================
  Future<void> _showEditEmployeeDialog(Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();

    final firstCtrl =
        TextEditingController(text: emp['firstName'] as String? ?? '');
    final lastCtrl =
        TextEditingController(text: emp['lastName'] as String? ?? '');
    final designCtrl =
        TextEditingController(text: emp['designation'] as String? ?? '');
    final phoneCtrl =
        TextEditingController(text: emp['phone'] as String? ?? '');

    DateTime joiningDate = DateTime.now();
    if (emp['joiningDate'] != null) {
      try {
        joiningDate = DateTime.parse(emp['joiningDate'] as String);
      } catch (_) {}
    }

    int? selectedDeptId = emp['departmentId'] as int?;
    int? selectedShiftId = emp['shiftId'] as int?;
    String selectedStatus =
        (emp['employmentStatus'] as String? ?? 'ACTIVE').toUpperCase();
    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          InputDecoration fieldDecoration(String label, {String? hint}) =>
              InputDecoration(
                labelText: label,
                hintText: hint,
                filled: true,
                fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppTheme.accent, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                labelStyle: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSub
                        : AppTheme.lightTextSub,
                    fontSize: 13),
              );

          return Dialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              size: 18, color: AppTheme.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Employee',
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkText
                                      : AppTheme.lightText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                emp['employeeCode'] as String? ?? '',
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextMuted
                                      : AppTheme.lightTextMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              size: 18),
                          onPressed:
                              saving ? null : () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // Error banner
                      if (dialogError != null) ...[
                        _DialogErrorBanner(message: dialogError!),
                        const SizedBox(height: 14),
                      ],

                      // First Name + Last Name
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: firstCtrl,
                            decoration: fieldDecoration('First Name *'),
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: lastCtrl,
                            decoration: fieldDecoration('Last Name *'),
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),

                      // Designation
                      TextFormField(
                        controller: designCtrl,
                        decoration: fieldDecoration('Designation'),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: fieldDecoration('Phone'),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 12),

                      // Joining Date
                      _FieldLabel('Joining Date', isDark: isDark),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: joiningDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setS(() => joiningDate = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.darkInput
                                : AppTheme.lightInput,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isDark
                                    ? AppTheme.darkBorder
                                    : AppTheme.lightBorder),
                          ),
                          child: Row(children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 15,
                                color: isDark
                                    ? AppTheme.darkTextSub
                                    : AppTheme.lightTextSub),
                            const SizedBox(width: 8),
                            Text(
                              '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 14,
                              ),
                            ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Department
                      _FieldLabel('Department', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<int?>(
                        value: selectedDeptId,
                        isDark: isDark,
                        hint: 'Select department',
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ..._departments.map((d) => DropdownMenuItem<int?>(
                                value: d['id'] as int?,
                                child: Text(
                                    d['department_name'] as String? ?? ''),
                              )),
                        ],
                        onChanged: (v) =>
                            setS(() => selectedDeptId = v),
                      ),
                      const SizedBox(height: 12),

                      // Shift
                      _FieldLabel('Shift', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<int?>(
                        value: selectedShiftId,
                        isDark: isDark,
                        hint: 'Select shift',
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ..._shifts.map((s) => DropdownMenuItem<int?>(
                                value: s.id,
                                child: Text(s.shiftName),
                              )),
                        ],
                        onChanged: (v) =>
                            setS(() => selectedShiftId = v),
                      ),
                      const SizedBox(height: 12),

                      // Employment Status
                      _FieldLabel('Employment Status', isDark: isDark),
                      const SizedBox(height: 6),
                      _StyledDropdown<String>(
                        value: selectedStatus,
                        isDark: isDark,
                        hint: 'Select status',
                        items: const [
                          DropdownMenuItem(
                              value: 'ACTIVE', child: Text('ACTIVE')),
                          DropdownMenuItem(
                              value: 'INACTIVE', child: Text('INACTIVE')),
                          DropdownMenuItem(
                              value: 'SUSPENDED', child: Text('SUSPENDED')),
                        ],
                        onChanged: (v) =>
                            setS(() => selectedStatus = v ?? 'ACTIVE'),
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextSub
                                      : AppTheme.lightTextSub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _GradientButton(
                            label: 'Save Changes',
                            icon: Icons.save_rounded,
                            loading: saving,
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              setS(() {
                                saving = true;
                                dialogError = null;
                              });
                              try {
                                final payload = {
                                  'first_name': firstCtrl.text.trim(),
                                  'last_name': lastCtrl.text.trim(),
                                  if (designCtrl.text.trim().isNotEmpty)
                                    'designation': designCtrl.text.trim(),
                                  if (phoneCtrl.text.trim().isNotEmpty)
                                    'phone': phoneCtrl.text.trim(),
                                  'joining_date':
                                      '${joiningDate.year}-${joiningDate.month.toString().padLeft(2, '0')}-${joiningDate.day.toString().padLeft(2, '0')}',
                                  'department_id': selectedDeptId,
                                  'shift_id': selectedShiftId,
                                  'employment_status': selectedStatus,
                                };
                                final empId = emp['id'];
                                final res = await http.put(
                                  Uri.parse('$_base/employees/$empId'),
                                  headers: _headers,
                                  body: jsonEncode(payload),
                                );
                                final rb = jsonDecode(res.body)
                                    as Map<String, dynamic>;
                                if (res.statusCode == 200 &&
                                    rb['success'] == true) {
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } else {
                                  setS(() {
                                    saving = false;
                                    dialogError =
                                        (rb['error'] as Map?)?['message']
                                                as String? ??
                                            'Failed to update employee';
                                  });
                                }
                              } catch (e) {
                                setS(() {
                                  saving = false;
                                  dialogError = e.toString();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    firstCtrl.dispose();
    lastCtrl.dispose();
    designCtrl.dispose();
    phoneCtrl.dispose();
    _loadAll();
  }

  // ============================================================================
  // DIALOG: RESET PASSWORD
  // ============================================================================
  Future<void> _showResetPasswordDialog(Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formKey = GlobalKey<FormState>();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscurePass = true;
    bool obscureConfirm = true;
    bool saving = false;
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          InputDecoration passDecoration(String label,
                  {required bool obscure,
                  required VoidCallback onToggle}) =>
              InputDecoration(
                labelText: label,
                filled: true,
                fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppTheme.accent, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                labelStyle: TextStyle(
                    color: isDark
                        ? AppTheme.darkTextSub
                        : AppTheme.lightTextSub,
                    fontSize: 13),
                suffixIcon: IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: isDark
                        ? AppTheme.darkTextMuted
                        : AppTheme.lightTextMuted,
                  ),
                  onPressed: onToggle,
                ),
              );

          return Dialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.key_rounded,
                              size: 18, color: AppTheme.brandWarning),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reset Password',
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkText
                                      : AppTheme.lightText,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim(),
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextMuted
                                      : AppTheme.lightTextMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              size: 18),
                          onPressed:
                              saving ? null : () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // Error banner
                      if (dialogError != null) ...[
                        _DialogErrorBanner(message: dialogError!),
                        const SizedBox(height: 14),
                      ],

                      // New Password
                      TextFormField(
                        controller: passCtrl,
                        obscureText: obscurePass,
                        decoration: passDecoration(
                          'New Password',
                          obscure: obscurePass,
                          onToggle: () =>
                              setS(() => obscurePass = !obscurePass),
                        ),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password is required';
                          }
                          if (v.length < 6) {
                            return 'Minimum 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Confirm Password
                      TextFormField(
                        controller: confirmCtrl,
                        obscureText: obscureConfirm,
                        decoration: passDecoration(
                          'Confirm Password',
                          obscure: obscureConfirm,
                          onToggle: () =>
                              setS(() => obscureConfirm = !obscureConfirm),
                        ),
                        style: TextStyle(
                            color: isDark
                                ? AppTheme.darkText
                                : AppTheme.lightText,
                            fontSize: 14),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please confirm password';
                          }
                          if (v != passCtrl.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                saving ? null : () => Navigator.pop(ctx),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextSub
                                      : AppTheme.lightTextSub),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandWarning,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                            ),
                            onPressed: saving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    setS(() {
                                      saving = true;
                                      dialogError = null;
                                    });
                                    try {
                                      final empId = emp['id'];
                                      final res = await http.post(
                                        Uri.parse(
                                            '$_base/employees/$empId/reset-password'),
                                        headers: _headers,
                                        body: jsonEncode({
                                          'newPassword': passCtrl.text,
                                        }),
                                      );
                                      final rb = jsonDecode(res.body)
                                          as Map<String, dynamic>;
                                      if (res.statusCode == 200 &&
                                          rb['success'] == true) {
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _showSuccess(
                                            'Password reset successfully');
                                      } else {
                                        setS(() {
                                          saving = false;
                                          dialogError =
                                              (rb['error'] as Map?)?[
                                                          'message']
                                                      as String? ??
                                                  'Failed to reset password';
                                        });
                                      }
                                    } catch (e) {
                                      setS(() {
                                        saving = false;
                                        dialogError = e.toString();
                                      });
                                    }
                                  },
                            child: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Text('Reset Password'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    passCtrl.dispose();
    confirmCtrl.dispose();
  }

  // ============================================================================
  // DIALOG: MANAGE ROLES
  // ============================================================================
  Future<void> _showManageRolesDialog(Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool loading = true;
    List<Map<String, dynamic>> allRoles = [];
    Set<int> selectedRoleIds = {};
    String? accountInfo;
    bool saving = false;
    String? dialogError;
    String? loadError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Load roles on first build
          if (loading && allRoles.isEmpty && loadError == null) {
            final empId = emp['id'];
            http
                .get(Uri.parse('$_base/employees/$empId/roles'),
                    headers: _headers)
                .then((res) {
              final rb =
                  jsonDecode(res.body) as Map<String, dynamic>;
              if (res.statusCode == 200 && rb['success'] == true) {
                final data = rb['data'] as Map<String, dynamic>? ?? {};
                final rawAll = data['allRoles'] as List? ?? [];
                final rawAssigned =
                    data['assignedRoles'] as List? ?? [];

                final roles = rawAll
                    .map((r) => Map<String, dynamic>.from(r as Map))
                    .toList();
                final assignedIds = rawAssigned
                    .map((r) => (r is Map ? r['id'] : r) as int)
                    .toSet();

                // Account info
                final userInfo = data['userAccount'] as Map?;
                String? info;
                if (userInfo != null) {
                  info =
                      '${userInfo['username'] ?? ''} • ${userInfo['email'] ?? ''}';
                }

                if (ctx.mounted) {
                  setS(() {
                    allRoles = roles;
                    selectedRoleIds = assignedIds;
                    accountInfo = info;
                    loading = false;
                  });
                }
              } else {
                if (ctx.mounted) {
                  setS(() {
                    loadError =
                        (rb['error'] as Map?)?['message'] as String? ??
                            'Failed to load roles';
                    loading = false;
                  });
                }
              }
            }).catchError((e) {
              if (ctx.mounted) {
                setS(() {
                  loadError = e.toString();
                  loading = false;
                });
              }
            });
          }

          return Dialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.shield_rounded,
                            size: 18, color: AppTheme.brandInfo),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manage Roles',
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim(),
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkTextMuted
                                    : AppTheme.lightTextMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted,
                            size: 18),
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // Account info line
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.darkCard2
                            : AppTheme.lightElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isDark
                                ? AppTheme.darkBorder
                                : AppTheme.lightBorder),
                      ),
                      child: Row(children: [
                        Icon(
                          accountInfo != null
                              ? Icons.account_circle_rounded
                              : Icons.account_circle_outlined,
                          size: 16,
                          color: accountInfo != null
                              ? AppTheme.accent
                              : (isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            accountInfo ?? 'No account linked',
                            style: TextStyle(
                              color: accountInfo != null
                                  ? (isDark
                                      ? AppTheme.darkTextSub
                                      : AppTheme.lightTextSub)
                                  : (isDark
                                      ? AppTheme.darkTextMuted
                                      : AppTheme.lightTextMuted),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Error/loading/roles
                    if (loading)
                      const Center(
                          child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ))
                    else if (loadError != null)
                      _DialogErrorBanner(message: loadError!)
                    else if (allRoles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'No roles available.',
                          style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              fontSize: 13),
                        ),
                      )
                    else ...[
                      if (dialogError != null) ...[
                        _DialogErrorBanner(message: dialogError!),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Assign Roles',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSub
                              : AppTheme.lightTextSub,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...allRoles.map((role) {
                        final roleId = role['id'] as int;
                        final roleName =
                            role['role_name'] as String? ?? role['name'] as String? ?? 'Unknown';
                        final isChecked =
                            selectedRoleIds.contains(roleId);
                        final roleColor = _roleColor(roleName);

                        return InkWell(
                          onTap: () => setS(() {
                            if (isChecked) {
                              selectedRoleIds.remove(roleId);
                            } else {
                              selectedRoleIds.add(roleId);
                            }
                          }),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isChecked
                                  ? roleColor.withOpacity(0.1)
                                  : (isDark
                                      ? AppTheme.darkCard2
                                      : AppTheme.lightElevated),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isChecked
                                      ? roleColor.withOpacity(0.3)
                                      : (isDark
                                          ? AppTheme.darkBorder
                                          : AppTheme.lightBorder)),
                            ),
                            child: Row(children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isChecked
                                      ? roleColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: isChecked
                                          ? roleColor
                                          : (isDark
                                              ? AppTheme.darkTextMuted
                                              : AppTheme.lightTextMuted),
                                      width: 1.5),
                                ),
                                child: isChecked
                                    ? const Icon(Icons.check,
                                        size: 12, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                roleName,
                                style: TextStyle(
                                  color: isChecked
                                      ? roleColor
                                      : (isDark
                                          ? AppTheme.darkText
                                          : AppTheme.lightText),
                                  fontSize: 13,
                                  fontWeight: isChecked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ]),
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              saving ? null : () => Navigator.pop(ctx),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkTextSub
                                    : AppTheme.lightTextSub),
                          ),
                        ),
                        if (!loading && loadError == null && allRoles.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.brandInfo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                            ),
                            onPressed: saving
                                ? null
                                : () async {
                                    setS(() {
                                      saving = true;
                                      dialogError = null;
                                    });
                                    try {
                                      final empId = emp['id'];
                                      final res = await http.put(
                                        Uri.parse(
                                            '$_base/employees/$empId/roles'),
                                        headers: _headers,
                                        body: jsonEncode({
                                          'roleIds':
                                              selectedRoleIds.toList(),
                                        }),
                                      );
                                      final rb = jsonDecode(res.body)
                                          as Map<String, dynamic>;
                                      if (res.statusCode == 200 &&
                                          rb['success'] == true) {
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                        }
                                        _showSuccess(
                                            'Roles updated successfully');
                                      } else {
                                        setS(() {
                                          saving = false;
                                          dialogError =
                                              (rb['error'] as Map?)?[
                                                          'message']
                                                      as String? ??
                                                  'Failed to update roles';
                                        });
                                      }
                                    } catch (e) {
                                      setS(() {
                                        saving = false;
                                        dialogError = e.toString();
                                      });
                                    }
                                  },
                            child: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Text('Save Roles'),
                          ),
                        ],
                      ],
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

  // ── Role color helper ──────────────────────────────────────────────────────
  Color _roleColor(String name) {
    switch (name.toLowerCase()) {
      case 'admin':
        return AppTheme.roleAdmin;
      case 'hr':
        return AppTheme.roleHR;
      case 'manager':
        return AppTheme.roleManager;
      default:
        return AppTheme.roleEmployee;
    }
  }

  // ============================================================================
  // STATUS CHANGE POPUP MENU
  // ============================================================================
  Future<void> _showStatusMenu(
      BuildContext context, Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final RenderBox button =
        context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      color: isDark ? AppTheme.darkCard2 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      items: [
        _statusMenuItem('ACTIVE', Icons.check_circle_rounded,
            AppTheme.statusPresent, isDark),
        _statusMenuItem('SUSPENDED', Icons.pause_circle_rounded,
            AppTheme.statusAbsent, isDark),
        _statusMenuItem('INACTIVE', Icons.cancel_rounded,
            AppTheme.darkTextMuted, isDark),
      ],
    );

    if (result == null) return;
    final current = (emp['employmentStatus'] as String? ?? '').toUpperCase();
    if (result == current) return;

    try {
      final empId = emp['id'];
      final res = await http.put(
        Uri.parse('$_base/employees/$empId/status'),
        headers: _headers,
        body: jsonEncode({'status': result}),
      );
      final rb = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && rb['success'] == true) {
        _showSuccess('Status updated to $result');
        _loadAll();
      } else {
        _showError((rb['error'] as Map?)?['message'] as String? ??
            'Failed to update status');
      }
    } catch (e) {
      _showError(e.toString());
    }
  }

  PopupMenuItem<String> _statusMenuItem(
      String value, IconData icon, Color color, bool isDark) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ]),
    );
  }

  // ============================================================================
  // DIALOG: VIEW EMPLOYEE PROFILE
  // ============================================================================
  Future<void> _showViewProfileDialog(Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gx = ref.read(authProvider).user?.gx ?? false;

    // Load roles + user account
    String? accountLine;
    int? linkedUserId;
    List<String> roleNames = [];
    try {
      final res = await http.get(
        Uri.parse('$_base/employees/${emp['id']}/roles'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final rb = jsonDecode(res.body) as Map<String, dynamic>;
        if (rb['success'] == true) {
          final data = rb['data'] as Map<String, dynamic>? ?? {};
          final ui = data['userAccount'] as Map?;
          if (ui != null) {
            accountLine = '${ui['username'] ?? ''} • ${ui['email'] ?? ''}';
            linkedUserId = (ui['id'] as num?)?.toInt();
          }
          final rawA = data['assignedRoles'] as List? ?? [];
          roleNames = rawA
              .map((r) => (r is Map ? (r['role_name'] ?? r['name']) : r).toString())
              .toList();
        }
      }
    } catch (_) {}

    if (!mounted) return;

    // ── Helpers ───────────────────────────────────────────────────────────────
    Widget _infoRow(String label, String? value, {Color? valueColor}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value?.isNotEmpty == true ? value! : '—',
              style: TextStyle(
                  color: valueColor ?? (isDark ? AppTheme.darkText : AppTheme.lightText),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );

    final fullName = '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
    final statusStr = (emp['employmentStatus'] as String? ?? 'INACTIVE').toUpperCase();
    final statusColor = statusStr == 'ACTIVE'
        ? AppTheme.statusPresent
        : statusStr == 'SUSPENDED'
            ? AppTheme.statusAbsent
            : AppTheme.darkTextMuted;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          List<Map<String, dynamic>> attLogs = [];
          bool attLoading = false;
          bool attLoaded = false;
          String? attError;

          Future<void> loadAtt() async {
            if (linkedUserId == null) return;
            setS(() { attLoading = true; attError = null; });
            try {
              final r = await http.get(
                Uri.parse('$_base/attendance/records/$linkedUserId'),
                headers: _headers,
              );
              final rb = jsonDecode(r.body) as Map<String, dynamic>;
              if (r.statusCode == 200 && rb['success'] == true) {
                setS(() {
                  attLogs = (rb['data'] as List)
                      .map((x) => Map<String, dynamic>.from(x as Map))
                      .toList();
                  attLoading = false;
                  attLoaded = true;
                });
              } else {
                setS(() { attLoading = false; attError = 'Failed to load'; });
              }
            } catch (e) {
              setS(() { attLoading = false; attError = e.toString(); });
            }
          }

          Future<void> deleteRecord(String id) async {
            try {
              final r = await http.delete(
                Uri.parse('$_base/attendance/records/$id'),
                headers: _headers,
              );
              if (r.statusCode == 200) loadAtt();
            } catch (_) {}
          }

          Future<void> editRecord(Map<String, dynamic> rec) async {
            final ciCtrl = TextEditingController(text: rec['check_in_time']?.toString() ?? '');
            final coCtrl = TextEditingController(text: rec['check_out_time']?.toString() ?? '');
            final wmCtrl = TextEditingController(text: '${rec['total_worked_minutes'] ?? 0}');
            String selStatus = rec['status']?.toString() ?? 'ON_TIME';
            bool saving = false;

            await showDialog(
              context: ctx,
              builder: (ctx2) => StatefulBuilder(builder: (ctx2, setS2) => AlertDialog(
                backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                title: Text('Edit Record — ${rec['date']}',
                    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 15)),
                content: SizedBox(
                  width: 340,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _AttField('Check-in Time', ciCtrl, isDark),
                    const SizedBox(height: 10),
                    _AttField('Check-out Time', coCtrl, isDark),
                    const SizedBox(height: 10),
                    _AttField('Worked Minutes', wmCtrl, isDark, number: true),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selStatus,
                      dropdownColor: isDark ? AppTheme.darkCard2 : Colors.white,
                      decoration: InputDecoration(
                        labelText: 'Status',
                        filled: true,
                        fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: ['ON_TIME','LATE','ABSENT','MISSED_CHECKOUT','PRESENT']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => setS2(() => selStatus = v ?? selStatus),
                    ),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx2), child: const Text('Cancel')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: saving ? null : () async {
                      setS2(() => saving = true);
                      try {
                        final body = <String, dynamic>{
                          'status': selStatus,
                          'totalWorkedMinutes': int.tryParse(wmCtrl.text) ?? 0,
                        };
                        if (ciCtrl.text.isNotEmpty) body['checkInTime'] = ciCtrl.text.trim();
                        if (coCtrl.text.isNotEmpty) body['checkOutTime'] = coCtrl.text.trim();
                        final r = await http.put(
                          Uri.parse('$_base/attendance/records/${rec['id']}'),
                          headers: _headers,
                          body: jsonEncode(body),
                        );
                        if (r.statusCode == 200) {
                          if (ctx2.mounted) Navigator.pop(ctx2);
                          loadAtt();
                        } else {
                          setS2(() => saving = false);
                        }
                      } catch (_) { setS2(() => saving = false); }
                    },
                    child: saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                ],
              )),
            );
            ciCtrl.dispose();
            coCtrl.dispose();
            wmCtrl.dispose();
          }

          return Dialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: gx ? 680.0 : 500.0, maxHeight: 700),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(fullName.isNotEmpty ? fullName : '—',
                            style: TextStyle(
                                color: isDark ? AppTheme.darkText : AppTheme.lightText,
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        if ((emp['designation'] as String?)?.isNotEmpty == true)
                          Text(emp['designation'] as String,
                              style: TextStyle(
                                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                  fontSize: 12)),
                      ])),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                    const SizedBox(height: 18),

                    // Employee details
                    _SectionDivider(label: 'Employee Details', isDark: isDark),
                    const SizedBox(height: 10),
                    _infoRow('Employee Code', emp['employeeCode'] as String?),
                    _infoRow('Department', emp['departmentName'] as String?),
                    _infoRow('Shift', emp['shiftName'] as String?),
                    _infoRow('Joining Date', emp['joiningDate'] as String?),
                    _infoRow('Phone', emp['phone'] as String?),
                    _infoRow('Status', statusStr, valueColor: statusColor),
                    const SizedBox(height: 14),

                    // Account section
                    _SectionDivider(label: 'Login Account', isDark: isDark),
                    const SizedBox(height: 10),
                    if (accountLine != null)
                      _infoRow('Account', accountLine)
                    else
                      Text('No login account linked',
                          style: TextStyle(
                              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                              fontSize: 13, fontStyle: FontStyle.italic)),
                    if (roleNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          width: 130,
                          child: Text('Roles',
                              style: TextStyle(
                                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                  fontSize: 12.5, fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: roleNames.map((r) {
                          final c = _roleColor(r);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.withOpacity(0.3)),
                            ),
                            child: Text(r, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
                          );
                        }).toList())),
                      ]),
                    ],

                    // ── Attendance records (gx only) ──────────────────────────
                    if (gx && linkedUserId != null) ...[
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: _SectionDivider(label: 'Attendance Records', isDark: isDark)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: loadAtt,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.refresh_rounded, size: 12, color: AppTheme.accent),
                              const SizedBox(width: 4),
                              Text(attLoaded ? 'Reload' : 'Load',
                                  style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (!attLoaded && !attLoading)
                        Text('Tap Load to fetch attendance records.',
                            style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                fontSize: 12.5, fontStyle: FontStyle.italic))
                      else if (attLoading)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        ))
                      else if (attError != null)
                        Text(attError!, style: const TextStyle(color: AppTheme.brandDanger, fontSize: 12.5))
                      else if (attLogs.isEmpty)
                        Text('No attendance records found.',
                            style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 12.5))
                      else
                        ...attLogs.map((rec) {
                          final ciStr = rec['check_in_time']?.toString();
                          final coStr = rec['check_out_time']?.toString();
                          final wm = (rec['total_worked_minutes'] as num? ?? 0).toInt();
                          final st = rec['status']?.toString() ?? '--';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                            ),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(rec['date']?.toString() ?? '--',
                                    style: TextStyle(
                                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_fmtAttTime(ciStr)} → ${_fmtAttTime(coStr)}  •  '
                                  '${wm > 0 ? '${wm ~/ 60}h${wm % 60}m' : '--'}  •  $st',
                                  style: TextStyle(
                                      color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                      fontSize: 11.5),
                                ),
                              ])),
                              _ActionIconBtn(
                                icon: Icons.edit_rounded,
                                color: AppTheme.accent,
                                tooltip: 'Edit',
                                onTap: () => editRecord(rec),
                              ),
                              const SizedBox(width: 4),
                              _ActionIconBtn(
                                icon: Icons.delete_outline_rounded,
                                color: AppTheme.statusAbsent,
                                tooltip: 'Delete',
                                onTap: () async {
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                                      title: const Text('Delete Record?'),
                                      content: Text('Delete attendance for ${rec['date']}? This cannot be undone.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.statusAbsent,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => Navigator.pop(c, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) deleteRecord(rec['id']?.toString() ?? '');
                                },
                              ),
                            ]),
                          );
                        }),
                    ],

                    const SizedBox(height: 20),
                    // Actions row
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit_rounded, size: 14),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                          side: const BorderSide(color: AppTheme.accent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () { Navigator.pop(ctx); _showEditEmployeeDialog(emp); },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.key_rounded, size: 14),
                        label: const Text('Reset Password'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brandWarning,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        onPressed: () { Navigator.pop(ctx); _showResetPasswordDialog(emp); },
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _fmtAttTime(String? dt) {
    if (dt == null || dt.isEmpty) return '--';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(dt).toLocal());
    } catch (_) {
      return dt.length >= 5 ? dt.substring(11, 16) : dt;
    }
  }

  // ============================================================================
  // BUILD
  // ============================================================================
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employee Management',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_employees.length} employee${_employees.length == 1 ? '' : 's'} total',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.darkTextSub
                            : AppTheme.lightTextSub,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // Search field
              SizedBox(
                width: 240,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(
                      color:
                          isDark ? AppTheme.darkText : AppTheme.lightText,
                      fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name, code, dept...',
                    hintStyle: TextStyle(
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted,
                        fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 17,
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted),
                    filled: true,
                    fillColor:
                        isDark ? AppTheme.darkInput : AppTheme.lightInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.darkBorder
                              : AppTheme.lightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppTheme.accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Status filter dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _statusFilter != null
                          ? AppTheme.accent
                          : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _statusFilter,
                    hint: Text('All Status',
                        style: TextStyle(
                            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                            fontSize: 13)),
                    dropdownColor: isDark ? AppTheme.darkCard2 : Colors.white,
                    style: TextStyle(
                        color: isDark ? AppTheme.darkText : AppTheme.lightText,
                        fontSize: 13),
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Status')),
                      const DropdownMenuItem<String?>(value: 'ACTIVE', child: Text('Active')),
                      const DropdownMenuItem<String?>(value: 'INACTIVE', child: Text('Inactive')),
                      const DropdownMenuItem<String?>(value: 'SUSPENDED', child: Text('Suspended')),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Refresh button
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? AppTheme.darkTextSub
                      : AppTheme.lightTextSub,
                  side: BorderSide(
                      color: isDark
                          ? AppTheme.darkBorder
                          : AppTheme.lightBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                onPressed: _loading ? null : _loadAll,
              ),
              const SizedBox(width: 10),

              // Add Employee button (gradient)
              _GradientButton(
                label: 'Add Employee',
                icon: Icons.person_add_rounded,
                loading: false,
                onPressed: _showAddEmployeeDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Error banner ───────────────────────────────────────────────────
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.brandDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.brandDanger.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.brandDanger, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppTheme.brandDanger, fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 16, color: AppTheme.brandDanger),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

          // ── Table card ─────────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isDark
                        ? AppTheme.darkBorder
                        : AppTheme.lightBorder),
              ),
              child: Column(
                children: [
                  // Column headers
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.darkCard2
                          : AppTheme.lightElevated,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13)),
                      border: Border(
                        bottom: BorderSide(
                            color: isDark
                                ? AppTheme.darkBorder
                                : AppTheme.lightBorder),
                      ),
                    ),
                    child: Row(children: [
                      _ColHeader('Code', flex: 2, isDark: isDark),
                      _ColHeader('Full Name', flex: 3, isDark: isDark),
                      _ColHeader('Department', flex: 3, isDark: isDark),
                      _ColHeader('Roles', flex: 3, isDark: isDark),
                      _ColHeader('Status', flex: 2, isDark: isDark),
                      _ColHeader('Login Account', flex: 3, isDark: isDark),
                      _ColHeader('Actions', flex: 3, isDark: isDark, align: TextAlign.center),
                    ]),
                  ),

                  // Body
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? _EmptyState(
                                isDark: isDark,
                                hasSearch: _search.isNotEmpty,
                                onAdd: _showAddEmployeeDialog,
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (ctx, i) {
                                  final emp = filtered[i];
                                  return _EmployeeRow(
                                    emp: emp,
                                    isDark: isDark,
                                    isEven: i.isEven,
                                    statusBadge: _statusBadge(
                                        emp['employmentStatus']
                                            as String?),
                                    onView: () =>
                                        _showViewProfileDialog(emp),
                                    onEdit: () =>
                                        _showEditEmployeeDialog(emp),
                                    onResetPassword: () =>
                                        _showResetPasswordDialog(emp),
                                    onManageRoles: () =>
                                        _showManageRolesDialog(emp),
                                    onStatusTap: (btnCtx) =>
                                        _showStatusMenu(btnCtx, emp),
                                    onDelete: () =>
                                        _showDeleteConfirmDialog(emp),
                                  );
                                },
                              ),
                  ),

                  // Footer
                  if (!_loading && _employees.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: isDark
                                    ? AppTheme.darkBorder
                                    : AppTheme.lightBorder)),
                      ),
                      child: Row(children: [
                        Text(
                          'Showing ${filtered.length} of ${_employees.length} employee${_employees.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted,
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

  // ── Delete employee confirmation ────────────────────────────────────────────
  Future<void> _showDeleteConfirmDialog(Map<String, dynamic> emp) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.statusAbsent, size: 22),
          const SizedBox(width: 10),
          Text('Delete Employee', style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Delete "$name" (${emp['employeeCode'] ?? ''})? This also removes their login account. This action cannot be undone.',
          style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.statusAbsent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final token = ref.read(authProvider).accessToken ?? '';
      final res = await http.delete(
        Uri.parse('$_base/employees/${emp['id']}'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      );
      final rb = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && rb['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Employee deleted'), backgroundColor: AppTheme.statusPresent));
        _loadAll();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(rb['error']?['message'] ?? 'Delete failed'), backgroundColor: AppTheme.statusAbsent));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.statusAbsent));
    }
  }
}

// ============================================================================
// EMPLOYEE TABLE ROW
// ============================================================================

class _EmployeeRow extends StatefulWidget {
  final Map<String, dynamic> emp;
  final bool isDark;
  final bool isEven;
  final Widget statusBadge;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onManageRoles;
  final void Function(BuildContext) onStatusTap;
  final VoidCallback onDelete;

  const _EmployeeRow({
    required this.emp,
    required this.isDark,
    required this.isEven,
    required this.statusBadge,
    required this.onView,
    required this.onEdit,
    required this.onResetPassword,
    required this.onManageRoles,
    required this.onStatusTap,
    required this.onDelete,
  });

  @override
  State<_EmployeeRow> createState() => _EmployeeRowState();
}

class _EmployeeRowState extends State<_EmployeeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final emp = widget.emp;
    final isDark = widget.isDark;

    final Color rowBg;
    if (_hovered) {
      rowBg = isDark
          ? const Color(0xFF1A2B47)
          : const Color(0xFFEDF2FB);
    } else if (widget.isEven) {
      rowBg = isDark ? AppTheme.darkCard : Colors.white;
    } else {
      rowBg = isDark
          ? const Color(0xFF0F1A2E)
          : const Color(0xFFF7FAFF);
    }

    final fullName =
        '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.trim();
    final deptName = emp['departmentName'] as String?;
    final roleNames = emp['roleNames'] as String?;
    final username = emp['username'] as String?;
    final email = emp['email'] as String?;
    final hasAccount = username != null && username.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            bottom: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Code
            Expanded(
              flex: 2,
              child: Text(
                emp['employeeCode'] as String? ?? '—',
                style: TextStyle(
                  color:
                      isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Full Name
            Expanded(
              flex: 3,
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      fullName.isNotEmpty
                          ? fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
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
                        fullName.isNotEmpty ? fullName : '—',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkText
                              : AppTheme.lightText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((emp['designation'] as String?)?.isNotEmpty == true)
                        Text(
                          emp['designation'] as String,
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ]),
            ),

            // Department
            Expanded(
              flex: 3,
              child: deptName != null && deptName.isNotEmpty
                  ? Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          deptName,
                          style: TextStyle(
                            color: isDark
                                ? AppTheme.darkTextSub
                                : AppTheme.lightTextSub,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ])
                  : Text(
                      '—',
                      style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextMuted
                              : AppTheme.lightTextMuted,
                          fontSize: 13),
                    ),
            ),

            // Roles
            Expanded(
              flex: 3,
              child: roleNames != null && roleNames.isNotEmpty
                  ? Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: roleNames.split(', ').map((r) {
                        Color rc;
                        switch (r.toLowerCase()) {
                          case 'admin':   rc = AppTheme.roleAdmin;    break;
                          case 'hr':      rc = AppTheme.roleHR;       break;
                          case 'manager': rc = AppTheme.roleManager;  break;
                          default:        rc = AppTheme.roleEmployee;
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: rc.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: rc.withOpacity(0.3)),
                          ),
                          child: Text(r, style: TextStyle(color: rc, fontSize: 11, fontWeight: FontWeight.w600)),
                        );
                      }).toList(),
                    )
                  : Text('—',
                      style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 13)),
            ),

            // Status
            Expanded(
              flex: 2,
              child: widget.statusBadge,
            ),

            // Login Account
            Expanded(
              flex: 3,
              child: hasAccount
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Icon(Icons.person_rounded,
                              size: 12,
                              color: isDark
                                  ? AppTheme.darkTextSub
                                  : AppTheme.lightTextSub),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              username,
                              style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                        if (email != null && email.isNotEmpty)
                          Text(
                            email,
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.lightTextMuted,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    )
                  : Text(
                      'No account',
                      style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextMuted
                              : AppTheme.lightTextMuted,
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
            ),

            // Actions
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionIconBtn(icon: Icons.remove_red_eye_rounded, color: AppTheme.brandInfo, tooltip: 'View Profile', onTap: widget.onView),
                  const SizedBox(width: 4),
                  _ActionIconBtn(icon: Icons.edit_rounded, color: AppTheme.accent, tooltip: 'Edit', onTap: widget.onEdit),
                  const SizedBox(width: 4),
                  _ActionIconBtn(icon: Icons.key_rounded, color: AppTheme.brandWarning, tooltip: 'Reset Password', onTap: widget.onResetPassword),
                  const SizedBox(width: 4),
                  // More actions popup
                  Builder(builder: (btnCtx) => GestureDetector(
                    onTap: () async {
                      final rect = (btnCtx.findRenderObject() as RenderBox?)
                          ?.localToGlobal(Offset.zero);
                      final chosen = await showMenu<String>(
                        context: btnCtx,
                        position: RelativeRect.fromLTRB(
                          rect?.dx ?? 0, (rect?.dy ?? 0) + 28, 0, 0),
                        color: widget.isDark ? AppTheme.darkCard2 : Colors.white,
                        items: [
                          PopupMenuItem(value: 'view',   child: Row(children: [Icon(Icons.remove_red_eye_rounded, size: 16, color: AppTheme.brandInfo), const SizedBox(width: 10), const Text('View Profile')])),
                          PopupMenuItem(value: 'roles',  child: Row(children: [Icon(Icons.shield_rounded, size: 16, color: AppTheme.accent), const SizedBox(width: 10), const Text('Manage Roles')])),
                          PopupMenuItem(value: 'status', child: Row(children: [Icon(Icons.manage_accounts_rounded, size: 16, color: AppTheme.brandSuccess), const SizedBox(width: 10), const Text('Change Status')])),
                          PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 16, color: AppTheme.statusAbsent), const SizedBox(width: 10), Text('Delete', style: TextStyle(color: AppTheme.statusAbsent))])),
                        ],
                      );
                      if (chosen == 'view')   widget.onView();
                      if (chosen == 'roles')  widget.onManageRoles();
                      if (chosen == 'status') widget.onStatusTap(btnCtx);
                      if (chosen == 'delete') widget.onDelete();
                    },
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: (widget.isDark ? AppTheme.darkInput : AppTheme.lightInput),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                      child: Icon(Icons.more_vert_rounded, size: 15, color: widget.isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SHARED SMALL WIDGETS
// ============================================================================

class _ColHeader extends StatelessWidget {
  final String label;
  final int flex;
  final bool isDark;
  final TextAlign align;

  const _ColHeader(this.label,
      {required this.flex,
      required this.isDark,
      this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        style: TextStyle(
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 13),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionDivider({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 14, decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(99))),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(
        color: isDark ? AppTheme.darkText : AppTheme.lightText,
        fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3,
      )),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
    ]);
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _FieldLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final bool isDark;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;

  const _StyledDropdown({
    required this.value,
    required this.isDark,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: isDark ? AppTheme.darkCard2 : Colors.white,
      style: TextStyle(
        color: isDark ? AppTheme.darkText : AppTheme.lightText,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            fontSize: 13),
      ),
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          size: 18),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onPressed;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: loading
            ? const LinearGradient(
                colors: [Color(0xFF1A6ED8), Color(0xFF3D94F7)])
            : AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 15, color: Colors.white),
        label: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: loading ? null : onPressed,
      ),
    );
  }
}

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              color: AppTheme.brandDanger, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppTheme.brandDanger, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final bool hasSearch;
  final VoidCallback onAdd;

  const _EmptyState({
    required this.isDark,
    required this.hasSearch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch
                ? Icons.search_off_rounded
                : Icons.people_outline_rounded,
            size: 48,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
          const SizedBox(height: 14),
          Text(
            hasSearch ? 'No employees match your search' : 'No employees yet',
            style: TextStyle(
              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasSearch
                ? 'Try adjusting your search terms'
                : 'Add your first employee to get started',
            style: TextStyle(
              color:
                  isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              fontSize: 13,
            ),
          ),
          if (!hasSearch) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.person_add_rounded, size: 15),
              label: const Text('Add Employee'),
              onPressed: onAdd,
            ),
          ],
        ],
      ),
    );
  }
}

// Simple text field for the attendance edit dialog
class _AttField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final bool isDark;
  final bool number;
  const _AttField(this.label, this.ctrl, this.isDark, {this.number = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : TextInputType.datetime,
      style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: number ? 'Minutes' : 'YYYY-MM-DD HH:MM:SS',
        filled: true,
        fillColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        labelStyle: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12),
        hintStyle: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 12),
      ),
    );
  }
}
