import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Theme Mode Provider ───────────────────────────────────────────────────────
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// ============================================================================
// APP THEME — CyberZeus AMS design language
// Deep navy / electric blue / cyan palette
// ============================================================================

class AppTheme {
  AppTheme._();

  // ── Brand Palette ─────────────────────────────────────────────────────────
  static const Color accent        = Color(0xFF3D94F7); // Electric blue (primary)
  static const Color accentDim     = Color(0xFF1A6ED8); // Blue dim
  static const Color accent2       = Color(0xFF00C2FF); // Cyan secondary
  static const Color accentGlow    = Color(0x261A6ED8); // 15% blue glow

  // backward-compat aliases used by existing screens
  static const Color brandPrimary   = Color(0xFF0A1628);
  static const Color brandPrimaryLt = Color(0xFF1A6ED8);
  static const Color brandSecondary = Color(0xFF00C2FF);
  static const Color brandSuccess   = Color(0xFF00D68F);
  static const Color brandWarning   = Color(0xFFFFB020);
  static const Color brandDanger    = Color(0xFFFF4D6A);
  static const Color brandInfo      = Color(0xFF7C5CFC);

  // ── Role accent colors ────────────────────────────────────────────────────
  static const Color roleAdmin    = Color(0xFFF5A623); // Gold
  static const Color roleHR       = Color(0xFF3D94F7); // Blue
  static const Color roleManager  = Color(0xFF7C5CFC); // Purple
  static const Color roleEmployee = Color(0xFF00D68F); // Green

  // ── Sidebar ───────────────────────────────────────────────────────────────
  static const Color sidebarBg      = Color(0xFF0F1E38); // dark mode
  static const Color sidebarBgLight = Color(0xFF1C3358); // light mode (lighter navy)
  static const Color sidebarBorder  = Color(0x2E1A6ED8); // 18% blue border

  // ── Dark Mode ────────────────────────────────────────────────────────────
  static const Color darkBg           = Color(0xFF0A1628); // deep navy
  static const Color darkSurface      = Color(0xFF0F1E38); // nav/topbar
  static const Color darkSurface2     = Color(0xFF152844); // elevated
  static const Color darkCard         = Color(0xFF111D33); // card bg
  static const Color darkCard2        = Color(0xFF142036); // secondary card
  static const Color darkInput        = Color(0xFF152844); // inputs
  static const Color darkBorder       = Color(0x2E1A6ED8); // 18% blue border
  static const Color darkBorderStrong = Color(0x511A6ED8); // 32% blue border
  static const Color darkText         = Color(0xFFEEF2FF); // near-white
  static const Color darkTextSub      = Color(0xFF8BA3C7); // muted blue-gray
  static const Color darkTextMuted    = Color(0xFF4A6080); // dim blue-gray

  // ── Light Mode ───────────────────────────────────────────────────────────
  static const Color lightBg           = Color(0xFFF0F4FA);
  static const Color lightSurface      = Color(0xFFFFFFFF);
  static const Color lightElevated     = Color(0xFFE8EEF8);
  static const Color lightInput        = Color(0xFFEDF2FB);
  static const Color lightBorder       = Color(0x261A6ED8); // 15% blue
  static const Color lightBorderStrong = Color(0x4D1A6ED8); // 30% blue
  static const Color lightText         = Color(0xFF0A1628);
  static const Color lightTextSub      = Color(0xFF3A5070);
  static const Color lightTextMuted    = Color(0xFF8AA0BE);

  // backward-compat
  static const Color lightSurface2 = Color(0xFFE8EEF8);
  static const Color lightDivider  = Color(0x261A6ED8);

  // ── Status / Semantic Colors ──────────────────────────────────────────────
  static const Color statusPresent  = Color(0xFF00D68F); // Emerald green
  static const Color statusLate     = Color(0xFFFFB020); // Amber
  static const Color statusAbsent   = Color(0xFFFF4D6A); // Red
  static const Color statusBreak    = Color(0xFF7C5CFC); // Purple
  static const Color statusPending  = Color(0xFFF5A623); // Gold
  static const Color statusApproved = Color(0xFF00D68F);
  static const Color statusRejected = Color(0xFFFF4D6A);
  static const Color statusOvertime = Color(0xFF00C2FF); // Cyan

  // ── Light Theme ──────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1A6ED8),
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFDCEBFF),
        onPrimaryContainer: Color(0xFF0A1628),
        secondary: Color(0xFF00B8D9),
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFCCF7FF),
        onSecondaryContainer: Color(0xFF003344),
        surface: lightSurface,
        onSurface: lightText,
        surfaceContainerHighest: lightElevated,
        onSurfaceVariant: lightTextSub,
        outline: Color(0x4D1A6ED8),
        outlineVariant: lightBorder,
        error: Color(0xFFFF4D6A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFE4E9),
        shadow: Color(0x1A0A1628),
        scrim: Color(0x330A1628),
      ),
      scaffoldBackgroundColor: lightBg,
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(color: lightText, fontSize: 16, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: lightTextSub),
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1, space: 0),
      textTheme: const TextTheme(
        displayLarge:   TextStyle(color: lightText, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: -1.5),
        displayMedium:  TextStyle(color: lightText, fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1),
        headlineLarge:  TextStyle(color: lightText, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: lightText, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        headlineSmall:  TextStyle(color: lightText, fontSize: 20, fontWeight: FontWeight.w600),
        titleLarge:     TextStyle(color: lightText, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium:    TextStyle(color: lightText, fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall:     TextStyle(color: lightTextSub, fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge:      TextStyle(color: lightText, fontSize: 15),
        bodyMedium:     TextStyle(color: lightTextSub, fontSize: 14),
        bodySmall:      TextStyle(color: lightTextMuted, fontSize: 12),
        labelLarge:     TextStyle(color: lightText, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium:    TextStyle(color: lightTextSub, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall:     TextStyle(color: lightTextMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A6ED8),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF1A6ED8),
          side: const BorderSide(color: lightBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF1A6ED8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: lightBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1A6ED8), width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: statusAbsent)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: lightTextSub, fontSize: 14),
        hintStyle: const TextStyle(color: lightTextMuted, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightElevated,
        selectedColor: const Color(0xFFDCEBFF),
        labelStyle: const TextStyle(color: lightTextSub, fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: lightBorder)),
      ),
      tooltipTheme: const TooltipThemeData(
        textStyle: TextStyle(color: Colors.white, fontSize: 12),
        decoration: BoxDecoration(color: Color(0xFF152844), borderRadius: BorderRadius.all(Radius.circular(6))),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(lightElevated),
        dataRowColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? const Color(0xFFEDF2FB) : lightSurface),
        dividerThickness: 1,
        headingTextStyle: const TextStyle(color: lightTextSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7),
        dataTextStyle: const TextStyle(color: lightText, fontSize: 13),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    );
  }

  // ── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Color(0xFF0A1628),
        primaryContainer: Color(0xFF0F2A5A),
        onPrimaryContainer: Color(0xFFBBD6FF),
        secondary: Color(0xFF00C2FF),
        onSecondary: Color(0xFF003344),
        secondaryContainer: Color(0xFF004D66),
        onSecondaryContainer: Color(0xFFB3F0FF),
        surface: darkSurface,
        onSurface: darkText,
        surfaceContainerHighest: darkSurface2,
        onSurfaceVariant: darkTextSub,
        outline: darkBorderStrong,
        outlineVariant: darkBorder,
        error: Color(0xFFFF4D6A),
        onError: Color(0xFF3D0010),
        errorContainer: Color(0xFF7A0020),
        shadow: Colors.black,
        scrim: Color(0x660A1628),
      ),
      scaffoldBackgroundColor: darkBg,
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(color: darkText, fontSize: 16, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: darkTextSub),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1, space: 0),
      textTheme: const TextTheme(
        displayLarge:   TextStyle(color: darkText, fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: -1.5),
        displayMedium:  TextStyle(color: darkText, fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1),
        headlineLarge:  TextStyle(color: darkText, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: darkText, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        headlineSmall:  TextStyle(color: darkText, fontSize: 20, fontWeight: FontWeight.w600),
        titleLarge:     TextStyle(color: darkText, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        titleMedium:    TextStyle(color: darkText, fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall:     TextStyle(color: darkTextSub, fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge:      TextStyle(color: darkText, fontSize: 15),
        bodyMedium:     TextStyle(color: darkTextSub, fontSize: 14),
        bodySmall:      TextStyle(color: darkTextMuted, fontSize: 12),
        labelLarge:     TextStyle(color: darkText, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium:    TextStyle(color: darkTextSub, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall:     TextStyle(color: darkTextMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF0A1628),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: const BorderSide(color: darkBorderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: darkBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: darkBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: statusAbsent)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        labelStyle: const TextStyle(color: darkTextSub, fontSize: 14),
        hintStyle: const TextStyle(color: darkTextMuted, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurface2,
        selectedColor: const Color(0xFF0F2A5A),
        labelStyle: const TextStyle(color: darkTextSub, fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: darkBorder)),
      ),
      tooltipTheme: const TooltipThemeData(
        textStyle: TextStyle(color: darkText, fontSize: 12),
        decoration: BoxDecoration(color: Color(0xFF1C3358), borderRadius: BorderRadius.all(Radius.circular(6))),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(darkCard2),
        dataRowColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? const Color(0xFF1A2B47) : darkCard),
        dividerThickness: 1,
        headingTextStyle: const TextStyle(color: darkTextSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7),
        dataTextStyle: const TextStyle(color: darkText, fontSize: 13),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    );
  }

  // ── Shared Helpers ────────────────────────────────────────────────────────

  static Color statusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'ON_TIME': case 'CHECKED_IN': case 'PRESENT': case 'APPROVED': return statusPresent;
      case 'EARLY': return accent;           // Blue — arrived early
      case 'LATE': return statusLate;
      case 'MISSED_CHECKOUT': case 'ABSENT': case 'REJECTED': return statusAbsent;
      case 'BREAK_ACTIVE': return statusBreak;
      case 'PENDING': case 'PARTIAL': return statusPending;
      case 'OVERTIME': return statusOvertime;
      default: return const Color(0xFF4A6080);
    }
  }

  static Color statusBg(String? status, bool isDark) => statusColor(status).withOpacity(isDark ? 0.14 : 0.1);

  static BoxDecoration cardDecoration(BuildContext context, {bool elevated = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? darkCard : lightSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: isDark ? darkBorder : lightBorder),
      boxShadow: elevated ? [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.08), blurRadius: 20, offset: const Offset(0, 6))] : null,
    );
  }

  /// Pill status badge matching CyberZeus style
  static Widget statusBadge(String label, Color color, {double fontSize = 11.5}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w600, letterSpacing: 0.2), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  /// Gradient for primary actions (blue)
  static const LinearGradient primaryGradient = LinearGradient(colors: [accentDim, accent]);

  /// Gradient for logo icon
  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF1A6ED8), Color(0xFF3D94F7)],
  );
}
