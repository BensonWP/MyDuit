import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/report_math.dart';
import '../../widgets/flow_toggle.dart';
import '../home/home_day_sheet.dart';

// ── Tren arus kas masuk/keluar (bulanan / harian) ─────────────────

class FlowTrendCard extends ConsumerWidget {
  const FlowTrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(trendDailyModeProvider);
    final out = ref.watch(flowOutProvider);
    final month = ref.watch(reportMonthProvider);
    final reduced = MediaQuery.of(context).disableAnimations;
    final monthName = monthShortName(month.month);
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
                TrendLegendDot(color: D.cobalt, label: 'Keluar'),
                const SizedBox(width: D.s3),
                TrendLegendDot(color: D.income, label: 'Masuk'),
              ] else ...[
                TrendLegendDot(
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
                                        TrendBar(
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
                                          onTap: _barTap(
                                              ref, context, daily, now, i, month),
                                        ),
                                        const SizedBox(width: 3),
                                        TrendBar(
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
                                          onTap: _barTap(
                                              ref, context, daily, now, i, month),
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
                            : TrendBar(
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
                                onTap: _barTap(
                                    ref, context, daily, now, i, month),
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

  /// Tap bar: mode harian → sheet transaksi hari itu; mode bulanan →
  /// pindah bulan laporan ke bulan bar tsb.
  VoidCallback _barTap(WidgetRef ref, BuildContext context, bool daily,
      DateTime now, int i, DateTime month) {
    if (daily) {
      return () => showDayTransactionsSheet(
          context, now.subtract(Duration(days: 6 - i)));
    }
    return () => ref.read(reportMonthProvider.notifier).state =
        DateTime(month.year, month.month - 5 + i, 1);
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
    final name = monthShortName(d.month);
    final first = DateTime(month.year, month.month - 5);
    final spansYear = first.year != month.year;
    if (d.month == 1 || (spansYear && i == 0)) {
      return '$name ${d.year % 100}';
    }
    return name;
  }
}

class TrendLegendDot extends StatelessWidget {
  const TrendLegendDot({super.key, required this.color, required this.label});
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

class TrendBar extends StatelessWidget {
  const TrendBar({
    super.key,
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
