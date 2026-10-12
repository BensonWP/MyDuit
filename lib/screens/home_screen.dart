import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/flow_toggle.dart';
import '../widgets/transaction_tile.dart';
import 'home/home_common.dart';
import 'home/home_hero_card.dart';
import 'home/home_unpaid_bills.dart';
import 'home/home_week_summary.dart';
import 'home/home_wallet_rail.dart';

/// Re-export agar konsumen lama (mis. Laporan) tetap bisa impor dari sini.
export '../widgets/flow_toggle.dart' show FlowToggle;
export 'home/home_day_sheet.dart' show showDayTransactionsSheet;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.valueOrNull ?? [];
    // Skeleton rail hanya saat pemuatan awal (bukan saat kosong beneran).
    final accountsLoading = accountsAsync.isLoading && accounts.isEmpty;
    // Rail wallet: saldo terbesar dulu (saldo belum termuat dihitung 0).
    int balanceOf(Account a) =>
        ref.watch(accountBalanceProvider(a.id)).valueOrNull ?? 0;
    final sortedAccounts = [...accounts]
      ..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
    // "Hari ini" dari ticker, bukan DateTime.now() — daftar Hari Ini
    // tetap segar saat app dibiarkan menyala melewati tengah malam.
    final today = ref.watch(todayProvider);
    // Semua transaksi hari ini, difilter SQL; to=besok karena date
    // disimpan dengan jam. Filter arus ikut FlowToggle (null = semua).
    final flowOut = ref.watch(flowOutProvider);
    final transactions = ref
            .watch(historyProvider(HistoryFilter(
                type: flowOut == null
                    ? null
                    : flowOut
                        ? 'expense'
                        : 'income',
                from: today.toIso8601String().substring(0, 10),
                to: today.add(const Duration(days: 1)).toIso8601String().substring(0, 10))))
            .valueOrNull ??
        [];
    final totalBalanceAsync = ref.watch(totalBalanceProvider);
    final totalBalance = totalBalanceAsync.valueOrNull;
    final balanceLoading =
        totalBalance == null && totalBalanceAsync.isLoading;
    final unpaidBills = ref.watch(unpaidBillsTotalProvider);
    // Bump tiap unlock sukses → KeyedSubtree di bawah me-remount dan
    // me-replay entrance (count-up + stagger). Sekali jalan, tanpa loop.
    final nonce = ref.watch(unlockNonceProvider);
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final privacy = ref.watch(privacyModeProvider);
    final catMap = <String, String>{
      for (final c
          in ref.watch(categoriesStreamProvider).valueOrNull ?? const [])
        c.id: c.name,
    };

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
          children: [
            KeyedSubtree(
              key: ValueKey('home-$nonce'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            // ── Hero saldo ──
            if (balanceLoading)
              const HeroSkeleton()
            else
              HeroCard(
                totalBalance: totalBalance,
                walletCount: accounts.length,
                unpaidBills: unpaidBills,
                animate: !reducedMotion,
                privacy: privacy,
              ),
            const SizedBox(height: D.s6),

            // ── Tagihan belum dibayar ──
            UnpaidBillsCard(reducedMotion: reducedMotion, privacy: privacy),

            // ── Peringatan anggaran (hanya tampil saat ada) ──
            const BudgetBanner(),

            if (accountsLoading) ...[
              const SizedBox(height: D.s6),
              // ── Rail wallet ──
              const SectionHeader(title: 'Dompet'),
              const SizedBox(height: D.s3),
              const RailSkeleton(),
            ] else if (accounts.isNotEmpty) ...[
              const SizedBox(height: D.s6),
              // ── Rail wallet ──
              const SectionHeader(title: 'Dompet'),
              const SizedBox(height: D.s3),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: D.s3),
                  itemBuilder: (ctx, i) => WalletChip(
                    account: sortedAccounts[i],
                    index: i,
                    animate: !reducedMotion,
                    privacy: privacy,
                  ),
                ),
              ),
            ],

            // ── Ringkasan 7 hari ──
            const SizedBox(height: D.s6),
            const SectionHeader(title: 'Ringkasan 7 Hari', trailing: FlowToggle()),
            const SizedBox(height: D.s3),
            WeekBars(privacy: privacy),

            // ── Transaksi hari ini ──
            const SizedBox(height: D.s6),
            const SectionHeader(title: 'Hari Ini'),
            const SizedBox(height: D.s3),
            if (transactions.isEmpty)
              EmptyTransactions(reducedMotion: reducedMotion)
            else
              ...transactions.map((tx) => TransactionTile(
                    transaction: tx,
                    accountName: accounts
                            .where((a) => a.id == tx.accountId)
                            .firstOrNull
                            ?.name ??
                        '-',
                    categoryName:
                        tx.categoryId == null ? null : catMap[tx.categoryId],
                    hideAmount: privacy,
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
