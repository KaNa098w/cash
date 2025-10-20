import 'package:flutter/material.dart';

class AppTheme {
  static const green = Color(0xFF00C853); // верхняя панель
  static const darkPanel = Color(0xFF2E2E2E); // нижняя левая панель
  static const greyB = Color(0xFFF5F5F5);
  static const appBarColor = Color(0xFF2E3136);
  static const grey = Color(0x80D9D9D9);
  static const greyPanel = Color(0xFFD9D9D9);
  static const green1 = Color(0xFF33CC99);  

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: false);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.white,
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      dividerColor: const Color(0xFFE6EEF3),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
