import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../approvals_provider.dart';
import '../../overtime/overtime_provider.dart';
import '../../adjustments/adjustments_provider.dart';
import '../../authentication/presentation/auth_state.dart';
import '../../../core/theme/app_theme.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  String _searchQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _typeFilter = 'All';

  final _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateFrom = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateTo = picked);
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchCtrl.clear();
      _dateFrom = null;
      _dateTo = null;
      _typeFilter = 'All';
    });
  }

  bool _dateInRange(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return true;
    DateTime? dt;
    try { dt = DateTime.parse(dateStr.substring(0, 10)); } catch (_) { return true; }
    if (_dateFrom != null && dt.isBefore(_dateFrom!)) return false;
    if (_dateTo != null && dt.isAfter(_dateTo!.add(const Duration(days: 1)))) return false;
    return true;
  }

  bool _nameMatches(String? first, String? last, String? username) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final full = '${first ?? ''} ${last ?? ''} ${username ?? ''}'.toLowerCase();
    return full.contains(q);
  }

  // ── Filter bar ────────────────────────────────────────────────────────────
  Widget _buildFilterBar(BuildContext context, bool isDark) {
    final hasFilters = _searchQuery.isNotEmpty || _dateFrom != null || _dateTo != null || _typeFilter != 'All';
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final fillColor = isDark ? AppTheme.darkInput : AppTheme.lightInput;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(color: isDark ? AppTheme.darkText : AppTheme.lightText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by employee name…',
              hintStyle: TextStyle(color: subColor, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: subColor),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, size: 16, color: subColor),
                      onPressed: () => setState(() { _searchQuery = ''; _searchCtrl.clear(); }),
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: fillColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.accent, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: _dateFrom != null ? 'From: ${DateFormat('MMM d').format(_dateFrom!)}' : 'From Date',
                  icon: Icons.calendar_today_rounded,
                  active: _dateFrom != null,
                  color: AppTheme.accent,
                  isDark: isDark,
                  onTap: _pickFrom,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: _dateTo != null ? 'To: ${DateFormat('MMM d').format(_dateTo!)}' : 'To Date',
                  icon: Icons.calendar_month_rounded,
                  active: _dateTo != null,
                  color: AppTheme.accent,
                  isDark: isDark,
                  onTap: _pickTo,
                ),
                const SizedBox(width: 8),
                for (final t in ['All', 'OT', 'Adjustment'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: t == 'OT' ? 'Overtime' : t == 'Adjustment' ? 'Adjustment' : 'All',
                      icon: t == 'OT' ? Icons.more_time_rounded : t == 'Adjustment' ? Icons.edit_calendar_outlined : Icons.filter_list_rounded,
                      active: _typeFilter == t,
                      color: t == 'OT' ? AppTheme.statusOvertime : t == 'Adjustment' ? AppTheme.statusPending : AppTheme.accent,
                      isDark: isDark,
                      onTap: () => setState(() => _typeFilter = t),
                    ),
                  ),
                if (hasFilters) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _clearFilters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.statusRejected.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppTheme.statusRejected.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.clear_rounded, size: 13, color: AppTheme.statusRejected),
                        const SizedBox(width: 4),
                        Text('Clear', style: TextStyle(color: AppTheme.statusRejected, fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final approvalsState = ref.watch(approvalsProvider);
    final roles = ref.watch(authProvider).user?.roles ?? [];
    final isAdmin = roles.contains('Admin');
    final isManager = roles.contains('Manager') && !isAdmin && !roles.contains('HR');
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;

    final filteredOT = approvalsState.pendingOvertime.where((req) {
      if (_typeFilter == 'Adjustment') return false;
      if (!_nameMatches(req.firstName, req.lastName, req.username)) return false;
      if (!_dateInRange(req.requestDate)) return false;
      return true;
    }).toList();

    const _correctionTypes = {'MISSED_CHECKIN', 'MISSED_CHECKOUT', 'CUSTOM'};

    // Split adjustments into corrections vs other adjustments
    final filteredCorrections = approvalsState.pendingAdjustments.where((req) {
      if (_typeFilter == 'OT') return false;
      if (!_correctionTypes.contains(req.adjustmentType)) return false;
      if (!_nameMatches(req.firstName, req.lastName, req.username)) return false;
      final dateStr = req.requestedCheckinTime ?? req.requestedCheckoutTime ?? req.createdAt;
      if (!_dateInRange(dateStr)) return false;
      return true;
    }).toList();

    final filteredAdj = approvalsState.pendingAdjustments.where((req) {
      if (_typeFilter == 'OT') return false;
      if (_correctionTypes.contains(req.adjustmentType)) return false; // corrections go to their own tab
      if (!_nameMatches(req.firstName, req.lastName, req.username)) return false;
      final dateStr = req.requestedCheckinTime ?? req.requestedCheckoutTime ?? req.createdAt;
      if (!_dateInRange(dateStr)) return false;
      return true;
    }).toList();

    final totalPending = approvalsState.pendingOvertime.length + approvalsState.pendingAdjustments.length;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Approval Center',
                          style: TextStyle(
                            color: isDark ? AppTheme.darkText : AppTheme.lightText,
                            fontSize: 20, fontWeight: FontWeight.w700,
                          )),
                        const SizedBox(width: 12),
                        if (totalPending > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppTheme.accent, AppTheme.accent2]),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text('$totalPending pending',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        isManager
                          ? 'Stage 1 — Review and forward to HR for final approval'
                          : isAdmin
                            ? 'Admin view — all pending requests across all stages'
                            : 'Final review — approve or reject manager-forwarded requests',
                        style: TextStyle(
                          color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
                  onPressed: () => ref.read(approvalsProvider.notifier).fetchPending(),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // ── Error banner ──────────────────────────────────────────────────
          if (approvalsState.error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.statusRejected.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.statusRejected.withOpacity(0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: AppTheme.statusRejected, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(approvalsState.error!,
                    style: const TextStyle(color: AppTheme.statusRejected, fontSize: 13)),
                ),
                GestureDetector(
                  onTap: () => ref.read(approvalsProvider.notifier).fetchPending(),
                  child: const Text('Retry', style: TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),

          const SizedBox(height: 12),

          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(colors: [AppTheme.accent, AppTheme.accent2]),
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              tabs: [
                Tab(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.more_time_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Text('Overtime'),
                    if (filteredOT.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: filteredOT.length, total: approvalsState.pendingOvertime.length),
                    ],
                  ]),
                )),
                Tab(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.fact_check_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Text('Corrections'),
                    if (filteredCorrections.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: filteredCorrections.length, total: filteredCorrections.length),
                    ],
                  ]),
                )),
                Tab(child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.edit_calendar_outlined, size: 16),
                    const SizedBox(width: 6),
                    const Text('Adjustments'),
                    if (filteredAdj.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: filteredAdj.length, total: filteredAdj.length),
                    ],
                  ]),
                )),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Filter bar ────────────────────────────────────────────────────
          _buildFilterBar(context, isDark),

          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: approvalsState.isLoading &&
                    approvalsState.pendingOvertime.isEmpty &&
                    approvalsState.pendingAdjustments.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOvertimeQueue(filteredOT, approvalsState.pendingOvertime.length, isDark),
                      _buildCorrectionsQueue(filteredCorrections, isDark, roles),
                      _buildAdjustmentsQueue(filteredAdj, filteredAdj.length, isDark, roles),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Overtime queue ────────────────────────────────────────────────────────
  Widget _buildOvertimeQueue(List<OvertimeRequest> list, int totalCount, bool isDark) {
    if (list.isEmpty) {
      return _EmptyState(
        icon: Icons.more_time_rounded,
        message: totalCount == 0 ? 'No pending overtime requests.' : 'No requests match the filters.',
        isDark: isDark,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = list[index];
        return _ApprovalCard(
          isDark: isDark,
          accentColor: AppTheme.statusOvertime,
          icon: Icons.more_time_rounded,
          employeeName: '${req.firstName ?? ''} ${req.lastName ?? ''}'.trim(),
          username: req.username ?? '',
          dateLabel: req.requestDate,
          typeLabel: 'Overtime · Paid',
          details: '${req.requestedMinutes} minutes requested',
          reason: req.reason,
          stageBadge: null,
          actionLabel: 'Review',
          onAction: () => _showOvertimeReviewDialog(req),
        );
      },
    );
  }

  // ── Type label helper ─────────────────────────────────────────────────────
  static String _adjTypeLabel(String type) {
    switch (type) {
      case 'MISSED_CHECKIN':  return 'Wrong / Missing Check-In';
      case 'MISSED_CHECKOUT': return 'Wrong / Missing Check-Out';
      case 'CUSTOM':          return 'Both Times Correction';
      case 'LATE_COMPENSATION': return 'Late Compensation';
      case 'EARLY_LEAVE':     return 'Early Leave';
      case 'TIME_ADJUSTMENT': return 'Time Adjustment';
      case 'LATE_CHECKOUT':  return 'Late Checkout';
      default: return type.replaceAll('_', ' ');
    }
  }

  // ── Corrections queue (MISSED_CHECKIN / MISSED_CHECKOUT / CUSTOM) ─────────
  Widget _buildCorrectionsQueue(List<AdjustmentRequest> list, bool isDark, List<String> roles) {
    final isAdmin   = roles.contains('Admin');
    final isManager = roles.contains('Manager') && !isAdmin && !roles.contains('HR');

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.brandWarning.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.brandWarning.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: AppTheme.brandWarning, size: 16),
            const SizedBox(width: 10),
            const Expanded(child: Text(
              'Approval will update the actual attendance record with the corrected times.',
              style: TextStyle(color: AppTheme.brandWarning, fontSize: 12.5),
            )),
          ]),
        ),
        if (list.isEmpty)
          Expanded(child: _EmptyState(
            icon: Icons.fact_check_rounded,
            message: 'No pending correction requests.',
            isDark: isDark,
          ))
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final req = list[index];
                final timeToParse = req.requestedCheckinTime ?? req.requestedCheckoutTime ?? req.createdAt;
                String dateLabel = 'N/A';
                try { dateLabel = DateFormat('yyyy-MM-dd').format(DateTime.parse(timeToParse)); } catch (_) {}

                final bool atManagerStage = req.managerApprovedAt == null;
                String actionLabel;
                VoidCallback onAction;

                if (isManager) {
                  actionLabel = 'Stage 1: Approve';
                  onAction = () => _showAdjustmentManagerApproveDialog(req);
                } else if (isAdmin && atManagerStage) {
                  actionLabel = 'Manager Approve';
                  onAction = () => _showAdjustmentManagerApproveDialog(req);
                } else {
                  actionLabel = 'Approve & Apply';
                  onAction = () => _showAdjustmentReviewDialog(req);
                }

                final String ciStr = req.requestedCheckinTime != null
                    ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckinTime!).toLocal())
                    : '--:--';
                final String coStr = req.requestedCheckoutTime != null
                    ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckoutTime!).toLocal())
                    : '--:--';
                final String timesDetail =
                    (req.requestedCheckinTime != null ? 'Check-In → $ciStr  ' : '') +
                    (req.requestedCheckoutTime != null ? 'Check-Out → $coStr' : '');

                return _ApprovalCard(
                  isDark: isDark,
                  accentColor: AppTheme.brandWarning,
                  icon: Icons.fact_check_rounded,
                  employeeName: '${req.firstName ?? ''} ${req.lastName ?? ''}'.trim(),
                  username: req.username ?? '',
                  dateLabel: dateLabel,
                  typeLabel: _adjTypeLabel(req.adjustmentType),
                  details: timesDetail.trim().isNotEmpty ? timesDetail.trim() : req.reason,
                  reason: req.reason,
                  stageBadge: isAdmin
                      ? (atManagerStage ? 'Awaiting Manager' : 'Ready for HR/Admin')
                      : null,
                  actionLabel: actionLabel,
                  onAction: onAction,
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Adjustments queue ─────────────────────────────────────────────────────
  Widget _buildAdjustmentsQueue(
      List<AdjustmentRequest> list, int totalCount, bool isDark, List<String> roles) {
    final isAdmin = roles.contains('Admin');
    final isHROnly = roles.contains('HR') && !isAdmin;
    final isManager = roles.contains('Manager') && !isAdmin && !roles.contains('HR');

    String contextMsg;
    Color contextColor;
    IconData contextIcon;

    if (isManager) {
      contextMsg = 'Stage 1 — Approve to forward to HR for final review.';
      contextColor = AppTheme.accent;
      contextIcon = Icons.info_outline_rounded;
    } else if (isHROnly) {
      contextMsg = 'Final review — these requests have passed manager stage and are ready for your decision.';
      contextColor = AppTheme.statusPresent;
      contextIcon = Icons.check_circle_outline_rounded;
    } else {
      contextMsg = 'Admin view — all pending adjustments shown. Stage indicator shows approval progress.';
      contextColor = AppTheme.roleAdmin;
      contextIcon = Icons.admin_panel_settings_rounded;
    }

    return Column(
      children: [
        // Context banner
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: contextColor.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: contextColor.withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(contextIcon, color: contextColor, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(contextMsg, style: TextStyle(color: contextColor, fontSize: 12.5))),
          ]),
        ),

        if (list.isEmpty)
          Expanded(child: _EmptyState(
            icon: Icons.edit_calendar_outlined,
            message: totalCount == 0 ? 'No pending adjustment requests.' : 'No requests match the filters.',
            isDark: isDark,
          ))
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final req = list[index];
                final timeToParse = req.requestedCheckinTime ?? req.requestedCheckoutTime ?? req.createdAt;
                String dateLabel = 'N/A';
                try { dateLabel = DateFormat('yyyy-MM-dd').format(DateTime.parse(timeToParse)); } catch (_) {}

                // Determine action based on role and stage
                final bool atManagerStage = req.managerApprovedAt == null;
                String actionLabel;
                VoidCallback onAction;

                if (isManager) {
                  actionLabel = 'Stage 1: Approve';
                  onAction = () => _showAdjustmentManagerApproveDialog(req);
                } else if (isAdmin && atManagerStage) {
                  // Admin can do stage-1 approval on requests not yet manager-approved
                  actionLabel = 'Manager Approve';
                  onAction = () => _showAdjustmentManagerApproveDialog(req);
                } else {
                  actionLabel = 'Final Approve';
                  onAction = () => _showAdjustmentReviewDialog(req);
                }

                final stageBadge = isAdmin
                    ? (atManagerStage ? 'Awaiting Manager' : 'Ready for HR')
                    : null;

                final isLateCheckout = req.adjustmentType == 'LATE_CHECKOUT';
                return _ApprovalCard(
                  isDark: isDark,
                  accentColor: isLateCheckout ? Colors.orange : AppTheme.statusPending,
                  icon: isLateCheckout ? Icons.schedule_rounded : Icons.edit_calendar_outlined,
                  employeeName: '${req.firstName ?? ''} ${req.lastName ?? ''}'.trim(),
                  username: req.username ?? '',
                  dateLabel: dateLabel,
                  typeLabel: _adjTypeLabel(req.adjustmentType),
                  details: isLateCheckout
                      ? '${req.requestedMinutes} min overtime after shift end'
                      : req.requestedCheckinTime != null || req.requestedCheckoutTime != null
                          ? 'In: ${req.requestedCheckinTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckinTime!).toLocal()) : '--:--'}'
                            '  ·  Out: ${req.requestedCheckoutTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckoutTime!).toLocal()) : '--:--'}'
                          : '${req.requestedMinutes} minutes',
                  reason: req.reason,
                  stageBadge: stageBadge,
                  actionLabel: actionLabel,
                  onAction: onAction,
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Review dialogs ────────────────────────────────────────────────────────
  void _showOvertimeReviewDialog(OvertimeRequest req) {
    final formKey = GlobalKey<FormState>();
    final commentController = TextEditingController();
    final minutesController = TextEditingController(text: req.requestedMinutes.toString());
    String reviewStatus = 'APPROVED';
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppTheme.statusOvertime.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.more_time_rounded, color: AppTheme.statusOvertime, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('Review Overtime', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ]),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DialogInfoRow('Employee', '${req.firstName} ${req.lastName} (@${req.username})'),
                  _DialogInfoRow('Date', req.requestDate),
                  _DialogInfoRow('Requested', '${req.requestedMinutes} minutes'),
                  _DialogInfoRow('Reason', req.reason),
                  const SizedBox(height: 16),
                  if (dialogError != null)
                    _DialogErrorBanner(dialogError!),
                  DropdownButtonFormField<String>(
                    value: reviewStatus,
                    decoration: const InputDecoration(labelText: 'Decision', isDense: true,
                      border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'APPROVED', child: Text('Approve Full')),
                      DropdownMenuItem(value: 'REJECTED', child: Text('Reject Request')),
                      DropdownMenuItem(value: 'PARTIAL', child: Text('Partially Approve')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => reviewStatus = val);
                    },
                  ),
                  if (reviewStatus == 'PARTIAL') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Approved Minutes', isDense: true,
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.more_time),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        final n = int.tryParse(val.trim());
                        if (n == null || n <= 0 || n > req.requestedMinutes) {
                          return 'Must be 1–${req.requestedMinutes}';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Comment (Optional)', isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.comment_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => dialogError = null);
                final approvedMinutes = reviewStatus == 'PARTIAL'
                    ? int.parse(minutesController.text.trim())
                    : req.requestedMinutes;
                final success = await ref.read(approvalsProvider.notifier).reviewOvertime(
                  id: req.id,
                  status: reviewStatus,
                  approvedMinutes: approvedMinutes,
                  comment: commentController.text.trim(),
                );
                if (success && context.mounted) {
                  Navigator.pop(context);
                  _showSnack('Overtime request $reviewStatus');
                } else if (context.mounted) {
                  final err = ref.read(approvalsProvider).error ?? 'Review failed. Please try again.';
                  setDialogState(() => dialogError = err);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdjustmentManagerApproveDialog(AdjustmentRequest req) {
    final timeToParse = req.requestedCheckinTime ?? req.requestedCheckoutTime ?? req.createdAt;
    String dateLabel = 'N/A';
    try { dateLabel = DateFormat('yyyy-MM-dd').format(DateTime.parse(timeToParse)); } catch (_) {}
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.how_to_reg_rounded, color: AppTheme.accent, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Stage 1 — Manager Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DialogInfoRow('Employee', '${req.firstName} ${req.lastName} (@${req.username})'),
                _DialogInfoRow('Type', _adjTypeLabel(req.adjustmentType)),
                _DialogInfoRow('Date', dateLabel),
                if (req.requestedCheckinTime != null || req.requestedCheckoutTime != null)
                  _DialogInfoRow('Times',
                    'In: ${req.requestedCheckinTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckinTime!).toLocal()) : '--:--'}'
                    '  →  Out: ${req.requestedCheckoutTime != null ? DateFormat('hh:mm a').format(DateTime.parse(req.requestedCheckoutTime!).toLocal()) : '--:--'}'),
                if (req.requestedMinutes > 0)
                  _DialogInfoRow('Minutes', '${req.requestedMinutes} minutes'),
                _DialogInfoRow('Reason', req.reason),
                const SizedBox(height: 12),
                if (dialogError != null)
                  _DialogErrorBanner(dialogError!),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.statusRejected, side: const BorderSide(color: AppTheme.statusRejected)),
              onPressed: () async {
                setDialogState(() => dialogError = null);
                final success = await ref.read(approvalsProvider.notifier).reviewAdjustment(
                  id: req.id, status: 'REJECTED', comment: '',
                );
                if (success && context.mounted) {
                  Navigator.pop(context);
                  _showSnack('Request rejected.');
                } else if (context.mounted) {
                  final err = ref.read(approvalsProvider).error ?? 'Action failed. Please try again.';
                  setDialogState(() => dialogError = err);
                }
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.white),
              onPressed: () async {
                setDialogState(() => dialogError = null);
                final success = await ref.read(approvalsProvider.notifier).reviewAdjustment(
                  id: req.id, status: 'MANAGER_APPROVE', comment: '',
                );
                if (success && context.mounted) {
                  Navigator.pop(context);
                  _showSnack('Approved — forwarded to HR.');
                } else if (context.mounted) {
                  final err = ref.read(approvalsProvider).error ?? 'Action failed. Please try again.';
                  setDialogState(() => dialogError = err);
                }
              },
              child: const Text('Approve → Send to HR'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdjustmentReviewDialog(AdjustmentRequest req) {
    final formKey = GlobalKey<FormState>();
    final commentController = TextEditingController();
    String reviewStatus = 'APPROVED';
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppTheme.statusPresent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.verified_rounded, color: AppTheme.statusPresent, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Final Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DialogInfoRow('Employee', '${req.firstName} ${req.lastName} (@${req.username})'),
                  _DialogInfoRow('Type', _adjTypeLabel(req.adjustmentType)),
                  _DialogInfoRow('Reason', req.reason),
                  const SizedBox(height: 16),
                  if (dialogError != null)
                    _DialogErrorBanner(dialogError!),
                  DropdownButtonFormField<String>(
                    value: reviewStatus,
                    decoration: const InputDecoration(labelText: 'Decision', isDense: true,
                      border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'APPROVED', child: Text('Approve & Apply')),
                      DropdownMenuItem(value: 'REJECTED', child: Text('Reject Request')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => reviewStatus = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Comment (Optional)', isDense: true,
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.comment_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: reviewStatus == 'APPROVED' ? AppTheme.statusPresent : AppTheme.statusRejected,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                setDialogState(() => dialogError = null);
                final success = await ref.read(approvalsProvider.notifier).reviewAdjustment(
                  id: req.id,
                  status: reviewStatus,
                  comment: commentController.text.trim(),
                );
                if (success && context.mounted) {
                  Navigator.pop(context);
                  _showSnack('Adjustment request $reviewStatus');
                } else if (context.mounted) {
                  final err = ref.read(approvalsProvider).error ?? 'Review failed. Please try again.';
                  setDialogState(() => dialogError = err);
                }
              },
              child: const Text('Submit Decision'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ── Approval card ─────────────────────────────────────────────────────────────

class _ApprovalCard extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final IconData icon;
  final String employeeName;
  final String username;
  final String dateLabel;
  final String typeLabel;
  final String details;
  final String reason;
  final String? stageBadge;
  final String actionLabel;
  final VoidCallback onAction;

  const _ApprovalCard({
    required this.isDark,
    required this.accentColor,
    required this.icon,
    required this.employeeName,
    required this.username,
    required this.dateLabel,
    required this.typeLabel,
    required this.details,
    required this.reason,
    required this.stageBadge,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: accentColor, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(
                                  employeeName.isNotEmpty ? employeeName : username,
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                if (username.isNotEmpty && employeeName.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Text('@$username',
                                    style: TextStyle(color: subColor, fontSize: 11)),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(typeLabel,
                                    style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                                if (stageBadge != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.statusPending.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppTheme.statusPending.withOpacity(0.3)),
                                    ),
                                    child: Text(stageBadge!,
                                      style: const TextStyle(color: AppTheme.statusPending, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ]),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: onAction,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppTheme.accent, AppTheme.accent2]),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(color: AppTheme.accent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Text(actionLabel,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkInput : AppTheme.lightInput,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.calendar_today_rounded, size: 12, color: subColor),
                            const SizedBox(width: 5),
                            Text(dateLabel, style: TextStyle(color: subColor, fontSize: 12)),
                            const SizedBox(width: 14),
                            Icon(Icons.schedule_rounded, size: 12, color: subColor),
                            const SizedBox(width: 5),
                            Expanded(child: Text(details, style: TextStyle(color: subColor, fontSize: 12), overflow: TextOverflow.ellipsis)),
                          ]),
                          const SizedBox(height: 4),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.notes_rounded, size: 12, color: subColor),
                            const SizedBox(width: 5),
                            Expanded(child: Text(reason,
                              style: TextStyle(color: subColor, fontSize: 12, fontStyle: FontStyle.italic),
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Count badge ───────────────────────────────────────────────────────────────
class _CountBadge extends StatelessWidget {
  final int count;
  final int total;
  const _CountBadge({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        count == total ? '$count' : '$count/$total',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isDark;
  const _EmptyState({required this.icon, required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppTheme.accent.withOpacity(0.5)),
          ),
          const SizedBox(height: 14),
          Text(message,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
              fontSize: 14, fontWeight: FontWeight.w500,
            )),
        ],
      ),
    );
  }
}

// ── Dialog info row ───────────────────────────────────────────────────────────
class _DialogInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _DialogInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ── Dialog error banner ────────────────────────────────────────────────────────
class _DialogErrorBanner extends StatelessWidget {
  final String message;
  const _DialogErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.statusRejected.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.statusRejected.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: AppTheme.statusRejected, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: const TextStyle(color: AppTheme.statusRejected, fontSize: 12.5))),
      ]),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: active ? color.withOpacity(0.4) : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: active ? color : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            color: active ? color : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
            fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          )),
        ]),
      ),
    );
  }
}
