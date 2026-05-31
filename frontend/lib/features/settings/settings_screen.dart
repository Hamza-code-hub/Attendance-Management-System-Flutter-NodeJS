import 'dart:convert';
import '../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';
import '../../features/authentication/presentation/auth_state.dart';

String get _base => ServerConfig.apiBase;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, dynamic> _settings = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  // Controllers for editable fields
  final Map<String, TextEditingController> _controllers = {};

  static const Map<String, String> _labels = {
    'grace_period_minutes': 'Grace Period (minutes)',
    'office_subnet': 'Office IP Subnet Prefix',
    'enforce_subnet': 'Enforce Office Subnet',
    'missed_checkout_hours': 'Missed Checkout Threshold (hours)',
    'max_break_minutes': 'Max Break Duration (minutes)',
    'org_name': 'Organization Name',
    'allow_self_checkout': 'Allow Self Check-out',
    'require_manager_approval': 'Require Manager Approval for OT',
    // Shift & break settings
    'shift_name': 'Default Shift Name',
    'shift_start': 'Shift Start Time',
    'shift_end': 'Shift End Time',
    'break_start': 'Break Start Time',
    'break_end': 'Break End Time',
  };

  static const Map<String, String> _hints = {
    'grace_period_minutes': 'e.g. 10',
    'office_subnet': 'e.g. 192.168.1.',
    'enforce_subnet': 'true or false',
    'missed_checkout_hours': 'e.g. 12',
    'max_break_minutes': 'e.g. 60',
    'org_name': 'Your company name',
    'allow_self_checkout': 'true or false',
    'require_manager_approval': 'true or false',
    'shift_name': 'e.g. Morning Shift',
    'shift_start': 'HH:mm  e.g. 09:00',
    'shift_end': 'HH:mm  e.g. 18:00',
    'break_start': 'HH:mm  e.g. 13:00',
    'break_end': 'HH:mm  e.g. 14:00',
  };

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${ref.read(authProvider).accessToken ?? ''}',
    'Content-Type': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await http.get(Uri.parse('$_base/settings'), headers: _headers);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        final data = Map<String, dynamic>.from(body['data'] ?? {});
        setState(() {
          _settings = data;
          _loading = false;
        });
        // Initialize controllers
        for (final key in data.keys) {
          _controllers.putIfAbsent(key, () => TextEditingController());
          _controllers[key]!.text = data[key]?['value'] ?? '';
        }
      } else {
        setState(() { _loading = false; _error = body['error']?['message'] ?? 'Failed to load settings'; });
      }
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      final updates = <String, String>{};
      for (final key in _controllers.keys) {
        updates[key] = _controllers[key]!.text.trim();
      }
      final res = await http.put(
        Uri.parse('$_base/settings'),
        headers: _headers,
        body: jsonEncode(updates),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true) {
        setState(() { _saving = false; _success = 'Settings saved successfully'; });
        await _load();
      } else {
        setState(() { _saving = false; _error = body['error']?['message'] ?? 'Save failed'; });
      }
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  Text('System Settings', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Configure global CyberZeus Attendance settings (Admin only)', style: theme.textTheme.bodyMedium),
                ],
              )),
              ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Settings'),
                onPressed: _saving || _loading ? null : _save,
              ),
            ]),
            const SizedBox(height: 20),

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
                  Expanded(child: Text(_error!, style: TextStyle(color: AppTheme.brandDanger))),
                ]),
              ),

            if (_success != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.statusPresent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.statusPresent.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.check_circle_outline, color: AppTheme.statusPresent, size: 18),
                  const SizedBox(width: 8),
                  Text(_success!, style: TextStyle(color: AppTheme.statusPresent)),
                ]),
              ),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          // Shift & Break Configuration — pinned at top
                          _buildSection(
                            title: 'Shift & Break Configuration',
                            icon: Icons.schedule_rounded,
                            color: AppTheme.accent,
                            children: ['shift_name', 'shift_start', 'shift_end', 'break_start', 'break_end'],
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            title: 'Attendance Rules',
                            icon: Icons.rule_rounded,
                            children: ['grace_period_minutes', 'missed_checkout_hours', 'max_break_minutes', 'allow_self_checkout'],
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            title: 'Organization',
                            icon: Icons.business_rounded,
                            children: ['org_name'],
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            title: 'Network & Access Control',
                            icon: Icons.security_rounded,
                            children: ['office_subnet', 'enforce_subnet'],
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            title: 'Approvals',
                            icon: Icons.fact_check_outlined,
                            children: ['require_manager_approval'],
                          ),
                          const SizedBox(height: 40),
                          // System Health Card
                          _SystemHealthCard(headers: _headers),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required List<String> children, Color? color}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color != null ? color.withOpacity(0.3) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
        boxShadow: color != null ? [BoxShadow(color: color.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 17, color: accentColor),
            ),
            const SizedBox(width: 10),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          ]),
          const SizedBox(height: 16),
          ...children.map((key) {
            final info = _settings[key] as Map<String, dynamic>?;
            final desc = info?['description'] ?? '';
            final ctrl = _controllers.putIfAbsent(key, () => TextEditingController(text: info?['value'] ?? ''));
            final isBool = key == 'enforce_subnet' || key == 'allow_self_checkout' || key == 'require_manager_approval';

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_labels[key] ?? key, style: theme.textTheme.labelLarge),
                        if (desc.isNotEmpty)
                          Text(desc, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: isBool
                        ? DropdownButtonFormField<String>(
                            value: ctrl.text.isEmpty ? 'false' : ctrl.text,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'true', child: Text('Enabled')),
                              DropdownMenuItem(value: 'false', child: Text('Disabled')),
                            ],
                            onChanged: (v) => ctrl.text = v ?? 'false',
                          )
                        : TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: _hints[key] ?? '',
                              isDense: true,
                            ),
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── System Health Card ────────────────────────────────────────────────────

class _SystemHealthCard extends StatefulWidget {
  final Map<String, String> headers;
  const _SystemHealthCard({required this.headers});

  @override
  State<_SystemHealthCard> createState() => _SystemHealthCardState();
}

class _SystemHealthCardState extends State<_SystemHealthCard> {
  Map<String, dynamic>? _health;
  bool _loading = false;

  Future<void> _check() async {
    setState(() { _loading = true; _health = null; });
    try {
      final res = await http.get(Uri.parse('$_base/health'), headers: widget.headers);
      setState(() { _health = jsonDecode(res.body); _loading = false; });
    } catch (e) {
      setState(() { _health = {'status': 'error', 'error': e.toString()}; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final healthy = _health?['status'] == 'healthy';

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
            const Icon(Icons.monitor_heart_outlined, size: 18),
            const SizedBox(width: 8),
            Text('System Health', style: theme.textTheme.titleMedium),
            const Spacer(),
            OutlinedButton.icon(
              icon: _loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.health_and_safety_outlined, size: 16),
              label: const Text('Check Health'),
              onPressed: _loading ? null : _check,
            ),
          ]),
          if (_health != null) ...[
            const SizedBox(height: 16),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (healthy ? AppTheme.statusPresent : AppTheme.statusAbsent).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Icon(
                    healthy ? Icons.check_circle_outline : Icons.error_outline,
                    size: 14,
                    color: healthy ? AppTheme.statusPresent : AppTheme.statusAbsent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    healthy ? 'Healthy' : 'Degraded',
                    style: TextStyle(
                      color: healthy ? AppTheme.statusPresent : AppTheme.statusAbsent,
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              if (_health!['uptime'] != null)
                Text('Uptime: ${_fmtUptime(_health!['uptime'])}', style: theme.textTheme.bodySmall),
              if (_health!['database'] != null) ...[
                const SizedBox(width: 16),
                Text(
                  'DB: ${(_health!['database'] as Map)['status']} (${(_health!['database'] as Map)['latencyMs'] ?? '?'}ms)',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ]),
            if (_health!['system'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Memory: ${(_health!['system'] as Map)['memoryUsedMB']}MB  •  Node: ${(_health!['system'] as Map)['nodeVersion']}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _fmtUptime(dynamic s) {
    final secs = (s as num).toInt();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return '${h}h ${m}m';
  }
}
