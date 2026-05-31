import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

// ============================================================================
// WeekDay — data model for WeeklyBarChart
// ============================================================================

class WeekDay {
  final String label; // MON, TUE, WED, THU, FRI, SAT, SUN
  final int present;
  final int late;
  final int absent;
  final bool isToday;

  const WeekDay({
    required this.label,
    required this.present,
    required this.late,
    required this.absent,
    this.isToday = false,
  });
}

// ============================================================================
// WIDGET 1: MonthlyRateCircle
// ============================================================================

class MonthlyRateCircle extends StatelessWidget {
  final double rate; // 0.0 – 1.0
  final int presentDays;
  final int absentDays;
  final int lateDays;
  final int overTimeHours;
  final bool isDark;
  final String monthLabel;

  const MonthlyRateCircle({
    super.key,
    required this.rate,
    required this.presentDays,
    required this.absentDays,
    required this.lateDays,
    required this.overTimeHours,
    required this.isDark,
    required this.monthLabel,
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Monthly Rate',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              _MonthChip(label: monthLabel, isDark: isDark),
            ],
          ),
          const SizedBox(height: 20),
          // ── Body: circle + stats ─────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circle
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _RateArcPainter(rate: rate, isDark: isDark),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(rate * 100).round()}%',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'RATE',
                          style: TextStyle(
                            color: subColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Stats column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatRow(
                      label: 'Present Days',
                      value: presentDays.toString(),
                      valueColor: AppTheme.statusPresent,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                    _StatRow(
                      label: 'Absent',
                      value: absentDays.toString(),
                      valueColor: AppTheme.statusAbsent,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                    _StatRow(
                      label: 'Late Arrivals',
                      value: lateDays.toString(),
                      valueColor: AppTheme.statusLate,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 10),
                    _StatRow(
                      label: 'Overtime Hrs',
                      value: overTimeHours.toString(),
                      valueColor: AppTheme.statusBreak,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final bool isDark;

  const _MonthChip({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool isDark;

  const _StatRow({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: subColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RateArcPainter extends CustomPainter {
  final double rate;
  final bool isDark;

  const _RateArcPainter({required this.rate, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 10) / 2;
    const strokeWidth = 10.0;

    // Background arc (full circle)
    final bgPaint = Paint()
      ..color = isDark ? AppTheme.darkInput : AppTheme.lightElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Foreground arc
    if (rate > 0) {
      final fgPaint = Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final rect = Rect.fromCircle(center: center, radius: radius);
      const startAngle = -math.pi / 2; // -90 degrees (top)
      final sweepAngle = rate * 2 * math.pi;

      canvas.drawArc(rect, startAngle, sweepAngle, false, fgPaint);
    }
  }

  @override
  bool shouldRepaint(_RateArcPainter old) =>
      old.rate != rate || old.isDark != isDark;
}

// ============================================================================
// WIDGET 2: WeeklyBarChart
// ============================================================================

class WeeklyBarChart extends StatelessWidget {
  final List<WeekDay> days;
  final bool isDark;

  const WeeklyBarChart({
    super.key,
    required this.days,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    // Compute date range label
    final now = DateTime.now();
    final monday =
        now.subtract(Duration(days: now.weekday - 1)); // weekday: Mon=1
    final sunday = monday.add(const Duration(days: 6));
    final rangeLabel =
        '${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(sunday)}';

    // Max total for bar scaling
    int maxTotal = 1;
    for (final d in days) {
      final t = d.present + d.late + d.absent;
      if (t > maxTotal) maxTotal = t;
    }
    const maxBarHeight = 80.0;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Weekly Overview',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppTheme.accent.withOpacity(0.22)),
                ),
                child: Text(
                  rangeLabel,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // ── Bars ─────────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days.map((day) {
              final total = day.present + day.late + day.absent;
              final scale = maxTotal > 0 ? total / maxTotal : 0.0;
              final totalBarH = maxBarHeight * scale;

              // Heights of each segment
              final presentH = total > 0
                  ? totalBarH * (day.present / total)
                  : 0.0;
              final lateH =
                  total > 0 ? totalBarH * (day.late / total) : 0.0;
              final absentH =
                  total > 0 ? totalBarH * (day.absent / total) : 0.0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Total count
                  Text(
                    total > 0 ? total.toString() : '',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Stacked bar
                  SizedBox(
                    height: maxBarHeight,
                    width: 28,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Absent (top)
                        if (absentH > 0)
                          _BarSegment(
                            height: absentH,
                            color: AppTheme.statusAbsent,
                            isTop: lateH == 0 && presentH == 0,
                            isBottom: presentH == 0 && lateH == 0,
                          ),
                        // Late (middle)
                        if (lateH > 0)
                          _BarSegment(
                            height: lateH,
                            color: AppTheme.statusLate,
                            isTop: absentH == 0,
                            isBottom: presentH == 0,
                          ),
                        // Present (bottom)
                        if (presentH > 0)
                          _BarSegment(
                            height: presentH,
                            color: AppTheme.accent,
                            isTop: absentH == 0 && lateH == 0,
                            isBottom: true,
                          ),
                        // Empty placeholder when no data
                        if (total == 0)
                          Container(
                            height: 4,
                            width: 28,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkInput
                                  : AppTheme.lightElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Day label
                  Text(
                    day.label,
                    style: TextStyle(
                      color: day.isToday ? AppTheme.accent : subColor,
                      fontSize: 10,
                      fontWeight: day.isToday
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Today blue dot
                  day.isToday
                      ? Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accent,
                          ),
                        )
                      : const SizedBox(height: 5),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // ── Legend ───────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppTheme.accent, label: 'Present'),
              const SizedBox(width: 16),
              _LegendDot(color: AppTheme.statusLate, label: 'Late'),
              const SizedBox(width: 16),
              _LegendDot(color: AppTheme.statusAbsent, label: 'Absent'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BarSegment extends StatelessWidget {
  final double height;
  final Color color;
  final bool isTop;
  final bool isBottom;

  const _BarSegment({
    required this.height,
    required this.color,
    this.isTop = false,
    this.isBottom = false,
  });

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(4);
    return Container(
      height: height,
      width: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: isTop ? radius : Radius.zero,
          topRight: isTop ? radius : Radius.zero,
          bottomLeft: isBottom ? radius : Radius.zero,
          bottomRight: isBottom ? radius : Radius.zero,
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.darkTextSub,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// WIDGET 3: AttendanceCalendar
// ============================================================================

class AttendanceCalendar extends StatelessWidget {
  final DateTime month;
  final Map<String, String> dayStatus; // 'yyyy-MM-dd' → status string
  final bool isDark;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  const AttendanceCalendar({
    super.key,
    required this.month,
    required this.dayStatus,
    required this.isDark,
    this.onPrevMonth,
    this.onNextMonth,
  });

  Color _statusDotColor(String status) {
    switch (status) {
      case 'present':
        return AppTheme.statusPresent;
      case 'late':
        return AppTheme.statusLate;
      case 'absent':
        return AppTheme.statusAbsent;
      case 'overtime':
        return AppTheme.statusBreak;
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;
    final mutedColor = isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted;

    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // weekday of first day: Mon=1 … Sun=7, we want Sun=0 offset
    // Grid starts on Sunday (index 0)
    int startOffset = firstDay.weekday % 7; // Sun=0, Mon=1, …, Sat=6

    final monthLabel = DateFormat('MMMM yyyy').format(month);
    const dayHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Attendance Calendar',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Prev button
              _CalNavButton(
                icon: Icons.chevron_left_rounded,
                onTap: onPrevMonth,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              // Month chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppTheme.accent.withOpacity(0.22)),
                ),
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Next button
              _CalNavButton(
                icon: Icons.chevron_right_rounded,
                onTap: onNextMonth,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Day-of-week headers ───────────────────────────────────────────
          Row(
            children: dayHeaders.map((h) {
              return Expanded(
                child: Center(
                  child: Text(
                    h,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // ── Calendar grid ─────────────────────────────────────────────────
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: startOffset + daysInMonth,
            itemBuilder: (context, index) {
              if (index < startOffset) {
                return const SizedBox.shrink();
              }
              final day = index - startOffset + 1;
              final date = DateTime(month.year, month.month, day);
              final dateKey = DateFormat('yyyy-MM-dd').format(date);
              final status = dayStatus[dateKey];
              final isToday = date.year == today.year &&
                  date.month == today.month &&
                  date.day == today.day;
              final isFuture = date.isAfter(today);
              final dotColor = (status != null && !isFuture)
                  ? _statusDotColor(status)
                  : Colors.transparent;

              return _CalendarCell(
                day: day,
                isToday: isToday,
                isFuture: isFuture,
                dotColor: dotColor,
                isDark: isDark,
                textColor: isFuture ? mutedColor : textColor,
              );
            },
          ),
          const SizedBox(height: 16),
          // ── Legend ───────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendCircle(color: AppTheme.statusPresent, label: 'Present'),
              const SizedBox(width: 14),
              _LegendCircle(color: AppTheme.statusLate, label: 'Late'),
              const SizedBox(width: 14),
              _LegendCircle(color: AppTheme.statusAbsent, label: 'Absent'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _CalNavButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final iconColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
          color: isDark ? AppTheme.darkInput : AppTheme.lightElevated,
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  final int day;
  final bool isToday;
  final bool isFuture;
  final Color dotColor;
  final bool isDark;
  final Color textColor;

  const _CalendarCell({
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.dotColor,
    required this.isDark,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: isToday
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent,
                  )
                : null,
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(
                color: isToday ? Colors.white : textColor,
                fontSize: 12,
                fontWeight:
                    isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 2),
          dotColor != Colors.transparent
              ? Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                )
              : const SizedBox(height: 5),
        ],
      ),
    );
  }
}

class _LegendCircle extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendCircle({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.darkTextSub,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// WIDGET 4: LiveStatCard
// ============================================================================

class LiveStatCard extends StatelessWidget {
  final String value;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDark;
  final bool? isUp; // null = no arrow, true = up, false = down

  const LiveStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isDark,
    this.isUp,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textColor = isDark ? AppTheme.darkText : AppTheme.lightText;
    final subColor = isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
        color: cardColor,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Top accent line ───────────────────────────────────────────────
          Container(
            height: 2,
            color: color,
          ),
          // ── Card body ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon box
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 12),
                // Value
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                // Label
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: subColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isUp != null)
                      Icon(
                        isUp!
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        color: color,
                        size: 13,
                      ),
                    if (isUp != null) const SizedBox(width: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
