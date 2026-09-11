import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/category_color.dart';
import '../utils/currency.dart';
import '../theme/app_theme.dart';
import '../widgets/donut_chart.dart';
import 'history_screen.dart';
import 'home_screen.dart' show FlowToggle, showDayTransactionsSheet;

/// GlobalKey tab Transaksi — tap legenda donut lompat ke tab Transaksi
/// dengan filter kategori terisi (dipanggil lintas _ReportsSummaryTab).
final _summaryToHistoryKey = GlobalKey<HistoryTabState>();

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Ringkasan'), Tab(text: 'Transaksi')],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportsSummaryTab(),
            HistoryTab(key: _summaryToHistoryKey),
          ],
        ),
      ),
    );
  }
}

/// Agregat per kategori di tab Ringkasan: total nominal + jumlah transaksi.
class _CategoryRow {
  const _CategoryRow({required this.id, required this.total, required this.count});
  final String id;
  final int total;
  final int count;
}

class _ReportsSummaryTab extends ConsumerWidget {
  const _ReportsSummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);

    /// Tap legenda donut → tab Transaksi terfilter kategori tsb.
    void openCategory(String categoryId) {
      final tabState = _summaryToHistoryKey.currentState;
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
    int income = 0, expense = 0, incomeCount = 0, expenseCount = 0;
    final byCategory = <String, int>{};
    final byCategoryCount = <String, int>{};
    for (final tx in txs) {
      if (tx.type == 'income') {
        income += tx.amount;
        incomeCount++;
      } else if (tx.type == 'expense') {
        expense += tx.amount;
        expenseCount++;
        if (tx.categoryId != null) {
          byCategory[tx.categoryId!] = (byCategory[tx.categoryId!] ?? 0) + tx.amount;
          byCategoryCount[tx.categoryId!] =
              (byCategoryCount[tx.categoryId!] ?? 0) + 1;
        }
      }
    }

    final rows = byCategory.entries
        .map((e) => _CategoryRow(
            id: e.key, total: e.value, count: byCategoryCount[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

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
          _MonthSwitcher(month: month),
          const SizedBox(height: D.s4),

          // ── Hierarki ringkasan: Keluar = metrik utama (full-width),
          // Masuk + Selisih sejajar di bawahnya (layout B).
          _BigStatCard(
            label: 'Total Keluar',
            value: formatRupiah(expense),
            sub: expenseCount > 0
                ? '$expenseCount transaksi • ${_expenseDeltaText(expense, prevExpense, prevMonth)}'
                : _expenseDeltaText(expense, prevExpense, prevMonth),
          ),
          const SizedBox(height: D.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Masuk',
                  value: formatRupiah(income),
                  sub: '$incomeCount transaksi',
                  color: D.income,
                  icon: Icons.south_west_rounded,
                ),
              ),
              const SizedBox(width: D.s3),
              Expanded(
                child: _StatCard(
                  label: 'Selisih',
                  value:
                      '${income - expense < 0 ? '-' : '+'}${formatRupiah((income - expense).abs())}',
                  sub: 'Masuk - Keluar',
                  color: income - expense >= 0 ? D.cobalt : D.expense,
                  icon: Icons.swap_horiz_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: D.s6),

          // ── Donut pengeluaran per kategori ──
          _CategoryDonutCard(
            title: 'Pengeluaran per Kategori',
            rows: rows,
            total: expense,
            centerTitle: 'Keluar',
            emptyText: 'Belum ada pengeluaran bulan ini.',
            catName: catName,
            onOpenCategory: openCategory,
          ),
          const SizedBox(height: D.s6),

          // ── Tren pengeluaran 6 bulan ──
          const _FlowTrendCard(),

          const SizedBox(height: D.s6),
        ],
      ),
    );
  }

  /// "▲ 23% vs Januari" / "▼ 10% vs Januari" / null saat data bulan lalu
  /// masih dimuat atau tidak ada pembanding sama sekali.
  String _expenseDeltaText(int expense, int? prevExpense, DateTime prevMonth) {
    if (prevExpense == null) return 'memuat perbandingan…';
    if (prevExpense == 0) {
      return expense > 0 ? 'mulai tercatat bulan ini' : 'belum ada pengeluaran';
    }
    final pct = ((expense - prevExpense) / prevExpense * 100).round();
    const name = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    if (pct == 0) return 'sama dengan ${name[prevMonth.month - 1]}';
    return pct > 0
        ? '▲ $pct% vs ${name[prevMonth.month - 1]}'
        : '▼ ${-pct}% vs ${name[prevMonth.month - 1]}';
  }
}

/// Kartu donut + legenda pengeluaran per kategori.
class _CategoryDonutCard extends StatelessWidget {
  const _CategoryDonutCard({
    required this.title,
    required this.rows,
    required this.total,
    required this.centerTitle,
    required this.emptyText,
    required this.catName,
    required this.onOpenCategory,
  });

  final String title;
  final List<_CategoryRow> rows;
  final int total;
  final String centerTitle;
  final String emptyText;
  final Map<String, Category> catName;
  final void Function(String categoryId) onOpenCategory;

  List<DonutSegment> _segments() {
    final segs = <DonutSegment>[];
    for (var i = 0; i < rows.length && i < 5; i++) {
      segs.add(DonutSegment(
          value: rows[i].total.toDouble(),
          color: categoryColor(rows[i].id)));
    }
    if (rows.length > 5) {
      segs.add(DonutSegment(
        value: rows.skip(5).fold<int>(0, (a, r) => a + r.total).toDouble(),
        color: D.inkMuted,
      ));
    }
    return segs;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: D.s1 + 2),
        Text('Ketuk kategori untuk filter',
            style: const TextStyle(fontSize: 11, color: D.inkMuted)),
        const SizedBox(height: D.s3),
        if (rows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(D.s6),
            decoration: BoxDecoration(
              color: D.card,
              borderRadius: BorderRadius.circular(D.rMd),
              border: Border.all(color: D.line),
            ),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: D.inkMuted),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DonutChart(
                segments: _segments(),
                centerTitle: centerTitle,
                centerValue: formatRupiah(total),
                size: 132,
                stroke: 20,
              ),
              const SizedBox(width: D.s4),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length && i < 5; i++)
                      _legendRow(
                        color: categoryColor(rows[i].id),
                        name: catName[rows[i].id]?.name ?? 'Tanpa kategori',
                        amount: rows[i].total,
                        count: rows[i].count,
                        pct: total == 0
                            ? 0.0
                            : rows[i].total / total * 100,
                        onTap: () => onOpenCategory(rows[i].id),
                      ),
                    if (rows.length > 5)
                      _legendRow(
                        color: D.inkMuted,
                        name: 'Lainnya (${rows.length - 5})',
                        amount: rows
                            .skip(5)
                            .fold<int>(0, (a, r) => a + r.total),
                        count: rows
                            .skip(5)
                            .fold<int>(0, (a, r) => a + r.count),
                        pct: total == 0
                            ? 0.0
                            : rows
                                    .skip(5)
                                    .fold<int>(0, (a, r) => a + r.total) /
                                total *
                                100,
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _legendRow({
    required Color color,
    required String name,
    required int amount,
    required int count,
    required double pct,
    VoidCallback? onTap,
  }) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: D.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: D.s2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${formatRupiah(amount)} • $count transaksi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: D.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

// ── Tren arus kas masuk/keluar (bulanan / harian) ─────────────────

class _FlowTrendCard extends ConsumerWidget {
  const _FlowTrendCard();

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(trendDailyModeProvider);
    final out = ref.watch(flowOutProvider);
    final month = ref.watch(reportMonthProvider);
    final reduced = MediaQuery.of(context).disableAnimations;
    final monthName = _monthNames[month.month - 1];
    final now = DateTime.now();

    final monthly = ref.watch(trendMonthsProvider).valueOrNull;
    final weekly = ref.watch(last7DaysFlowProvider).valueOrNull;
    final flow = daily ? weekly : monthly;

    final expenseValues = flow?.expense;
    final incomeValues = flow?.income;
    final showBoth = out == null && flow != null;
    final values = flow == null
        ? null
        : (out == null ? null : (out ? expenseValues : incomeValues));
    final color = out == false ? D.income : D.cobalt;
    final totalExpense = expenseValues?.fold<int>(0, (a, b) => a + b) ?? 0;
    final totalIncome = incomeValues?.fold<int>(0, (a, b) => a + b) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s3),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  daily
                      ? 'Tren 7 Hari Terakhir'
                      : 'Tren 6 Bulan s/d $monthName ${month.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: D.s2),
              SegmentedButton<bool>(
                selected: {daily},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('Bulan')),
                  ButtonSegment(value: true, label: Text('Hari')),
                ],
                onSelectionChanged: (s) =>
                    ref.read(trendDailyModeProvider.notifier).state = s.first,
              ),
            ],
          ),
          const SizedBox(height: D.s3),
          Row(
            children: [
              if (showBoth) ...[
                _TrendLegendDot(color: D.cobalt, label: 'Keluar'),
                const SizedBox(width: D.s3),
                _TrendLegendDot(color: D.income, label: 'Masuk'),
              ] else ...[
                _TrendLegendDot(
                    color: color, label: out == false ? 'Masuk' : 'Keluar'),
              ],
              const Spacer(),
              const FlowToggle(),
            ],
          ),
          const SizedBox(height: D.s2),
          if (showBoth)
            Row(
              children: [
                Text('Keluar ${formatRupiah(totalExpense)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: D.cobalt)),
                const SizedBox(width: D.s3),
                Text('Masuk ${formatRupiah(totalIncome)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: D.income)),
              ],
            )
          else if (values != null)
            Text(
              'Total ${out == false ? 'Masuk' : 'Keluar'}: ${formatRupiah(values.fold<int>(0, (a, b) => a + b))}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          const SizedBox(height: D.s3),
          Builder(builder: (context) {
            if (flow == null) return const SizedBox(height: 130);
            final ev = flow.expense;
            final iv = flow.income;
            final sb = out == null;
            final vals = sb ? null : (out ? ev : iv);
            final maxV = sb
                ? [...ev, ...iv].fold<int>(0, (a, b) => b > a ? b : a)
                : vals!.fold<int>(0, (a, b) => b > a ? b : a);
            final count = ev.length;
            return TweenAnimationBuilder<double>(
              key: ValueKey('$daily-$out-${daily ? 0 : month}'),
              tween: Tween(begin: 0, end: 1),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => SizedBox(
                height: 130,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: sb
                            ? Column(
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        _TrendBar(
                                          value: (ev[i] /
                                                  (maxV == 0 ? 1 : maxV)) *
                                              t,
                                          color: D.cobalt,
                                          isHighlighted: daily
                                              ? i == 6
                                              : i == count - 1,
                                          label: '',
                                          showValue: false,
                                          showLabel: false,
                                          barWidth: daily ? 5 : 12,
                                          onTap: daily
                                              ? () =>
                                                  showDayTransactionsSheet(
                                                      context,
                                                      now.subtract(Duration(
                                                          days: 6 - i)))
                                              : () => ref
                                                      .read(
                                                          reportMonthProvider
                                                              .notifier)
                                                      .state =
                                                  DateTime(
                                                      month.year,
                                                      month.month -
                                                          5 +
                                                          i,
                                                      1),
                                        ),
                                        const SizedBox(width: 3),
                                        _TrendBar(
                                          value: (iv[i] /
                                                  (maxV == 0 ? 1 : maxV)) *
                                              t,
                                          color: D.income,
                                          isHighlighted: daily
                                              ? i == 6
                                              : i == count - 1,
                                          label: '',
                                          showValue: false,
                                          showLabel: false,
                                          barWidth: daily ? 5 : 12,
                                          onTap: daily
                                              ? () =>
                                                  showDayTransactionsSheet(
                                                      context,
                                                      now.subtract(Duration(
                                                          days: 6 - i)))
                                              : () => ref
                                                      .read(
                                                          reportMonthProvider
                                                              .notifier)
                                                      .state =
                                                  DateTime(
                                                      month.year,
                                                      month.month -
                                                          5 +
                                                          i,
                                                      1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: D.s1 + 2),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 14,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        daily
                                            ? _dayTrendLabel(now, i)
                                            : _monthTrendLabel(month, i),
                                        maxLines: 1,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: D.inkMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : _TrendBar(
                                value: (vals![i] /
                                        (maxV == 0 ? 1 : maxV)) *
                                    t,
                                color: color,
                                isHighlighted: daily
                                    ? i == 6
                                    : i == count - 1,
                                label: daily
                                    ? _dayTrendLabel(now, i)
                                    : _monthTrendLabel(month, i),
                                valueText: vals[i] > 0
                                    ? formatCompactId(vals[i])
                                    : null,
                                showValue: !daily,
                                barWidth: daily ? 5 : 12,
                                onTap: daily
                                    ? () => showDayTransactionsSheet(
                                        context,
                                        now.subtract(
                                            Duration(days: 6 - i)))
                                    : () => ref
                                            .read(
                                                reportMonthProvider.notifier)
                                            .state =
                                        DateTime(
                                            month.year,
                                            month.month - 5 + i,
                                            1),
                              ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Label bar harian: nomor tanggal + inisial bulan saat pertama
  /// muncul di dalam jendela 7 hari.
  String _dayTrendLabel(DateTime now, int i) {
    final day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: 6 - i));
    const names = ['Jn', 'Fb', 'Mr', 'Ap', 'Me', 'Jn', 'Jl', 'Ag', 'Sp', 'Ok', 'Nv', 'Ds'];
    return day.day == 1 ? '${day.day} ${names[day.month - 1]}' : '${day.day}';
  }

  /// Label bulan tren 6 bulan: "Mar" biasa, tambah 2 digit tahun
  /// ("Jan 26") saat Januari atau bar pertama bila rentang
  /// melewati tahun baru — tetap tengah via FittedBox pemanggil.
  String _monthTrendLabel(DateTime month, int i) {
    final d = DateTime(month.year, month.month - 5 + i);
    final name = _monthNames[d.month - 1];
    final first = DateTime(month.year, month.month - 5);
    final spansYear = first.year != month.year;
    if (d.month == 1 || (spansYear && i == 0)) {
      return '$name ${d.year % 100}';
    }
    return name;
  }
}

class _TrendLegendDot extends StatelessWidget {
  const _TrendLegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: D.s1 + 2),
        Text(label, style: const TextStyle(fontSize: 11.5, color: D.inkMuted)),
      ],
    );
  }
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.value,
    required this.color,
    required this.isHighlighted,
    required this.label,
    required this.showValue,
    this.valueText,
    this.barWidth = 14,
    this.showLabel = true,
    this.onTap,
  });

  final double value; // 0..1 (relatif periode terbesar)
  final Color color;
  final bool isHighlighted;
  final String label;
  final bool showValue;
  final String? valueText;
  final double barWidth;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = value <= 0
        ? D.line
        : this.color.withValues(alpha: isHighlighted ? 1.0 : 0.28);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          if (showValue) ...[
            SizedBox(
              height: 12,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  valueText ?? '',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: isHighlighted ? D.cobalt : D.inkMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: D.s1),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: value <= 0 ? 0.07 : 0.14 + 0.86 * value,
                child: SizedBox(
                  width: barWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: D.s1 + 2),
            SizedBox(
              width: double.infinity,
              height: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        isHighlighted ? FontWeight.w800 : FontWeight.w500,
                    color: isHighlighted ? D.cobalt : D.inkMuted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = _formatMonth(month);
    final now = DateTime.now();
    final canForward =
        DateTime(month.year, month.month + 1).isBefore(DateTime(now.year, now.month + 1));

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => ref.read(reportMonthProvider.notifier).state =
              DateTime(month.year, month.month - 1, 1),
        ),
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: canForward
              ? () => ref.read(reportMonthProvider.notifier).state =
                  DateTime(month.year, month.month + 1, 1)
              : null,
        ),
      ],
    );
  }

  String _formatMonth(DateTime m) {
    const names = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${names[m.month - 1]} ${m.year}';
  }
}

class _BigStatCard extends StatelessWidget {
  const _BigStatCard({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.cobaltDeep,
        borderRadius: BorderRadius.circular(D.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: D.s1 + 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: Colors.white)),
          ),
          const SizedBox(height: D.s1),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    this.sub,
    this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final String? sub;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: color),
                ),
                const SizedBox(width: D.s2),
              ],
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        color: D.inkMuted,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: D.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, color: D.inkMuted)),
          ],
        ],
      ),
    );
  }
}

