import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../db/database.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/report_math.dart';
import '../reports_screen.dart';
import 'reports_stats.dart';
import 'reports_donut_card.dart';
import 'reports_flow_trend.dart';
import 'reports_budget_section.dart';

/// Tab Ringkasan Laporan: bulan switcher, stat utama, donut per kategori,
/// tren arus, dan anggaran.
class ReportsSummaryTab extends ConsumerWidget {
  const ReportsSummaryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);

    /// Tap legenda donut → tab Transaksi terfilter kategori tsb.
    void openCategory(String categoryId) {
      final tabState = summaryToHistoryKey.currentState;
      if (tabState != null) {
        final r = monthRange(month);
        tabState.applyCategoryFilter(
          categoryId,
          from: r.from,
          to: r.to,
          label: 'Bulan laporan',
        );
        DefaultTabController.of(context).animateTo(1);
      }
    }

    final txs =
        ref.watch(monthTransactionsProvider(month)).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];

    // Hitung di Dart — data sebulan kecil, SQL tambahan tak diperlukan.
    final totals = computeReportTotals(txs);

    final catName = <String, Category>{
      for (final c in categories) c.id: c,
    };

    // Delta pengeluaran vs bulan sebelumnya.
    final prevMonth = DateTime(month.year, month.month - 1);
    final prevTxs =
        ref.watch(monthTransactionsProvider(prevMonth)).valueOrNull;
    final prevExpense = prevTxs
        ?.where((t) => t.type == 'expense')
        .fold<int>(0, (a, t) => a + t.amount);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
        children: [
          MonthSwitcher(month: month),
          const SizedBox(height: D.s4),

          // ── Hierarki ringkasan: Keluar = metrik utama (full-width),
          // Masuk + Selisih sejajar di bawahnya (layout B).
          BigStatCard(
            label: 'Total Keluar',
            value: formatRupiah(totals.expense),
            sub: totals.expenseCount > 0
                ? '${totals.expenseCount} transaksi • ${expenseDeltaText(totals.expense, prevExpense, prevMonth)}'
                : expenseDeltaText(totals.expense, prevExpense, prevMonth),
          ),
          const SizedBox(height: D.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatCard(
                  label: 'Masuk',
                  value: formatRupiah(totals.income),
                  sub: '${totals.incomeCount} transaksi',
                  color: D.income,
                  icon: Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: D.s3),
              Expanded(
                child: StatCard(
                  label: 'Selisih',
                  value:
                      '${totals.income - totals.expense < 0 ? '-' : '+'}${formatRupiah((totals.income - totals.expense).abs())}',
                  sub: 'Masuk - Keluar',
                  color: totals.income - totals.expense >= 0
                      ? D.cobalt
                      : D.expense,
                  icon: Icons.swap_horiz_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: D.s6),

          // ── Donut pengeluaran per kategori ──
          CategoryDonutCard(
            title: 'Pengeluaran per Kategori',
            rows: totals.expenseByCategory,
            total: totals.expense,
            centerTitle: 'Keluar',
            emptyText: 'Belum ada pengeluaran bulan ini.',
            catName: catName,
            onOpenCategory: openCategory,
          ),
          const SizedBox(height: D.s6),

          // ── Donut pemasukan per kategori ──
          CategoryDonutCard(
            title: 'Pemasukan per Kategori',
            rows: totals.incomeByCategory,
            total: totals.income,
            centerTitle: 'Masuk',
            emptyText: 'Belum ada pemasukan bulan ini.',
            catName: catName,
            onOpenCategory: openCategory,
          ),
          const SizedBox(height: D.s6),

          // ── Tren pengeluaran 6 bulan ──
          const FlowTrendCard(),
          const SizedBox(height: D.s6),

          // ── Anggaran bulanan (mengikuti bulan yang dipilih) ──
          BudgetSection(month: month, spentByCat: _spentByCategory(txs)),

          const SizedBox(height: D.s6),
        ],
      ),
    );
  }

  /// spentByCat untuk anggaran: pengeluaran per kategori bulan terpilih.
  Map<String, int> _spentByCategory(List<Transaction> txs) {
    final map = <String, int>{};
    for (final tx in txs) {
      if (tx.type == 'expense' && tx.categoryId != null) {
        map[tx.categoryId!] = (map[tx.categoryId!] ?? 0) + tx.amount;
      }
    }
    return map;
  }
}
