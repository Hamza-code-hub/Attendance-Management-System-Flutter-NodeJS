import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'dashboard_provider.dart';

class AttendanceMonitorScreen extends ConsumerStatefulWidget {
  const AttendanceMonitorScreen({super.key});

  @override
  ConsumerState<AttendanceMonitorScreen> createState() => _AttendanceMonitorScreenState();
}

class _AttendanceMonitorScreenState extends ConsumerState<AttendanceMonitorScreen> {
  DateTime _date = DateTime.now();
  String _statusFilter = '';
  int? _deptFilter;
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  String? _error;

  final List<String> _statuses = ['', 'ON_TIME', 'EARLY', 'LATE', 'MISSED_CHECKOUT', 'PRESENT'];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final res = await ref.read(dashboardProvider.notifier).fetchDepartments();
      if (mounted) setState(() => _departments = res);
    } catch (_) {}
  }

  Future<void> _load({int page = 1}) async {
    setState(() { _loading = true; _error = null; _page = page; });
    try {
      final result = await ref.read(dashboardProvider.notifier).fetchAttendanceMonitor(
        date: DateFormat('yyyy-MM-dd').format(_date),
        status: _statusFilter.isEmpty ? null : _statusFilter,
        departmentId: _deptFilter,
        page: page,
      );
      setState(() {
        _rows = result.data;
        _total = result.total;
        _loading = false;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalPages = (_total / 25).ceil().clamp(1, 999);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance Monitor', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Real-time employee attendance for ${DateFormat('EEEE, MMM dd').format(_date)}',
                      style: theme.textTheme.bodyMedium),
                ],
              )),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(DateFormat('MMM dd, yyyy').format(_date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) { setState(() => _date = picked); _load(); }
                },
              ),
            ]),
            const SizedBox(height: 16),

            // Filters Row
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Status filter
                _FilterDrop<String>(
                  value: _statusFilter,
                  hint: 'All Statuses',
                  items: _statuses.map((s) => DropdownMenuItem(
                    value: s,
                    child: Row(children: [
                      if (s.isNotEmpty) ...[
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _statusDotColor(s), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                      ],
                      Text(s.isEmpty ? 'All Statuses' : s.replaceAll('_', ' ')),
                    ]),
                  )).toList(),
                  onChanged: (v) { setState(() => _statusFilter = v ?? ''); _load(); },
                  isDark: isDark,
                ),
                // Department filter
                if (_departments.isNotEmpty)
                  _FilterDrop<int?>(
                    value: _deptFilter,
                    hint: 'All Departments',
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All Departments')),
                      ..._departments.map((d) => DropdownMenuItem<int?>(
                        value: d['id'] as int?,
                        child: Text(d['department_name'] as String? ?? ''),
                      )),
                    ],
                    onChanged: (v) { setState(() => _deptFilter = v); _load(); },
                    isDark: isDark,
                  ),
                Text('$_total records',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () => _load(page: _page),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Error
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.brandDanger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
                ),
                child: Text(_error!, style: TextStyle(color: AppTheme.brandDanger)),
              ),

            // Table
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? _EmptyState(message: 'No attendance records for selected date/filter')
                      : Column(children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildTable(theme, isDark),
                              ),
                            ),
                          ),
                          _Pagination(page: _page, totalPages: totalPages, onPage: (p) => _load(page: p)),
                        ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ThemeData theme, bool isDark) {
    return DataTable(
      columnSpacing: 20,
      headingRowHeight: 42,
      dataRowMinHeight: 52,
      dataRowMaxHeight: 60,
      columns: const [
        DataColumn(label: Text('EMPLOYEE')),
        DataColumn(label: Text('DEPT')),
        DataColumn(label: Text('SHIFT')),
        DataColumn(label: Text('CHECK IN')),
        DataColumn(label: Text('CHECK OUT')),
        DataColumn(label: Text('WORKED')),
        DataColumn(label: Text('BREAKS')),
        DataColumn(label: Text('STATUS')),
      ],
      rows: _rows.map((r) {
        final status = r['status']?.toString() ?? '';
        return DataRow(cells: [
          DataCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r['employee_name'] ?? '', style: theme.textTheme.labelLarge),
              Text(r['employee_code'] ?? '', style: theme.textTheme.bodySmall),
            ],
          )),
          DataCell(Text(r['department_name'] ?? '—', style: theme.textTheme.bodyMedium)),
          DataCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r['shift_name'] ?? '—', style: theme.textTheme.bodyMedium),
              Text('${r['shift_start'] ?? ''}–${r['shift_end'] ?? ''}', style: theme.textTheme.bodySmall),
            ],
          )),
          DataCell(Text(_fmtTime(r['check_in_time']?.toString()),
              style: const TextStyle(fontWeight: FontWeight.w500))),
          DataCell(Text(_fmtTime(r['check_out_time']?.toString()),
              style: TextStyle(color: r['check_out_time'] == null ? AppTheme.statusLate : null))),
          DataCell(Text(_fmtMins(r['total_worked_minutes']))),
          DataCell(Text(_fmtBreaks(r['break_count'], r['total_break_minutes'], r['total_worked_minutes']))),
          DataCell(_StatusChip(status: status)),
        ]);
      }).toList(),
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) { return iso; }
  }

  String _fmtMins(dynamic mins) {
    if (mins == null) return '—';
    final m = int.tryParse(mins.toString()) ?? 0;
    if (m == 0) return '—';
    final h = m ~/ 60;
    final rem = m % 60;
    return h > 0 ? '${h}h ${rem}m' : '${rem}m';
  }

  String _fmtBreaks(dynamic count, dynamic breakMins, dynamic workedMins) {
    final c = int.tryParse(count?.toString() ?? '0') ?? 0;
    if (c == 0) return '0 (—)';
    final bm = int.tryParse(breakMins?.toString() ?? '0') ?? 0;
    final wm = int.tryParse(workedMins?.toString() ?? '0') ?? 0;
    // Sanity check: break can't exceed worked time (data corruption guard)
    final safeBm = (wm > 0 && bm > wm * 2) ? 0 : bm;
    return '$c (${_fmtMins(safeBm)})';
  }

  Color _statusDotColor(String s) {
    switch (s) {
      case 'ON_TIME':  return AppTheme.statusPresent;
      case 'EARLY':    return AppTheme.accent;
      case 'LATE':     return AppTheme.statusLate;
      case 'MISSED_CHECKOUT': return AppTheme.statusAbsent;
      default:         return AppTheme.darkTextMuted;
    }
  }
}

// ── Styled filter dropdown ────────────────────────────────────────────────────

class _FilterDrop<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final bool isDark;
  const _FilterDrop({required this.value, required this.hint, required this.items,
      required this.onChanged, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
          dropdownColor: isDark ? AppTheme.darkCard2 : Colors.white,
          style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 13),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Shift Monitor Screen ──────────────────────────────────────────────────

class ShiftMonitorScreen extends ConsumerStatefulWidget {
  const ShiftMonitorScreen({super.key});

  @override
  ConsumerState<ShiftMonitorScreen> createState() => _ShiftMonitorScreenState();
}

class _ShiftMonitorScreenState extends ConsumerState<ShiftMonitorScreen> {
  List<Map<String, dynamic>> _shifts = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ref.read(dashboardProvider.notifier).fetchShiftMonitor();
      setState(() { _shifts = data; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shift Monitor', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Today\'s shift-wise attendance breakdown', style: theme.textTheme.bodyMedium),
                ],
              )),
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _load),
            ]),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.brandDanger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: AppTheme.brandDanger)),
              ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_shifts.isEmpty)
              Expanded(child: _EmptyState(message: 'No active shifts configured'))
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: _shifts.length,
                  itemBuilder: (ctx, i) => _ShiftCard(shift: _shifts[i], isDark: isDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final Map<String, dynamic> shift;
  final bool isDark;
  const _ShiftCard({required this.shift, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = (shift['total_employees'] ?? 0) as int;
    final present = (shift['present_today'] ?? 0) as int;
    final late = (shift['late_today'] ?? 0) as int;
    final checkedOut = (shift['checked_out_today'] ?? 0) as int;
    final pct = total == 0 ? 0.0 : (present / total).clamp(0.0, 1.0);
    final isNight = (shift['night_shift_enabled'] ?? 0) == 1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isNight ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
              size: 18,
              color: isNight ? AppTheme.brandInfo : AppTheme.brandWarning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(shift['shift_name'] ?? '', style: theme.textTheme.titleMedium),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${shift['shift_start'] ?? ''} – ${shift['shift_end'] ?? ''}  •  ${shift['grace_minutes'] ?? 0}m grace',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: isDark ? AppTheme.darkSurface2 : AppTheme.lightBg,
            color: AppTheme.statusPresent,
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ShiftStat('Total', total, isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
              _ShiftStat('Present', present, AppTheme.statusPresent),
              _ShiftStat('Late', late, AppTheme.statusLate),
              _ShiftStat('Out', checkedOut, isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShiftStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _ShiftStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('$value', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 18)),
      const SizedBox(height: 2),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

// ── Shared ────────────────────────────────────────────────────────────────

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

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final void Function(int) onPage;
  const _Pagination({required this.page, required this.totalPages, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Page $page of $totalPages', style: theme.textTheme.bodySmall),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 1 ? () => onPage(page - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: page < totalPages ? () => onPage(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: AppTheme.lightTextMuted),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
