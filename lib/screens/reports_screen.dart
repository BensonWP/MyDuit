import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/category_color.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/donut_chart.dart';
import 'history_screen.dart';
import 'home_screen.dart' show showDayExpensesSheet;

/// GlobalKey tab Transaksi — tap legenda donut lompat ke tab Transaksi
/// dengan filter kategori terisi (dipanggil lintas _ReportsSummaryTab).
final _summaryToHistoryKey = GlobalKey<HistoryTabState>();

void _showBudgetSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BudgetSheet(),
  );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan'),
          actions: [
            IconButton(
              tooltip: 'Anggaran',
              icon: const Icon(Icons.savings_rounded, size: 22),
              onPressed: () => _showBudgetSheet(context),
            ),
          ],
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
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];

    // Hitung di Dart — data sebulan kecil, SQL tambahan tak diperlukan.
    int income = 0, expense = 0;
    final byCategory = <String, int>{};
    for (final tx in txs) {
      if (tx.type == 'income') {
        income += tx.amount;
      } else if (tx.type == 'expense') {
        expense += tx.amount;
        if (tx.categoryId != null) {
          byCategory[tx.categoryId!] = (byCategory[tx.categoryId!] ?? 0) + tx.amount;
        }
      }
    }

    final rows = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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

          // ── Hierarki ringkasan: Keluar = metrik utama ──
          // IntrinsicHeight: ListView memberi tinggi tak terbatas —
          // tanpa ini, Column ber-Expanded di dalam Row akan crash.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _BigStatCard(
                    label: 'Total Keluar',
                    value: formatRupiah(expense),
                    sub: _expenseDeltaText(expense, prevExpense, prevMonth),
                  ),
                ),
                const SizedBox(width: D.s3),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Expanded(
                        child: _StatCard(
                            label: 'Masuk',
                            value: formatRupiah(income),
                            color: D.income),
                      ),
                      const SizedBox(height: D.s3),
                      Expanded(
                        child: _StatCard(
                            label: 'Selisih',
                            value: formatRupiah(income - expense),
                            color:
                                income - expense >= 0 ? D.cobalt : D.expense),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: D.s6),

          // ── Donut pengeluaran per kategori + legenda ──
          const Text('Pengeluaran per Kategori',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
              child: const Text(
                'Belum ada pengeluaran bulan ini.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: D.inkMuted),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DonutChart(
                  segments: _donutSegments(rows),
                  centerTitle: 'Keluar',
                  centerValue: formatRupiah(expense),
                ),
                const SizedBox(width: D.s4),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length && i < 5; i++)
                        _legendRow(
                          context,
                          categoryColor(rows[i].key),
                          catName[rows[i].key]?.name ?? 'Tanpa kategori',
                          rows[i].value,
                          expense == 0 ? 0.0 : rows[i].value / expense * 100,
                          categoryId: rows[i].key,
                          onTap: () => openCategory(rows[i].key),
                        ),
                      if (rows.length > 5)
                        _legendRow(
                          context,
                          D.inkMuted,
                          'Lainnya (${rows.length - 5})',
                          rows.skip(5).fold<int>(0, (a, r) => a + r.value),
                          expense == 0
                              ? 0.0
                              : rows.skip(5).fold<int>(0, (a, r) => a + r.value) /
                                  expense *
                                  100,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: D.s6),

          // ── Tren pengeluaran 6 bulan ──
          const _ExpenseTrendCard(),

          // ── Anggaran bulanan ──
          if (budgets.isNotEmpty) ...[
            const SizedBox(height: D.s6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Anggaran Bulan Ini',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => _showBudgetSheet(context),
                  child: const Text('Kelola'),
                ),
              ],
            ),
            const SizedBox(height: D.s1),
            ...budgets.map((b) {
              final spent = byCategory[b.categoryId] ?? 0;
              return _BudgetBar(
                name: b.categoryName,
                spent: spent,
                budget: b.monthlyAmount,
                color: categoryColor(b.categoryId),
              );
            }),
          ],
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

  List<DonutSegment> _donutSegments(List<MapEntry<String, int>> rows) {
    final segs = <DonutSegment>[];
    for (var i = 0; i < rows.length && i < 5; i++) {
      segs.add(DonutSegment(
          value: rows[i].value.toDouble(), color: categoryColor(rows[i].key)));
    }
    if (rows.length > 5) {
      segs.add(DonutSegment(
        value: rows.skip(5).fold<int>(0, (a, r) => a + r.value).toDouble(),
        color: D.inkMuted,
      ));
    }
    return segs;
  }

  Widget _legendRow(
    BuildContext context,
    Color color,
    String name,
    int amount,
    double pct, {
    String? categoryId,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: D.s1 + 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: D.s2),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Text(formatRupiah(amount),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: D.s2),
          SizedBox(
            width: 34,
            child: Text('${pct.toStringAsFixed(0)}%',
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 11.5, color: D.inkMuted)),
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

// ── Tren pengeluaran (bulanan / harian) ───────────────────────────

class _ExpenseTrendCard extends ConsumerWidget {
  const _ExpenseTrendCard();

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(trendDailyModeProvider);
    final month = ref.watch(reportMonthProvider);
    final reduced = MediaQuery.of(context).disableAnimations;
    final monthName = _monthNames[month.month - 1];
    final now = DateTime.now();

    // Mode Bulan: 6 bulan s/d bulan laporan; mode Hari: 7 hari kalender
    // terakhir (rolling, tidak bergantung bulan laporan).
    final monthly = ref.watch(trendMonthsProvider).valueOrNull;
    final weekly = ref.watch(last7DaysExpenseProvider).valueOrNull;
    final trend = daily ? weekly : monthly;

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
                  daily ? 'Tren 7 Hari Terakhir' : 'Tren 6 Bulan s/d $monthName',
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
          trend == null
              ? const SizedBox(height: 84)
              : Builder(builder: (context) {
                  final maxV = trend.fold<int>(0, (a, b) => b > a ? b : a);
                  return TweenAnimationBuilder<double>(
                    key: ValueKey('$daily-${daily ? 0 : month}'),
                    tween: Tween(begin: 0, end: 1),
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => SizedBox(
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < trend.length; i++)
                            Expanded(
                              child: _TrendBar(
                                amount:
                                    (trend[i] / (maxV == 0 ? 1 : maxV)) * t,
                                isHighlighted: daily
                                    ? i == 6
                                    : i == trend.length - 1,
                                label: daily ? _dayTrendLabel(now, i)
                                    : _monthNames[DateTime(month.year,
                                            month.month - 5 + i)
                                        .month -
                                        1],
                                valueText: trend[i] > 0
                                    ? formatRupiah(trend[i])
                                    : null,
                                showValue: !daily,
                                barWidth: daily ? 6 : 14,
                                onTap: daily
                                    ? () => showDayExpensesSheet(
                                        context,
                                        now
                                            .subtract(Duration(days: 6 - i)))
                                    : () => ref
                                            .read(reportMonthProvider.notifier)
                                            .state = DateTime(
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
}

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.amount,
    required this.isHighlighted,
    required this.label,
    required this.showValue,
    this.valueText,
    this.barWidth = 14,
    this.onTap,
  });

  final double amount; // 0..1 (relatif periode terboros)
  final bool isHighlighted;
  final String label;
  final bool showValue;
  final String? valueText;
  final double barWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = amount <= 0
        ? D.line
        : isHighlighted
            ? D.cobalt
            : D.cobalt.withValues(alpha: 0.28);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          if (showValue) ...[
            Text(
              valueText ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: isHighlighted ? D.cobalt : D.inkMuted,
              ),
            ),
            const SizedBox(height: D.s1),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: amount <= 0 ? 0.07 : 0.14 + 0.86 * amount,
                child: SizedBox(
                  width: barWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: D.s1 + 2),
          SizedBox(
            height: 13,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w500,
                color: isHighlighted ? D.cobalt : D.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet kelola anggaran ──────────────────────────────────────────

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet();

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  Future<void> _setBudget(String categoryId, int current) async {
    final controller = TextEditingController(
        text: current > 0 ? current.toString() : '');
    final amountStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anggaran Bulanan'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Jumlah per bulan (Rp)',
            prefixText: 'Rp ',
          ),
        ),
        actions: [
          if (current > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'DELETE'),
              style: TextButton.styleFrom(foregroundColor: D.expense),
              child: const Text('Hapus'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, null), child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Simpan')),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (amountStr == null) return;
    final amount =
        int.tryParse(amountStr == 'DELETE' ? '0' : amountStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    await ref.read(dbProvider).setBudget(categoryId, amount);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    final expenseCategories = categories
        .where((c) => c.type == 'expense')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        D.s4, 0, D.s4, MediaQuery.of(context).viewInsets.bottom + D.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kelola Anggaran',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: D.s1),
          const Text(
            'Anggaran per kategori pengeluaran, dihitung ulang tiap bulan.',
            style: TextStyle(fontSize: 12.5, color: D.inkMuted),
          ),
          const SizedBox(height: D.s4),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final cat in expenseCategories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(getIcon(cat.icon), size: 20, color: D.inkMuted),
                    title: Text(cat.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    trailing: Text(
                      budgets
                              .where((b) => b.categoryId == cat.id)
                              .firstOrNull
                              ?.monthlyAmount
                              .toString() ??
                          '—',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: budgets.any((b) => b.categoryId == cat.id)
                            ? D.cobalt
                            : D.inkMuted,
                      ),
                    ),
                    onTap: () => _setBudget(
                      cat.id,
                      budgets
                              .where((b) => b.categoryId == cat.id)
                              .firstOrNull
                              ?.monthlyAmount ??
                          0,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bar progress anggaran ──────────────────────────────────────────

class _BudgetBar extends StatelessWidget {
  const _BudgetBar({
    required this.name,
    required this.spent,
    required this.budget,
    required this.color,
  });

  final String name;
  final int spent;
  final int budget;

  /// Warna kategori; merah mengambil alih saat anggaran terlampaui.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = budget == 0 ? 0.0 : spent / budget;
    final over = ratio > 1.0;
    final fill = over ? D.expense : color;
    final textColor = over
        ? D.expense
        : ratio >= 0.8
            ? D.amber
            : D.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: D.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(
                      '${formatRupiah(spent)} / ${formatRupiah(budget)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: D.s1 + 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: D.line,
                    valueColor: AlwaysStoppedAnimation(fill),
                  ),
                ),
              ],
            ),
          ),
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
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(D.s3),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5, color: D.inkMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: D.s1 + 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

