import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _formatter = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

String formatRupiah(int amount) => _formatter.format(amount);

String formatDate(String iso) {
  final d = DateTime.parse(iso);
  return DateFormat('dd MMM yyyy', 'id_ID').format(d);
}

String formatDateTime(String iso) {
  final d = DateTime.parse(iso);
  return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(d);
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
    final formatted = NumberFormat.decimalPattern('id_ID').format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
