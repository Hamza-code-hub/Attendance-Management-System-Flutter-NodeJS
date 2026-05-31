import 'dart:convert';
import '../../../core/config/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../authentication/presentation/auth_state.dart';
import '../adjustments_provider.dart';

// ============================================================================
// CORRECTION REQUEST SCREEN — CyberZeus AMS
// Handles MISSED_CHECKIN and MISSED_CHECKOUT correction requests.
// ============================================================================

class CorrectionRequestScreen extends ConsumerStatefulWidget {
  const CorrectionRequestScreen({super.key});

  @override
  ConsumerState<CorrectionRequestScreen> createState() =>
      _CorrectionRequestScreenState();
}

class _CorrectionRequestScreenState
    extends ConsumerState<CorrectionRequestScreen> {
  // ── Form state ─────────────────────────────────────────────────────────────
  String _typeCtrl = 'WRONG_CHECKIN'; // default: most common correction
  DateTime _date = DateTime.now();
  final _checkinCtrl = TextEditingController();
  final _checkoutCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  // Existing record for the selected date (shown for WRONG_CHECKIN/WRONG_CHECKOUT/CUSTOM)
  String? _existingCheckin;
  String? _existingCheckout;
  bool _isLoadingExisting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchExistingRecord());
  }

  @override
  void dispose() {
    _checkinCtrl.dispose();
    _checkoutCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Combine selected date + "hh:mm a" time field into an ISO datetime string.
  String? _buildDateTime(String timeText) {
    final trimmed = timeText.trim();
    if (trimmed.isEmpty) return null;
    try {
      final dt = DateFormat('hh:mm a').parse(trimmed);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${_formatDate(_date)}T$h:$m:00';
    } catch (_) {
      // Fallback: legacy HH:mm format
      final parts = trimmed.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return '${_formatDate(_date)}T${trimmed.padLeft(5, '0')}:00';
    }
  }

  Future<void> _fetchExistingRecord() async {
    if (!mounted) return;
    setState(() => _isLoadingExisting = true);
    try {
      final token = ref.read(authProvider).accessToken ?? '';
      final dateStr = _formatDate(_date);
      final resp = await http.get(
        Uri.parse('$ServerConfig.apiBase/attendance/check-date/$dateStr'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['success'] == true) {
          final data = body['data'] as Map<String, dynamic>;
          setState(() {
            _existingCheckin  = data['checkInTime']  as String?;
            _existingCheckout = data['checkOutTime'] as String?;
            _isLoadingExisting = false;
          });
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _existingCheckin  = null;
        _existingCheckout = null;
        _isLoadingExisting = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 3)), // 3-day window
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _fetchExistingRecord();
    }
  }

  // Which time fields are shown for the current type
  bool get _needsCheckin  => ['WRONG_CHECKIN',  'MISSED_CHECKIN',  'CUSTOM'].contains(_typeCtrl);
  bool get _needsCheckout => ['WRONG_CHECKOUT', 'MISSED_CHECKOUT', 'CUSTOM'].contains(_typeCtrl);

  // Returns a user-friendly validation error before submitting, null if OK
  String? _validateForm() {
    if (_reasonCtrl.text.trim().isEmpty) return 'Reason / explanation is required.';
    if (_needsCheckin  && _checkinCtrl.text.trim().isEmpty)  return 'The correct check-in time is required.';
    if (_needsCheckout && _checkoutCtrl.text.trim().isEmpty) return 'The correct check-out time is required.';
    return null;
  }

  // Friendly display label used in history cards
  static String typeDisplayLabel(String type) {
    switch (type) {
      case 'WRONG_CHECKIN':  return 'Wrong Check-In Time';
      case 'WRONG_CHECKOUT': return 'Wrong Check-Out Time';
      case 'MISSED_CHECKIN': return 'Missed Check-In';
      case 'MISSED_CHECKOUT': return 'Missed Check-Out';
      case 'CUSTOM':          return 'Both Times Correction';
      default: return type.replaceAll('_', ' ');
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    TimeOfDay initial = TimeOfDay.now();
    final text = ctrl.text.trim();
    if (text.isNotEmpty) {
      try {
        final dt = DateFormat('hh:mm a').parse(text);
        initial = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {
        // Fallback: old HH:mm format
        final parts = text.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1].split(' ')[0]);
          if (h != null && m != null) initial = TimeOfDay(hour: h, minute: m);
        }
      }
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final h12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      ctrl.text = '${h12.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period';
    }
  }

  Future<void> _submit() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _submitError = validationError);
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final token = ref.read(authProvider).accessToken ?? '';
      // Map frontend sub-types to backend DB types
      final String apiType;
      switch (_typeCtrl) {
        case 'WRONG_CHECKIN':  apiType = 'MISSED_CHECKIN';  break;
        case 'WRONG_CHECKOUT': apiType = 'MISSED_CHECKOUT'; break;
        default:               apiType = _typeCtrl;
      }
      final body = <String, dynamic>{
        'adjustmentType': apiType,
        'reason': _reasonCtrl.text.trim(),
      };

      final checkinDt = _buildDateTime(_checkinCtrl.text);
      final checkoutDt = _buildDateTime(_checkoutCtrl.text);
      if (checkinDt != null) body['requestedCheckinTime'] = checkinDt;
      if (checkoutDt != null) body['requestedCheckoutTime'] = checkoutDt;

      final response = await http.post(
        Uri.parse('$ServerConfig.apiBase/adjustments/request'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final resBody = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201 && resBody['success'] == true) {
        if (mounted) {
          setState(() {
            _submitting = false;
            _typeCtrl = 'WRONG_CHECKIN';
            _date = DateTime.now();
            _checkinCtrl.clear();
            _checkoutCtrl.clear();
            _reasonCtrl.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Correction request submitted'),
              ]),
              backgroundColor: AppTheme.statusPresent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
          ref.read(adjustmentProvider.notifier).fetchHistory();
        }
      } else {
        final msg = (resBody['error'] as Map?)?['message'] as String? ??
            'Failed to submit request.';
        if (mounted) {
          setState(() {
            _submitting = false;
            _submitError = msg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitError = 'Network error. Please verify connection.';
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final adjState = ref.watch(adjustmentProvider);

    // Filter history to correction types only
    final corrections = adjState.history
        .where((r) =>
            r.adjustmentType == 'MISSED_CHECKIN' ||
            r.adjustmentType == 'MISSED_CHECKOUT' ||
            r.adjustmentType == 'CUSTOM')
        .toList();

    final pendingCount =
        corrections.where((r) => r.status == 'PENDING').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Correction Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(adjustmentProvider.notifier).fetchHistory(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page heading ─────────────────────────────────────────
            Text(
              'Correction Requests',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Request corrections for missed or wrong check-in / check-out records.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),

            // ── Audit warning banner ─────────────────────────────────
            _AuditBanner(isDark: isDark),
            const SizedBox(height: 20),

            // ── Responsive two-column layout ─────────────────────────
            LayoutBuilder(builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _SubmitCard(
                        isDark: isDark,
                        typeCtrl: _typeCtrl,
                        date: _date,
                        checkinCtrl: _checkinCtrl,
                        checkoutCtrl: _checkoutCtrl,
                        reasonCtrl: _reasonCtrl,
                        submitting: _submitting,
                        submitError: _submitError,
                        existingCheckin: _existingCheckin,
                        existingCheckout: _existingCheckout,
                        isLoadingExisting: _isLoadingExisting,
                        onTypeChanged: (v) {
                          setState(() => _typeCtrl = v ?? _typeCtrl);
                          _fetchExistingRecord();
                        },
                        onPickDate: _pickDate,
                        onPickCheckin: () => _pickTime(_checkinCtrl),
                        onPickCheckout: () => _pickTime(_checkoutCtrl),
                        onSubmit: _submit,
                        onDismissError: () =>
                            setState(() => _submitError = null),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: _HistoryCard(
                        isDark: isDark,
                        corrections: corrections,
                        pendingCount: pendingCount,
                        isLoading: adjState.isLoading,
                      ),
                    ),
                  ],
                );
              }
              // Narrow: stacked
              return Column(
                children: [
                  _SubmitCard(
                    isDark: isDark,
                    typeCtrl: _typeCtrl,
                    date: _date,
                    checkinCtrl: _checkinCtrl,
                    checkoutCtrl: _checkoutCtrl,
                    reasonCtrl: _reasonCtrl,
                    submitting: _submitting,
                    submitError: _submitError,
                    existingCheckin: _existingCheckin,
                    existingCheckout: _existingCheckout,
                    isLoadingExisting: _isLoadingExisting,
                    onTypeChanged: (v) {
                      setState(() => _typeCtrl = v ?? _typeCtrl);
                      _fetchExistingRecord();
                    },
                    onPickDate: _pickDate,
                    onPickCheckin: () => _pickTime(_checkinCtrl),
                    onPickCheckout: () => _pickTime(_checkoutCtrl),
                    onSubmit: _submit,
                    onDismissError: () => setState(() => _submitError = null),
                  ),
                  const SizedBox(height: 20),
                  _HistoryCard(
                    isDark: isDark,
                    corrections: corrections,
                    pendingCount: pendingCount,
                    isLoading: adjState.isLoading,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// AUDIT WARNING BANNER
// ============================================================================

class _AuditBanner extends StatelessWidget {
  final bool isDark;

  const _AuditBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.statusLate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Original records are never deleted. All corrections are logged for audit.',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUBMIT FORM CARD
// ============================================================================

class _SubmitCard extends StatelessWidget {
  final bool isDark;
  final String typeCtrl;
  final DateTime date;
  final TextEditingController checkinCtrl;
  final TextEditingController checkoutCtrl;
  final TextEditingController reasonCtrl;
  final bool submitting;
  final String? submitError;
  final String? existingCheckin;
  final String? existingCheckout;
  final bool isLoadingExisting;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onPickDate;
  final VoidCallback onPickCheckin;
  final VoidCallback onPickCheckout;
  final VoidCallback onSubmit;
  final VoidCallback onDismissError;

  const _SubmitCard({
    required this.isDark,
    required this.typeCtrl,
    required this.date,
    required this.checkinCtrl,
    required this.checkoutCtrl,
    required this.reasonCtrl,
    required this.submitting,
    required this.submitError,
    this.existingCheckin,
    this.existingCheckout,
    required this.isLoadingExisting,
    required this.onTypeChanged,
    required this.onPickDate,
    required this.onPickCheckin,
    required this.onPickCheckout,
    required this.onSubmit,
    required this.onDismissError,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final fillColor = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    final mutedColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    InputDecoration _inputDeco({
      required String label,
      Widget? suffix,
      bool readOnly = false,
    }) =>
        InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: subColor, fontSize: 13),
          hintStyle: TextStyle(color: mutedColor, fontSize: 13),
          filled: true,
          fillColor: fillColor,
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppTheme.accent, width: 1.5),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card header ────────────────────────────────────────────
          _CardHeader(
            isDark: isDark,
            icon: Icons.edit_calendar_rounded,
            title: 'Submit Correction Request',
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Correction Type dropdown
                DropdownButtonFormField<String>(
                  value: typeCtrl,
                  dropdownColor: cardColor,
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: _inputDeco(label: 'Correction Type'),
                  items: [
                    DropdownMenuItem(
                      value: 'WRONG_CHECKIN',
                      child: Text('Wrong Check-In Time',
                          style: TextStyle(color: textColor)),
                    ),
                    DropdownMenuItem(
                      value: 'WRONG_CHECKOUT',
                      child: Text('Wrong Check-Out Time',
                          style: TextStyle(color: textColor)),
                    ),
                    DropdownMenuItem(
                      value: 'MISSED_CHECKIN',
                      child: Text('Missed / Forgot Check-In',
                          style: TextStyle(color: textColor)),
                    ),
                    DropdownMenuItem(
                      value: 'MISSED_CHECKOUT',
                      child: Text('Missed / Forgot Check-Out',
                          style: TextStyle(color: textColor)),
                    ),
                    DropdownMenuItem(
                      value: 'CUSTOM',
                      child: Text('Both Times Need Correction',
                          style: TextStyle(color: textColor)),
                    ),
                  ],
                  onChanged: onTypeChanged,
                ),
                const SizedBox(height: 14),

                // 2. Date picker
                GestureDetector(
                  onTap: onPickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 16, color: AppTheme.accent),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy').format(date),
                          style:
                              TextStyle(color: textColor, fontSize: 14),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_drop_down_rounded,
                            color: subColor),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Existing record info — confirmation banner for wrong-time types
                if (['WRONG_CHECKIN', 'WRONG_CHECKOUT', 'CUSTOM'].contains(typeCtrl))
                  _ExistingTimeInfo(
                    isDark: isDark,
                    typeCtrl: typeCtrl,
                    existingCheckin: existingCheckin,
                    existingCheckout: existingCheckout,
                    isLoading: isLoadingExisting,
                  ),

                // 3. Time fields — show only what the selected type requires
                Builder(builder: (_) {
                  final needsCi = ['WRONG_CHECKIN',  'MISSED_CHECKIN',  'CUSTOM'].contains(typeCtrl);
                  final needsCo = ['WRONG_CHECKOUT', 'MISSED_CHECKOUT', 'CUSTOM'].contains(typeCtrl);
                  Widget ciField = GestureDetector(
                    onTap: onPickCheckin,
                    child: AbsorbPointer(
                      child: TextFormField(
                        controller: checkinCtrl,
                        readOnly: true,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: _inputDeco(
                          label: typeCtrl == 'WRONG_CHECKIN'
                              ? 'Correct Check-In Time'
                              : 'Check-In Time',
                          suffix: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.access_time_rounded, size: 18, color: subColor),
                          ),
                        ),
                      ),
                    ),
                  );
                  Widget coField = GestureDetector(
                    onTap: onPickCheckout,
                    child: AbsorbPointer(
                      child: TextFormField(
                        controller: checkoutCtrl,
                        readOnly: true,
                        style: TextStyle(color: textColor, fontSize: 14),
                        decoration: _inputDeco(
                          label: typeCtrl == 'WRONG_CHECKOUT'
                              ? 'Correct Check-Out Time'
                              : 'Check-Out Time',
                          suffix: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Icon(Icons.access_time_rounded, size: 18, color: subColor),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (needsCi && needsCo) {
                    return Row(children: [
                      Expanded(child: ciField),
                      const SizedBox(width: 12),
                      Expanded(child: coField),
                    ]);
                  } else if (needsCi) {
                    return ciField;
                  } else {
                    return coField;
                  }
                }),
                const SizedBox(height: 14),

                // 4. Reason multiline
                TextField(
                  controller: reasonCtrl,
                  minLines: 3,
                  maxLines: 6,
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: _inputDeco(label: 'Reason / Explanation')
                      .copyWith(alignLabelWithHint: true),
                ),
                const SizedBox(height: 16),

                // Error banner
                if (submitError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.statusAbsent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.statusAbsent.withOpacity(0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.statusAbsent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            submitError!,
                            style: const TextStyle(
                                color: AppTheme.statusAbsent, fontSize: 13),
                          ),
                        ),
                        GestureDetector(
                          onTap: onDismissError,
                          child: const Icon(Icons.close,
                              size: 15, color: AppTheme.statusAbsent),
                        ),
                      ],
                    ),
                  ),

                // Submit button
                _GradientButton(
                  onPressed: submitting ? null : onSubmit,
                  loading: submitting,
                  icon: Icons.send_rounded,
                  label: 'Submit Request',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HISTORY CARD
// ============================================================================

class _HistoryCard extends StatelessWidget {
  final bool isDark;
  final List<AdjustmentRequest> corrections;
  final int pendingCount;
  final bool isLoading;

  const _HistoryCard({
    required this.isDark,
    required this.corrections,
    required this.pendingCount,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    final mutedColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card header ────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(
                  bottom:
                      BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history_rounded,
                      size: 17, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'My Requests',
                    style: TextStyle(
                      color: isDark ? AppTheme.darkText : AppTheme.lightText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.statusPending.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.statusPending.withOpacity(0.25)),
                    ),
                    child: Text(
                      '$pendingCount pending',
                      style: const TextStyle(
                        color: AppTheme.statusPending,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Content ────────────────────────────────────────────────
          if (isLoading && corrections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (corrections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_calendar_outlined,
                      size: 44,
                      color: mutedColor),
                  const SizedBox(height: 12),
                  Text(
                    'No correction requests yet.',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            // Table header
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Column headers
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkCard2
                        : AppTheme.lightElevated,
                    border: Border(
                        bottom: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      _ColHeader('Date', flex: 3, isDark: isDark),
                      _ColHeader('Type', flex: 3, isDark: isDark),
                      _ColHeader('Requested In / Out', flex: 5, isDark: isDark),
                      _ColHeader('Status', flex: 3, isDark: isDark),
                    ],
                  ),
                ),

                // Rows
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: corrections.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: borderColor),
                  itemBuilder: (context, i) {
                    final req = corrections[i];
                    return _HistoryRow(
                        req: req, isDark: isDark, isEven: i.isEven);
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Table column header helper ─────────────────────────────────────────────

class _ColHeader extends StatelessWidget {
  final String label;
  final int flex;
  final bool isDark;

  const _ColHeader(this.label, {required this.flex, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── History table row ──────────────────────────────────────────────────────

class _HistoryRow extends StatefulWidget {
  final AdjustmentRequest req;
  final bool isDark;
  final bool isEven;

  const _HistoryRow(
      {required this.req, required this.isDark, required this.isEven});

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hovered = false;

  Color get _rowBg {
    if (_hovered) {
      return widget.isDark
          ? const Color(0xFF1A2B47)
          : const Color(0xFFEDF2FB);
    }
    if (widget.isEven) {
      return widget.isDark ? AppTheme.darkCard : Colors.white;
    }
    return widget.isDark
        ? const Color(0xFF0F1A2E)
        : const Color(0xFFF7FAFF);
  }

  // Resolve display date from the request's datetime strings
  String get _dateStr {
    final raw =
        widget.req.requestedCheckinTime ?? widget.req.requestedCheckoutTime;
    if (raw == null) return '—';
    try {
      return DateFormat('dd MMM yyyy')
          .format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }

  String _formatTime(String? isoStr) {
    if (isoStr == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(isoStr).toLocal());
    } catch (_) {
      return '--:--';
    }
  }

  String get _typeLabel {
    switch (widget.req.adjustmentType) {
      case 'MISSED_CHECKIN':  return 'Wrong / Missing Check-In';
      case 'MISSED_CHECKOUT': return 'Wrong / Missing Check-Out';
      case 'CUSTOM':          return 'Both Check-In & Check-Out';
      default:                return widget.req.adjustmentType.replaceAll('_', ' ');
    }
  }

  Color get _statusColor {
    switch (widget.req.status) {
      case 'APPROVED':
      case 'MANAGER_APPROVED':
        return widget.req.status == 'MANAGER_APPROVED'
            ? AppTheme.accent
            : AppTheme.statusApproved;
      case 'REJECTED':
        return AppTheme.statusRejected;
      case 'PENDING':
        return AppTheme.statusPending;
      default:
        return AppTheme.darkTextMuted;
    }
  }

  String get _statusLabel {
    switch (widget.req.status) {
      case 'APPROVED':
        return 'Approved';
      case 'REJECTED':
        return 'Rejected';
      case 'MANAGER_APPROVED':
        return 'Manager Approved';
      case 'PENDING':
        return 'Pending';
      default:
        return widget.req.status;
    }
  }

  /// Stage sub-text shown beneath the status badge for PENDING items.
  String? get _stageHint {
    if (widget.req.status != 'PENDING') return null;
    // If reviewedAt is set but still PENDING → Manager approved, awaiting HR
    if (widget.req.reviewedAt != null) return 'Manager Approved · Awaiting HR';
    return 'Awaiting Manager';
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final subColor =
        widget.isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    final textColor =
        widget.isDark ? AppTheme.darkText : AppTheme.lightText;
    final mutedColor =
        widget.isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    final inTime = _formatTime(widget.req.requestedCheckinTime);
    final outTime = _formatTime(widget.req.requestedCheckoutTime);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _rowBg,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Date
            Expanded(
              flex: 3,
              child: Text(
                _dateStr,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            // Type
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                constraints: const BoxConstraints(maxWidth: 130),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppTheme.accent.withOpacity(0.18)),
                ),
                child: Text(
                  _typeLabel,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Requested In / Out
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'In: $inTime  ·  Out: $outTime',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (widget.req.hrComment != null &&
                      widget.req.hrComment!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'HR: ${widget.req.hrComment}',
                        style: TextStyle(
                            color: AppTheme.statusLate, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

            // Status
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTheme.statusBadge(_statusLabel, _statusColor,
                      fontSize: 11),
                  if (_stageHint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _stageHint!,
                        style: TextStyle(
                            color: mutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w400),
                      ),
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

// ============================================================================
// EXISTING TIME INFO — shows currently recorded time for wrong-type corrections
// ============================================================================

class _ExistingTimeInfo extends StatelessWidget {
  final bool isDark;
  final String typeCtrl;
  final String? existingCheckin;
  final String? existingCheckout;
  final bool isLoading;

  const _ExistingTimeInfo({
    required this.isDark,
    required this.typeCtrl,
    this.existingCheckin,
    this.existingCheckout,
    required this.isLoading,
  });

  String _fmt(String? iso) {
    if (iso == null) return 'not recorded';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0D1B2E) : const Color(0xFFF0F6FF);
    final borderColor = AppTheme.accent.withOpacity(0.22);
    final labelColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    if (isLoading) {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: const Row(children: [
          SizedBox(
            width: 13, height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
          SizedBox(width: 8),
          Text('Loading current record…', style: TextStyle(fontSize: 12)),
        ]),
      );
    }

    final showCI = typeCtrl == 'WRONG_CHECKIN' || typeCtrl == 'CUSTOM';
    final showCO = typeCtrl == 'WRONG_CHECKOUT' || typeCtrl == 'CUSTOM';

    Widget chip(String label, String? iso) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.access_time_rounded, size: 13,
            color: AppTheme.accent.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          _fmt(iso),
          style: TextStyle(
            color: iso != null
                ? (isDark ? AppTheme.darkText : AppTheme.lightText)
                : Colors.grey,
            fontSize: 12,
            fontWeight: iso != null ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (showCI) chip('Current check-in:', existingCheckin),
                if (showCO) chip('Current check-out:', existingCheckout),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED WIDGETS
// ============================================================================

class _CardHeader extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;

  const _CardHeader({
    required this.isDark,
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard2 : AppTheme.lightElevated,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(13)),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;
  final String label;

  const _GradientButton({
    required this.onPressed,
    required this.loading,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedOpacity(
        opacity: onPressed == null ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            gradient: onPressed == null
                ? const LinearGradient(
                    colors: [Color(0xFF4A5568), Color(0xFF4A5568)])
                : AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
