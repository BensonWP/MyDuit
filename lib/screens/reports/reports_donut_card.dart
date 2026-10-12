import 'package:flutter/material.dart';
import '../../db/database.dart';
import '../../theme/app_theme.dart';
import '../../utils/category_color.dart';
import '../../utils/currency.dart';
import '../../utils/report_math.dart';
import '../../widgets/donut_chart.dart';

/// Kartu donut + legenda per kategori (dipakai expense & income).
class CategoryDonutCard extends StatelessWidget {
  const CategoryDonutCard({
    super.key,
    required this.title,
    required this.rows,
    required this.total,
    required this.centerTitle,
    required this.emptyText,
    required this.catName,
    required this.onOpenCategory,
  });

  final String title;
  final List<CategoryTotal> rows;
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
