import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import '../utils/wallet_brand.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import 'account_detail_screen.dart';
import 'account_form_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final archived = ref.watch(archivedAccountsProvider).valueOrNull ?? [];
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Dompet')),
      body: accounts.isEmpty && archived.isEmpty
          ? _EmptyWallets(reducedMotion: reducedMotion)
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(D.s4),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: D.s3,
                      crossAxisSpacing: D.s3,
                      // Tinggi tetap (bukan aspect-ratio) agar SEMUA kartu
                      // persis seragam, tak terpengaruh lebar layar maupun
                      // panjang nama/nominal.
                      mainAxisExtent: 134,
                    ),
                    itemCount: accounts.length,
                    itemBuilder: (ctx, i) => _WalletCard(
                      account: accounts[i],
                      index: i,
                      animate: !reducedMotion,
                    ),
                  ),
                ),
                if (archived.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, D.s2),
                      child: Text(
                        'DIARSIPKAN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: D.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding:
                        const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s4),
                    sliver: SliverList.builder(
                      itemCount: archived.length,
                      itemBuilder: (ctx, i) =>
                          _ArchivedWalletTile(account: archived[i]),
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard({
    required this.account,
    required this.index,
    required this.animate,
  });

  final Account account;
  final int index;
  final bool animate;

  Future<void> _archiveWallet(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final (txCount, billCount) = await db.accountUsage(account.id);
    final hasContent = txCount > 0 || billCount > 0;

    if (!context.mounted) return;
    final confirmed = await confirmDelete(
      context,
      'Arsipkan ${account.name}?',
      description: hasContent
          ? 'Dompet ini punya $txCount transaksi dan $billCount tagihan. '
              'Data tetap utuh dan bisa diaktifkan lagi dari Diarsipkan.'
          : 'Dompet masih kosong — diarsipkan dan bisa diaktifkan lagi.',
      confirmLabel: 'Arsipkan',
    );
    if (!confirmed) return;
    await db.archiveAccount(account.id);
  }

  Future<void> _deleteWallet(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final (txCount, billCount) = await db.accountUsage(account.id);
    final hasContent = txCount > 0 || billCount > 0;

    final confirmed = await confirmDelete(
      context,
      'Hapus ${account.name}?',
      description: hasContent
          ? 'Dompet ini punya $txCount transaksi dan $billCount tagihan. '
              'Semua akan dihapus permanen dan saldo dihitung ulang.'
          : 'Dompet masih kosong dan bisa dihapus dengan aman.',
    );
    if (!confirmed) return;
    await db.deleteAccountCascade(account.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(accountBalanceProvider(account.id)).valueOrNull ?? 0;
    final color = hexToColor(account.color);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: account.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(D.s3),
        decoration: BoxDecoration(
          color: D.card,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baris atas: badge kiri + titik-tiga kanan, keduanya
            // sejajar vertikal (dulu Positioned menempel tepi kartu).
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                WalletBadge(account: account, size: 38),
                const Spacer(),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  splashRadius: 18,
                  tooltip: 'Opsi dompet',
                  icon: const Icon(Icons.more_vert_rounded,
                      color: D.inkMuted),
                  onSelected: (v) {
                    if (v == 'archive') _archiveWallet(context, ref);
                    if (v == 'delete') _deleteWallet(context, ref);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'archive', child: Text('Arsipkan')),
                    PopupMenuItem(
                        value: 'delete', child: Text('Hapus permanen')),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              formatRupiah(balance),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3),
            ),
          ],
        ),
      )
          .animate(target: animate ? 1 : 0)
          .fade(duration: 300.ms, delay: (50 * index).clamp(0, 400).ms)
          .slideY(
            begin: 0.1,
            end: 0,
            duration: 300.ms,
            delay: (50 * index).clamp(0, 400).ms,
            curve: Curves.easeOutCubic,
          ),
    );
  }
}

class _ArchivedWalletTile extends ConsumerWidget {
  const _ArchivedWalletTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance =
        ref.watch(accountBalanceProvider(account.id)).valueOrNull ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: D.s2),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AccountDetailScreen(accountId: account.id)),
        ),
        leading: WalletBadge(account: account, size: 34),
        title: Text(
          account.name,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: D.inkMuted),
        ),
        subtitle: Text(
          'Saldo terakhir ${formatRupiah(balance)}',
          style: const TextStyle(fontSize: 12, color: D.inkMuted),
        ),
        trailing: TextButton(
          onPressed: () =>
              ref.read(dbProvider).unarchiveAccount(account.id),
          child: const Text('Aktifkan lagi'),
        ),
      ),
    );
  }
}

class _EmptyWallets extends StatelessWidget {
  const _EmptyWallets({required this.reducedMotion});
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(D.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_rounded,
                size: 48, color: D.inkMuted),
            const SizedBox(height: D.s4),
            const Text('Belum ada dompet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: D.s2),
            const Text(
              'Tambahkan dompet pertama — Tunai, Bank, atau e-wallet — agar saldo bisa terlacak.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: D.inkMuted, height: 1.5),
            ),
            const SizedBox(height: D.s6),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountFormScreen()),
              ),
              child: const Text('Tambah Dompet'),
            ),
          ],
        ),
      )
          .animate(target: reducedMotion ? 0 : 1)
          .fade(duration: 400.ms)
          .slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
    );
  }
}
