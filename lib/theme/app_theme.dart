import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — sumber kebenaran: DESIGN.md
abstract final class D {
  // Warna
  static const cobalt = Color(0xFF1A3A6B);
  static const cobaltDeep = Color(0xFF122A52);
  static const surface = Color(0xFFF7F8FB);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF101828);
  static const inkMuted = Color(0xFF667085);
  static const line = Color(0xFFEAECF0);
  static const amber = Color(0xFFF5A524);
  static const income = Color(0xFF0E9F6E);
  static const expense = Color(0xFFE02D3C);

  // Radius
  static const rSm = 8.0;
  static const rMd = 16.0;
  static const rLg = 24.0;

  // Spacing
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s12 = 48.0;
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: D.cobalt,
      primary: D.cobalt,
      surface: D.surface,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: D.surface,
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
      bodyColor: D.ink,
      displayColor: D.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: D.surface,
      foregroundColor: D.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: D.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: D.card,
      indicatorColor: D.cobalt.withValues(alpha: 0.12),
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? D.cobalt : D.inkMuted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? D.cobalt : D.inkMuted,
          )),
    ),
    cardTheme: CardThemeData(
      color: D.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(D.rMd),
        side: const BorderSide(color: D.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: D.cobalt,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rMd)),
        minimumSize: const Size.fromHeight(52),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: D.card,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s3 + 2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.rMd),
        borderSide: const BorderSide(color: D.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.rMd),
        borderSide: const BorderSide(color: D.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(D.rMd),
        borderSide: const BorderSide(color: D.cobalt, width: 1.6),
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14, color: D.inkMuted, fontWeight: FontWeight.w500),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: D.amber,
      foregroundColor: D.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rLg)),
      extendedTextStyle:
          GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rSm)),
      labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
    ),
    dividerTheme: const DividerThemeData(color: D.line, thickness: 1, space: 1),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: D.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(D.rLg)),
      ),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: D.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rLg)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: D.ink,
      contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13.5, color: Colors.white, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.rMd)),
    ),
  );
}
