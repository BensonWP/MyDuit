import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/tx_grouping.dart';
import '../../widgets/transaction_tile.dart';

// ── Bottom sheet pengeluaran satu hari ─────────────────────────────

void showDayTransactionsSheet(BuildContext context, DateTime day) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, controller) =>
          DayExpensesSheet(day: day, scrollController: controller),
    ),
  );
}

class DayExpensesSheet extends ConsumerWidget {
  const DayExpensesSheet({
    super.key,
    required this.day,
    required this.scrollController,
  });
  final DateTime day;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final out = ref.watch(flowOutProvider);
    final all = ref.watch(dayTransactionsProvider(day)).valueOrNull ?? [];
    // Ikuti filter arus Beranda: null = tampil semua transaksi hari itu.
    final txs = (out == null
            ? all
            : all.where((t) => out ? t.type == 'expense' : t.type == 'income'))
        .toList();
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final catMap = <String, String>{
      for (final c in ref.watch(categoriesStreamProvider).valueOrNull ?? const [])
        c.id: c.name,
    };
    final total = txs.fold<int>(0, (a, t) => a + t.amount);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, D.s3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  dayLabel(day.toIso8601String()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (total > 0)
                Text(formatRupiah(total),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        if (txs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(D.s6),
            child: Text(
                out == null
                    ? 'Tidak ada transaksi hari ini'
                    : out
                        ? 'Tidak ada pengeluaran hari ini'
                        : 'Tidak ada pemasukan hari ini',
                style:
                    const TextStyle(fontSize: 13, color: D.inkMuted)),
          )
        else
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s4),
              itemCount: txs.length,
              separatorBuilder: (_, _) => const SizedBox(height: D.s1),
              itemBuilder: (ctx, i) {
                final tx = txs[i];
                return TransactionTile(
                  transaction: tx,
                  accountName: accounts
                          .where((a) => a.id == tx.accountId)
                          .firstOrNull
                          ?.name ??
                      '-',
                  categoryName:
                      tx.categoryId == null ? null : catMap[tx.categoryId],
                );
              },
            ),
          ),
      ],
    );
  }
}
