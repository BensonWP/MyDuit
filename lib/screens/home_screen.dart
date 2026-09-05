import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import '../theme/app_theme.dart';
import 'transaction_form_screen.dart';
import 'account_form_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(recentTransactionsProvider).valueOrNull ?? [];
    final totalBalance = ref.watch(totalBalanceProvider).valueOrNull;
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),          children: [
            // ── Hero saldo ──
            _HeroCard(
              totalBalance: totalBalance,
              walletCount: accounts.length,
              animate: !reducedMotion,
            ),
            const SizedBox(height: D.s6),

            // ── Rail wallet ──
            if (accounts.isNotEmpty) ...[
              _SectionHeader(title: 'Wallet'),
              const SizedBox(height: D.s3),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: D.s3),
                  itemBuilder: (ctx, i) => _WalletChip(
                    account: accounts[i],
                    index: i,
                    animate: !reducedMotion,
                  ),
                ),
              ),
              const SizedBox(height: D.s6),
            ],

            // ── Transaksi per tanggal ──
            _SectionHeader(title: 'Transaksi Terakhir'),
            const SizedBox(height: D.s3),
            if (transactions.isEmpty)
              _EmptyTransactions(reducedMotion: reducedMotion)
            else
              ..._groupedByDate(transactions, accounts),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupedByDate(List<Transaction> txs, List<Account> accounts) {
    final widgets = <Widget>[];
    String? lastDay;
    for (var i = 0; i < txs.length; i++) {
      final tx = txs[i];
      final day = tx.date.substring(0, 10);
      if (day != lastDay) {
        lastDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: D.s2, bottom: D.s1),
          child: Text(
            _dayLabel(day),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: D.inkMuted),
          ),
        ));
      }
      final accountName =
          accounts.where((a) => a.id == tx.accountId).firstOrNull?.name ?? '-';
      widgets.add(_TransactionTile(
        transaction: tx,
        accountName: accountName,
        index: i,
      ));
    }
    return widgets;
  }

  String _dayLabel(String isoDay) {
    final d = DateTime.parse(isoDay);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Hari ini';
    if (day == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return formatDate(isoDay);
  }
}

// ── Hero saldo ─────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totalBalance,
    required this.walletCount,
    required this.animate,
  });

  final int? totalBalance;
  final int walletCount;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final balance = totalBalance ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(D.s6),
      decoration: BoxDecoration(
        color: D.cobaltDeep,
        borderRadius: BorderRadius.circular(D.rLg),
        boxShadow: animate
            ? [
                BoxShadow(
                  color: D.cobaltDeep.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Saldo',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: D.s1),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: balance.toDouble()),
            duration: animate ? 900.ms : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => Text(
              formatRupiah(value.round()),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: D.s2),
          Text(
            '$walletCount wallet terdaftar',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    )
        .animate(target: animate ? 1 : 0)
        .shimmer(
          delay: 900.ms,
          duration: 600.ms,
          color: Colors.white.withValues(alpha: 0.18),
        ); // sweep 1× saat count-up selesai, lalu berhenti
  }
}

// ── Section header ─────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700));
  }
}

// ── Wallet chip di rail ────────────────────────────────────────────

class _WalletChip extends ConsumerWidget {
  const _WalletChip({
    required this.account,
    required this.index,
    required this.animate,
  });

  final Account account;
  final int index;
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(accountBalanceProvider(account.id)).valueOrNull ?? 0;
    final color = hexToColor(account.color);

    return _Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountFormScreen(accountId: account.id)),
      ),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(D.s3 + 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(getAccountIcon(account.type), size: 18, color: color),
            const Spacer(),
            Text(
              account.name,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              formatRupiah(balance),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      )
          .animate(target: animate ? 1 : 0)
          .fade(duration: 300.ms, delay: (60 * index).ms)
          .slideY(begin: 0.2, end: 0, duration: 300.ms, delay: (60 * index).ms, curve: Curves.easeOutCubic),
    );
  }
}

// ── Pressable: spring scale feedback ───────────────────────────────

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, this.onTap, this.onLongPress});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
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

// ── Baris transaksi ────────────────────────────────────────────────

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({
    required this.transaction,
    required this.accountName,
    required this.index,
  });

  final Transaction transaction;
  final String accountName;
  final int index;

  Color get _semanticColor {
    switch (transaction.type) {
      case 'income':
        return D.income;
      case 'transfer':
        return D.cobalt;
      default:
        return D.expense;
    }
  }

  IconData get _icon {
    switch (transaction.type) {
      case 'income':
        return Icons.south_west_rounded;
      case 'transfer':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.north_east_rounded;
    }
  }

  String get _amountPrefix {
    switch (transaction.type) {
      case 'income':
        return '+';
      case 'expense':
        return '−';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _semanticColor;
    final reduced = MediaQuery.of(context).disableAnimations;

    return _Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TransactionForm(existing: transaction)),
      ),
      onLongPress: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus transaksi?'),
            content: const Text('Transaksi dihapus permanen dan saldo dihitung ulang.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: D.expense),
                child: const Text('Hapus'),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await ref.read(dbProvider).deleteTransaction(transaction.id);
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
                decoration:
                    BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(_icon, color: color, size: 20),
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
                    Text(accountName,
                        style: const TextStyle(
                            fontSize: 12, color: D.inkMuted)),
                  ],
                ),
              ),
              Text(
                '$_amountPrefix${formatRupiah(transaction.amount)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: transaction.type == 'transfer' ? D.ink : color,
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

  String _typeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Pemasukan';
      case 'transfer':
        return 'Transfer';
      default:
        return 'Pengeluaran';
    }
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions({required this.reducedMotion});
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(D.s6),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_rounded, size: 40, color: D.inkMuted),
          const SizedBox(height: D.s3),
          const Text('Belum ada transaksi',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: D.s1),
          const Text(
            'Catat pengeluaran pertama Anda lewat tombol tambah di bawah.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: D.inkMuted),
          ),
        ],
      ),
    )
        .animate(target: reducedMotion ? 0 : 1)
        .fade(duration: 400.ms, delay: 100.ms)
        .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOutCubic);
  }
}
