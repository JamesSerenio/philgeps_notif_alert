import 'package:flutter/material.dart';

class AppStyles {
  static const Color primary = Color(0xFF1769FF);
  static const Color background = Color(0xFFF4F7FB);
  static const Color card = Colors.white;

  static const Color danger = Color(0xFFE53935);
  static const Color warning = Color(0xFFFF9800);
  static const Color safe = Color(0xFF2E7D32);

  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    useMaterial3: true,
    fontFamily: 'Arial',
    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 18,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
  );
}
