import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'dashboard_provider.dart';

class EmployeeDirectoryScreen extends ConsumerStatefulWidget {
  const EmployeeDirectoryScreen({super.key});

  @override
  ConsumerState<EmployeeDirectoryScreen> createState() => _EmployeeDirectoryScreenState();
}

class _EmployeeDirectoryScreenState extends ConsumerState<EmployeeDirectoryScreen> {
  final _searchCtrl = TextEditingController();
  String _status = 'ACTIVE';
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() { _loading = true; _error = null; _page = page; });
    try {
      final result = await ref.read(dashboardProvider.notifier).fetchEmployeeDirectory(
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        status: _status,
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
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Employee Directory', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$_total employee(s) found', style: theme.textTheme.bodyMedium),
                ],
              )),
            ]),
            const SizedBox(height: 16),

            // Filters
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search by name, code, or email...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                  onChanged: (v) { if (v.isEmpty) _load(); },
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  DropdownMenuItem(value: 'SUSPENDED', child: Text('Suspended')),
                ],
                onChanged: (v) { if (v != null) { setState(() => _status = v); _load(); } },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
                onPressed: _load,
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(page: _page)),
            ]),
            const SizedBox(height: 12),

            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.brandDanger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.brandDanger.withOpacity(0.3)),
                ),
                child: Text(_error!, style: TextStyle(color: AppTheme.brandDanger, fontSize: 13)),
              ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 48, color: AppTheme.lightTextMuted),
                            SizedBox(height: 16),
                            Text('No employees found'),
                          ],
                        ))
                      : Column(children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: _buildTable(theme, isDark),
                              ),
                            ),
                          ),
                          _PaginationRow(page: _page, totalPages: totalPages, onPage: (p) => _load(page: p)),
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
        DataColumn(label: Text('CODE')),
        DataColumn(label: Text('EMPLOYEE')),
        DataColumn(label: Text('DESIGNATION')),
        DataColumn(label: Text('DEPARTMENT')),
        DataColumn(label: Text('SHIFT')),
        DataColumn(label: Text('EMAIL')),
        DataColumn(label: Text('JOINED')),
        DataColumn(label: Text('LAST LOGIN')),
        DataColumn(label: Text('STATUS')),
      ],
      rows: _rows.map((r) {
        final empStatus = r['employment_status']?.toString() ?? '';
        return DataRow(cells: [
          DataCell(Text(r['employee_code'] ?? '', style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace', fontWeight: FontWeight.w600,
          ))),
          DataCell(Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.brandPrimaryLt.withOpacity(0.12),
              child: Text(
                (r['employee_name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                style: TextStyle(color: AppTheme.brandPrimaryLt, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Text(r['employee_name'] ?? '', style: theme.textTheme.labelLarge),
          ])),
          DataCell(Text(r['designation'] ?? '—', style: theme.textTheme.bodyMedium)),
          DataCell(Text(r['department_name'] ?? '—', style: theme.textTheme.bodyMedium)),
          DataCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(r['shift_name'] ?? '—', style: theme.textTheme.bodyMedium),
              if (r['shift_start'] != null)
                Text('${r['shift_start']}–${r['shift_end']}', style: theme.textTheme.bodySmall),
            ],
          )),
          DataCell(Text(r['email'] ?? '—', style: theme.textTheme.bodySmall)),
          DataCell(Text(_fmtDate(r['joining_date']?.toString()), style: theme.textTheme.bodySmall)),
          DataCell(Text(_fmtDate(r['last_login']?.toString()), style: theme.textTheme.bodySmall)),
          DataCell(_StatusBadge(status: empStatus)),
        ]);
      }).toList(),
    );
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '—';
    try { return DateFormat('MMM dd, yyyy').format(DateTime.parse(s)); }
    catch (_) { return s; }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case 'ACTIVE': return AppTheme.statusPresent;
      case 'INACTIVE': return AppTheme.lightTextMuted;
      case 'SUSPENDED': return AppTheme.statusAbsent;
      default: return AppTheme.lightTextMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.only(top: 12),
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
