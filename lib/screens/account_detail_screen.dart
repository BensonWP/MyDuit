import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import '../utils/tx_grouping.dart';
import '../utils/wallet_brand.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/transaction_tile.dart';
import 'transaction_form_screen.dart';
import 'account_form_screen.dart';

class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  static const _typeLabels = {
    'cash': 'Cash',
    'bank': 'Bank',
    'ewallet': 'E-Wallet',
    'card': 'Kartu',
  };

  /// Hapus permanen: konfirmasi menampilkan isi wallet agar keputusan sadar.
  Future<void> _deleteWallet(
      BuildContext context, WidgetRef ref, String accountName) async {
    final db = ref.read(dbProvider);
    final (txCount, billCount, planCount) = await db.accountUsage(accountId);
    final hasContent = txCount > 0 || billCount > 0 || planCount > 0;

    final confirmed = await confirmDelete(
      context,
      'Hapus $accountName?',
      description: hasContent
          ? 'Wallet ini punya $txCount transaksi, $billCount tagihan, '
              'dan $planCount rencana. Semua akan dihapus permanen dan '
              'saldo dihitung ulang.'
          : 'Wallet masih kosong dan bisa dihapus dengan aman.',
    );
    if (!confirmed) return;

    await db.deleteAccountCascade(accountId);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider(accountId)).valueOrNull;
    final txs =
        ref.watch(accountTransactionsProvider(accountId)).valueOrNull ?? [];
    final balance =
        ref.watch(accountBalanceProvider(accountId)).valueOrNull ?? 0;
    final catMap = <String, String>{
      for (final c
          in ref.watch(categoriesStreamProvider).valueOrNull ?? const [])
        c.id: c.name,
    };

    if (account == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final color = hexToColor(account.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 20),
            tooltip: 'Edit wallet',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AccountFormScreen(accountId: accountId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 22, color: D.expense),
            tooltip: 'Hapus wallet',
            onPressed: () =>
                _deleteWallet(context, ref, account.name),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
        children: [
          // ── Kartu saldo ──
          Container(
            padding: const EdgeInsets.all(D.s6),
            decoration: BoxDecoration(
              color: D.cobaltDeep,
              borderRadius: BorderRadius.circular(D.rLg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    WalletBadge(account: account, size: 24),
                    const SizedBox(width: D.s2),
                    Text(
                      _typeLabels[account.type] ?? account.type,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: D.s3),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: balance.toDouble()),
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : 700.ms,
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => Text(
                    formatRupiah(value.round()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: D.s1),
                Text('Saldo tersedia',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: D.s6),

          // ── Transaksi wallet ──
          const Text('Transaksi',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: D.s3),
          if (txs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(D.s6),
              decoration: BoxDecoration(
                color: D.card,
                borderRadius: BorderRadius.circular(D.rMd),
                border: Border.all(color: D.line),
              ),
              child: const Column(
                children: [
                  Icon(Icons.receipt_long_rounded,
                      size: 40, color: D.inkMuted),
                  SizedBox(height: D.s3),
                  Text('Belum ada transaksi di wallet ini',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: D.s1),
                  Text(
                    'Tambahkan lewat tombol di bawah.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: D.inkMuted),
                  ),
                ],
              ),
            )
          else
            ..._groupedByDay(txs, account.name, catMap),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            TransactionForm.showAddSheet(context, initialAccountId: accountId),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Transaksi'),
      ),
    );
  }

  List<Widget> _groupedByDay(
      List<Transaction> txs, String accountName, Map<String, String> catMap) {
    final widgets = <Widget>[];
    for (final group in groupByDay(txs)) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: D.s2, bottom: D.s1),
        child: Text(
          dayLabel(group.key),
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: D.inkMuted),
        ),
      ));
      for (final tx in group.value) {
        widgets.add(TransactionTile(
          transaction: tx,
          accountName: accountName,
          categoryName:
              tx.categoryId == null ? null : catMap[tx.categoryId],
        ));
      }
    }
    return widgets;
  }
}
