import 'package:flutter/material.dart';

/// Light SaaS-style dashboard theme.
ThemeData buildAppTheme() {
  const seed = Color(0xFF2563EB);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFF4F6F8),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF111827),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.white,
      selectedIconTheme: const IconThemeData(color: seed),
      selectedLabelTextStyle: const TextStyle(color: seed, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        color: Color(0xFF374151),
        fontSize: 13,
      ),
      dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
    ),
  );
}
