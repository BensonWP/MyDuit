import 'package:flutter/material.dart';

/// Palet tetap kategori — dipilih via hash deterministik dari id.
/// Hash manual (bukan String.hashCode) agar warna stabil antar sesi,
/// perangkat, dan versi Dart — tanpa mengubah skema DB.
const _palette = <Color>[
  Color(0xFF0D9488), // teal
  Color(0xFF2563EB), // biru
  Color(0xFFE11D48), // rose
  Color(0xFFD97706), // amber tua
  Color(0xFF7C3AED), // violet
  Color(0xFF059669), // hijau
  Color(0xFFEA580C), // oranye
  Color(0xFF0891B2), // cyan
  Color(0xFFDB2777), // pink
  Color(0xFF4F46E5), // indigo
  Color(0xFF65A30D), // lime
  Color(0xFF0F766E), // teal gelap
];

Color categoryColor(String categoryId) {
  var h = 0;
  for (final code in categoryId.codeUnits) {
    h = (h * 31 + code) & 0x7FFFFFFF;
  }
  return _palette[h % _palette.length];
}
