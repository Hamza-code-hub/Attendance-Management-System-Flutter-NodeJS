import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/server_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../authentication/presentation/auth_state.dart';
import '../../adjustments/adjustments_provider.dart';
import '../../overtime/overtime_provider.dart';

// ============================================================================
// EMPLOYEE REQUESTS SCREEN — Three independent request modules
//
// 1. Correction Request  — fix a wrong or missed check-in / check-out punch
// 2. Overtime Request    — record paid extra hours worked after shift
// 3. Time Adjustment     — unpaid makeup hours to cover an absent day
// ============================================================================

class EmployeeRequestsScreen extends ConsumerStatefulWidget {
  const EmployeeRequestsScreen({super.key});

  @override
  ConsumerState<EmployeeRequestsScreen> createState() =>
      _EmployeeRequestsScreenState();
}

class _EmployeeRequestsScreenState
    extends ConsumerState<EmployeeRequestsScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabs;
  int _type = 0; // 0=Correction  1=Overtime  2=Time Adjustment

  // ── Correction state ────────────────────────────────────────────────────
  String _corrSubType = 'WRONG_CHECKOUT'; // default: most common — wrong checkout time
  DateTime _corrDate = DateTime.now();
  TimeOfDay? _corrTime;
  final _corrReason = TextEditingController();

  bool   _dateChecking = false;
  bool?  _dateHasCheckin;
  bool?  _dateHasCheckout;
  String? _existingCheckin;
  String? _existingCheckout;

  // ── Overtime state ───────────────────────────────────────────────────────
  DateTime _otDate = DateTime.now();
  final _otMins   = TextEditingController();
  final _otReason = TextEditingController();

  // ── Time Adjustment state ────────────────────────────────────────────────
  DateTime _adjDate = DateTime.now();
  final _adjMins   = TextEditingController();
  final _adjReason = TextEditingController();

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDate(_corrDate));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _corrReason.dispose();
    _otMins.dispose();
    _otReason.dispose();
    _adjMins.dispose();
    _adjReason.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Date-attendance check
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _checkDate(DateTime d) async {
    final ds = DateFormat('yyyy-MM-dd').format(d);
    setState(() {
      _dateChecking = true;
      _dateHasCheckin = _dateHasCheckout = null;
      _existingCheckin = _existingCheckout = null;
    });
    try {
      final token = ref.read(authProvider).accessToken ?? '';
      final res = await http.get(
        Uri.parse('${ServerConfig.apiBase}/attendance/check-date/$ds'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final d2 = (jsonDecode(res.body) as Map)['data'] as Map;
        setState(() {
          _dateHasCheckin  = d2['checkInTime'] != null;
          _dateHasCheckout = d2['checkOutTime'] != null;
          if (d2['checkInTime']  != null)
            _existingCheckin  = DateFormat('hh:mm a').format(DateTime.parse(d2['checkInTime']).toLocal());
          if (d2['checkOutTime'] != null)
            _existingCheckout = DateFormat('hh:mm a').format(DateTime.parse(d2['checkOutTime']).toLocal());
        });
      }
    } catch (_) {}
    setState(() => _dateChecking = false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Submit handlers
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _submitCorrection() async {
    if (_corrTime == null) { _err('Select the correct time first.'); return; }
    if (_corrReason.text.trim().isEmpty) { _err('Reason is required.'); return; }
    setState(() => _submitting = true);
    try {
      final token = ref.read(authProvider).accessToken ?? '';
      final dt = DateTime(_corrDate.year, _corrDate.month, _corrDate.day,
          _corrTime!.hour, _corrTime!.minute);

      // Map frontend types to API types — WRONG_* maps to MISSED_* (same backend logic)
      final bool needsCheckin  = ['WRONG_CHECKIN',  'MISSED_CHECKIN'].contains(_corrSubType);
      final bool needsCheckout = ['WRONG_CHECKOUT', 'MISSED_CHECKOUT'].contains(_corrSubType);
      final String apiType = needsCheckin ? 'MISSED_CHECKIN' : 'MISSED_CHECKOUT';

      final body = {
        'adjustmentType': apiType,
        'reason': _corrReason.text.trim(),
        if (needsCheckin)  'requestedCheckinTime':  dt.toUtc().toIso8601String(),
        if (needsCheckout) 'requestedCheckoutTime': dt.toUtc().toIso8601String(),
      };
      final res = await http.post(Uri.parse('${ServerConfig.apiBase}/adjustments/request'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode(body));
      final rb = jsonDecode(res.body) as Map;
      if (res.statusCode == 201 && rb['success'] == true) {
        _ok('Correction request submitted — awaiting approval.');
        setState(() {
          _corrSubType = 'WRONG_CHECKOUT'; _corrDate = DateTime.now(); _corrTime = null;
          _corrReason.clear();
          _dateHasCheckin = _dateHasCheckout = null;
        });
        ref.read(adjustmentProvider.notifier).fetchHistory();
      } else {
        _err((rb['error'] as Map?)?['message'] as String? ?? 'Submit failed.');
      }
    } catch (_) { _err('Network error.'); }
    setState(() => _submitting = false);
  }

  Future<void> _submitOvertime() async {
    final mins = int.tryParse(_otMins.text.trim());
    if (mins == null || mins <= 0 || mins > 480) {
      _err('Enter valid minutes (1–480).'); return;
    }
    if (_otReason.text.trim().isEmpty) { _err('Reason is required.'); return; }
    setState(() => _submitting = true);
    try {
      final ok = await ref.read(overtimeProvider.notifier)
          .createRequest(DateFormat('yyyy-MM-dd').format(_otDate), mins, _otReason.text.trim());
      if (ok && mounted) {
        _ok('Overtime request submitted — awaiting approval.');
        setState(() { _otDate = DateTime.now(); _otMins.clear(); _otReason.clear(); });
      } else { _err('Submit failed.'); }
    } catch (_) { _err('Network error.'); }
    setState(() => _submitting = false);
  }

  Future<void> _submitAdjustment() async {
    final mins = int.tryParse(_adjMins.text.trim());
    if (mins == null || mins <= 0 || mins > 480) {
      _err('Enter valid minutes (1–480).'); return;
    }
    if (_adjReason.text.trim().isEmpty) { _err('Reason is required.'); return; }
    setState(() => _submitting = true);
    try {
      final token = ref.read(authProvider).accessToken ?? '';
      final res = await http.post(Uri.parse('${ServerConfig.apiBase}/adjustments/request'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'adjustmentType': 'TIME_ADJUSTMENT',
            'reason': _adjReason.text.trim(),
            'requestedMinutes': mins,
            'requestDate': DateFormat('yyyy-MM-dd').format(_adjDate),
          }));
      final rb = jsonDecode(res.body) as Map;
      if (res.statusCode == 201 && rb['success'] == true) {
        _ok('Time adjustment request submitted — awaiting approval.');
        setState(() { _adjDate = DateTime.now(); _adjMins.clear(); _adjReason.clear(); });
        ref.read(adjustmentProvider.notifier).fetchHistory();
      } else {
        _err((rb['error'] as Map?)?['message'] as String? ?? 'Submit failed.');
      }
    } catch (_) { _err('Network error.'); }
    setState(() => _submitting = false);
  }

  void _ok(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.statusPresent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.statusAbsent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final adjState = ref.watch(adjustmentProvider);
    final otState  = ref.watch(overtimeProvider);

    // Build combined history list
    final hist = <_HItem>[];
    for (final r in adjState.history) {
      final isCorr = {'MISSED_CHECKIN','MISSED_CHECKOUT','CUSTOM'}
          .contains(r.adjustmentType.toUpperCase());
      hist.add(_HItem(
        type: isCorr ? 'Correction' : 'Time Adjustment',
        icon: isCorr ? Icons.edit_note_rounded : Icons.swap_horiz_rounded,
        color: isCorr ? AppTheme.accent : AppTheme.statusPending,
        date: _pd(r.requestedCheckinTime ?? r.requestedCheckoutTime ?? r.createdAt),
        detail: isCorr ? _corrDetail(r) : '${r.requestedMinutes} min makeup',
        status: r.status,
        comment: r.hrComment,
      ));
    }
    for (final r in otState.history) {
      hist.add(_HItem(
        type: 'Overtime',
        icon: Icons.more_time_rounded,
        color: AppTheme.statusOvertime,
        date: _pd(r.requestDate),
        detail: '${r.requestedMinutes} min'
            + (r.approvedMinutes > 0 ? ' → ${r.approvedMinutes} min approved' : ''),
        status: r.status,
        comment: r.hrComment,
      ));
    }
    hist.sort((a, b) => b.date.compareTo(a.date));
    final pending = hist.where((h) => h.status == 'PENDING').length;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────
          _header(isDark, pending),

          // ── Type pills ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _typePills(isDark),
          ),

          // ── Tab bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _tabBar(isDark, hist),
          ),
          const SizedBox(height: 12),

          // ── Tab content (fills remaining space, scrolls) ──────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _form(isDark),
                _history(isDark, hist),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(bool isDark, int pending) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final text   = isDark ? AppTheme.darkText    : AppTheme.lightText;
    final sub    = isDark ? AppTheme.darkTextSub  : AppTheme.lightTextSub;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
        color: isDark ? AppTheme.darkSurface : Colors.white,
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => context.go('/attendance'),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightElevated,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
            ),
            child: Icon(Icons.arrow_back_rounded, size: 17, color: sub),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.assignment_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Requests',
              style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 16),
              overflow: TextOverflow.ellipsis),
            Text('Submit and track your requests',
              style: TextStyle(color: sub, fontSize: 11.5),
              overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (pending > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.statusPending.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.statusPending.withOpacity(0.3)),
            ),
            child: Text('$pending pending',
              style: const TextStyle(color: AppTheme.statusPending, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }

  // ── Type pills (compact mobile-friendly) ──────────────────────────────────
  Widget _typePills(bool isDark) {
    const types = [
      ('Correction', Icons.edit_note_rounded,    Color(0xFF3D94F7)),
      ('Overtime',   Icons.more_time_rounded,    Color(0xFF00C2FF)),
      ('Adjustment', Icons.swap_horiz_rounded,   Color(0xFFFFB020)),
    ];

    return Row(
      children: types.asMap().entries.map((e) {
        final idx     = e.key;
        final label   = e.value.$1;
        final icon    = e.value.$2;
        final color   = e.value.$3;
        final sel     = _type == idx;
        final border  = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _type = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(right: idx < 2 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? color.withOpacity(0.14)
                    : (isDark ? AppTheme.darkCard : Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? color.withOpacity(0.55) : border,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: sel ? color : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
                const SizedBox(height: 4),
                Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? color : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────
  Widget _tabBar(bool isDark, List<_HItem> hist) {
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final card   = isDark ? AppTheme.darkCard : Colors.white;
    final sub    = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: TabBar(
        controller: _tabs,
        indicator: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(8)),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: sub,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: [
          Tab(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_circle_outline_rounded, size: 15),
              const SizedBox(width: 6),
              const Text('New Request'),
            ]),
          )),
          Tab(child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.history_rounded, size: 15),
              const SizedBox(width: 6),
              const Text('History'),
              if (hist.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('${hist.length}', style: const TextStyle(fontSize: 10)),
                ),
              ],
            ]),
          )),
        ],
      ),
    );
  }

  // ── Form panel ────────────────────────────────────────────────────────────
  Widget _form(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(children: [
        if (_type == 0) _correctionForm(isDark),
        if (_type == 1) _overtimeForm(isDark),
        if (_type == 2) _adjustmentForm(isDark),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CORRECTION FORM
  // ─────────────────────────────────────────────────────────────────────────
  Widget _correctionForm(bool isDark) {
    final f = _FormStyle(isDark);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fmHdr(
        isDark: isDark,
        icon: Icons.edit_note_rounded,
        color: AppTheme.accent,
        title: 'Correction Request',
        sub: 'Fix a missed or wrong check-in / check-out punch',
      ),
      const SizedBox(height: 14),

      // What was missed
      _lbl('What needs to be corrected?', f.sub),
      const SizedBox(height: 6),
      _dropCard(
        isDark: isDark,
        value: _corrSubType,
        items: const [
          ('WRONG_CHECKOUT',  'Wrong Check-Out — I checked out at the wrong time'),
          ('WRONG_CHECKIN',   'Wrong Check-In  — I checked in at the wrong time'),
          ('MISSED_CHECKOUT', 'Missed Check-Out — forgot to punch out'),
          ('MISSED_CHECKIN',  'Missed Check-In  — forgot to punch in'),
        ],
        onChanged: (v) => setState(() { _corrSubType = v; _corrTime = null; _checkDate(_corrDate); }),
      ),
      const SizedBox(height: 12),

      // Date
      _lbl('Date of the missed punch', f.sub),
      const SizedBox(height: 6),
      _dateTile(
        date: _corrDate,
        accentColor: AppTheme.accent,
        isDark: isDark,
        onTap: () => _pickDate((d) { setState(() { _corrDate = d; _corrTime = null; }); _checkDate(d); },
            initial: _corrDate),
      ),
      const SizedBox(height: 8),

      // Date validation — shows existing recorded time for WRONG types, warns for MISSED types
      if (_dateChecking)
        _validChip(icon: Icons.hourglass_top_rounded, msg: 'Checking attendance record…', color: AppTheme.accent, isDark: isDark)
      else if (_corrSubType == 'WRONG_CHECKIN' && _dateHasCheckin == true)
        _validChip(
          icon: Icons.update_rounded,
          msg: 'Currently recorded check-in: $_existingCheckin. Enter the correct time below.',
          color: AppTheme.accent, isDark: isDark)
      else if (_corrSubType == 'WRONG_CHECKIN' && _dateHasCheckin == false)
        _validChip(
          icon: Icons.error_outline_rounded,
          msg: 'No check-in found for this date. Use "Missed Check-In" type instead.',
          color: AppTheme.statusAbsent, isDark: isDark)
      else if (_corrSubType == 'WRONG_CHECKOUT' && _dateHasCheckout == true)
        _validChip(
          icon: Icons.update_rounded,
          msg: 'Currently recorded check-out: $_existingCheckout. Enter the correct time below.',
          color: AppTheme.accent, isDark: isDark)
      else if (_corrSubType == 'WRONG_CHECKOUT' && _dateHasCheckout == false)
        _validChip(
          icon: Icons.error_outline_rounded,
          msg: 'No check-out found for this date. Use "Missed Check-Out" type instead.',
          color: AppTheme.statusAbsent, isDark: isDark)
      else if (_corrSubType == 'MISSED_CHECKIN' && _dateHasCheckin == true)
        _validChip(icon: Icons.warning_amber_rounded, msg: 'Check-in already recorded at $_existingCheckin. Submit only if it was wrong.', color: AppTheme.statusPending, isDark: isDark)
      else if (_corrSubType == 'MISSED_CHECKOUT' && _dateHasCheckout == true)
        _validChip(icon: Icons.warning_amber_rounded, msg: 'Check-out already recorded at $_existingCheckout. Submit only if it was wrong.', color: AppTheme.statusPending, isDark: isDark)
      else if (_corrSubType == 'MISSED_CHECKOUT' && _dateHasCheckin == false)
        _validChip(icon: Icons.error_outline_rounded, msg: 'No check-in found for this date. Cannot correct check-out without a check-in.', color: AppTheme.statusAbsent, isDark: isDark)
      else if (_dateHasCheckin != null)
        _validChip(
          icon: Icons.check_circle_outline_rounded,
          msg: _corrSubType == 'MISSED_CHECKIN'
              ? 'No existing check-in — the correction will add the missing punch.'
              : 'Check-in found at ${_existingCheckin ?? "?"}. Correction will add the missing check-out.',
          color: AppTheme.statusPresent, isDark: isDark,
        ),
      const SizedBox(height: 12),

      // Time picker
      _lbl(
        _corrSubType == 'WRONG_CHECKIN'  ? 'What is the correct check-in time?' :
        _corrSubType == 'WRONG_CHECKOUT' ? 'What is the correct check-out time?' :
        _corrSubType == 'MISSED_CHECKIN' ? 'What time did you actually arrive?' :
                                           'What time did you actually leave?',
        f.sub,
      ),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => _pickTime((t) => setState(() => _corrTime = t), initial: _corrTime),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: f.fill,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _corrTime != null ? AppTheme.accent.withOpacity(0.6) : f.border, width: _corrTime != null ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(Icons.access_time_rounded, size: 17, color: _corrTime != null ? AppTheme.accent : f.sub),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _corrTime != null ? _corrTime!.format(context) : 'Tap to select time',
                style: TextStyle(color: _corrTime != null ? f.text : f.sub, fontSize: 14,
                    fontWeight: _corrTime != null ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            if (_corrTime != null)
              GestureDetector(onTap: () => setState(() => _corrTime = null),
                  child: Icon(Icons.clear_rounded, size: 16, color: f.sub)),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      _lbl('Reason / Explanation', f.sub),
      const SizedBox(height: 6),
      _textArea(ctrl: _corrReason, hint: 'e.g. Scanner was busy when I arrived at 9 AM…', f: f),
      const SizedBox(height: 12),

      _infoBanner(
        icon: Icons.shield_outlined,
        msg: 'Original records are never deleted. After approval, the attendance log is updated.',
        color: AppTheme.accent, isDark: isDark,
      ),
      const SizedBox(height: 16),

      _submitBtn(
        label: 'Submit Correction',
        loading: _submitting,
        onTap: _submitting ? null : _submitCorrection,
        gradient: const LinearGradient(colors: [Color(0xFF3D94F7), Color(0xFF00C2FF)]),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OVERTIME FORM
  // ─────────────────────────────────────────────────────────────────────────
  Widget _overtimeForm(bool isDark) {
    final f = _FormStyle(isDark);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fmHdr(
        isDark: isDark,
        icon: Icons.more_time_rounded,
        color: AppTheme.statusOvertime,
        title: 'Overtime Request',
        sub: 'Request paid compensation for extra hours worked after your shift',
      ),
      const SizedBox(height: 14),

      _lbl('Date you worked overtime', f.sub),
      const SizedBox(height: 6),
      _dateTile(date: _otDate, accentColor: AppTheme.statusOvertime, isDark: isDark,
          onTap: () => _pickDate((d) => setState(() => _otDate = d), initial: _otDate)),
      const SizedBox(height: 12),

      _lbl('Extra minutes worked', f.sub),
      const SizedBox(height: 6),
      _minField(ctrl: _otMins, hint: 'e.g. 120 for 2 hours', f: f),
      const SizedBox(height: 12),

      _lbl('Reason for overtime', f.sub),
      const SizedBox(height: 6),
      _textArea(ctrl: _otReason, hint: 'e.g. Stayed for project deployment deadline…', f: f),
      const SizedBox(height: 12),

      _infoBanner(
        icon: Icons.payments_outlined,
        msg: 'Overtime is paid at your overtime rate after manager and HR approval.',
        color: AppTheme.statusOvertime, isDark: isDark,
      ),
      const SizedBox(height: 16),

      _submitBtn(
        label: 'Submit Overtime Request',
        loading: _submitting,
        onTap: _submitting ? null : _submitOvertime,
        gradient: const LinearGradient(colors: [Color(0xFF00C2FF), Color(0xFF00D68F)]),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TIME ADJUSTMENT FORM
  // ─────────────────────────────────────────────────────────────────────────
  Widget _adjustmentForm(bool isDark) {
    final f = _FormStyle(isDark);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _fmHdr(
        isDark: isDark,
        icon: Icons.swap_horiz_rounded,
        color: AppTheme.statusPending,
        title: 'Time Adjustment',
        sub: 'Unpaid makeup hours to cover work not done during normal hours',
      ),
      const SizedBox(height: 14),

      _lbl('Date you were absent / short on hours', f.sub),
      const SizedBox(height: 6),
      _dateTile(date: _adjDate, accentColor: AppTheme.statusPending, isDark: isDark,
          onTap: () => _pickDate((d) => setState(() => _adjDate = d), initial: _adjDate)),
      const SizedBox(height: 12),

      _lbl('Makeup minutes to cover', f.sub),
      const SizedBox(height: 6),
      _minField(ctrl: _adjMins, hint: 'e.g. 480 for a full 8-hour day', f: f),
      const SizedBox(height: 12),

      _lbl('Reason for absence / short hours', f.sub),
      const SizedBox(height: 6),
      _textArea(ctrl: _adjReason,
          hint: 'e.g. Personal emergency on Monday — will work extra Tue & Wed…', f: f),
      const SizedBox(height: 12),

      _infoBanner(
        icon: Icons.swap_horiz_rounded,
        msg: 'This is unpaid. You commit to working these hours on other days to compensate.',
        color: AppTheme.statusPending, isDark: isDark,
      ),
      const SizedBox(height: 16),

      _submitBtn(
        label: 'Submit Adjustment',
        loading: _submitting,
        onTap: _submitting ? null : _submitAdjustment,
        gradient: const LinearGradient(colors: [Color(0xFFF5A623), Color(0xFFFFB020)]),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HISTORY LIST
  // ─────────────────────────────────────────────────────────────────────────
  Widget _history(bool isDark, List<_HItem> hist) {
    final card   = isDark ? AppTheme.darkCard : Colors.white;
    final border = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final sub    = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    if (hist.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 54, height: 54,
              decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(Icons.inbox_rounded, size: 26, color: AppTheme.accent.withOpacity(0.4))),
          const SizedBox(height: 12),
          Text('No requests yet', style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Submit your first request above', style: TextStyle(color: sub, fontSize: 13)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: hist.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final h = hist[i];
        final sc = _sColor(h.status);
        final sl = _sLabel(h.status);
        final si = _sIcon(h.status);
        return Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: IntrinsicHeight(
            child: Row(children: [
              // Left accent bar
              Container(width: 4, decoration: BoxDecoration(
                  color: h.color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 30, height: 30,
                          decoration: BoxDecoration(color: h.color.withOpacity(0.1), borderRadius: BorderRadius.circular(7)),
                          child: Icon(h.icon, size: 15, color: h.color)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.type,
                              style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText,
                                  fontWeight: FontWeight.w700, fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                          Text(DateFormat('dd MMM yyyy').format(h.date),
                              style: TextStyle(color: sub, fontSize: 11.5)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      // Status chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sc.withOpacity(0.25)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(si, size: 10, color: sc),
                          const SizedBox(width: 3),
                          Text(sl, style: TextStyle(color: sc, fontSize: 10, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(h.detail,
                        style: TextStyle(color: sub, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                    if (h.comment != null && h.comment!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: border),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.comment_rounded, size: 12, color: sub),
                          const SizedBox(width: 6),
                          Expanded(child: Text('HR: ${h.comment}',
                              style: TextStyle(color: sub, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED FORM BUILDING BLOCKS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _fmHdr({required bool isDark, required IconData icon, required Color color,
      required String title, required String sub}) {
    final text = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subC = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 14),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: subC, fontSize: 11.5), overflow: TextOverflow.ellipsis, maxLines: 2),
          ]),
        ),
      ]),
    );
  }

  Widget _lbl(String t, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(t, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
  );

  Widget _dropCard({required bool isDark, required String value,
      required List<(String, String)> items, required ValueChanged<String> onChanged}) {
    final f = _FormStyle(isDark);
    return Container(
      decoration: BoxDecoration(color: f.fill, borderRadius: BorderRadius.circular(9), border: Border.all(color: f.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(9),
          dropdownColor: f.fill,
          style: TextStyle(color: f.text, fontSize: 13.5),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          items: items.map((p) => DropdownMenuItem(value: p.$1, child: Text(p.$2, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _dateTile({required DateTime date, required Color accentColor,
      required bool isDark, required VoidCallback onTap}) {
    final f = _FormStyle(isDark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: f.fill, borderRadius: BorderRadius.circular(9), border: Border.all(color: f.border)),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded, size: 16, color: accentColor),
          const SizedBox(width: 10),
          Expanded(child: Text(DateFormat('EEE, d MMM yyyy').format(date),
              style: TextStyle(color: f.text, fontSize: 14), overflow: TextOverflow.ellipsis)),
          Icon(Icons.expand_more_rounded, color: f.sub, size: 20),
        ]),
      ),
    );
  }

  Widget _minField({required TextEditingController ctrl, required String hint, required _FormStyle f}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: TextStyle(color: f.text, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13),
        filled: true, fillColor: f.fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        suffix: Text('min', style: TextStyle(color: f.sub, fontSize: 13)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: f.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: f.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
      ),
    );
  }

  Widget _textArea({required TextEditingController ctrl, required String hint, required _FormStyle f}) {
    return TextField(
      controller: ctrl,
      minLines: 3, maxLines: 5,
      style: TextStyle(color: f.text, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted, fontSize: 13),
        filled: true, fillColor: f.fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: f.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: f.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
      ),
    );
  }

  Widget _validChip({required IconData icon, required String msg, required Color color, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.1 : 0.07),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: color, fontSize: 12, height: 1.4))),
        ]),
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required String msg, required Color color, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.09 : 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: TextStyle(color: color, fontSize: 12, height: 1.4))),
      ]),
    );
  }

  Widget _submitBtn({required String label, required bool loading, required VoidCallback? onTap, required Gradient gradient}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 180),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: onTap == null ? null : gradient,
            color: onTap == null ? (isDark ? AppTheme.darkInput : AppTheme.lightInput) : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: onTap != null ? [
              BoxShadow(color: (gradient as LinearGradient).colors.first.withOpacity(0.28), blurRadius: 12, offset: const Offset(0, 4)),
            ] : null,
          ),
          child: Center(child: loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
          ),
        ),
      ),
    );
  }

  // ── Pickers ────────────────────────────────────────────────────────────────
  Future<void> _pickDate(ValueSetter<DateTime> set, {DateTime? initial}) async {
    final p = await showDatePicker(context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime.now().subtract(const Duration(days: 90)),
        lastDate: DateTime.now());
    if (p != null) set(p);
  }

  Future<void> _pickTime(ValueSetter<TimeOfDay> set, {TimeOfDay? initial}) async {
    final p = await showTimePicker(context: context, initialTime: initial ?? TimeOfDay.now());
    if (p != null) set(p);
  }

  // ── Status helpers ─────────────────────────────────────────────────────────
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color _sColor(String s) {
    switch (s) {
      case 'APPROVED': return AppTheme.statusApproved;
      case 'REJECTED': return AppTheme.statusRejected;
      case 'MANAGER_APPROVE': return AppTheme.accent;
      case 'PARTIAL': return AppTheme.statusPending;
      default: return AppTheme.statusPending;
    }
  }

  String _sLabel(String s) {
    switch (s) {
      case 'APPROVED': return 'Approved';
      case 'REJECTED': return 'Rejected';
      case 'MANAGER_APPROVE': return 'With HR';
      case 'PARTIAL': return 'Partial';
      default: return 'Pending';
    }
  }

  IconData _sIcon(String s) {
    switch (s) {
      case 'APPROVED': return Icons.check_circle_rounded;
      case 'REJECTED': return Icons.cancel_rounded;
      case 'MANAGER_APPROVE': return Icons.send_rounded;
      default: return Icons.schedule_rounded;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _FormStyle {
  final Color fill;
  final Color border;
  final Color text;
  final Color sub;

  _FormStyle(bool isDark)
      : fill   = isDark ? AppTheme.darkInput    : AppTheme.lightInput,
        border = isDark ? AppTheme.darkBorder   : AppTheme.lightBorder,
        text   = isDark ? AppTheme.darkText     : AppTheme.lightText,
        sub    = isDark ? AppTheme.darkTextSub  : AppTheme.lightTextSub;
}

class _HItem {
  final String   type;
  final IconData icon;
  final Color    color;
  final DateTime date;
  final String   detail;
  final String   status;
  final String?  comment;

  const _HItem({
    required this.type, required this.icon, required this.color,
    required this.date, required this.detail, required this.status,
    this.comment,
  });
}

DateTime _pd(String? s) {
  if (s == null || s.isEmpty) return DateTime.now();
  try { return DateTime.parse(s).toLocal(); } catch (_) { return DateTime.now(); }
}

String _corrDetail(AdjustmentRequest r) {
  final inT  = r.requestedCheckinTime  != null ? DateFormat('hh:mm a').format(DateTime.parse(r.requestedCheckinTime!).toLocal())  : null;
  final outT = r.requestedCheckoutTime != null ? DateFormat('hh:mm a').format(DateTime.parse(r.requestedCheckoutTime!).toLocal()) : null;
  if (inT  != null) return 'Requested check-in → $inT';
  if (outT != null) return 'Requested check-out → $outT';
  return 'Correction';
}
