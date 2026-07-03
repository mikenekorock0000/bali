import 'package:flutter/material.dart';

/// ジャンル別のビジュアル設定
class GenrePalette {
  const GenrePalette({
    required this.primary,
    required this.secondary,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
  });

  final Color primary;
  final Color secondary;
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;

  static GenrePalette forGenre(String genre) {
    return switch (genre) {
      '現代' => const GenrePalette(
          primary: Color(0xFF3D8BFD),
          secondary: Color(0xFF1B6CA8),
          icon: Icons.apartment,
          gradientStart: Color(0xFF0D1B2A),
          gradientEnd: Color(0xFF1B263B),
        ),
      '和風' => const GenrePalette(
          primary: Color(0xFFD64545),
          secondary: Color(0xFF8B4513),
          icon: Icons.temple_buddhist,
          gradientStart: Color(0xFF1A0F0F),
          gradientEnd: Color(0xFF2D1810),
        ),
      'ホラー' => const GenrePalette(
          primary: Color(0xFFB71C1C),
          secondary: Color(0xFF1B5E20),
          icon: Icons.nights_stay,
          gradientStart: Color(0xFF0A0A0A),
          gradientEnd: Color(0xFF1A1A1A),
        ),
      'ファンタジー' => const GenrePalette(
          primary: Color(0xFF9C27B0),
          secondary: Color(0xFFFFB300),
          icon: Icons.auto_fix_high,
          gradientStart: Color(0xFF1A0F2E),
          gradientEnd: Color(0xFF2D1B4E),
        ),
      'ミステリー' => const GenrePalette(
          primary: Color(0xFFFFB74D),
          secondary: Color(0xFF1565C0),
          icon: Icons.search,
          gradientStart: Color(0xFF0F1520),
          gradientEnd: Color(0xFF1A2332),
        ),
      _ => const GenrePalette(
          primary: Color(0xFFE94560),
          secondary: Color(0xFF533483),
          icon: Icons.castle,
          gradientStart: Color(0xFF0F0F1A),
          gradientEnd: Color(0xFF1A1A2E),
        ),
    };
  }
}

class AppTheme {
  static ThemeData build({GenrePalette? palette}) {
    final p = palette ?? GenrePalette.forGenre('洋館');
    final scheme = ColorScheme.dark(
      primary: p.primary,
      onPrimary: Colors.white,
      secondary: p.secondary,
      onSecondary: Colors.white,
      surface: const Color(0xFF1A1A2E),
      onSurface: const Color(0xFFEEEEEE),
      surfaceContainerHighest: const Color(0xFF252540),
      error: const Color(0xFFFF6B6B),
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      useMaterial3: true,
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: const Color(0xFF0F0F1A),
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, height: 1.3),
        headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.3),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.6),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.1)),
    );
  }

  static ThemeData forGenre(String genre) => build(palette: GenrePalette.forGenre(genre));
}
