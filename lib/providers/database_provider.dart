import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';

/// Satu rangkaian pengeluaran & pemasukan (list sejajar, indeks = periode).
typedef MonthFlow = ({List<int> expense, List<int> income});

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
    StreamProvider.autoDispose.family<List<Transaction>, HistoryFilter>((ref, filter) {
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

/// Satu-satunya sumber data tagihan aktif. Daftar tagihan dan proyeksi
/// di-derive dari stream yang sama → tak bisa lagi beda frame antar konsumen.
final activeBillsDetailedProvider = StreamProvider<List<ActiveBillRow>>(
    (ref) => ref.watch(dbProvider).watchActiveBillsDetailed());

final activeBillsProvider = Provider<List<Bill>>((ref) {
  final rows = ref.watch(activeBillsDetailedProvider).valueOrNull ?? const [];
  return [for (final r in rows) r.bill];
});

final completedBillsStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(dbProvider).watchCompletedBills();
});

/// Total tagihan aktif yang belum dibayar bulan ini (baris Hero Beranda) —
/// derive dari stream tagihan aktif, bukan query kedua.
final unpaidBillsTotalProvider = Provider<int>((ref) {
  final rows = ref.watch(activeBillsDetailedProvider).valueOrNull ?? const [];
  return billsForMonth(rows, 0).total;
});

// ─── Plan providers ───────────────────────────────────────────────

/// Target belanja ("Rencana") — urut terbaru.
final plansStreamProvider = StreamProvider<List<Plan>>((ref) {
  return ref.watch(dbProvider).watchPlans();
});

// ─── Proyeksi saldo (Beranda) ──────────────────────────────────────

/// Toggle kartu Proyeksi: ikut kurangkan total Rencana.
final includePlansInProjectionProvider = StateProvider<bool>((_) => false);

/// Bulan yang sedang dibuka di kartu hero Beranda (0 = bulan ini,
/// 1–12 = proyeksi). Bagian Tagihan ikut mengikuti nilai ini.
final homeMonthOffsetProvider = StateProvider<int>((_) => 0);

/// Apakah tagihan ini jatuh pada bulan ke-m dari sekarang.
/// Cicilan (durationMonths>0) hanya dihitung selama sisa bulaninya ada;
/// bulan ini hanya dihitung bila belum dibayar.
bool billHitsMonth(ActiveBillRow e, int m) {
  if (m == 0) return !e.paidThisMonth;
  if (e.bill.durationMonths == 0) return true; // langganan tanpa batas
  final remaining = e.bill.durationMonths - e.paidMonths -
      (e.paidThisMonth ? 0 : 1);
  return remaining >= m;
}

/// Tagihan yang jatuh pada bulan ke-m dari sekarang (m=0 bulan ini).
({int total, int count}) billsForMonth(List<ActiveBillRow> entries, int m) {
  var total = 0, count = 0;
  for (final e in entries) {
    if (billHitsMonth(e, m)) {
      total += e.bill.amount;
      count++;
    }
  }
  return (total: total, count: count);
}

/// Tagihan untuk bulan terpilih di hero Beranda (urut jatuh tempo,
/// mengikuti urutan watchActiveBillsDetailed). Predikat sama dengan
/// billsForMonth — satu stream sumber, jadi selalu cocok dengan Proyeksi.
final monthBillsProvider =
    Provider.autoDispose.family<List<Bill>, int>((ref, m) {
  final rows = ref.watch(activeBillsDetailedProvider).valueOrNull ?? const [];
  return [for (final r in rows) if (billHitsMonth(r, m)) r.bill];
});

/// Akumulasi tagihan dari bulan ini s/d bulan ke-m (kumulatif — membayar
/// bulan ini mengurangi saldo bulan depan).
int billsThroughMonth(List<ActiveBillRow> entries, int m) {
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

/// Bucket pengeluaran & pemasukan 6 bulan yang berakhir di [anchor]
/// (indeks 5). Fungsi murni — transaksi sudah difilter ke rentang tepat.
/// Transfer diabaikan (bukan arus kas masuk/keluar riil).
MonthFlow monthTrendBuckets(List<Transaction> txs, DateTime anchor) {
  final first = DateTime(anchor.year, anchor.month - 5);
  final expense = List.filled(6, 0);
  final income = List.filled(6, 0);
  for (final tx in txs) {
    final target = tx.type == 'expense'
        ? expense
        : tx.type == 'income'
            ? income
            : null;
    if (target == null) continue;
    final d = DateTime.parse(tx.date);
    final idx = (d.year - first.year) * 12 + d.month - first.month;
    if (idx >= 0 && idx < 6) target[idx] += tx.amount;
  }
  return (expense: expense, income: income);
}

/// Tren bulanan: 6 bulan s/d bulan yang dipilih di Laporan.
final trendMonthsProvider =
    FutureProvider.autoDispose<MonthFlow>((ref) async {
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

/// Filter arus: true = keluar, false = masuk, null = OFF (semua).
/// Klik segmen aktif lagi mematikan filter (lihat FlowToggle di Beranda).
final flowOutProvider = StateProvider<bool?>((_) => true);

// ─── Mode privasi (mata di Beranda) ────────────────────────────────

const privacyModePrefKey = 'privacy_mode';

/// true = nominal uang di Beranda disembunyikan. Nilai awal disematkan
/// dari SharedPreferences di main.dart (overrideWith) agar frame pertama
/// sudah benar.
final privacyModeProvider = StateProvider<bool>((_) => false);

/// Ubah status mata + persist antar restart app.
Future<void> setPrivacyMode(WidgetRef ref, bool value) async {
  ref.read(privacyModeProvider.notifier).state = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(privacyModePrefKey, value);
}

// ─── Mini chart 7 hari (Beranda) ───────────────────────────────────

/// Transaksi pemasukan & pengeluaran pada satu hari tertentu — dipakai
/// sheet tap-bar chart 7 hari (Beranda & Laporan). Transfer dikecualikan.
final dayTransactionsProvider = FutureProvider.autoDispose
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
  return txs.where((t) => t.type != 'transfer').toList();
});

/// Pengeluaran & pemasukan per hari selama 7 hari terakhir (termasuk hari
/// ini), indeks 0 = 6 hari lalu … indeks 6 = hari ini.
final last7DaysFlowProvider =
    FutureProvider.autoDispose<MonthFlow>((ref) async {
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

  final expense = List.filled(7, 0);
  final income = List.filled(7, 0);
  for (final tx in txs) {
    final target = tx.type == 'expense'
        ? expense
        : tx.type == 'income'
            ? income
            : null;
    if (target == null) continue;
    final day = DateTime.parse(tx.date);
    final idx = DateTime(day.year, day.month, day.day)
        .difference(today)
        .inDays;
    if (idx >= -6 && idx <= 0) target[idx + 6] += tx.amount;
  }
  return (expense: expense, income: income);
});

// ─── Anggaran bulanan ──────────────────────────────────────────────

/// Tab aktif MainShell — agar widget lintas file (misal banner anggaran)
/// bisa memindahkan tab.
final navIndexProvider = StateProvider<int>((_) => 0);
