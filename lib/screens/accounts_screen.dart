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
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: accounts.isEmpty
          ? _EmptyWallets(reducedMotion: reducedMotion)
          : GridView.builder(
              padding: const EdgeInsets.all(D.s4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: D.s3,
                crossAxisSpacing: D.s3,
                childAspectRatio: 1.45,
              ),
              itemCount: accounts.length,
              itemBuilder: (ctx, i) => _WalletCard(
                account: accounts[i],
                index: i,
                animate: !reducedMotion,
              ),
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

  Future<void> _deleteWallet(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final (txCount, billCount, planCount) = await db.accountUsage(account.id);
    final hasContent = txCount > 0 || billCount > 0 || planCount > 0;

    final confirmed = await confirmDelete(
      context,
      'Hapus ${account.name}?',
      description: hasContent
          ? 'Wallet ini punya $txCount transaksi, $billCount tagihan, '
              'dan $planCount rencana. Semua akan dihapus permanen dan '
              'saldo dihitung ulang.'
          : 'Wallet masih kosong dan bisa dihapus dengan aman.',
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
      onLongPress: () => _deleteWallet(context, ref),
      child: Container(
        padding: const EdgeInsets.all(D.s4),
        decoration: BoxDecoration(
          color: D.card,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WalletBadge(account: account, size: 38),
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
            const Text('Belum ada wallet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: D.s2),
            const Text(
              'Tambahkan wallet pertama — Cash, Bank, atau e-wallet — agar saldo bisa terlacak.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: D.inkMuted, height: 1.5),
            ),
            const SizedBox(height: D.s6),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountFormScreen()),
              ),
              child: const Text('Tambah Wallet'),
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
