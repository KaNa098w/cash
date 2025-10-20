import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color grey999;

  const AppColors({required this.grey999});

  static const light = AppColors(grey999: Color(0xFF999999));

  @override
  AppColors copyWith({Color? grey999}) =>
      AppColors(grey999: grey999 ?? this.grey999);

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(grey999: Color.lerp(grey999, other.grey999, t)!);
  }
}

class PosTheme {
  static final blurSigma = ImageFilter.blur(sigmaX: 10, sigmaY: 10);
  static ThemeData light() {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3D5AFE),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2E3136),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
    );
  }
}
