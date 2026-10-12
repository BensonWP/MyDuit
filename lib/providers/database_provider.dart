import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import '../utils/dates.dart';
import '../utils/wallet_brand.dart';

/// Satu rangkaian pengeluaran & pemasukan (list sejajar, indeks = periode).
typedef MonthFlow = ({List<int> expense, List<int> income});

final dbProvider = Provider<MyDuitDatabase>((ref) {
  final db = MyDuitDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// ─── Waktu berjalan (app melewati tengah malam) ────────────────────

/// "Sekarang" untuk app yang dibiarkan menyala: di-bump tiap tengah
/// malam via rantai Timer. Nilai harian/bulanan (status tagihan
/// sudah-dibayar, daftar Hari Ini, chart 7 hari) mengambil dari sini,
/// bukan DateTime.now(), agar tidak basi setelah lewat tengah malam.
class _MidnightTicker extends Notifier<DateTime> {
  Timer? _timer;
  @override
  DateTime build() {
    _schedule();
    ref.onDispose(() => _timer?.cancel());
    return DateTime.now();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(nextMidnight(now).difference(now), () {
      state = DateTime.now();
      _schedule();
    });
  }
}

final midnightTickerProvider =
    NotifierProvider<_MidnightTicker, DateTime>(_MidnightTicker.new);

/// Tanggal/jam saat ticker terakhir bump — alias semantik konsumen UI.
final todayProvider =
    Provider<DateTime>((ref) => ref.watch(midnightTickerProvider));

/// Kunci bulan berjalan (YYYY-MM) dari ticker.
final currentMonthProvider = Provider<String>((ref) =>
    ref.watch(midnightTickerProvider).toIso8601String().substring(0, 7));

// ─── Account providers ────────────────────────────────────────────

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(dbProvider).watchAllAccounts();
});

/// Wallet arsip — untuk seksi Diarsipkan di tab Wallet.
final archivedAccountsProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(dbProvider).watchArchivedAccounts();
});

// ─── Brand wallet (master: bawaan + custom) ────────────────────

/// SEMUA brand dari DB (bawaan di-seed saat migrasi + tambahan user).
final brandsProvider = StreamProvider<List<CustomBrand>>((ref) {
  return ref.watch(dbProvider).watchCustomBrands();
});

/// Brand per kind (bank/ewallet/card) untuk picker form & Kelola Brand.
final brandsByKindProvider =
    StreamProvider.family<List<CustomBrand>, String>((ref, kind) {
  return ref.watch(dbProvider).watchBrandsByKind(kind);
});

/// Opsi brand per kind untuk picker form wallet.
final brandOptionsProvider =
    Provider.family<List<BrandOption>, String>((ref, kind) {
  final brands = ref.watch(brandsByKindProvider(kind)).valueOrNull ??
      const <CustomBrand>[];
  return mergeBrandOptions(brands);
});

// ─── Category providers ──────────────────────────────────────────

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(dbProvider).watchAllCategories();
});

/// Kategori aktif untuk picker form (yang diarsip disembunyikan).
/// Daftar penuh ([categoriesStreamProvider]) tetap dipakai untuk
/// resolusi nama transaksi/tagihan lama yang memakai kategori arsip.
final activeCategoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(dbProvider).watchActiveCategories();
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
/// Watch currentMonthProvider: stream dibuat ulang saat ganti bulan
/// (watchActiveBillsDetailed mengikat monthKey saat stream dibuat).
final activeBillsDetailedProvider = StreamProvider<List<ActiveBillRow>>((ref) {
  ref.watch(currentMonthProvider);
  return ref.watch(dbProvider).watchActiveBillsDetailed();
});

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

// ─── Anggaran bulanan ──────────────────────────────────────────

final budgetsProvider = StreamProvider<List<BudgetInfo>>((ref) {
  return ref.watch(dbProvider).watchBudgets();
});

/// Status satu anggaran terhadap belanja berjalan.
enum BudgetState { ok, warning, over }

/// warning saat ≥ 80 %, over saat > 100 %. Budget ≤ 0 selalu ok.
BudgetState budgetState(int spent, int budget) {
  if (budget <= 0) return BudgetState.ok;
  final ratio = spent / budget;
  if (ratio > 1) return BudgetState.over;
  if (ratio >= 0.8) return BudgetState.warning;
  return BudgetState.ok;
}

/// Belanja expense per kategori dari daftar transaksi.
Map<String, int> spentByCategory(List<Transaction> txs) {
  final spent = <String, int>{};
  for (final t in txs) {
    if (t.type == 'expense' && t.categoryId != null) {
      spent[t.categoryId!] = (spent[t.categoryId!] ?? 0) + t.amount;
    }
  }
  return spent;
}

/// Hitung peringatan dari data jadi (fungsi murni — gampang dites).
({int warning, int over}) budgetAlerts(
    List<BudgetInfo> budgets, Map<String, int> spent) {
  var warning = 0, over = 0;
  for (final b in budgets) {
    if (b.type != 'expense') continue;
    switch (budgetState(spent[b.categoryId] ?? 0, b.monthlyAmount)) {
      case BudgetState.warning:
        warning++;
      case BudgetState.over:
        over++;
      case BudgetState.ok:
        break;
    }
  }
  return (warning: warning, over: over);
}

/// Peringatan anggaran bulan berjalan — untuk banner Beranda.
/// Bulan berjalan dari ticker agar ikut berganti saat lewat tengah malam.
final budgetAlertsProvider = Provider<({int warning, int over})>((ref) {
  final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];
  if (budgets.isEmpty) return (warning: 0, over: 0);
  final now = ref.watch(todayProvider);
  final txs = ref
          .watch(monthTransactionsProvider(DateTime(now.year, now.month)))
          .valueOrNull ??
      const [];
  return budgetAlerts(budgets, spentByCategory(txs));
});

// ─── Proyeksi saldo (Beranda) ──────────────────────────────────────

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
/// Hanya expense/income; tipe lain (mis. data transfer lama)
/// dikecualikan dari arus kas.
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
/// sheet tap-bar chart 7 hari (Beranda & Laporan). Tipe selain
/// expense/income (mis. data transfer lama) dikecualikan.
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
  // todayProvider juga dipakai sebagai pemicu: chart ikut bergeser
  // saat app melewati tengah malam.
  final now = ref.watch(todayProvider);
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

// ─── Navigasi ────────────────────────────────────────────────────

/// Tab aktif MainShell — agar widget lintas file (misal banner anggaran)
/// bisa memindahkan tab.
final navIndexProvider = StateProvider<int>((_) => 0);

// ─── Cinematic unlock ──────────────────────────────────────────

/// Bump tiap unlock sukses — HomeScreen me-replay entrance-nya
/// (count-up + stagger) lewat KeyedSubtree. Di test tak pernah
/// berubah → nol efek ke suite.
final unlockNonceProvider = StateProvider<int>((_) => 0);
