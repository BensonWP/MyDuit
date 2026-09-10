import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String formatRupiah(int amount) => _formatter.format(amount);

/// Nominal ter-mask untuk mode privasi (mata aktif).
String formatMasked() => 'Rp ••••••';

String formatDate(String iso) {
  final d = DateTime.parse(iso);
  return DateFormat('dd MMM yyyy', 'id_ID').format(d);
}

/// Jam & menit dari tanggal ISO — "14:30".
String formatTime(String iso) {
  final d = DateTime.parse(iso);
  return DateFormat('HH:mm').format(d);
}

String formatMonth(String iso) {
  final d = DateTime.parse(iso);
  return DateFormat('MMMM yyyy', 'id_ID').format(d);
}

String parseCurrency(String text) => text.replaceAll(RegExp(r'[^0-9]'), '');

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    // Clamp 15 digit (≈ Rp 999 triliun): paste lebih panjang tidak
    // boleh melewati int.parse — 64-bit int masih aman.
    final safeDigits = digits.length > 15 ? digits.substring(0, 15) : digits;
    final formatted = NumberFormat.decimalPattern('id_ID').format(int.parse(safeDigits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
