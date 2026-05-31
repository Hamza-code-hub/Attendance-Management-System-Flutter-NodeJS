import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../dashboard/dashboard_provider.dart';
import '../authentication/presentation/auth_state.dart';
import '../attendance/presentation/attendance_state_provider.dart';
import '../../core/theme/app_theme.dart';

// ============================================================================
// MANAGER PORTAL — team-focused dashboard with department filter
// ============================================================================

class ManagerDashboardScreen extends ConsumerStatefulWidget {
  const ManagerDashboardScreen({super.key});
  @override
  ConsumerState<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends ConsumerState<ManagerDashboardScreen> {
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _approvals  = [];
  bool _loading = false;

  // Department filter — populated from attendance data
  String? _selectedDept;
  List<String> _depts = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final n = ref.read(dashboardProvider.notifier);
    await n.loadSummary();
    try {
      final results = await Future.wait([
        n.fetchAttendanceMonitor(),
        n.fetchPendingApprovals(),
      ]);
      if (mounted) {
        final allRows = results[0].data;
        // Extract unique departments
        final deptSet = <String>{};
        for (final r in allRows) {
          final d = _readString(r, ['departmentName', 'department_name']);
          if (d.isNotEmpty) deptSet.add(d);
        }
        setState(() {
          _attendance = allRows;
          _approvals  = results[1].data;
          _depts      = ['All Departments', ...deptSet.toList()..sort()];
          _selectedDept ??= 'All Departments';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_selectedDept == null || _selectedDept == 'All Departments') return _attendance;
    return _attendance.where((r) => _readString(r, ['departmentName', 'department_name']) == _selectedDept).toList();
  }

  // KPIs from filtered rows
  int get _presentCount => _filteredRows.where((r) => ['CHECKED_IN', 'BREAK_ACTIVE', 'CHECKED_OUT', 'LATE'].contains(r['status'])).length;
  int get _lateCount    => _filteredRows.where((r) => r['status'] == 'LATE').length;
  int get _breakCount   => _filteredRows.where((r) => r['status'] == 'BREAK_ACTIVE').length;
  int get _absentCount  => _filteredRows.where((r) => r['status'] == 'ABSENT').length;

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final dash    = ref.watch(dashboardProvider);
    final user    = ref.watch(authProvider).user;
    final name    = (user?.username ?? 'Manager').split(' ').first;

    final att = ref.watch(attendanceStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Personal attendance actions ────────────────────────────
          _PersonalAttendanceCard(att: att, isDark: isDark, ref: ref),
          const SizedBox(height: 18),

          // ── Gradient banner ────────────────────────────────────────
          _MgrBanner(name: name, isDark: isDark, summary: dash.summary, onRefresh: _load),
          const SizedBox(height: 18),

          // ── Department filter + team KPIs ──────────────────────────
          _DeptFilterBar(
            depts: _depts,
            selected: _selectedDept ?? 'All Departments',
            onChanged: (d) => setState(() => _selectedDept = d),
            isDark: isDark,
          ),
          const SizedBox(height: 14),

          // ── Team KPI strip (computed from filtered data) ────────────
          _TeamKpiRow(
            present: _presentCount, late: _lateCount,
            onBreak: _breakCount, absent: _absentCount,
            total: _filteredRows.length, isDark: isDark,
          ),
          const SizedBox(height: 18),

          // ── Two-column content ─────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              final teamTable = _MgrAttendanceTable(rows: _filteredRows, loading: _loading, isDark: isDark);
              final sidePanel = Column(children: [
                _MgrApprovalsCard(approvals: _approvals, loading: _loading, isDark: isDark),
                const SizedBox(height: 14),
                _MgrQuickLinks(isDark: isDark),
              ]);

              if (compact) {
                return Column(children: [
                  teamTable,
                  const SizedBox(height: 14),
                  sidePanel,
                ]);
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: teamTable),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: sidePanel),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _readString(Map<String, dynamic> row, List<String> keys, [String fallback = '']) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return fallback;
}

int _readInt(Map<String, dynamic> row, List<String> keys) {
  final value = keys.map((key) => row[key]).firstWhere((v) => v != null, orElse: () => 0);
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

// ── Manager banner ────────────────────────────────────────────────────────────

class _MgrBanner extends StatelessWidget {
  final String name;
  final bool isDark;
  final DashboardSummary? summary;
  final VoidCallback onRefresh;
  const _MgrBanner({required this.name, required this.isDark, required this.summary, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
            ? [const Color(0xFF1E1B4B), const Color(0xFF2D1B4E)]
            : [const Color(0xFF3730A3), const Color(0xFF6D28D9)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppTheme.roleManager.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.roleManager.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppTheme.roleManager.withOpacity(0.4)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.groups_rounded, size: 12, color: AppTheme.roleManager),
                      SizedBox(width: 5),
                      Text('Team Manager', style: TextStyle(color: AppTheme.roleManager, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onRefresh,
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.15))),
                      child: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text('Welcome back, $name',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text('Team overview — ${DateFormat('EEEE, d MMMM yyyy').format(DateTime.now())}',
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13)),
              ],
            ),
          ),
          if (summary != null) ...[
            const SizedBox(width: 24),
            _bstat('${summary!.totalActiveEmployees}', 'Total Staff'),
            const SizedBox(width: 24),
            _bstat('${summary!.presentCount}', 'Present Now'),
            const SizedBox(width: 24),
            _bstat('${summary!.totalPendingApprovals}', 'Awaiting Review'),
          ],
        ],
      ),
    );
  }

  Widget _bstat(String v, String l) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(v, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
      Text(l, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
    ],
  );
}

// ── Department filter bar ─────────────────────────────────────────────────────

class _DeptFilterBar extends StatelessWidget {
  final List<String> depts;
  final String selected;
  final ValueChanged<String> onChanged;
  final bool isDark;
  const _DeptFilterBar({required this.depts, required this.selected, required this.onChanged, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.filter_list_rounded, size: 16, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
        const SizedBox(width: 8),
        Text('Filter by Department:', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: depts.map((d) {
                final isSelected = d == selected;
                return GestureDetector(
                  onTap: () => onChanged(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.roleManager.withOpacity(0.12) : (isDark ? AppTheme.darkCard : Colors.white),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: isSelected ? AppTheme.roleManager.withOpacity(0.4) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
                    ),
                    child: Text(d,
                      style: TextStyle(
                        color: isSelected ? AppTheme.roleManager : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                        fontSize: 12.5, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      )),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Team KPI strip ────────────────────────────────────────────────────────────

class _TeamKpiRow extends StatelessWidget {
  final int present, late, onBreak, absent, total;
  final bool isDark;
  const _TeamKpiRow({required this.present, required this.late, required this.onBreak, required this.absent, required this.total, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final rate = total > 0 ? (present / total * 100).round() : 0;
    return Row(children: [
      _kpi('$present', 'Present', AppTheme.statusPresent, Icons.check_circle_rounded, isDark),
      const SizedBox(width: 10),
      _kpi('$late', 'Late', AppTheme.statusLate, Icons.schedule_rounded, isDark),
      const SizedBox(width: 10),
      _kpi('$onBreak', 'On Break', AppTheme.statusBreak, Icons.free_breakfast_rounded, isDark),
      const SizedBox(width: 10),
      _kpi('$absent', 'Absent', AppTheme.statusAbsent, Icons.person_off_rounded, isDark),
      const SizedBox(width: 10),
      // Attendance rate card
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
          child: Row(children: [
            SizedBox(
              width: 50, height: 50,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: rate / 100, strokeWidth: 5,
                  backgroundColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                  valueColor: AlwaysStoppedAnimation(rate >= 80 ? AppTheme.statusPresent : rate >= 60 ? AppTheme.statusLate : AppTheme.statusAbsent),
                ),
                Text('$rate%', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Team Rate', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5)),
              Text('$present / $total', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _kpi(String val, String label, Color color, IconData icon, bool isDark) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(val, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5)),
        ]),
      ]),
    ),
  );
}

// ── Team attendance table ─────────────────────────────────────────────────────

class _MgrAttendanceTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final bool loading, isDark;
  const _MgrAttendanceTable({required this.rows, required this.loading, required this.isDark});

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
              const Icon(Icons.groups_rounded, size: 15, color: AppTheme.roleManager),
              const SizedBox(width: 8),
              Text('My Team  (${rows.length} members)',
                style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/hr/attendance-monitor'),
                child: const Text('Full Monitor →', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
            child: Row(children: [
              _th('Member', 3, isDark), _th('Dept', 2, isDark),
              _th('Check In', 2, isDark), _th('Worked', 2, isDark), _th('Status', 2, isDark),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          if (loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Padding(padding: const EdgeInsets.all(20),
              child: Text('No team members found', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)))
          else
            ...rows.map((r) => _MgrRow(row: r, isDark: isDark)),
        ],
      ),
    );
  }

  Widget _th(String l, int flex, bool isDark) => Expanded(
    flex: flex,
    child: Text(l.toUpperCase(), style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
  );
}

class _MgrRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isDark;
  const _MgrRow({required this.row, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final name    = _readString(row, ['employeeName', 'employee_name'], '${row['firstName'] ?? ''} ${row['lastName'] ?? ''}'.trim());
    final dept    = _readString(row, ['departmentName', 'department_name'], '—');
    final status  = _readString(row, ['status']);
    final sc      = AppTheme.statusColor(status);
    final inT     = _ft(_readString(row, ['checkInTime', 'check_in_time']));
    final wm      = _readInt(row, ['totalWorkedMinutes', 'total_worked_minutes']);
    final worked  = wm > 0 ? '${wm ~/ 60}h ${wm % 60}m' : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Row(children: [
        Expanded(flex: 3, child: Row(children: [
          _MiniAvatar(name: name, color: sc),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w500, fontSize: 13), overflow: TextOverflow.ellipsis)),
        ])),
        Expanded(flex: 2, child: Text(dept, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12.5))),
        Expanded(flex: 2, child: Text(inT, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppTheme.accent))),
        Expanded(flex: 2, child: Text(worked, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 12.5))),
        Expanded(flex: 2, child: AppTheme.statusBadge(_sl(status), sc, fontSize: 10.5)),
      ]),
    );
  }

  String _ft(String? dt) {
    if (dt == null || dt.isEmpty) return '—';
    try { return DateFormat('hh:mm a').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return '—'; }
  }

  String _sl(String s) {
    const m = {'CHECKED_IN': 'Active', 'BREAK_ACTIVE': 'Break', 'CHECKED_OUT': 'Done', 'LATE': 'Late', 'ABSENT': 'Absent', 'MISSED_CHECKOUT': 'No Out'};
    return m[s] ?? s;
  }
}

class _MiniAvatar extends StatelessWidget {
  final String name;
  final Color color;
  const _MiniAvatar({required this.name, required this.color});
  @override
  Widget build(BuildContext context) {
    final init = name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle),
      child: Center(child: Text(init, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
    );
  }
}

// ── Pending approvals ─────────────────────────────────────────────────────────

class _MgrApprovalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> approvals;
  final bool loading, isDark;
  const _MgrApprovalsCard({required this.approvals, required this.loading, required this.isDark});

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
              const Icon(Icons.inbox_rounded, size: 15, color: AppTheme.accent),
              const SizedBox(width: 8),
              Text('Pending Approvals',
                style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 6),
              if (approvals.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.statusAbsent, borderRadius: BorderRadius.circular(99)),
                  child: Text('${approvals.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/hr/approvals'),
                child: const Text('Manage →', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

          if (loading)
            const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
          else if (approvals.isEmpty)
            Padding(padding: const EdgeInsets.all(18),
              child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: AppTheme.statusPresent, size: 22),
                const SizedBox(width: 10),
                Text('All clear — no pending requests', style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
              ]))
          else
            ...approvals.take(5).map((a) {
              final type = _readString(a, ['requestType', 'type']);
              final name = _readString(a, ['employeeName', 'employee_name'], '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim());
              final date = _readString(a, ['requestDate', 'request_date', 'date']);
              final isOT = type.toUpperCase().contains('OT') || type.toUpperCase().contains('OVER');
              final color = isOT ? AppTheme.accent : AppTheme.accent2;

              return Container(
                padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder))),
                child: Row(children: [
                  Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(isOT ? Icons.more_time_rounded : Icons.edit_calendar_rounded, color: color, size: 14)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isNotEmpty ? name : 'Employee', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w500, fontSize: 13), overflow: TextOverflow.ellipsis),
                    Text('${isOT ? 'Overtime' : 'Adjustment'} · $date', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5)),
                  ])),
                  AppTheme.statusBadge('Pending', AppTheme.statusPending, fontSize: 10),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

// ── Quick links ───────────────────────────────────────────────────────────────

class _MgrQuickLinks extends StatelessWidget {
  final bool isDark;
  const _MgrQuickLinks({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final links = [
      ('Approval Center', Icons.fact_check_rounded, AppTheme.statusPresent, '/hr/approvals'),
      ('Attendance Monitor', Icons.monitor_rounded, AppTheme.accent, '/hr/attendance-monitor'),
      ('My Overtime Requests', Icons.more_time_rounded, AppTheme.statusLate, '/employee/overtime'),
      ('Reports & Exports', Icons.bar_chart_rounded, AppTheme.statusBreak, '/hr/reports'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('Quick Actions',
              style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          ...links.map((l) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => context.go(l.$4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: l.$3.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: l.$3.withOpacity(0.16)),
                ),
                child: Row(children: [
                  Icon(l.$2, color: l.$3, size: 15),
                  const SizedBox(width: 9),
                  Text(l.$1, style: TextStyle(color: l.$3, fontWeight: FontWeight.w500, fontSize: 12.5)),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded, color: l.$3.withOpacity(0.5), size: 11),
                ]),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Personal Attendance Card — shows today's check-in status and action buttons.
// Reused by both Manager and HR dashboards.
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalAttendanceCard extends StatelessWidget {
  final TodayAttendanceState att;
  final bool isDark;
  final WidgetRef ref;

  const _PersonalAttendanceCard({
    required this.att,
    required this.isDark,
    required this.ref,
  });

  void _snack(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.statusAbsent : AppTheme.statusPresent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cardColor  = isDark ? AppTheme.darkCard : Colors.white;
    final border     = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor  = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor   = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    final isNotIn  = att.status == 'NOT_CHECKED_IN';
    final isIn     = att.status == 'CHECKED_IN';
    final onBreak  = att.status == 'BREAK_ACTIVE';
    final isOut    = att.status == 'CHECKED_OUT';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isNotIn)     { statusColor = AppTheme.statusPending; statusText = 'Not checked in'; statusIcon = Icons.login_rounded; }
    else if (onBreak){ statusColor = AppTheme.statusBreak;   statusText = 'On break';        statusIcon = Icons.coffee_rounded; }
    else if (isIn)   { statusColor = AppTheme.statusPresent; statusText = 'Checked in';      statusIcon = Icons.check_circle_rounded; }
    else             { statusColor = AppTheme.statusAbsent;  statusText = 'Checked out';     statusIcon = Icons.logout_rounded; }

    String checkInLabel = att.checkInTime != null
        ? 'Since ${DateFormat('hh:mm a').format(att.checkInTime!.toLocal())}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // Status indicator
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('My Attendance', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 2),
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(statusText, style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
            if (checkInLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(checkInLabel, style: TextStyle(color: subColor, fontSize: 11.5)),
            ],
          ]),
        ])),
        // Action buttons
        if (att.isLoading)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (isNotIn)
              _AttBtn(label: 'Check In', color: AppTheme.statusPresent, icon: Icons.login_rounded, onTap: () async {
                final ok = await ref.read(attendanceStateProvider.notifier).checkIn();
                if (context.mounted) _snack(context, ok ? 'Checked in successfully' : (att.error ?? 'Check-in failed'), error: !ok);
              }),
            if (isIn) ...[
              _AttBtn(label: 'Break', color: AppTheme.statusBreak, icon: Icons.coffee_rounded, onTap: () async {
                final ok = await ref.read(attendanceStateProvider.notifier).startBreak();
                if (context.mounted) _snack(context, ok ? 'Break started' : (att.error ?? 'Failed'), error: !ok);
              }),
              const SizedBox(width: 8),
              _AttBtn(label: 'Check Out', color: AppTheme.statusAbsent, icon: Icons.logout_rounded, onTap: () async {
                final ok = await ref.read(attendanceStateProvider.notifier).checkOut();
                if (context.mounted) _snack(context, ok ? 'Checked out successfully' : (att.error ?? 'Check-out failed'), error: !ok);
              }),
            ],
            if (onBreak)
              _AttBtn(label: 'End Break', color: AppTheme.statusPresent, icon: Icons.play_arrow_rounded, onTap: () async {
                final ok = await ref.read(attendanceStateProvider.notifier).endBreak();
                if (context.mounted) _snack(context, ok ? 'Break ended' : (att.error ?? 'Failed'), error: !ok);
              }),
            if (isOut)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.statusAbsent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.statusAbsent.withOpacity(0.25)),
                ),
                child: const Text('Done for today', style: TextStyle(color: AppTheme.statusAbsent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
      ]),
    );
  }
}

class _AttBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _AttBtn({required this.label, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}
