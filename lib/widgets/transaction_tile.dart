import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/category_color.dart';
import '../utils/currency.dart';
import '../theme/app_theme.dart';
import '../screens/transaction_form_screen.dart';
import 'confirm_dialog.dart';/// Kontainer yang mengecil saat ditekan (spring feedback).
/// Dipakai lintas layar: beranda, riwayat, detail wallet.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final scale = _down && !reduced ? 0.96 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: scale,
        duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Baris transaksi: ikon berwarna kategori, catatan/label,
/// subtitle "Kategori · Wallet", nominal. Ketuk → edit; tekan lama → hapus.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.accountName,
    this.categoryName,
    this.index = 0,
    this.hideAmount = false,
  });

  final Transaction transaction;
  final String accountName;
  final String? categoryName;
  final int index;

  /// Mode privasi Beranda: nominal diganti mask.
  final bool hideAmount;

  Color get _semanticColor {
    switch (transaction.type) {
      case 'income':
        return D.income;
      default:
        return D.expense;
    }
  }

  IconData get _icon {
    switch (transaction.type) {
      case 'income':
        return Icons.south_west_rounded;
      default:
        return Icons.north_east_rounded;
    }
  }

  String get _amountPrefix {
    switch (transaction.type) {
      case 'income':
        return '+';
      default:
        return '−';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Pemasukan';
      default:
        return 'Pengeluaran';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _semanticColor;
    final reduced = MediaQuery.of(context).disableAnimations;
    final catColor = transaction.categoryId == null
        ? color
        : categoryColor(transaction.categoryId!);

    return Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TransactionForm(existing: transaction)),
      ),
      onLongPress: () async {
        final confirmed = await confirmDelete(
          context,
          'Hapus transaksi ini?',
          description:
              'Transaksi dihapus permanen dan saldo wallet dihitung ulang.',
        );
        if (!confirmed || !context.mounted) return;
        final db = ref.read(dbProvider);
        // Snapshot dulu agar bisa diurungkan lewat snackbar.
        final undo = await db.captureTransactionUndo(transaction.id);
        await db.deleteTransactionCascade(transaction.id);
        if (context.mounted && undo != null) {
          showUndoBar(context, 'Transaksi dihapus',
              () => db.restoreTransactionUndo(undo));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: D.s1),
        child: Container(
          padding: const EdgeInsets.all(D.s3),
          decoration: BoxDecoration(
            color: D.card,
            borderRadius: BorderRadius.circular(D.rMd),
            border: Border.all(color: D.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Icon(_icon, color: catColor, size: 20),
              ),
              const SizedBox(width: D.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.note.isEmpty
                          ? _typeLabel(transaction.type)
                          : transaction.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      categoryName == null
                          ? '$accountName · ${formatTime(transaction.date)}'
                          : '$categoryName · $accountName · ${formatTime(transaction.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              Text(
                hideAmount
                    ? formatMasked()
                    : '$_amountPrefix${formatRupiah(transaction.amount)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      )
          .animate(target: reduced ? 0 : 1)
          .fade(duration: 300.ms, delay: (40 * index).clamp(0, 400).ms)
          .slideY(begin: 0.08, end: 0, duration: 300.ms, delay: (40 * index).clamp(0, 400).ms, curve: Curves.easeOutCubic),
    );
  }
}
