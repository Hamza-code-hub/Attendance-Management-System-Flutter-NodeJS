import 'dart:convert';
import '../../core/config/server_config.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/file_saver.dart';
import '../../features/authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabs;

  final List<_ReportDef> _reportTypes = const [
    _ReportDef(key: 'attendance', label: 'Attendance', icon: Icons.fingerprint_rounded),
    _ReportDef(key: 'overtime', label: 'Overtime', icon: Icons.more_time_rounded),
    _ReportDef(key: 'adjustment', label: 'Adjustments', icon: Icons.edit_calendar_rounded),
    _ReportDef(key: 'late', label: 'Late Arrivals', icon: Icons.timer_off_rounded),
    _ReportDef(key: 'break', label: 'Breaks', icon: Icons.coffee_rounded),
  ];

  // Monthly sheet tab is tab index 5 (after the 5 existing)
  static const int _monthlyTabIndex = 5;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _reportTypes.length + 1, vsync: this);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reports & Exports',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('Generate and download attendance reports',
                  style: theme.textTheme.bodyMedium),
              ]),
            ]),
          ),

          const SizedBox(height: 16),

          // Tab Bar
          Container(
            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              indicatorColor: theme.colorScheme.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                ..._reportTypes.map((r) => Tab(icon: Icon(r.icon, size: 17), text: r.label)),
                // Monthly Sheet tab — highlighted
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.table_chart_rounded, size: 17),
                    const SizedBox(width: 6),
                    const Text('Monthly Sheet'),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                      ),
                      child: const Text('NEW', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                    ),
                  ]),
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ..._reportTypes.map((r) => _ReportTab(reportType: r)),
                const _MonthlySheetTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportDef {
  final String key;
  final String label;
  final IconData icon;
  const _ReportDef({required this.key, required this.label, required this.icon});
}

// ── Report Tab ────────────────────────────────────────────────────────────

class _ReportTab extends ConsumerStatefulWidget {
  final _ReportDef reportType;
  const _ReportTab({required this.reportType});

  @override
  ConsumerState<_ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends ConsumerState<_ReportTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String _statusFilter = '';
  String? _selectedDeptId;
  String _selectedDeptName = 'All Departments';
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await http.get(
        Uri.parse('$_base/settings/departments'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) setState(() => _departments = List<Map<String, dynamic>>.from(body['data'] ?? []));
      }
    } catch (_) {}
  }

  String get _token => ref.read(authProvider).accessToken ?? '';

  Map<String, String> get _headers =>
      {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'};

  Future<void> _load({int page = 1}) async {
    setState(() { _loading = true; _error = null; _page = page; });
    try {
      final params = _buildParams(page: page);
      final uri = Uri.parse('$_base/reports/${widget.reportType.key}').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(body['data'] ?? []);
          _total = (body['total'] ?? 0) as int;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = body['error']?['message'] ?? 'Failed to load report';
        });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _export(String format) async {
    setState(() { _exporting = true; _error = null; });
    try {
      final params = _buildParams();
      params['format'] = format;
      final uri = Uri.parse('$_base/reports/${widget.reportType.key}/export')
          .replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final contentDisp = res.headers['content-disposition'] ?? '';
        final deptSuffix = _selectedDeptId != null ? '_${_selectedDeptName.replaceAll(' ', '_')}' : '';
        String filename = '${widget.reportType.key}${deptSuffix}_report.$format';
        final match = RegExp(r'filename="([^"]+)"').firstMatch(contentDisp);
        if (match != null) filename = match.group(1)!.replaceAll('.', '${deptSuffix}.');

        await saveFile(Uint8List.fromList(res.bodyBytes), filename);

        if (mounted) {
          final msg = kIsWeb
              ? 'Downloaded: $filename'
              : 'Saved to Documents: $filename';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppTheme.statusPresent),
          );
        }
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _error = body['error']?['message'] ?? 'Export failed (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _exporting = false);
    }
  }

  Map<String, String> _buildParams({int? page}) {
    final params = <String, String>{
      'dateFrom': DateFormat('yyyy-MM-dd').format(_from),
      'dateTo': DateFormat('yyyy-MM-dd').format(_to),
      'page': '${page ?? _page}',
      'limit': '50',
    };
    if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
    if (_selectedDeptId != null) params['departmentId'] = _selectedDeptId!;
    return params;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalPages = (_total / 50).ceil().clamp(1, 999);
    final roles = ref.watch(authProvider).user?.roles ?? [];
    final canExport = !roles.contains('Manager');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report Filters', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // From date
                    _DateButton(
                      label: 'From: ${DateFormat('MMM dd, yyyy').format(_from)}',
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: _from,
                            firstDate: DateTime(2024), lastDate: DateTime.now());
                        if (d != null) setState(() => _from = d);
                      },
                    ),
                    // To date
                    _DateButton(
                      label: 'To: ${DateFormat('MMM dd, yyyy').format(_to)}',
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: _to,
                            firstDate: DateTime(2024), lastDate: DateTime.now());
                        if (d != null) setState(() => _to = d);
                      },
                    ),
                    // Department filter (for all report types)
                    if (_departments.isNotEmpty)
                      DropdownButton<String?>(
                        value: _selectedDeptId,
                        hint: const Text('All Departments'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Departments')),
                          ..._departments.map((d) => DropdownMenuItem(
                            value: '${d['id']}',
                            child: Text('${d['department_name']}'),
                          )),
                        ],
                        onChanged: (v) => setState(() {
                          _selectedDeptId = v;
                          _selectedDeptName = v == null
                              ? 'All Departments'
                              : _departments.firstWhere((d) => '${d['id']}' == v)['department_name'] as String;
                        }),
                      ),
                    // Status filter (for attendance/late)
                    if (widget.reportType.key == 'attendance')
                      DropdownButton<String>(
                        value: _statusFilter,
                        hint: const Text('All Statuses'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All Statuses')),
                          DropdownMenuItem(value: 'ON_TIME', child: Text('On Time')),
                          DropdownMenuItem(value: 'LATE', child: Text('Late')),
                          DropdownMenuItem(value: 'MISSED_CHECKOUT', child: Text('Missed Checkout')),
                        ],
                        onChanged: (v) => setState(() => _statusFilter = v ?? ''),
                      ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Load Report'),
                      onPressed: _loading ? null : () => _load(page: 1),
                    ),
                    const SizedBox(width: 8),
                    // Export Buttons — restricted to HR and Admin
                    if (canExport) ...[
                      OutlinedButton.icon(
                        icon: _exporting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Excel'),
                        onPressed: _exporting ? null : () => _export('excel'),
                      ),
                      OutlinedButton.icon(
                        icon: _exporting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 16),
                        label: const Text('CSV'),
                        onPressed: _exporting ? null : () => _export('csv'),
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.25)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline, size: 14, color: Colors.amber),
                            SizedBox(width: 6),
                            Text(
                              'Exports are restricted to HR and Admin users.',
                              style: TextStyle(color: Colors.amber, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.brandDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: AppTheme.brandDanger, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: AppTheme.brandDanger, fontSize: 13))),
              ]),
            ),

          // Results info
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text('$_total record(s) total', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('Showing page $_page of $totalPages', style: theme.textTheme.bodySmall),
              ]),
            ),

          // Table
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.table_chart_outlined, size: 64, color: theme.colorScheme.primary.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text('Apply filters and click "Load Report" to view data', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      )
                    : Column(children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _ReportTable(rows: _rows, type: widget.reportType.key),
                            ),
                          ),
                        ),
                        _PaginationRow(page: _page, totalPages: totalPages, onPage: (p) => _load(page: p)),
                      ]),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_outlined, size: 15),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

// ── Dynamic Report Table ──────────────────────────────────────────────────

class _ReportTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String type;
  const _ReportTable({required this.rows, required this.type});

  List<_Col> get _columns {
    final base = [
      _Col('employee_code', 'CODE', 100),
      _Col('employee_name', 'EMPLOYEE', 160),
      _Col('designation', 'DESIGNATION', 140),
      _Col('department_name', 'DEPARTMENT', 140),
    ];
    switch (type) {
      case 'attendance':
      case 'late':
        return [...base,
          _Col('date', 'DATE', 100),
          _Col('check_in_time', 'CHECK IN', 110),
          _Col('check_out_time', 'CHECK OUT', 110),
          _Col('status', 'STATUS', 130),
          _Col('total_worked_minutes', 'WORKED', 90),
          _Col('total_break_minutes', 'BREAKS', 80),
          _Col('shift_name', 'SHIFT', 150),
        ];
      case 'overtime':
        return [...base,
          _Col('request_date', 'DATE', 100),
          _Col('requested_minutes', 'REQUESTED', 100),
          _Col('approved_minutes', 'APPROVED', 100),
          _Col('status', 'STATUS', 110),
          _Col('reason', 'REASON', 200),
          _Col('hr_comment', 'HR COMMENT', 200),
        ];
      case 'adjustment':
        return [...base,
          _Col('adjustment_type', 'TYPE', 150),
          _Col('requested_checkin_time', 'REQ CHECK-IN', 120),
          _Col('requested_checkout_time', 'REQ CHECK-OUT', 120),
          _Col('status', 'STATUS', 110),
          _Col('reason', 'REASON', 200),
        ];
      case 'break':
        return [...base,
          _Col('date', 'DATE', 100),
          _Col('break_start', 'BREAK START', 110),
          _Col('break_end', 'BREAK END', 110),
          _Col('duration_minutes', 'DURATION', 90),
          _Col('shift_name', 'SHIFT', 150),
        ];
      default: return base;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DataTable(
      columnSpacing: 16,
      headingRowHeight: 40,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 56,
      columns: _columns.map((c) => DataColumn(
        label: SizedBox(width: c.width - 16, child: Text(c.header, overflow: TextOverflow.ellipsis)),
      )).toList(),
      rows: rows.map((r) => DataRow(
        cells: _columns.map((c) {
          final val = r[c.key];
          final display = _format(c.key, val);
          if (c.key == 'status') {
            return DataCell(_StatusChip(status: val?.toString() ?? ''));
          }
          return DataCell(SizedBox(
            width: c.width - 16,
            child: Text(display, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
          ));
        }).toList(),
      )).toList(),
    );
  }

  String _format(String key, dynamic val) {
    if (val == null) return '—';
    final s = val.toString();
    if (s.isEmpty) return '—';
    if (key.endsWith('_time') || key == 'date') {
      try {
        final dt = DateTime.parse(s).toLocal();
        if (key == 'date') return DateFormat('MMM dd, yyyy').format(dt);
        return DateFormat('MMM dd, hh:mm a').format(dt);
      } catch (_) { return s; }
    }
    if (key.endsWith('_minutes')) {
      final m = int.tryParse(s) ?? 0;
      final h = m ~/ 60;
      final rem = m % 60;
      return h > 0 ? '${h}h ${rem}m' : '${rem}m';
    }
    return s.replaceAll('_', ' ');
  }
}

class _Col {
  final String key;
  final String header;
  final double width;
  const _Col(this.key, this.header, this.width);
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PaginationRow extends StatelessWidget {
  final int page;
  final int totalPages;
  final void Function(int) onPage;
  const _PaginationRow({required this.page, required this.totalPages, required this.onPage});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Page $page of $totalPages', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: page > 1 ? () => onPage(page - 1) : null),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: page < totalPages ? () => onPage(page + 1) : null),
        ],
      ),
    );
  }
}

// ============================================================================
// MONTHLY ATTENDANCE SHEET TAB
// Downloads matrix Excel: employee rows × day columns (merged date headers)
// ============================================================================

class _MonthlySheetTab extends ConsumerStatefulWidget {
  const _MonthlySheetTab();
  @override
  ConsumerState<_MonthlySheetTab> createState() => _MonthlySheetTabState();
}

class _MonthlySheetTabState extends ConsumerState<_MonthlySheetTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Default to current month
  late int _year;
  late int _month;
  String? _selectedDeptId;
  String _selectedDeptName = 'All Departments';
  List<Map<String, dynamic>> _departments = [];
  bool _exporting = false;
  String? _error;
  String? _success;

  String get _token => ref.read(authProvider).accessToken ?? '';
  Map<String, String> get _headers => {'Authorization': 'Bearer $_token'};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year  = now.year;
    _month = now.month;
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await http.get(Uri.parse('$_base/settings/departments'), headers: _headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) setState(() => _departments = List<Map<String, dynamic>>.from(body['data'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _download() async {
    setState(() { _exporting = true; _error = null; _success = null; });
    try {
      final monthStr = '$_year-${_month.toString().padLeft(2, '0')}';
      final params = <String, String>{'month': monthStr};
      if (_selectedDeptId != null) params['departmentId'] = _selectedDeptId!;

      final uri = Uri.parse('$_base/reports/monthly-matrix/export').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers);

      if (res.statusCode == 200) {
        final cd   = res.headers['content-disposition'] ?? '';
        final match = RegExp(r'filename="([^"]+)"').firstMatch(cd);
        final fname = match?.group(1) ?? 'attendance_matrix_$monthStr.xlsx';

        await saveFile(Uint8List.fromList(res.bodyBytes), fname);

        final msg = kIsWeb ? 'Downloaded: $fname' : 'Saved to Documents: $fname';
        setState(() => _success = msg);
      } else {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _error = body['error']?['message'] ?? 'Export failed (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _exporting = false);
    }
  }

  String get _monthLabel {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[_month - 1]} $_year';
  }

  void _prevMonth() => setState(() {
    if (_month == 1) { _month = 12; _year--; } else _month--;
  });

  void _nextMonth() {
    final now = DateTime.now();
    if (_year > now.year || (_year == now.year && _month >= now.month)) return;
    setState(() {
      if (_month == 12) { _month = 1; _year++; } else _month++;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roles = ref.watch(authProvider).user?.roles ?? [];
    final canExport = !roles.contains('Manager');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info banner ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.table_chart_rounded, color: AppTheme.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Monthly Attendance Sheet',
                  style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Text('Downloads an Excel workbook with one row per employee and one column pair per day (Check In + Check Out). Includes merged date headers and color-coded status rows.',
                  style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5)),
              ])),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Controls card ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Month & Department',
                  style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 16),

                // Month picker row
                Row(children: [
                  Text('Month:', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
                  const SizedBox(width: 12),
                  _iconBtn(Icons.chevron_left_rounded, isDark, _prevMonth),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                    ),
                    child: Text(_monthLabel,
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
                  ),
                  const SizedBox(width: 10),
                  _iconBtn(Icons.chevron_right_rounded, isDark, _nextMonth),
                ]),

                const SizedBox(height: 16),

                // Department dropdown
                if (_departments.isNotEmpty) ...[
                  Text('Department:', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: [
                      _deptChip(null, 'All Departments', isDark),
                      ..._departments.map((d) => _deptChip('${d['id']}', '${d['department_name']}', isDark)),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Divider
                Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                const SizedBox(height: 16),

                // Preview of what the Excel will look like
                _ExcelPreview(isDark: isDark),

                const SizedBox(height: 20),

                // Download button — restricted to HR and Admin
                if (canExport)
                  GestureDetector(
                    onTap: _exporting ? null : _download,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: _exporting ? null : AppTheme.primaryGradient,
                        color: _exporting ? (isDark ? AppTheme.darkInput : AppTheme.lightInput) : null,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _exporting ? null : [BoxShadow(color: AppTheme.accent.withOpacity(0.28), blurRadius: 16, offset: const Offset(0, 4))],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _exporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download_rounded, color: Color(0xFF0A1628), size: 18),
                        const SizedBox(width: 9),
                        Text(
                          _exporting ? 'Generating...' : 'Download Monthly Sheet  (Excel)',
                          style: const TextStyle(color: Color(0xFF0A1628), fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ]),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withOpacity(0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.amber),
                        SizedBox(width: 8),
                        Text(
                          'Exports are restricted to HR and Admin users.',
                          style: TextStyle(color: Colors.amber, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                // Status messages
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.statusAbsent.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.statusAbsent.withOpacity(0.2))),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: AppTheme.statusAbsent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.statusAbsent, fontSize: 13))),
                    ]),
                  ),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.statusPresent.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.statusPresent.withOpacity(0.2))),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded, color: AppTheme.statusPresent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_success!, style: const TextStyle(color: AppTheme.statusPresent, fontSize: 13))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, bool isDark, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Icon(icon, size: 20, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
    ),
  );

  Widget _deptChip(String? id, String label, bool isDark) {
    final isSelected = _selectedDeptId == id;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedDeptId = id;
        _selectedDeptName = label;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: isSelected ? AppTheme.accent.withOpacity(0.4) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
        ),
        child: Text(label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
            fontSize: 12.5, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          )),
      ),
    );
  }
}

// ── Visual preview of the Excel structure ────────────────────────────────────

class _ExcelPreview extends StatelessWidget {
  final bool isDark;
  const _ExcelPreview({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg   = isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated;
    final card = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Excel format preview:', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(8), border: Border.all(color: border)),
          child: Column(children: [
            // Title row mock
            Container(
              width: double.infinity, padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF0A1628), borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
              child: const Text('MONTHLY ATTENDANCE REPORT — MAY 2025', textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF3D94F7), fontWeight: FontWeight.w700, fontSize: 10)),
            ),
            // Header row mock
            Container(
              color: const Color(0xFF111D33),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _th('EMPLOYEE', 120),
                  _th('DEPT', 70),
                  _thDate('01 May\nMon'),
                  _thDate('02 May\nTue'),
                  _thDate('03 May\nWed'),
                  _th('···', 40),
                  _thSumm(),
                ]),
              ),
            ),
            // Sub-header row
            Container(
              color: const Color(0xFF0F1E38),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _sh('', 120), _sh('', 70),
                  _sh('Check In', 56, color: const Color(0xFF00D68F)),
                  _sh('Check Out', 56, color: const Color(0xFFFF4D6A)),
                  _sh('Check In', 56, color: const Color(0xFF00D68F)),
                  _sh('Check Out', 56, color: const Color(0xFFFF4D6A)),
                  _sh('Check In', 56, color: const Color(0xFF00D68F)),
                  _sh('Check Out', 56, color: const Color(0xFFFF4D6A)),
                  _sh('···', 40, color: const Color(0xFF4A6080)),
                  _sh('PRES', 42, color: const Color(0xFF00D68F)),
                  _sh('ABS', 42, color: const Color(0xFFFF4D6A)),
                  _sh('LATE', 42, color: const Color(0xFFFFB020)),
                  _sh('HRS', 48, color: const Color(0xFF3D94F7)),
                ]),
              ),
            ),
            // Data row mock
            ...[
              ('Ali Mughal', 'Engineering', '09:02', '18:05', '09:00', '18:00', '09:10', '18:03', '22', '1', '2', '176h', const Color(0xFF00D68F)),
              ('Sara Farooq', 'Design', '09:38', '—', '09:15', '18:00', 'ABS', '', '20', '3', '3', '158h', const Color(0xFFFFB020)),
            ].map((r) => Container(
              color: const Color(0xFF142036),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _td(r.$1, 120, bold: true),
                  _td(r.$2, 70),
                  _tdTime(r.$3, r.$7 == 'ABS' ? const Color(0xFF00D68F) : const Color(0xFF00D68F)),
                  _tdTime(r.$4, const Color(0xFF8BA3C7)),
                  _tdTime(r.$5, const Color(0xFF00D68F)),
                  _tdTime(r.$6, const Color(0xFF8BA3C7)),
                  _tdTime(r.$7, r.$7 == 'ABS' ? const Color(0xFFFF4D6A) : const Color(0xFF00D68F)),
                  _tdTime(r.$8, const Color(0xFF8BA3C7)),
                  _td('···', 40),
                  _tdNum(r.$9, const Color(0xFF00D68F)),
                  _tdNum(r.$10, r.$10 == '1' ? const Color(0xFFFF4D6A) : const Color(0xFF4A6080)),
                  _tdNum(r.$11, r.$11 == '3' ? const Color(0xFFFFB020) : const Color(0xFF4A6080)),
                  _tdNum(r.$12, const Color(0xFF3D94F7)),
                ]),
              ),
            )),
          ]),
        ),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.info_outline, size: 13, color: Color(0xFF4A6080)),
          const SizedBox(width: 5),
          Text('Weekends are dimmed · Green = On Time · Amber = Late · Red = Absent',
            style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 10.5)),
        ]),
      ],
    );
  }

  Widget _th(String t, double w) => Container(
    width: w, padding: const EdgeInsets.all(5),
    child: Text(t, style: const TextStyle(color: Color(0xFF3D94F7), fontWeight: FontWeight.w700, fontSize: 9), textAlign: TextAlign.center));

  Widget _thDate(String t) => Container(
    width: 72, padding: const EdgeInsets.all(5),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF152844)))),
    child: Text(t, style: const TextStyle(color: Color(0xFFEEF2FF), fontWeight: FontWeight.w700, fontSize: 8), textAlign: TextAlign.center));

  Widget _thSumm() => Container(
    width: 174, padding: const EdgeInsets.all(5),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0xFF1A6ED8), width: 2))),
    child: const Text('MONTHLY SUMMARY', style: TextStyle(color: Color(0xFF3D94F7), fontWeight: FontWeight.w700, fontSize: 9), textAlign: TextAlign.center));

  Widget _sh(String t, double w, {Color color = const Color(0xFF8BA3C7)}) => Container(
    width: w, padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(t, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 8), textAlign: TextAlign.center));

  Widget _td(String t, double w, {bool bold = false}) => Container(
    width: w, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: Text(t, style: TextStyle(color: const Color(0xFFEEF2FF), fontSize: 9, fontWeight: bold ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis));

  Widget _tdTime(String t, Color color) => Container(
    width: 56, padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(t, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w500), textAlign: TextAlign.center));

  Widget _tdNum(String t, Color color) => Container(
    width: 42, padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(t, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center));
}
