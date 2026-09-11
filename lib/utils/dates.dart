/// Selisih hari ke jatuh tempo berikutnya (0 = hari ini).
/// Tanggal 29–31 di bulan pendek diklem ke hari terakhir bulan tsb —
/// konsisten dengan _nextDueDate di NotificationService.
int daysUntilDue(int dueDay, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  for (var m = 0; m < 2; m++) {
    final first = DateTime(n.year, n.month + m);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    final day = dueDay > lastDay ? lastDay : dueDay;
    final due = DateTime(first.year, first.month, day);
    if (!due.isBefore(today)) return due.difference(today).inDays;
  }
  return 0;
}

/// Tengah malam berikutnya dari [now] — dipakai midnightTickerProvider
/// untuk bump "sekarang" saat app dibiarkan menyala melewati tengah malam.
/// DateTime klem otomatis (day 32 → bulan berikutnya).
DateTime nextMidnight(DateTime now) =>
    DateTime(now.year, now.month, now.day + 1);
