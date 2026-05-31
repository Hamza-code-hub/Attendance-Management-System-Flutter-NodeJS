import 'dart:convert';
import '../../../core/config/server_config.dart';
import '../../../core/utils/download_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

// ============================================================================
// AUDIT LOGS SCREEN
// ============================================================================

class AuditLogsScreen extends ConsumerStatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  ConsumerState<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends ConsumerState<AuditLogsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Filter state ─────────────────────────────────────────────────────────
  DateTime? _from;
  DateTime? _to;
  String _actionFilter = '';
  String _usernameFilter = '';

  // ── Pagination & data state ───────────────────────────────────────────────
  int _page = 1;
  List<Map<String, dynamic>> _logs = [];
  int _total = 0;
  int _pages = 1;
  bool _loading = false;
  String? _error;

  // ── Filter field controllers ──────────────────────────────────────────────
  final _actionCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${ref.read(authProvider).accessToken ?? ''}',
        'Content-Type': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetch({int? page}) async {
    final targetPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
      _page = targetPage;
    });

    try {
      final params = <String, String>{
        'page': '$targetPage',
        'limit': '50',
      };
      if (_from != null) params['from'] = DateFormat('yyyy-MM-dd').format(_from!);
      if (_to != null) params['to'] = DateFormat('yyyy-MM-dd').format(_to!);
      if (_actionFilter.trim().isNotEmpty) params['action'] = _actionFilter.trim();
      if (_usernameFilter.trim().isNotEmpty) params['username'] = _usernameFilter.trim();

      final uri = Uri.parse('$_base/audit-logs').replace(queryParameters: params);
      final res = await http.get(uri, headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>? ?? {};
        final rawLogs = data['logs'] ?? data['items'] ?? data['data'] ?? [];
        final pagination = data['pagination'] as Map<String, dynamic>? ?? {};

        setState(() {
          _logs = (rawLogs as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _total = (pagination['total'] ?? data['total'] ?? rawLogs.length) as int;
          _pages = (pagination['pages'] ?? data['pages'] ?? 1) as int;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = (body['error'] as Map?)?['message'] as String? ?? 'Failed to load audit logs';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _actionFilter = _actionCtrl.text;
      _usernameFilter = _usernameCtrl.text;
    });
    _fetch(page: 1);
  }

  void _clearFilters() {
    _actionCtrl.clear();
    _usernameCtrl.clear();
    setState(() {
      _from = null;
      _to = null;
      _actionFilter = '';
      _usernameFilter = '';
    });
    _fetch(page: 1);
  }

  // ── CSV export ───────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    try {
      final params = <String, String>{};
      if (_from != null) params['from'] = DateFormat('yyyy-MM-dd').format(_from!);
      if (_to != null) params['to'] = DateFormat('yyyy-MM-dd').format(_to!);
      if (_actionFilter.trim().isNotEmpty) params['action'] = _actionFilter.trim();
      if (_usernameFilter.trim().isNotEmpty) params['username'] = _usernameFilter.trim();

      final uri = Uri.parse('$_base/audit-logs/export')
          .replace(queryParameters: params.isNotEmpty ? params : null);
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final filename = 'audit_logs_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
        _downloadBytes(res.bodyBytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Exported $filename'),
              ]),
              backgroundColor: AppTheme.statusPresent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed'), backgroundColor: AppTheme.brandDanger),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: AppTheme.brandDanger),
        );
      }
    }
  }

  void _downloadBytes(List<int> bytes, String filename) {
    triggerCsvDownload(bytes, filename);
  }

  // ── Date picker helper ────────────────────────────────────────────────────

  Future<void> _pickDate(bool isFrom) async {
    final initial = isFrom
        ? (_from ?? DateTime.now().subtract(const Duration(days: 7)))
        : (_to ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _from = picked;
        } else {
          _to = picked;
        }
      });
    }
  }

  // ── Action color coding ───────────────────────────────────────────────────

  Color _actionColor(String action) {
    final a = action.toUpperCase();
    if (a.contains('LOGIN')) return AppTheme.statusPresent;
    if (a.contains('DELETE') || a.contains('REJECT')) return AppTheme.brandDanger;
    if (a.contains('APPROVE')) return AppTheme.accent;
    if (a.contains('RESET') || a.contains('ROLE')) return AppTheme.brandWarning;
    return AppTheme.darkTextMuted;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                      'Audit Logs',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'System activity and security event trail',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Export CSV'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.statusPresent,
                  side: BorderSide(color: AppTheme.statusPresent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loading ? null : _exportCsv,
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  side: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loading ? null : () => _fetch(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Filter bar ─────────────────────────────────────────────
          _FilterBar(
            isDark: isDark,
            from: _from,
            to: _to,
            actionCtrl: _actionCtrl,
            usernameCtrl: _usernameCtrl,
            onPickFrom: () => _pickDate(true),
            onPickTo: () => _pickDate(false),
            onApply: _applyFilters,
            onClear: _clearFilters,
          ),
          const SizedBox(height: 14),

          // ── Error banner ───────────────────────────────────────────
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                  icon: const Icon(Icons.close, size: 15, color: AppTheme.brandDanger),
                  onPressed: () => setState(() => _error = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

          // ── Table ──────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Column(
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
                      _colH('Timestamp', flex: 3),
                      _colH('User', flex: 2),
                      _colH('Action', flex: 3),
                      _colH('Description', flex: 6),
                      _colH('IP Address', flex: 2),
                    ]),
                  ),

                  // Rows
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _logs.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.security_rounded, size: 42,
                                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No audit logs found',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Try adjusting your filters',
                                      style: TextStyle(
                                        color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _logs.length,
                                itemBuilder: (ctx, i) => _LogRow(
                                  log: _logs[i],
                                  isDark: isDark,
                                  isEven: i.isEven,
                                  actionColor: _actionColor((_logs[i]['action'] ?? '') as String),
                                ),
                              ),
                  ),

                  // ── Pagination footer ──────────────────────────────
                  _PaginationBar(
                    isDark: isDark,
                    page: _page,
                    pages: _pages,
                    total: _total,
                    loading: _loading,
                    onPrev: _page > 1 ? () => _fetch(page: _page - 1) : null,
                    onNext: _page < _pages ? () => _fetch(page: _page + 1) : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colH(String label, {int flex = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
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

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final bool isDark;
  final DateTime? from;
  final DateTime? to;
  final TextEditingController actionCtrl;
  final TextEditingController usernameCtrl;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _FilterBar({
    required this.isDark,
    required this.from,
    required this.to,
    required this.actionCtrl,
    required this.usernameCtrl,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final fillColor = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;
    final fmt = DateFormat('dd MMM yyyy');

    InputDecoration _inputDeco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: subColor, fontSize: 13),
          filled: true,
          fillColor: fillColor,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
        );

    Widget _datePicker({required String label, required DateTime? value, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: value != null ? AppTheme.accent.withOpacity(0.5) : borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_rounded, size: 14,
                  color: value != null ? AppTheme.accent : subColor),
              const SizedBox(width: 7),
              Text(
                value != null ? fmt.format(value) : label,
                style: TextStyle(
                  color: value != null ? textColor : subColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Date From
          _datePicker(label: 'Date From', value: from, onTap: onPickFrom),
          // Date To
          _datePicker(label: 'Date To', value: to, onTap: onPickTo),
          // Action filter
          SizedBox(
            width: 180,
            child: TextField(
              controller: actionCtrl,
              style: TextStyle(color: textColor, fontSize: 13),
              decoration: _inputDeco('Filter by action…'),
              onSubmitted: (_) => onApply(),
            ),
          ),
          // Username filter
          SizedBox(
            width: 180,
            child: TextField(
              controller: usernameCtrl,
              style: TextStyle(color: textColor, fontSize: 13),
              decoration: _inputDeco('Filter by username…'),
              onSubmitted: (_) => onApply(),
            ),
          ),
          // Apply
          ElevatedButton.icon(
            icon: const Icon(Icons.search_rounded, size: 15),
            label: const Text('Apply'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            onPressed: onApply,
          ),
          // Clear
          OutlinedButton.icon(
            icon: const Icon(Icons.clear_rounded, size: 15),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

// ── Log table row ─────────────────────────────────────────────────────────────

class _LogRow extends StatefulWidget {
  final Map<String, dynamic> log;
  final bool isDark;
  final bool isEven;
  final Color actionColor;

  const _LogRow({
    required this.log,
    required this.isDark,
    required this.isEven,
    required this.actionColor,
  });

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final isDark = widget.isDark;

    Color rowBg;
    if (_hovered) {
      rowBg = isDark ? const Color(0xFF1A2B47) : const Color(0xFFEDF2FB);
    } else if (widget.isEven) {
      rowBg = isDark ? AppTheme.darkCard : Colors.white;
    } else {
      rowBg = isDark ? const Color(0xFF0F1A2E) : const Color(0xFFF7FAFF);
    }

    // Parse timestamp
    String timeStr = '—';
    final rawTs = log['timestamp'] ?? log['createdAt'] ?? log['created_at'];
    if (rawTs != null) {
      try {
        timeStr = DateFormat('yyyy-MM-dd hh:mm:ss a').format(DateTime.parse(rawTs as String).toLocal());
      } catch (_) {
        timeStr = rawTs as String;
      }
    }

    final action = (log['action'] ?? '') as String;
    final username = (log['username'] ?? log['performedBy'] ?? log['performed_by'] ?? 'System') as String;
    final description = (log['description'] ?? log['details'] ?? log['detail'] ?? '') as String;
    final ip = (log['ipAddress'] ?? log['ip_address'] ?? log['ip'] ?? '—') as String;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            bottom: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Timestamp
            Expanded(
              flex: 3,
              child: Text(
                timeStr,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // User
            Expanded(
              flex: 2,
              child: Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    username,
                    style: TextStyle(
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            // Action chip
            Expanded(
              flex: 3,
              child: _ActionChip(action: action, color: widget.actionColor),
            ),
            // Description
            Expanded(
              flex: 6,
              child: Text(
                description.isNotEmpty ? description : '—',
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                  fontSize: 12.5,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            // IP
            Expanded(
              flex: 2,
              child: Text(
                ip,
                style: TextStyle(
                  color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String action;
  final Color color;

  const _ActionChip({required this.action, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      constraints: const BoxConstraints(maxWidth: 160),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        action,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Pagination bar ────────────────────────────────────────────────────────────

class _PaginationBar extends StatelessWidget {
  final bool isDark;
  final int page;
  final int pages;
  final int total;
  final bool loading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.isDark,
    required this.page,
    required this.pages,
    required this.total,
    required this.loading,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textSub = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    final textMuted = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            '$total record${total == 1 ? '' : 's'}',
            style: TextStyle(color: textMuted, fontSize: 12),
          ),
          const Spacer(),
          // Previous
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_left_rounded, size: 16),
            label: const Text('Previous'),
            style: OutlinedButton.styleFrom(
              foregroundColor: onPrev != null ? textSub : textMuted,
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            onPressed: loading ? null : onPrev,
          ),
          const SizedBox(width: 12),
          // Page indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            ),
            child: Text(
              'Page $page of $pages',
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Next
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_right_rounded, size: 16),
            label: const Text('Next'),
            iconAlignment: IconAlignment.end,
            style: OutlinedButton.styleFrom(
              foregroundColor: onNext != null ? textSub : textMuted,
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            onPressed: loading ? null : onNext,
          ),
        ],
      ),
    );
  }
}
