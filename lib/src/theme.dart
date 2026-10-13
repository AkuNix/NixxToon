import 'package:flutter/material.dart';

// Kontrak visual NixxToon: ruang baca gelap, konten yang bicara.
// 1 aksen (amber) cuma buat aksi utama. Tanpa gradient di UI.
class NixxTheme {
  static const bg = Color(0xFF0F0F1A);
  static const surface = Color(0xFF171724);
  static const surface2 = Color(0xFF1F1F30);
  static const accent = Color(0xFFFFB224);
  static const textDim = Color(0xFF9CA3AF);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(fontFamily: 'PlusJakartaSans'),
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        surface: surface,
        onPrimary: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: accent,
        unselectedItemColor: textDim,
      ),
    );
  }
}
