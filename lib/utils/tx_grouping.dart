import '../db/database.dart';
import 'currency.dart';

/// Label tanggal: "Hari ini", "Kemarin", atau tanggal lengkap (id_ID).
String dayLabel(String isoDay) {
  final d = DateTime.parse(isoDay);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Hari ini';
  if (day == today.subtract(const Duration(days: 1))) return 'Kemarin';
  return formatDate(isoDay);
}

/// Kelompokkan transaksi (sudah terurut desc) per hari.
/// Urutan grup mempertahankan urutan input.
List<MapEntry<String, List<Transaction>>> groupByDay(List<Transaction> txs) {
  final groups = <String, List<Transaction>>{};
  for (final tx in txs) {
    (groups[tx.date.substring(0, 10)] ??= []).add(tx);
  }
  return groups.entries.toList();
}
