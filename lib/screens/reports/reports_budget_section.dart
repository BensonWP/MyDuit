import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_icons.dart';
import '../../utils/category_color.dart';
import '../../utils/currency.dart';

// ─── Anggaran bulanan ──────────────────────────────────────────

/// Section anggaran di tab Ringkasan: mengikuti bulan yang dipilih.
/// Tap baris / tombol Kelola membuka sheet atur nominal.
class BudgetSection extends ConsumerWidget {
  const BudgetSection({
    super.key,
    required this.month,
    required this.spentByCat,
  });

  final DateTime month;
  final Map<String, int> spentByCat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = (ref.watch(budgetsProvider).valueOrNull ?? const [])
        .where((b) => b.type == 'expense')
        .toList();
    final now = DateTime.now();
    final title = month.year == now.year && month.month == now.month
        ? 'Anggaran Bulan Ini'
        : 'Anggaran · ${DateFormat('MMM yyyy', 'id_ID').format(month)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            TextButton(
              onPressed: () => showBudgetSheet(context),
              child: const Text('Kelola'),
            ),
          ],
        ),
        const SizedBox(height: D.s1),
        if (budgets.isEmpty)
          const Text(
            'Belum ada anggaran — tap Kelola untuk menambah.',
            style: TextStyle(fontSize: 12.5, color: D.inkMuted),
          )
        else
          for (final b in budgets)
            BudgetBar(
              name: b.name,
              spent: spentByCat[b.categoryId] ?? 0,
              budget: b.monthlyAmount,
              color: categoryColor(b.categoryId),
              onTap: () => showBudgetSheet(context),
            ),
      ],
    );
  }
}

class BudgetBar extends StatelessWidget {
  const BudgetBar({
    super.key,
    required this.name,
    required this.spent,
    required this.budget,
    required this.color,
    this.onTap,
  });

  final String name;
  final int spent;
  final int budget;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = budgetState(spent, budget);
    final ratio =
        budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final fill = switch (state) {
      BudgetState.over => D.expense,
      BudgetState.warning => D.amber,
      BudgetState.ok => color,
    };

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: D.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: D.s2),
                Text(
                  '${formatRupiah(spent)} / ${formatRupiah(budget)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color:
                        state == BudgetState.over ? D.expense : D.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: D.s1 + 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: D.line,
                valueColor: AlwaysStoppedAnimation(fill),
              ),
            ),
            if (state == BudgetState.over)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Melebihi ${formatRupiah(spent - budget)}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: D.expense,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet kelola anggaran: daftar kategori pengeluaran aktif +
/// nominal saat ini; tap baris untuk atur/ubah/hapus.
Future<void> showBudgetSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const BudgetSheet(),
    ),
  );
}

class BudgetSheet extends ConsumerWidget {
  const BudgetSheet({super.key});

  Future<void> _editAmount(BuildContext context, WidgetRef ref,
      String categoryId, String name, int current) async {
    final controller =
        TextEditingController(text: current > 0 ? current.toString() : '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anggaran · $name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [CurrencyInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Jumlah per bulan',
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
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Simpan')),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (result == null) return;
    final amount = result == 'DELETE'
        ? 0
        : int.tryParse(parseCurrency(result)) ?? 0;

    try {
      await ref.read(dbProvider).setBudget(categoryId, amount);
    } on ArgumentError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        (ref.watch(activeCategoriesProvider).valueOrNull ?? const [])
            .where((c) => c.type == 'expense')
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];
    final amountOf = {
      for (final b in budgets) b.categoryId: b.monthlyAmount,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Kelola Anggaran',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: D.s1),
          const Text(
            'Batas belanja per kategori, dihitung ulang tiap bulan. '
            'Hanya peringatan — transaksi tetap bisa disimpan.',
            style: TextStyle(fontSize: 12.5, color: D.inkMuted),
          ),
          const SizedBox(height: D.s3),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final cat in categories)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: categoryColor(cat.id)
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(getIcon(cat.icon),
                          size: 18, color: categoryColor(cat.id)),
                    ),
                    title: Text(cat.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    trailing: Text(
                      amountOf[cat.id] == null
                          ? '—'
                          : formatRupiah(amountOf[cat.id]!),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: amountOf[cat.id] == null
                            ? D.inkMuted
                            : D.cobalt,
                      ),
                    ),
                    onTap: () => _editAmount(context, ref, cat.id,
                        cat.name, amountOf[cat.id] ?? 0),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
