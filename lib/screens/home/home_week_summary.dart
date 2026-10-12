import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import 'home_day_sheet.dart';

// ── Mini bar 7 hari ────────────────────────────────────────────────

class WeekBars extends ConsumerWidget {
  const WeekBars({super.key, required this.privacy});
  final bool privacy;

  static const _dayInitials = ['Sn', 'Sl', 'Rb', 'Km', 'Jm', 'Sb', 'Mg'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(last7DaysFlowProvider).valueOrNull;
    // Filter OFF → tampilkan stacked bar (keluar + masuk).
    final out = ref.watch(flowOutProvider);
    final stacked = out == null && flow != null;
    final values =
        flow == null ? null : (out == true ? flow.expense : flow.income);
    final color = (out ?? true) ? D.cobalt : D.income;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reduced = MediaQuery.of(context).disableAnimations;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(D.s4, D.s4, D.s4, D.s3),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: flow == null
          ? const SizedBox(height: 100)
          : Builder(builder: (context) {
              final maxV = stacked
                  ? [
                      ...flow.expense,
                      ...flow.income,
                    ].fold<int>(0, (a, b) => b > a ? b : a)
                  : values!.fold<int>(0, (a, b) => b > a ? b : a);
              final totalOut = flow.expense.fold<int>(0, (a, b) => a + b);
              final totalIn = flow.income.fold<int>(0, (a, b) => a + b);
              final totalSingle =
                  stacked ? 0 : values!.fold<int>(0, (a, b) => a + b);
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    reduced ? Duration.zero : const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (stacked && totalOut == 0 && totalIn == 0)
                      const Text('Belum ada transaksi',
                          style:
                              TextStyle(fontSize: 12, color: D.inkMuted))
                    else if (!stacked && totalSingle == 0)
                      const Text('Belum ada transaksi',
                          style:
                              TextStyle(fontSize: 12, color: D.inkMuted))
                    else if (stacked) ...[
                      Wrap(
                        spacing: D.s4,
                        runSpacing: D.s1,
                        children: [
                          FlowLegend(
                              color: D.cobalt,
                              label: 'Keluar',
                              value: privacy
                                  ? formatMasked()
                                  : formatRupiah(totalOut)),
                          FlowLegend(
                              color: D.income,
                              label: 'Masuk',
                              value: privacy
                                  ? formatMasked()
                                  : formatRupiah(totalIn)),
                        ],
                      ),
                    ] else
                      FlowLegend(
                          color: color,
                          label: out == true ? 'Keluar' : 'Masuk',
                          value: privacy
                              ? formatMasked()
                              : formatRupiah(totalSingle)),
                    const SizedBox(height: D.s3),
                    SizedBox(
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: stacked
                                  ? StackedWeekBar(
                                      expense:
                                          (flow.expense[i] / (maxV == 0 ? 1 : maxV)) *
                                              t,
                                      income:
                                          (flow.income[i] / (maxV == 0 ? 1 : maxV)) *
                                              t,
                                      isToday: i == 6,
                                      day: today.subtract(Duration(days: 6 - i)),
                                      label: _dayInitials[today
                                              .subtract(Duration(days: 6 - i))
                                              .weekday -
                                          1],
                                    )
                                  : WeekBar(
                                      value: (values![i] /
                                              (maxV == 0 ? 1 : maxV)) *
                                          t,
                                      color: color,
                                      isToday: i == 6,
                                      day: today.subtract(Duration(days: 6 - i)),
                                      label: _dayInitials[today
                                              .subtract(Duration(days: 6 - i))
                                              .weekday -
                                          1],
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
    );
  }
}

class FlowLegend extends StatelessWidget {
  const FlowLegend(
      {super.key,
      required this.color,
      required this.label,
      required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: D.s1 + 2),
        Text('$label ',
            style: const TextStyle(fontSize: 12, color: D.inkMuted)),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class WeekBar extends StatelessWidget {
  const WeekBar({
    super.key,
    required this.value,
    required this.color,
    required this.isToday,
    required this.label,
    required this.day,
  });

  final double value; // 0..1 (relatif hari terbesar)
  final Color color;
  final bool isToday;
  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final dim = isToday ? 1.0 : 0.28;
    // Tinggi bar max 54px (84 - 6 spacing - ~24 label), minimum 4px
    // agar bar tetap terlihat walau nilainya kecil.
    final barHeight = value <= 0 ? 4.0 : (4.0 + 50.0 * value).clamp(4.0, 54.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDayTransactionsSheet(context, day),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 8,
                height: barHeight,
                decoration: BoxDecoration(
                  color: value <= 0
                      ? D.line
                      : color.withValues(alpha: dim),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: D.s1 + 2),
          Text(label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isToday ? D.cobalt : D.inkMuted,
              )),
        ],
      ),
    );
  }
}

class StackedWeekBar extends StatelessWidget {
  const StackedWeekBar({
    super.key,
    required this.expense,
    required this.income,
    required this.isToday,
    required this.label,
    required this.day,
  });

  final double expense; // 0..1 relatif maxV global
  final double income; // 0..1 relatif maxV global
  final bool isToday;
  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final dim = isToday ? 1.0 : 0.28;
    final sum = income + expense;
    final ratio = sum > 0 ? 1 / sum : 0.0;
    final barMax = 54.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDayTransactionsSheet(context, day),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: sum <= 0
                  ? Container(
                      width: 8,
                      height: 4,
                      decoration: BoxDecoration(
                        color: D.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )
                  : SizedBox(
                      width: 8,
                      height: barMax,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (income > 0)
                            Container(
                              height: income * ratio * barMax,
                              decoration: BoxDecoration(
                                color: D.income.withValues(alpha: dim),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                              ),
                            ),
                          if (expense > 0)
                            Container(
                              height: expense * ratio * barMax,
                              decoration: BoxDecoration(
                                color: D.cobalt.withValues(alpha: dim),
                                borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(3)),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: D.s1 + 2),
          Text(label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isToday ? D.cobalt : D.inkMuted,
              )),
        ],
      ),
    );
  }
}
