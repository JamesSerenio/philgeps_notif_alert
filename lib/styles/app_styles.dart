import 'package:flutter/material.dart';

class AppStyles {
  static const Color primaryGreen = Color(0xFF0F4D2F);
  static const Color deepGreen = Color(0xFF08351F);
  static const Color softGreen = Color(0xFFEAF6EF);

  static const Color gold = Color(0xFFD4AF37);
  static const Color softGold = Color(0xFFFFF7DF);

  static const Color background = Color(0xFFF6F7F2);
  static const Color card = Colors.white;

  static const Color danger = Color(0xFFD92D20);
  static const Color warning = Color(0xFFF79009);
  static const Color safe = Color(0xFF027A48);
  static const Color old = Color(0xFF667085);

  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: background,
    useMaterial3: true,
    fontFamily: 'Arial',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryGreen,
      primary: primaryGreen,
      secondary: gold,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: deepGreen,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE4E7EC)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: gold, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 20,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
  );
}