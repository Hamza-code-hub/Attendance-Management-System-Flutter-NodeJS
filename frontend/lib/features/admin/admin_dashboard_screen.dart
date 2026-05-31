import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../authentication/presentation/auth_state.dart';
import '../dashboard/dashboard_provider.dart';
import '../../core/theme/app_theme.dart';

String get _base => ServerConfig.apiBase;

// ── Data models ───────────────────────────────────────────────────────────────

class _HealthData {
  final String status;
  final int uptimeSeconds;
  final double dbLatencyMs;
  final int memUsedMb;
  final int memTotalMb;

  const _HealthData({
    required this.status, required this.uptimeSeconds,
    required this.dbLatencyMs, required this.memUsedMb, required this.memTotalMb,
  });
}

class _AuditEntry {
  final String action, username, details, timestamp;
  const _AuditEntry({required this.action, required this.username, required this.details, required this.timestamp});
}

// ── Provider for admin-specific data ─────────────────────────────────────────

final adminHealthProvider = FutureProvider.autoDispose<_HealthData?>((ref) async {
  final token = ref.read(authProvider).accessToken ?? '';
  try {
    final res = await http.get(Uri.parse('$_base/health'), headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final sys = d['system'] as Map<String, dynamic>? ?? {};
      final mem = sys['memory'] as Map<String, dynamic>? ?? {};
      return _HealthData(
        status: (d['status'] ?? 'unknown') as String,
        uptimeSeconds: (d['uptime'] ?? 0) as int,
        dbLatencyMs: ((d['database']?['latencyMs'] ?? 0) as num).toDouble(),
        memUsedMb: ((mem['heapUsed'] ?? 0) as num) ~/ (1024 * 1024),
        memTotalMb: ((mem['heapTotal'] ?? 1) as num) ~/ (1024 * 1024),
      );
    }
  } catch (_) {}
  return null;
});

final adminAuditProvider = FutureProvider.autoDispose<List<_AuditEntry>>((ref) async {
  final token = ref.read(authProvider).accessToken ?? '';
  try {
    final res = await http.get(
      Uri.parse('$_base/audit-logs?limit=6&page=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows = (body['data']?['logs'] ?? body['data'] ?? []) as List;
      return rows.map((r) => _AuditEntry(
        action: (r['action'] ?? '') as String,
        username: (r['username'] ?? r['performedBy'] ?? 'System') as String,
        details: (r['details'] ?? r['targetType'] ?? '') as String,
        timestamp: (r['timestamp'] ?? r['createdAt'] ?? '') as String,
      )).toList();
    }
  } catch (_) {}
  return [];
});

// ============================================================================
// ADMIN DASHBOARD SCREEN
// ============================================================================

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dashboardProvider.notifier).loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final dash     = ref.watch(dashboardProvider);
    final health   = ref.watch(adminHealthProvider);
    final audit    = ref.watch(adminAuditProvider);
    final user     = ref.watch(authProvider).user;
    final name     = (user?.username ?? 'Admin').split(' ').first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Admin welcome banner ───────────────────────────────────
          _AdminBanner(name: name, isDark: isDark, summary: dash.summary),
          const SizedBox(height: 18),

          // ── Two-column layout ──────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column (wider)
              Expanded(
                flex: 5,
                child: Column(children: [
                  // System health
                  _SystemHealthCard(health: health, isDark: isDark),
                  const SizedBox(height: 14),
                  // Workforce overview
                  if (dash.summary != null) _WorkforceCard(summary: dash.summary!, isDark: isDark),
                  const SizedBox(height: 14),
                  // Audit log
                  _AuditLogCard(audit: audit, isDark: isDark),
                ]),
              ),
              const SizedBox(width: 14),
              // Right column (shortcuts)
              Expanded(
                flex: 3,
                child: Column(children: [
                  _AdminShortcuts(isDark: isDark),
                  const SizedBox(height: 14),
                  if (dash.summary != null) _PendingCountCard(summary: dash.summary!, isDark: isDark),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Admin welcome banner ──────────────────────────────────────────────────────

class _AdminBanner extends StatelessWidget {
  final String name;
  final bool isDark;
  final DashboardSummary? summary;
  const _AdminBanner({required this.name, required this.isDark, required this.summary});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF78350F), Color(0xFF92400E), Color(0xFF1E1B4B)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppTheme.roleAdmin.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))],
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
                      color: AppTheme.roleAdmin.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppTheme.roleAdmin.withOpacity(0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.admin_panel_settings_rounded, size: 13, color: AppTheme.roleAdmin),
                      const SizedBox(width: 5),
                      const Text('System Administrator', style: TextStyle(color: AppTheme.roleAdmin, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Text('Welcome back, $name',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text(DateFormat('EEEE, d MMMM yyyy • hh:mm a').format(now),
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13)),
              ],
            ),
          ),
          if (summary != null) ...[
            const SizedBox(width: 20),
            _bstat('${summary!.totalActiveEmployees}', 'Total Staff'),
            const SizedBox(width: 24),
            _bstat('${summary!.presentCount}', 'Present Now'),
            const SizedBox(width: 24),
            _bstat('${summary!.totalPendingApprovals}', 'Pending Actions'),
          ],
        ],
      ),
    );
  }

  Widget _bstat(String v, String l) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(v, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
      Text(l, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.5)),
    ],
  );
}

// ── System health card ────────────────────────────────────────────────────────

class _SystemHealthCard extends StatelessWidget {
  final AsyncValue<_HealthData?> health;
  final bool isDark;
  const _SystemHealthCard({required this.health, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      header: _cardHeader(Icons.monitor_heart_rounded, 'System Health', AppTheme.roleAdmin, isDark),
      child: health.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => _errText('Could not reach health endpoint', isDark),
        data: (h) {
          if (h == null) return _errText('Health check failed', isDark);
          final up = _uptime(h.uptimeSeconds);
          final memPct = h.memTotalMb > 0 ? h.memUsedMb / h.memTotalMb : 0.0;
          final ok = h.status == 'ok';
          return Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Row(children: [
                _healthChip(ok ? 'Operational' : 'Degraded', ok ? AppTheme.statusPresent : AppTheme.statusAbsent),
                const Spacer(),
                Text('Uptime: $up', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 12)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _HealthMetric(label: 'DB Latency', value: '${h.dbLatencyMs.toStringAsFixed(1)} ms', color: h.dbLatencyMs < 10 ? AppTheme.statusPresent : AppTheme.statusLate, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(child: _HealthMetric(label: 'Memory Used', value: '${h.memUsedMb} / ${h.memTotalMb} MB', color: AppTheme.accent2, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(child: _HealthMetric(label: 'Mem Usage', value: '${(memPct * 100).round()}%', color: memPct > 0.8 ? AppTheme.statusAbsent : AppTheme.accent, isDark: isDark)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: memPct,
                  minHeight: 6,
                  backgroundColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                  valueColor: AlwaysStoppedAnimation(memPct > 0.8 ? AppTheme.statusAbsent : AppTheme.accent),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _healthChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withOpacity(0.25))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  String _uptime(int s) {
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m';
    if (s < 86400) return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
    return '${s ~/ 86400}d ${(s % 86400) ~/ 3600}h';
  }
}

class _HealthMetric extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool isDark;
  const _HealthMetric({required this.label, required this.value, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Workforce overview ────────────────────────────────────────────────────────

class _WorkforceCard extends StatelessWidget {
  final DashboardSummary summary;
  final bool isDark;
  const _WorkforceCard({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final total = summary.totalActiveEmployees;
    final pct   = (s) => total > 0 ? s / total : 0.0;

    return _Card(
      isDark: isDark,
      header: _cardHeader(Icons.people_rounded, 'Workforce Overview', AppTheme.accent2, isDark),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          _WfRow('Present', summary.presentCount, total, AppTheme.statusPresent, isDark),
          const SizedBox(height: 10),
          _WfRow('On Break', summary.activeBreaks, total, AppTheme.statusBreak, isDark),
          const SizedBox(height: 10),
          _WfRow('Late Arrivals', summary.lateCount, total, AppTheme.statusLate, isDark),
          const SizedBox(height: 10),
          _WfRow('Absent', summary.absentCount, total, AppTheme.statusAbsent, isDark),
          const SizedBox(height: 10),
          _WfRow('Missing Checkout', summary.missingCheckouts, total, const Color(0xFF8B5CF6), isDark),
        ]),
      ),
    );
  }
}

class _WfRow extends StatelessWidget {
  final String label;
  final int count, total;
  final Color color;
  final bool isDark;
  const _WfRow(this.label, this.count, this.total, this.color, this.isDark);

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(children: [
      SizedBox(width: 130, child: Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: isDark ? AppTheme.darkInput : AppTheme.lightInput,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 48,
        child: Text('$count / $total', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 12.5, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
      ),
    ]);
  }
}

// ── Audit log card ────────────────────────────────────────────────────────────

class _AuditLogCard extends StatelessWidget {
  final AsyncValue<List<_AuditEntry>> audit;
  final bool isDark;
  const _AuditLogCard({required this.audit, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      header: Row(children: [
        _cardHeader(Icons.security_rounded, 'Recent Audit Log', AppTheme.statusAbsent, isDark),
        const Spacer(),
        GestureDetector(
          onTap: () => context.go('/admin/audit-logs'),
          child: const Text('View All →', style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 18),
      ]),
      child: audit.when(
        loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => _errText('Could not load audit logs', isDark),
        data: (entries) {
          if (entries.isEmpty) return _errText('No audit entries found', isDark);
          return Column(
            children: entries.map((e) => _AuditRow(entry: e, isDark: isDark)).toList(),
          );
        },
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final _AuditEntry entry;
  final bool isDark;
  const _AuditRow({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final action = entry.action.toUpperCase();
    final color  = action.contains('LOGIN') ? AppTheme.statusPresent
      : action.contains('REJECT') || action.contains('DELETE') ? AppTheme.statusAbsent
      : action.contains('APPROVE') ? AppTheme.accent
      : AppTheme.accent2;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      ),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(7)),
          child: Icon(Icons.receipt_long_rounded, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(text: TextSpan(children: [
              TextSpan(text: entry.username, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w500, fontSize: 13)),
              TextSpan(text: '  ${entry.action}', style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13)),
            ])),
            if (entry.details.isNotEmpty)
              Text(entry.details, style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11.5), overflow: TextOverflow.ellipsis),
          ],
        )),
        Text(_fmtTs(entry.timestamp), style: TextStyle(fontFamily: 'monospace', color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 11)),
      ]),
    );
  }

  String _fmtTs(String ts) {
    if (ts.isEmpty) return '';
    try { return DateFormat('hh:mm a, dd MMM').format(DateTime.parse(ts).toLocal()); }
    catch (_) { return ts.length > 16 ? ts.substring(0, 16) : ts; }
  }
}

// ── Admin shortcuts ───────────────────────────────────────────────────────────

class _AdminShortcuts extends StatelessWidget {
  final bool isDark;
  const _AdminShortcuts({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final links = [
      ('Employee Setup', Icons.manage_accounts_rounded, AppTheme.accent, '/hr/employees'),
      ('User Accounts', Icons.account_circle_rounded, AppTheme.roleAdmin, '/admin/users'),
      ('Departments', Icons.business_rounded, AppTheme.roleManager, '/admin/departments'),
      ('Shift Config', Icons.schedule_rounded, AppTheme.accent2, '/hr/shifts'),
      ('HR Dashboard', Icons.dashboard_rounded, AppTheme.roleHR, '/hr/dashboard'),
      ('Approval Center', Icons.fact_check_rounded, AppTheme.statusPresent, '/hr/approvals'),
      ('Employee Directory', Icons.people_alt_rounded, AppTheme.statusBreak, '/hr/employee-directory'),
      ('Reports & Exports', Icons.bar_chart_rounded, AppTheme.statusLate, '/hr/reports'),
      ('System Settings', Icons.settings_rounded, const Color(0xFF64748B), '/admin/settings'),
      ('Audit Logs', Icons.security_rounded, AppTheme.statusAbsent, '/admin/audit-logs'),
    ];

    return _Card(
      isDark: isDark,
      header: _cardHeader(Icons.grid_view_rounded, 'Admin Shortcuts', AppTheme.roleAdmin, isDark),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: links.map((l) => _ShortcutTile(label: l.$1, icon: l.$2, color: l.$3, path: l.$4, isDark: isDark)).toList(),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final String label, path;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _ShortcutTile({required this.label, required this.icon, required this.color, required this.path, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.16)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

// ── Pending count card ────────────────────────────────────────────────────────

class _PendingCountCard extends StatelessWidget {
  final DashboardSummary summary;
  final bool isDark;
  const _PendingCountCard({required this.summary, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      header: _cardHeader(Icons.inbox_rounded, 'Pending Actions', AppTheme.statusLate, isDark),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _pRow('OT Requests', summary.pendingOvertimeRequests, AppTheme.accent, isDark),
          const SizedBox(height: 10),
          _pRow('Adjustments', summary.pendingAdjustmentRequests, AppTheme.accent2, isDark),
          const SizedBox(height: 10),
          _pRow('Missing Checkouts', summary.missingCheckouts, AppTheme.statusAbsent, isDark),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => context.go('/hr/approvals'),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: const Center(child: Text('Go to Approvals', style: TextStyle(color: Color(0xFF0A1F1A), fontWeight: FontWeight.w600, fontSize: 13))),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pRow(String label, int count, Color color, bool isDark) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub, fontSize: 13))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(99)),
        child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    ]);
  }
}

// ── Shared card widget ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final bool isDark;
  final Widget header;
  final Widget child;
  const _Card({required this.isDark, required this.header, required this.child});

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
          Container(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
            ),
            child: header,
          ),
          child,
        ],
      ),
    );
  }
}

Widget _cardHeader(IconData icon, String title, Color color, bool isDark) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600, fontSize: 14)),
    ]),
  );
}

Widget _errText(String msg, bool isDark) => Padding(
  padding: const EdgeInsets.all(18),
  child: Text(msg, style: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13)),
);
