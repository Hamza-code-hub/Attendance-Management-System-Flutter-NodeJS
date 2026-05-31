import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'dashboard_provider.dart';
import 'widgets/dashboard_widgets.dart';
import '../attendance/presentation/attendance_state_provider.dart';

// ============================================================================
// HR DASHBOARD v2 — Redesigned for visual excellence & mobile responsiveness
// Animated live dot · Gradient stat cards · Progress bars · Responsive table
// ============================================================================

class HrDashboardScreen extends ConsumerStatefulWidget {
  const HrDashboardScreen({super.key});
  @override
  ConsumerState<HrDashboardScreen> createState() => _HrDashboardScreenState();
}

class _HrDashboardScreenState extends ConsumerState<HrDashboardScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _liveRows = [];
  List<Map<String, dynamic>> _approvals = [];
  List<WeekDay> _weekDays = [];
  Map<String, String> _calendarStatus = {};
  bool _loadingDetails = false;
  String _tab = 'All';
  DateTime _calMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    setState(() => _loadingDetails = true);
    final n = ref.read(dashboardProvider.notifier);
    await n.loadSummary(date: dateStr);
    try {
      final today = DateTime.now();
      final weekStart = today.subtract(Duration(days: today.weekday % 7));
      final weekDates = List.generate(7, (i) => weekStart.add(Duration(days: i)));
      final futures = <Future>[
        n.fetchAttendanceMonitor(date: dateStr),
        n.fetchPendingApprovals(),
      ];
      final r = await Future.wait(futures.cast<Future<dynamic>>());
      if (!mounted) return;

      final labels = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
      final wdays = List.generate(7, (i) {
        final d = weekDates[i];
        final isToday = d.year == today.year && d.month == today.month && d.day == today.day;
        return WeekDay(label: labels[i], present: 0, late: 0, absent: 0, isToday: isToday);
      });

      final calStatus = <String, String>{};
      for (final row in (r[0] as PagedResult<Map<String, dynamic>>).data) {
        final dateKey = (row['date'] ?? '').toString().substring(0, 10);
        final st = (row['status'] ?? '').toString();
        if (st == 'ON_TIME' || st == 'CHECKED_OUT') calStatus[dateKey] = 'present';
        else if (st == 'LATE') calStatus[dateKey] = 'late';
        else if (st == 'ABSENT' || st == 'MISSED_CHECKOUT') calStatus[dateKey] = 'absent';
        else if ((row['overtimeMinutes'] ?? 0) as int > 0) calStatus[dateKey] = 'overtime';
      }

      setState(() {
        _liveRows = (r[0] as PagedResult<Map<String, dynamic>>).data;
        _approvals = (r[1] as PagedResult<Map<String, dynamic>>).data;
        _weekDays = wdays;
        _calendarStatus = calStatus;
      });
    } catch (_) {}
    if (mounted) setState(() => _loadingDetails = false);
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_tab == 'All') return _liveRows;
    if (_tab == 'Present') return _liveRows.where((r) => ['CHECKED_IN', 'BREAK_ACTIVE'].contains(r['status'])).toList();
    if (_tab == 'Late') return _liveRows.where((r) => r['status'] == 'LATE').toList();
    if (_tab == 'Absent') return _liveRows.where((r) => ['ABSENT', 'MISSED_CHECKOUT'].contains(r['status'])).toList();
    return _liveRows;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dash = ref.watch(dashboardProvider);
    final att = ref.watch(attendanceStateProvider);
    final s = dash.summary;
    final screenW = MediaQuery.of(context).size.width;
    final isMobile = screenW < 600;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 22, isMobile ? 14 : 22, isMobile ? 14 : 22, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Topbar ──────────────────────────────────────────────────
          _HrTopRow(date: _date, isDark: isDark, loading: _loadingDetails, onDatePick: _pickDate, onRefresh: _load),
          const SizedBox(height: 18),

          // ── Alert banner ─────────────────────────────────────────────
          if (s != null && s.missingCheckouts > 0) ...[
            _AlertBanner(count: s.missingCheckouts, isDark: isDark),
            const SizedBox(height: 16),
          ],

          // ── Stat cards ───────────────────────────────────────────────
          if (s != null) ...[
            isMobile
                ? _StatCardsGrid(summary: s, isDark: isDark)
                : _StatCardsRow(summary: s, isDark: isDark),
            const SizedBox(height: 20),
          ],

          // ── Main two-column layout ───────────────────────────────────
          LayoutBuilder(builder: (ctx, cs) {
            final wide = cs.maxWidth >= 860;

            final leftCol = _LiveAttendanceSection(
              rows: _filteredRows,
              allRows: _liveRows,
              tab: _tab,
              loading: _loadingDetails,
              isDark: isDark,
              onTabChange: (t) => setState(() => _tab = t),
            );

            final rightCol = Column(children: [
              _HrAttendanceCard(att: att, isDark: isDark, ref: ref),
              const SizedBox(height: 14),
              if (s != null)
                MonthlyRateCircle(
                  rate: s.totalActiveEmployees > 0
                      ? (s.presentCount + s.checkedOutCount) / s.totalActiveEmployees
                      : 0.0,
                  presentDays: s.presentCount + s.checkedOutCount,
                  absentDays: s.absentCount,
                  lateDays: s.lateCount,
                  overTimeHours: 0,
                  isDark: isDark,
                  monthLabel: DateFormat('MMM yyyy').format(_date),
                ),
              const SizedBox(height: 14),
              AttendanceCalendar(
                month: _calMonth,
                dayStatus: _calendarStatus,
                isDark: isDark,
                onPrevMonth: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month - 1)),
                onNextMonth: () => setState(() => _calMonth = DateTime(_calMonth.year, _calMonth.month + 1)),
              ),
              const SizedBox(height: 14),
              _ApprovalsPanel(approvals: _approvals, loading: _loadingDetails, isDark: isDark),
              const SizedBox(height: 14),
              _HrQuickActions(isDark: isDark),
            ]);

            if (!wide) {
              return Column(children: [rightCol, const SizedBox(height: 16), leftCol]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: leftCol),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: rightCol),
            ]);
          }),

          const SizedBox(height: 20),
          if (_weekDays.isNotEmpty) WeeklyBarChart(days: _weekDays, isDark: isDark),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (p != null && mounted) {
      setState(() => _date = p);
      _load();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper functions
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Animated pulse dot for "Live" indicator
// ─────────────────────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.statusPresent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.statusPresent.withOpacity(0.3 + _anim.value * 0.5),
            blurRadius: 4 + _anim.value * 6,
            spreadRadius: _anim.value * 2,
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Row
// ─────────────────────────────────────────────────────────────────────────────

class _HrTopRow extends StatelessWidget {
  final DateTime date;
  final bool isDark, loading;
  final VoidCallback onDatePick, onRefresh;

  const _HrTopRow({
    required this.date, required this.isDark, required this.loading,
    required this.onDatePick, required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'HR Dashboard',
              style: TextStyle(
                color: textColor, fontSize: 22,
                fontWeight: FontWeight.w800, letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              _PulseDot(),
              const SizedBox(width: 7),
              Text(
                'Live · ${DateFormat('EEE, d MMMM yyyy').format(date)}',
                style: TextStyle(color: subColor, fontSize: 12.5),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        _TopChip(isDark: isDark, onTap: onDatePick, child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            DateFormat('MMM dd, yyyy').format(date),
            style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ])),
        const SizedBox(width: 8),
        _TopChip(isDark: isDark, onTap: onRefresh, child: loading
            ? SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
              )
            : Icon(Icons.refresh_rounded, size: 16, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
      ],
    );
  }
}

class _TopChip extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  final Widget child;

  const _TopChip({required this.isDark, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface2 : AppTheme.lightElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Alert Banner
// ─────────────────────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final int count;
  final bool isDark;

  const _AlertBanner({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppTheme.roleAdmin.withOpacity(0.18),
          AppTheme.roleAdmin.withOpacity(0.07),
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.roleAdmin.withOpacity(0.4)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.roleAdmin.withOpacity(0.2),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.warning_amber_rounded, color: AppTheme.roleAdmin, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '$count employee${count > 1 ? 's' : ''} missed checkout yesterday',
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontWeight: FontWeight.w700, fontSize: 13,
            ),
          ),
          Text(
            'Attendance correction required',
            style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5),
          ),
        ])),
        GestureDetector(
          onTap: () => context.go('/hr/approvals'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.roleAdmin.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.roleAdmin.withOpacity(0.4)),
            ),
            child: const Text(
              'Review',
              style: TextStyle(color: AppTheme.roleAdmin, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Cards — Row (desktop) & 2×2 Grid (mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _StatCardsRow extends StatelessWidget {
  final DashboardSummary summary;
  final bool isDark;

  const _StatCardsRow({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final total = summary.totalActiveEmployees;
    final presentCount = summary.presentCount + summary.checkedOutCount;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _StatCard(
        title: 'Present Today',
        value: '$presentCount',
        sub: 'of $total employees',
        progressValue: total > 0 ? presentCount / total : 0.0,
        changeLabel: total > 0 ? '${(presentCount / total * 100).round()}%' : '0%',
        changePositive: true,
        accentColor: AppTheme.statusPresent,
        icon: Icons.people_rounded, isDark: isDark,
      )),
      const SizedBox(width: 12),
      Expanded(child: _StatCard(
        title: 'Late Arrivals',
        value: '${summary.lateCount}',
        sub: 'need attention',
        progressValue: total > 0 ? (summary.lateCount / total).clamp(0.0, 1.0) : 0.0,
        changeLabel: summary.lateCount > 0 ? '+${summary.lateCount} today' : 'None today',
        changePositive: summary.lateCount == 0,
        accentColor: AppTheme.statusLate,
        icon: Icons.schedule_rounded, isDark: isDark,
      )),
      const SizedBox(width: 12),
      Expanded(child: _StatCard(
        title: 'On Break',
        value: '${summary.activeBreaks}',
        sub: summary.activeBreaks > 3 ? '${summary.activeBreaks - 3} exceed limit' : 'Within limits',
        progressValue: total > 0 ? (summary.activeBreaks / total).clamp(0.0, 1.0) : 0.0,
        changeLabel: summary.activeBreaks <= 3 ? 'Normal' : 'High',
        changePositive: summary.activeBreaks <= 3,
        accentColor: AppTheme.statusBreak,
        icon: Icons.free_breakfast_rounded, isDark: isDark,
      )),
      const SizedBox(width: 12),
      Expanded(child: _StatCard(
        title: 'Pending Requests',
        value: '${summary.totalPendingApprovals}',
        sub: 'needs approval',
        progressValue: 0.0,
        changeLabel: summary.totalPendingApprovals > 0 ? 'Action required' : 'All clear',
        changePositive: summary.totalPendingApprovals == 0,
        accentColor: AppTheme.accent,
        icon: Icons.inbox_rounded, isDark: isDark,
      )),
    ]);
  }
}

class _StatCardsGrid extends StatelessWidget {
  final DashboardSummary summary;
  final bool isDark;

  const _StatCardsGrid({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final total = summary.totalActiveEmployees;
    final presentCount = summary.presentCount + summary.checkedOutCount;
    final items = [
      (title: 'Present', value: '$presentCount', sub: 'of $total', prog: total > 0 ? presentCount / total : 0.0, change: '${total > 0 ? (presentCount / total * 100).round() : 0}%', positive: true, color: AppTheme.statusPresent, icon: Icons.people_rounded),
      (title: 'Late Arrivals', value: '${summary.lateCount}', sub: 'need attention', prog: total > 0 ? (summary.lateCount / total).clamp(0.0, 1.0) : 0.0, change: summary.lateCount == 0 ? 'None' : '+${summary.lateCount}', positive: summary.lateCount == 0, color: AppTheme.statusLate, icon: Icons.schedule_rounded),
      (title: 'On Break', value: '${summary.activeBreaks}', sub: summary.activeBreaks <= 3 ? 'Within limits' : 'Exceeding', prog: 0.0, change: summary.activeBreaks <= 3 ? 'Normal' : 'High', positive: summary.activeBreaks <= 3, color: AppTheme.statusBreak, icon: Icons.free_breakfast_rounded),
      (title: 'Pending', value: '${summary.totalPendingApprovals}', sub: 'approvals', prog: 0.0, change: summary.totalPendingApprovals == 0 ? 'All clear' : 'Action!', positive: summary.totalPendingApprovals == 0, color: AppTheme.accent, icon: Icons.inbox_rounded),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: items.map((c) => _StatCard(
        title: c.title, value: c.value, sub: c.sub,
        progressValue: c.prog, changeLabel: c.change,
        changePositive: c.positive, accentColor: c.color,
        icon: c.icon, isDark: isDark,
      )).toList(),
    );
  }
}

// Single stat card — used by both row and grid
class _StatCard extends StatelessWidget {
  final String title, value, sub, changeLabel;
  final double progressValue;
  final bool changePositive, isDark;
  final Color accentColor;
  final IconData icon;

  const _StatCard({
    required this.title, required this.value, required this.sub,
    required this.progressValue, required this.changeLabel,
    required this.changePositive, required this.accentColor,
    required this.icon, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardBg, accentColor.withOpacity(isDark ? 0.07 : 0.04)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.22), width: 1.2),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.1), blurRadius: 18, offset: const Offset(0, 5)),
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icon + change badge row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [accentColor.withOpacity(0.28), accentColor.withOpacity(0.10)],
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: Icon(icon, color: accentColor, size: 19),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: changePositive
                  ? AppTheme.statusPresent.withOpacity(0.12)
                  : AppTheme.statusAbsent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                changePositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 10,
                color: changePositive ? AppTheme.statusPresent : AppTheme.statusAbsent,
              ),
              const SizedBox(width: 3),
              Text(
                changeLabel,
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: changePositive ? AppTheme.statusPresent : AppTheme.statusAbsent,
                ),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        // Value
        Text(
          value,
          style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: accentColor, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 10),
        // Progress bar
        if (progressValue > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progressValue.clamp(0.0, 1.0),
              minHeight: 3.5,
              backgroundColor: accentColor.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          sub,
          style: TextStyle(
            color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
            fontSize: 11.5,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Attendance Section with filter tabs
// ─────────────────────────────────────────────────────────────────────────────

class _LiveAttendanceSection extends StatelessWidget {
  final List<Map<String, dynamic>> rows, allRows;
  final String tab;
  final bool loading, isDark;
  final ValueChanged<String> onTabChange;

  const _LiveAttendanceSection({
    required this.rows, required this.allRows, required this.tab,
    required this.loading, required this.isDark, required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final present = allRows.where((r) => ['CHECKED_IN', 'BREAK_ACTIVE', 'ON_TIME'].contains(r['status'])).length;
    final late = allRows.where((r) => r['status'] == 'LATE').length;
    final absent = allRows.where((r) => ['ABSENT', 'MISSED_CHECKOUT'].contains(r['status'])).length;

    final tabs = [
      (label: 'All', count: allRows.length, color: AppTheme.accent),
      (label: 'Present', count: present, color: AppTheme.statusPresent),
      (label: 'Late', count: late, color: AppTheme.statusLate),
      (label: 'Absent', count: absent, color: AppTheme.statusAbsent),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(children: [
        // ── Card header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 0),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.monitor_rounded, size: 17, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Live Attendance',
                style: TextStyle(
                  color: isDark ? AppTheme.darkText : AppTheme.lightText,
                  fontWeight: FontWeight.w700, fontSize: 14.5,
                ),
              ),
              Text(
                'Today · Real-time',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 11,
                ),
              ),
            ]),
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/hr/attendance-monitor'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('See all', style: TextStyle(color: AppTheme.accent, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded, color: AppTheme.accent, size: 11),
                ]),
              ),
            ),
          ]),
        ),

        // ── Filter tabs ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: tabs.map((t) {
              final isActive = t.label == tab;
              return GestureDetector(
                onTap: () => onTabChange(t.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? t.color.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isActive ? t.color.withOpacity(0.4) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                      width: 1.2,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isActive) ...[
                      Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: t.color)),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      t.label,
                      style: TextStyle(
                        color: isActive ? t.color : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                        fontSize: 12, fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isActive ? t.color.withOpacity(0.18) : (isDark ? AppTheme.darkBorder : const Color(0xFFF0F2F5)),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${t.count}',
                        style: TextStyle(
                          color: isActive ? t.color : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                          fontSize: 10.5, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }).toList()),
          ),
        ),

        const SizedBox(height: 12),
        Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

        // ── Column headers (desktop only) ──────────────────────────────
        if (!isMobile) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            color: isDark ? AppTheme.darkCard2 : const Color(0xFFF8FAFC),
            child: Row(children: [
              _TableHeader('EMPLOYEE', 3, isDark),
              _TableHeader('CHECK IN', 2, isDark),
              _TableHeader('CHECK OUT', 2, isDark),
              _TableHeader('WORKED', 2, isDark),
              _TableHeader('STATUS', 2, isDark),
              _TableHeader('BREAK', 1, isDark),
            ]),
          ),
          Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ],

        // ── Rows / empty state ─────────────────────────────────────────
        if (loading && rows.isEmpty)
          const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.search_off_rounded, size: 38, color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              const SizedBox(height: 8),
              Text('No records for this filter',
                style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
            ])),
          )
        else
          ...rows.take(10).toList().asMap().entries.map((e) => isMobile
              ? _AttendanceRowMobile(row: e.value, isDark: isDark, index: e.key)
              : _AttendanceRow(row: e.value, isDark: isDark, index: e.key)),

        if (rows.length > 10)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Center(
              child: GestureDetector(
                onTap: () => context.go('/hr/attendance-monitor'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
                  ),
                  child: Text(
                    'View all ${rows.length} records',
                    style: const TextStyle(color: AppTheme.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// Table header cell
Widget _TableHeader(String label, int flex, bool isDark) => Expanded(
  flex: flex,
  child: Text(label, style: TextStyle(
    color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
    fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.9,
  )),
);

// ─────────────────────────────────────────────────────────────────────────────
// Attendance row — Desktop (table style)
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isDark;
  final int index;

  const _AttendanceRow({required this.row, required this.isDark, required this.index});

  @override
  Widget build(BuildContext context) {
    final name = _readString(row, ['employeeName', 'employee_name'],
        '${row['firstName'] ?? ''} ${row['lastName'] ?? ''}'.trim());
    final dept = _readString(row, ['departmentName', 'department_name'], '—');
    final status = _readString(row, ['status']);
    final sc = AppTheme.statusColor(status);
    final inT = _ft(_readString(row, ['checkInTime', 'check_in_time']));
    final outT = _ft(_readString(row, ['checkOutTime', 'check_out_time']));
    final wm = _readInt(row, ['totalWorkedMinutes', 'total_worked_minutes']);
    final worked = wm > 0 ? '${wm ~/ 60}h ${wm % 60}m' : '—';
    final bm = _readInt(row, ['totalBreakMinutes', 'total_break_minutes']);
    final brk = bm > 0 ? '${bm}m' : '0m';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: index % 2 == 1
            ? (isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.015))
            : Colors.transparent,
        border: Border(bottom: BorderSide(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.8,
        )),
      ),
      child: Row(children: [
        Expanded(flex: 3, child: Row(children: [
          _EmpAvatar(name: name),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontWeight: FontWeight.w600, fontSize: 13,
            ), overflow: TextOverflow.ellipsis),
            Text(dept, style: TextStyle(
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
              fontSize: 11,
            )),
          ])),
        ])),
        Expanded(flex: 2, child: Text(inT, style: const TextStyle(
          fontFamily: 'monospace', fontSize: 12.5, color: AppTheme.accent, fontWeight: FontWeight.w600,
        ))),
        Expanded(flex: 2, child: Text(outT, style: TextStyle(
          fontFamily: 'monospace', fontSize: 12.5,
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
        ))),
        Expanded(flex: 2, child: Text(worked, style: TextStyle(
          color: isDark ? AppTheme.darkText : AppTheme.lightText,
          fontSize: 12.5, fontWeight: FontWeight.w500,
        ))),
        Expanded(flex: 2, child: _StatusPill(label: _statusLabel(status), color: sc)),
        Expanded(flex: 1, child: Text(brk, style: TextStyle(
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12,
        ))),
      ]),
    );
  }

  String _ft(String? dt) {
    if (dt == null || dt.isEmpty) return '—';
    try { return DateFormat('hh:mm a').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return '—'; }
  }

  String _statusLabel(String s) => {
    'CHECKED_IN': 'On Time', 'BREAK_ACTIVE': 'On Break',
    'CHECKED_OUT': 'Checked Out', 'LATE': 'Late',
    'ABSENT': 'Absent', 'MISSED_CHECKOUT': 'Missed Out', 'ON_TIME': 'On Time',
  }[s] ?? s;
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendance row — Mobile (card style)
// ─────────────────────────────────────────────────────────────────────────────

class _AttendanceRowMobile extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isDark;
  final int index;

  const _AttendanceRowMobile({required this.row, required this.isDark, required this.index});

  @override
  Widget build(BuildContext context) {
    final name = _readString(row, ['employeeName', 'employee_name'],
        '${row['firstName'] ?? ''} ${row['lastName'] ?? ''}'.trim());
    final dept = _readString(row, ['departmentName', 'department_name'], '—');
    final status = _readString(row, ['status']);
    final sc = AppTheme.statusColor(status);
    final inT = _ft(_readString(row, ['checkInTime', 'check_in_time']));
    final outT = _ft(_readString(row, ['checkOutTime', 'check_out_time']));
    final wm = _readInt(row, ['totalWorkedMinutes', 'total_worked_minutes']);
    final worked = wm > 0 ? '${wm ~/ 60}h ${wm % 60}m' : '—';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard2 : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: sc.withOpacity(0.18)),
      ),
      child: Row(children: [
        _EmpAvatar(name: name),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontWeight: FontWeight.w600, fontSize: 13,
            ), overflow: TextOverflow.ellipsis)),
            _StatusPill(label: _statusShort(status), color: sc),
          ]),
          Text(dept, style: TextStyle(
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
            fontSize: 11,
          )),
          const SizedBox(height: 5),
          Row(children: [
            Icon(Icons.login_rounded, size: 11, color: AppTheme.accent),
            const SizedBox(width: 3),
            Text(inT, style: const TextStyle(color: AppTheme.accent, fontSize: 11.5, fontWeight: FontWeight.w600)),
            if (outT != '—') ...[
              const SizedBox(width: 8),
              Icon(Icons.logout_rounded, size: 11, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
              const SizedBox(width: 3),
              Text(outT, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5)),
            ],
            const SizedBox(width: 8),
            Icon(Icons.timer_outlined, size: 11, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
            const SizedBox(width: 3),
            Text(worked, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5)),
          ]),
        ])),
      ]),
    );
  }

  String _ft(String? dt) {
    if (dt == null || dt.isEmpty) return '—';
    try { return DateFormat('hh:mm a').format(DateTime.parse(dt).toLocal()); }
    catch (_) { return '—'; }
  }

  String _statusShort(String s) => {
    'CHECKED_IN': 'On Time', 'BREAK_ACTIVE': 'Break', 'CHECKED_OUT': 'Out',
    'LATE': 'Late', 'ABSENT': 'Absent', 'MISSED_CHECKOUT': 'Missed', 'ON_TIME': 'On Time',
  }[s] ?? s;
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pill badge
// ─────────────────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.1)]),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withOpacity(0.3), width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Employee avatar
// ─────────────────────────────────────────────────────────────────────────────

class _EmpAvatar extends StatelessWidget {
  final String name;

  const _EmpAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    const palette = [
      Color(0xFF1A6ED8), Color(0xFF00D68F), Color(0xFFFFB020),
      Color(0xFFFF4D6A), Color(0xFF7C5CFC),
    ];
    final init = name.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();
    final c = name.isNotEmpty ? palette[name.codeUnitAt(0) % palette.length] : palette[0];

    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [c.withOpacity(0.3), c.withOpacity(0.12)],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Center(child: Text(init, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Approvals Panel
// ─────────────────────────────────────────────────────────────────────────────

class _ApprovalsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> approvals;
  final bool loading, isDark;

  const _ApprovalsPanel({required this.approvals, required this.loading, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.fact_check_rounded, size: 15, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
            Text('Pending Approvals', style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontWeight: FontWeight.w700, fontSize: 14,
            )),
            if (approvals.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.statusAbsent, borderRadius: BorderRadius.circular(99)),
                child: Text('${approvals.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
            const Spacer(),
            GestureDetector(
              onTap: () => context.go('/hr/approvals'),
              child: Text('View all →', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Container(height: 1, color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),

        if (loading)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (approvals.isEmpty)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppTheme.statusPresent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.check_circle_outline_rounded, color: AppTheme.statusPresent, size: 18),
              ),
              const SizedBox(width: 12),
              Text('All caught up! No pending requests.',
                style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
            ]),
          )
        else
          ...approvals.take(4).map((a) {
            final type = _readString(a, ['requestType', 'type']);
            final name = _readString(a, ['employeeName', 'employee_name'],
                '${a['firstName'] ?? ''} ${a['lastName'] ?? ''}'.trim());
            final date = _readString(a, ['requestDate', 'request_date', 'date']);
            final isOT = type.toUpperCase().contains('OT') || type.toUpperCase().contains('OVER');
            final color = isOT ? AppTheme.accent : AppTheme.accent2;

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              decoration: BoxDecoration(border: Border(
                bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.8),
              )),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withOpacity(0.2), color.withOpacity(0.08)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(isOT ? Icons.more_time_rounded : Icons.edit_calendar_rounded, color: color, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isNotEmpty ? name : 'Employee', style: TextStyle(
                    color: isDark ? AppTheme.darkText : AppTheme.lightText,
                    fontWeight: FontWeight.w600, fontSize: 13,
                  ), overflow: TextOverflow.ellipsis),
                  Text('${isOT ? 'Overtime' : 'Adjustment'} · $date', style: TextStyle(
                    color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 11.5,
                  )),
                ])),
                _StatusPill(label: 'Pending', color: AppTheme.statusPending),
              ]),
            );
          }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HR Quick Actions — 2×2 grid
// ─────────────────────────────────────────────────────────────────────────────

class _HrQuickActions extends StatelessWidget {
  final bool isDark;

  const _HrQuickActions({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final actions = [
      (title: 'Attendance Monitor', icon: Icons.monitor_rounded, color: AppTheme.accent, route: '/hr/attendance-monitor'),
      (title: 'Shift Monitor', icon: Icons.access_time_rounded, color: AppTheme.accent2, route: '/hr/shift-monitor'),
      (title: 'Employee Directory', icon: Icons.people_alt_rounded, color: AppTheme.statusPresent, route: '/hr/employee-directory'),
      (title: 'Reports & Export', icon: Icons.bar_chart_rounded, color: AppTheme.statusLate, route: '/hr/reports'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.15 : 0.05), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.flash_on_rounded, size: 16, color: AppTheme.accent),
          ),
          const SizedBox(width: 10),
          Text('Quick Actions', style: TextStyle(
            color: isDark ? AppTheme.darkText : AppTheme.lightText,
            fontWeight: FontWeight.w700, fontSize: 14,
          )),
        ]),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8, mainAxisSpacing: 8,
          childAspectRatio: 2.6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: actions.map((a) => GestureDetector(
            onTap: () => context.go(a.route),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [a.color.withOpacity(0.1), a.color.withOpacity(0.04)]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: a.color.withOpacity(0.22)),
              ),
              child: Row(children: [
                Icon(a.icon, color: a.color, size: 14),
                const SizedBox(width: 7),
                Expanded(child: Text(a.title, style: TextStyle(
                  color: a.color, fontWeight: FontWeight.w600, fontSize: 11.5,
                ), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          )).toList(),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Personal Attendance Card — fixed overflow with Wrap for buttons
// ─────────────────────────────────────────────────────────────────────────────

class _HrAttendanceCard extends StatelessWidget {
  final TodayAttendanceState att;
  final bool isDark;
  final WidgetRef ref;

  const _HrAttendanceCard({required this.att, required this.isDark, required this.ref});

  void _snack(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.statusAbsent : AppTheme.statusPresent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    final isNotIn = att.status == 'NOT_CHECKED_IN';
    final isIn = att.status == 'CHECKED_IN';
    final onBreak = att.status == 'BREAK_ACTIVE';
    final isOut = att.status == 'CHECKED_OUT';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isNotIn) { statusColor = AppTheme.statusPending; statusText = 'Not checked in'; statusIcon = Icons.login_rounded; }
    else if (onBreak) { statusColor = AppTheme.statusBreak; statusText = 'On break'; statusIcon = Icons.coffee_rounded; }
    else if (isIn) { statusColor = AppTheme.statusPresent; statusText = 'Checked in'; statusIcon = Icons.check_circle_rounded; }
    else { statusColor = AppTheme.statusAbsent; statusText = 'Checked out'; statusIcon = Icons.logout_rounded; }

    final checkInLabel = att.checkInTime != null
        ? 'Since ${DateFormat('hh:mm a').format(att.checkInTime!.toLocal())}'
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [cardBg, statusColor.withOpacity(isDark ? 0.07 : 0.04)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.28), width: 1.2),
        boxShadow: [
          BoxShadow(color: statusColor.withOpacity(0.1), blurRadius: 14, offset: const Offset(0, 4)),
          BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Status header
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [statusColor.withOpacity(0.22), statusColor.withOpacity(0.08)]),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Attendance', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 2),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
              const SizedBox(width: 5),
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (checkInLabel.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(checkInLabel, style: TextStyle(color: subColor, fontSize: 11.5)),
              ],
            ]),
          ])),
        ]),

        // Action buttons — Wrap prevents overflow on any screen width
        if (att.isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (isNotIn)
              _AttBtn(
                label: 'Check In', color: AppTheme.statusPresent, icon: Icons.login_rounded,
                onTap: () async {
                  final ok = await ref.read(attendanceStateProvider.notifier).checkIn();
                  if (context.mounted) _snack(context, ok ? 'Checked in ✓' : (att.error ?? 'Check-in failed'), error: !ok);
                },
              ),
            if (isIn) ...[
              _AttBtn(
                label: 'Start Break', color: AppTheme.statusBreak, icon: Icons.coffee_rounded,
                onTap: () async {
                  final ok = await ref.read(attendanceStateProvider.notifier).startBreak();
                  if (context.mounted) _snack(context, ok ? 'Break started' : (att.error ?? 'Failed'), error: !ok);
                },
              ),
              _AttBtn(
                label: 'Check Out', color: AppTheme.statusAbsent, icon: Icons.logout_rounded,
                onTap: () async {
                  final ok = await ref.read(attendanceStateProvider.notifier).checkOut();
                  if (context.mounted) _snack(context, ok ? 'Checked out ✓' : (att.error ?? 'Check-out failed'), error: !ok);
                },
              ),
            ],
            if (onBreak)
              _AttBtn(
                label: 'End Break', color: AppTheme.statusPresent, icon: Icons.play_arrow_rounded,
                onTap: () async {
                  final ok = await ref.read(attendanceStateProvider.notifier).endBreak();
                  if (context.mounted) _snack(context, ok ? 'Break ended' : (att.error ?? 'Failed'), error: !ok);
                },
              ),
            if (isOut)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.statusPresent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.statusPresent.withOpacity(0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline_rounded, size: 13, color: AppTheme.statusPresent),
                  SizedBox(width: 5),
                  Text('Done for today', style: TextStyle(color: AppTheme.statusPresent, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }
}

// Attendance action button — reusable gradient style
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.18), color.withOpacity(0.07)]),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.35), width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}