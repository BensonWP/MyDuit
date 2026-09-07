import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final dbProvider = Provider<MyDuitDatabase>((ref) {
  final db = MyDuitDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// ─── Account providers ────────────────────────────────────────────

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(dbProvider).watchAllAccounts();
});

// ─── Category providers ──────────────────────────────────────────

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(dbProvider).watchAllCategories();
});

// ─── Transaction providers ────────────────────────────────────────

final recentTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(dbProvider).watchRecentTransactions();
});

/// Kriteria filter riwayat. Field null = tanpa filter.
class HistoryFilter {
  const HistoryFilter({
    this.type,
    this.accountId,
    this.categoryId,
    this.search,
    this.from,
    this.to,
  });
  final String? type;
  final String? accountId;
  final String? categoryId;
  final String? search;

  /// Rentang tanggal [from, to) ISO YYYY-MM-DD.
  final String? from;
  final String? to;

  @override
  bool operator ==(Object other) =>
      other is HistoryFilter &&
      other.type == type &&
      other.accountId == accountId &&
      other.categoryId == categoryId &&
      other.search == search &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(type, accountId, categoryId, search, from, to);
}

final historyProvider =
    StreamProvider.family<List<Transaction>, HistoryFilter>((ref, filter) {
  return ref.watch(dbProvider).watchTransactionsFiltered(
        type: filter.type,
        accountId: filter.accountId,
        categoryId: filter.categoryId,
        search: filter.search,
        from: filter.from,
        to: filter.to,
      );
});

// ─── Bill providers ───────────────────────────────────────────────

final activeBillsStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(dbProvider).watchActiveBills();
});

final completedBillsStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(dbProvider).watchCompletedBills();
});

/// Total tagihan aktif yang belum dibayar bulan ini (untuk baris Hero).
final unpaidBillsTotalProvider = StreamProvider<int>((ref) {
  return ref.watch(dbProvider).watchUnpaidBillsTotalThisMonth();
});

// ─── Plan providers ───────────────────────────────────────────────

/// Target belanja ("Rencana") — urut terbaru.
final plansStreamProvider = StreamProvider<List<Plan>>((ref) {
  return ref.watch(dbProvider).watchPlans();
});

// ─── Proyeksi saldo (Beranda) ──────────────────────────────────────

final billProjectionProvider = StreamProvider<List<BillProjection>>((ref) {
  return ref.watch(dbProvider).watchBillProjection();
});

/// Toggle kartu Proyeksi: ikut kurangkan total Rencana.
final includePlansInProjectionProvider = StateProvider<bool>((_) => false);

/// Tagihan yang jatuh pada bulan ke-m dari sekarang (m=0 bulan ini).
/// Cicilan (durationMonths>0) hanya dihitung selama sisa bulaninya ada;
/// bulan ini hanya dihitung bila belum dibayar.
({int total, int count}) billsForMonth(List<BillProjection> entries, int m) {
  var total = 0, count = 0;
  for (final e in entries) {
    var hit = false;
    if (m == 0) {
      hit = !e.paidThisMonth;
    } else if (e.durationMonths == 0) {
      hit = true; // langganan tanpa batas
    } else {
      final remaining =
          e.durationMonths - e.paidMonths - (e.paidThisMonth ? 0 : 1);
      hit = remaining >= m;
    }
    if (hit) {
      total += e.amount;
      count++;
    }
  }
  return (total: total, count: count);
}

/// Akumulasi tagihan dari bulan ini s/d bulan ke-m (kumulatif — membayar
/// bulan ini mengurangi saldo bulan depan).
int billsThroughMonth(List<BillProjection> entries, int m) {
  var t = 0;
  for (var j = 0; j <= m; j++) {
    t += billsForMonth(entries, j).total;
  }
  return t;
}

// ─── Balance computation (manual state for total balance) ──────────

final totalBalanceProvider = FutureProvider<int>((ref) async {
  ref.watch(accountsStreamProvider);
  ref.watch(recentTransactionsProvider);
  return ref.watch(dbProvider).totalBalance();
});

final accountBalanceProvider = FutureProvider.family<int, String>((ref, accountId) async {
  ref.watch(accountsStreamProvider);
  ref.watch(recentTransactionsProvider);
  return ref.watch(dbProvider).accountBalance(accountId);
});

// ─── Detail wallet ─────────────────────────────────────────────────

final accountProvider = StreamProvider.autoDispose
    .family<Account?, String>((ref, id) => ref.watch(dbProvider).watchAccount(id));

final accountTransactionsProvider = StreamProvider.autoDispose
    .family<List<Transaction>, String>((ref, id) {
  return ref.watch(dbProvider).watchTransactionsByAccount(id);
});

// ─── Riwayat pembayaran tagihan ────────────────────────────────────

final billPaymentsProvider = StreamProvider.autoDispose
    .family<List<BillPayment>, String>((ref, billId) {
  return ref.watch(dbProvider).watchPaymentsForBill(billId);
});

// ─── Laporan bulanan ───────────────────────────────────────────────

/// Kursor bulan aktif untuk Laporan (hari selalu 1).
final reportMonthProvider =
    StateProvider<DateTime>((_) => DateTime(DateTime.now().year, DateTime.now().month));

/// Rentang [from, to) bulan aktif sebagai string tanggal ISO (YYYY-MM-DD).
({String from, String to}) monthRange(DateTime month) {
  final from = DateTime(month.year, month.month, 1);
  final to = DateTime(month.year, month.month + 1, 1);
  return (
    from: from.toIso8601String().substring(0, 10),
    to: to.toIso8601String().substring(0, 10),
  );
}

final monthTransactionsProvider = StreamProvider.autoDispose
    .family<List<Transaction>, DateTime>((ref, month) {
  final range = monthRange(month);
  return ref
      .watch(dbProvider)
      .watchTransactionsByDateRange(range.from, range.to);
});

/// Bucket pengeluaran 6 bulan yang berakhir di [anchor] (indeks 5).
/// Fungsi murni — transaksi sudah difilter ke rentang yang tepat.
List<int> monthTrendBuckets(List<Transaction> txs, DateTime anchor) {
  final first = DateTime(anchor.year, anchor.month - 5);
  final months = List.filled(6, 0);
  for (final tx in txs) {
    if (tx.type != 'expense') continue;
    final d = DateTime.parse(tx.date);
    final idx = (d.year - first.year) * 12 + d.month - first.month;
    if (idx >= 0 && idx < 6) months[idx] += tx.amount;
  }
  return months;
}

/// Tren bulanan: 6 bulan s/d bulan yang dipilih di Laporan.
final trendMonthsProvider =
    FutureProvider.autoDispose<List<int>>((ref) async {
  ref.watch(recentTransactionsProvider); // recompute saat data berubah
  final month = ref.watch(reportMonthProvider);
  final first = DateTime(month.year, month.month - 5);
  final lastRange = monthRange(month);
  final txs = await ref
      .watch(dbProvider)
      .watchTransactionsByDateRange(
        DateTime(first.year, first.month).toIso8601String().substring(0, 10),
        lastRange.to,
      )
      .first;
  return monthTrendBuckets(txs, month);
});

/// Mode kartu tren Laporan: false = per bulan, true = per hari
/// (7 hari kalender terakhir).
final trendDailyModeProvider = StateProvider<bool>((_) => false);

// ─── Mini chart 7 hari (Beranda) ───────────────────────────────────

/// Transaksi pengeluaran pada satu hari tertentu — dipakai sheet
/// tap-bar mini chart Beranda.
final dayExpensesProvider = FutureProvider.autoDispose
    .family<List<Transaction>, DateTime>((ref, day) async {
  ref.watch(recentTransactionsProvider); // recompute saat data berubah
  final db = ref.watch(dbProvider);
  final from = DateTime(day.year, day.month, day.day)
      .toIso8601String()
      .substring(0, 10);
  final to = DateTime(day.year, day.month, day.day + 1)
      .toIso8601String()
      .substring(0, 10);
  final txs = await db.watchTransactionsByDateRange(from, to).first;
  return txs.where((t) => t.type == 'expense').toList();
});

/// Pengeluaran per hari selama 7 hari terakhir (termasuk hari ini),
/// indeks 0 = 6 hari lalu … indeks 6 = hari ini.
final last7DaysExpenseProvider =
    FutureProvider.autoDispose<List<int>>((ref) async {
  ref.watch(recentTransactionsProvider); // recompute saat data berubah
  final db = ref.watch(dbProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: 6))
      .toIso8601String()
      .substring(0, 10);
  // Batas atas inklusif vs date ISO dengan jam ("…T14:30" > "…" polos),
  // jadi 'to' harus besok supaya transaksi hari ini ikut terbaca.
  final to = today.add(const Duration(days: 1))
      .toIso8601String()
      .substring(0, 10);
  final txs = await db.watchTransactionsByDateRange(from, to).first;

  final daily = List.filled(7, 0);
  for (final tx in txs) {
    if (tx.type != 'expense') continue;
    final day = DateTime.parse(tx.date);
    final idx = DateTime(day.year, day.month, day.day)
        .difference(today)
        .inDays;
    if (idx >= -6 && idx <= 0) daily[idx + 6] += tx.amount;
  }
  return daily;
});

// ─── Anggaran bulanan ──────────────────────────────────────────────

final budgetsProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(dbProvider).watchBudgets();
});

/// Tab aktif MainShell — agar widget lintas file (misal banner anggaran)
/// bisa memindahkan tab.
final navIndexProvider = StateProvider<int>((_) => 0);
