import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

// ============================================================================
// DEPARTMENTS SCREEN
// ============================================================================

class DepartmentsScreen extends ConsumerStatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  ConsumerState<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends ConsumerState<DepartmentsScreen> {
  List<Map<String, dynamic>> _departments = [];
  bool _loading = true;
  String? _error;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${ref.read(authProvider).accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(
        Uri.parse('$_base/settings/departments'),
        headers: _headers,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        final raw = body['data'];
        final List list = raw is List
            ? raw
            : (raw is Map && raw['departments'] is List)
                ? raw['departments'] as List
                : [];
        setState(() {
          _departments = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = (body['error'] as Map?)?['message'] as String? ?? 'Failed to load departments';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Add / Edit department ─────────────────────────────────────────────────

  Future<void> _showDepartmentDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['department_name'] as String? ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] as String? ?? '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    String? dialogError;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = existing != null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          title: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.corporate_fare_rounded, size: 17, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
            Text(
              isEdit ? 'Edit Department' : 'Add Department',
              style: TextStyle(
                color: isDark ? AppTheme.darkText : AppTheme.lightText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.brandDanger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: AppTheme.brandDanger, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: AppTheme.brandDanger, fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                  Text(
                    'Department Name *',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'e.g. Engineering',
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    ),
                    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Department name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Description',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: descCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Optional description',
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
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    ),
                    style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setS(() { saving = true; dialogError = null; });
                      try {
                        final payload = jsonEncode({
                          'department_name': nameCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                        });
                        final http.Response res;
                        if (isEdit) {
                          res = await http.put(
                            Uri.parse('$_base/settings/departments/${existing['id']}'),
                            headers: _headers,
                            body: payload,
                          );
                        } else {
                          res = await http.post(
                            Uri.parse('$_base/settings/departments'),
                            headers: _headers,
                            body: payload,
                          );
                        }
                        final rb = jsonDecode(res.body) as Map<String, dynamic>;
                        if ((res.statusCode == 200 || res.statusCode == 201) && rb['success'] == true) {
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } else {
                          setS(() {
                            saving = false;
                            dialogError = (rb['error'] as Map?)?['message'] as String? ??
                                (isEdit ? 'Failed to update department' : 'Failed to create department');
                          });
                        }
                      } catch (e) {
                        setS(() { saving = false; dialogError = e.toString(); });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? 'Save Changes' : 'Add Department'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    descCtrl.dispose();
    _load();
  }

  // ── Delete department ─────────────────────────────────────────────────────

  Future<void> _deleteDepartment(Map<String, dynamic> dept) async {
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.brandDanger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppTheme.brandDanger, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            'Delete Department',
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
        content: Text(
          'Are you sure you want to delete "${dept['department_name']}"? This action cannot be undone. Departments with assigned employees cannot be deleted.',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
            fontSize: 14,
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
        Uri.parse('$_base/settings/departments/${dept['id']}'),
        headers: _headers,
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        _load();
      } else {
        final msg = (body['error'] as Map?)?['message'] as String? ?? 'Failed to delete department';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppTheme.brandDanger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.brandDanger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Departments',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage organizational departments',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              // Refresh
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loading ? null : _load,
              ),
              const SizedBox(width: 10),
              // Add department
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Department'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showDepartmentDialog(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Error banner ───────────────────────────────────────────
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
                Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.brandDanger, fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.brandDanger),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

          // ── Table card ─────────────────────────────────────────────
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
                  // Table header row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      border: Border(
                        bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      ),
                    ),
                    child: Row(children: [
                      _colHeader('ID', flex: 1),
                      _colHeader('Department Name', flex: 3),
                      _colHeader('Description', flex: 5),
                      _colHeader('Employees', flex: 2),
                      _colHeader('Actions', flex: 2, align: TextAlign.center),
                    ]),
                  ),
                  // Body
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _departments.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.corporate_fare_rounded,
                                        size: 42, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No departments found',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    TextButton.icon(
                                      icon: const Icon(Icons.add, size: 15),
                                      label: const Text('Add your first department'),
                                      onPressed: () => _showDepartmentDialog(),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _departments.length,
                                itemBuilder: (context, index) {
                                  final dept = _departments[index];
                                  final isEven = index.isEven;
                                  return _DeptRow(
                                    dept: dept,
                                    isDark: isDark,
                                    isEven: isEven,
                                    onEdit: () => _showDepartmentDialog(existing: dept),
                                    onDelete: () => _deleteDepartment(dept),
                                  );
                                },
                              ),
                  ),
                  // Footer count
                  if (!_loading && _departments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                      ),
                      child: Text(
                        '${_departments.length} department${_departments.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String label, {int flex = 1, TextAlign align = TextAlign.left}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: align,
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

// ── Department table row ──────────────────────────────────────────────────────

class _DeptRow extends StatefulWidget {
  final Map<String, dynamic> dept;
  final bool isDark;
  final bool isEven;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DeptRow({
    required this.dept,
    required this.isDark,
    required this.isEven,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_DeptRow> createState() => _DeptRowState();
}

class _DeptRowState extends State<_DeptRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dept = widget.dept;
    final isDark = widget.isDark;

    Color rowBg;
    if (_hovered) {
      rowBg = isDark ? const Color(0xFF1A2B47) : const Color(0xFFEDF2FB);
    } else if (widget.isEven) {
      rowBg = isDark ? AppTheme.darkCard : Colors.white;
    } else {
      rowBg = isDark ? const Color(0xFF0F1A2E) : const Color(0xFFF7FAFF);
    }

    final empCount = dept['employee_count'] ?? dept['employeeCount'] ?? dept['totalEmployees'];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Row(
          children: [
            // ID
            Expanded(
              flex: 1,
              child: Text(
                '${dept['id'] ?? '—'}',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Name
            Expanded(
              flex: 3,
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.corporate_fare_rounded, size: 14, color: AppTheme.accent),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    dept['department_name'] as String? ?? '—',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            // Description
            Expanded(
              flex: 5,
              child: Text(
                (dept['description'] as String?)?.isNotEmpty == true
                    ? dept['description'] as String
                    : '—',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            // Employee count
            Expanded(
              flex: 2,
              child: empCount != null
                  ? Container(
                      width: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
                      ),
                      child: Text(
                        '$empCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text('—', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
            ),
            // Actions
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ActionBtn(
                    icon: Icons.edit_rounded,
                    color: AppTheme.accent,
                    tooltip: 'Edit',
                    onTap: widget.onEdit,
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    icon: Icons.delete_outline_rounded,
                    color: AppTheme.brandDanger,
                    tooltip: 'Delete',
                    onTap: widget.onDelete,
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionBtn({
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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
      ),
    );
  }
}
