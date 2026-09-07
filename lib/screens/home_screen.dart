import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/app_icons.dart';
import '../utils/category_color.dart';
import '../utils/currency.dart';
import '../utils/dates.dart';
import '../utils/tx_grouping.dart';
import '../utils/wallet_brand.dart';
import '../theme/app_theme.dart';
import '../widgets/transaction_tile.dart';
import 'account_detail_screen.dart';
import 'bills_screen.dart';
import 'plans_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    // Rail wallet: saldo terbesar dulu (saldo belum termuat dihitung 0).
    int balanceOf(Account a) =>
        ref.watch(accountBalanceProvider(a.id)).valueOrNull ?? 0;
    final sortedAccounts = [...accounts]..sort((a, b) => balanceOf(b).compareTo(balanceOf(a)));
    final today = DateTime.now();
    // Semua transaksi hari ini (masuk/keluar/transfer), difilter SQL;
    // to=besok karena date disimpan dengan jam.
    final transactions = ref
            .watch(historyProvider(HistoryFilter(
                from: today.toIso8601String().substring(0, 10),
                to: today.add(const Duration(days: 1)).toIso8601String().substring(0, 10))))
            .valueOrNull ??
        [];
    final totalBalance = ref.watch(totalBalanceProvider).valueOrNull;
    final unpaidBills = ref.watch(unpaidBillsTotalProvider).valueOrNull ?? 0;
    final plans = ref.watch(plansStreamProvider).valueOrNull ?? [];
    final reducedMotion = MediaQuery.of(context).disableAnimations;
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
            // ── Hero saldo ──
            _HeroCard(
              totalBalance: totalBalance,
              walletCount: accounts.length,
              unpaidBills: unpaidBills,
              animate: !reducedMotion,
            ),
            const SizedBox(height: D.s6),

            // ── Tagihan berikutnya ──
            _NextBillCard(reducedMotion: reducedMotion),

            // ── Peringatan anggaran ──
            const _BudgetAlertBanner(),

            if (accounts.isNotEmpty) ...[
              const SizedBox(height: D.s6),
              // ── Rail wallet ──
              const _SectionHeader(title: 'Wallet'),
              const SizedBox(height: D.s3),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const SizedBox(width: D.s3),
                  itemBuilder: (ctx, i) => _WalletChip(
                    account: sortedAccounts[i],
                    index: i,
                    animate: !reducedMotion,
                  ),
                ),
              ),
            ],

            // ── Rail rencana (max 3 + Kelola) ──
            if (plans.isNotEmpty) ...[
              const SizedBox(height: D.s6),
              const _SectionHeader(title: 'Rencana'),
              const SizedBox(height: D.s3),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: (plans.length > 3 ? 3 : plans.length) + 1,
                  separatorBuilder: (_, _) => const SizedBox(width: D.s3),
                  itemBuilder: (ctx, i) => i < 3 && i < plans.length
                      ? _PlanChip(plan: plans[i])
                      : const _PlanChip(plan: null),
                ),
              ),
            ],

            // ── Pengeluaran 7 hari ──
            const SizedBox(height: D.s6),
            const _SectionHeader(title: 'Pengeluaran 7 Hari'),
            const SizedBox(height: D.s3),
            const _WeekBars(),

            // ── Transaksi hari ini ──
            const SizedBox(height: D.s6),
            const _SectionHeader(title: 'Hari Ini'),
            const SizedBox(height: D.s3),
            if (transactions.isEmpty)
              _EmptyTransactions(reducedMotion: reducedMotion)
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
                  )),
          ],
        ),
      ),
    );
  }
}

// ── Tagihan berikutnya ─────────────────────────────────────────────

class _NextBillCard extends ConsumerWidget {
  const _NextBillCard({required this.reducedMotion});
  final bool reducedMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(activeBillsStreamProvider).valueOrNull ?? const [];
    if (bills.isEmpty) return const SizedBox.shrink();

    // Tagihan paling dekat jatuh tempo.
    Bill nearest = bills.first;
    for (final b in bills) {
      if (daysUntilDue(b.dueDay) < daysUntilDue(nearest.dueDay)) nearest = b;
    }

    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? const [];
    final accountName = accounts
            .where((a) => a.id == nearest.accountId)
            .firstOrNull
            ?.name ??
        '-';
    final payments =
        ref.watch(billPaymentsProvider(nearest.id)).valueOrNull ?? const [];
    final paid = paidThisMonth(payments);
    final daysLeft = daysUntilDue(nearest.dueDay);
    final urgent = daysLeft <= 3;
    // Kurang berapa vs wallet yang akan di-debit (bukan total saldo).
    final walletBalance =
        ref.watch(accountBalanceProvider(nearest.accountId)).valueOrNull;
    final short = walletBalance == null ? 0 : nearest.amount - walletBalance;

    return Container(
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(
            color: urgent && !paid ? D.amber.withValues(alpha: 0.5) : D.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: D.amber.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_rounded, color: D.amber, size: 20),
          ),
          const SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tagihan Berikutnya',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: D.inkMuted.withValues(alpha: 0.9))),
                const SizedBox(height: 2),
                Text(nearest.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Tgl ${nearest.dueDay} · $accountName',
                    style: const TextStyle(fontSize: 11.5, color: D.inkMuted)),
                if (!paid && short > 0)
                  Text('Kurang ${formatRupiah(short)}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: D.expense)),
              ],
            ),
          ),
          const SizedBox(width: D.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRupiah(nearest.amount),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              const SizedBox(height: D.s1 + 2),
              if (paid)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: D.s2, vertical: 3),
                  decoration: BoxDecoration(
                    color: D.income.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(D.rSm),
                  ),
                  child: const Text('✓ Dibayar',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: D.income)),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: D.s2, vertical: 2),
                  decoration: BoxDecoration(
                    color: urgent
                        ? D.expense.withValues(alpha: 0.1)
                        : D.surface,
                    borderRadius: BorderRadius.circular(D.rSm),
                  ),
                  child: Text('H-$daysLeft',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: urgent ? D.expense : D.inkMuted)),
                ),
                const SizedBox(height: D.s1 + 2),
                GestureDetector(
                  onTap: () =>
                      confirmAndPayBill(context, ref, nearest, accountName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: D.s3, vertical: 5),
                    decoration: BoxDecoration(
                      color: D.cobalt,
                      borderRadius: BorderRadius.circular(D.rSm),
                    ),
                    child: const Text('Bayar',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    )
        .animate(target: reducedMotion ? 0 : 1)
        .fade(duration: 300.ms, delay: 100.ms)
        .slideY(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

// ── Peringatan anggaran (80%+ terpakai) ───────────────────────────

class _BudgetAlertBanner extends ConsumerWidget {
  const _BudgetAlertBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final txs = ref
            .watch(monthTransactionsProvider(DateTime(now.year, now.month)))
            .valueOrNull ??
        [];
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? [];
    if (budgets.isEmpty) return const SizedBox.shrink();

    // Agregasi pengeluaran per kategori.
    final byCat = <String, int>{};
    for (final tx in txs) {
      if (tx.type == 'expense' && tx.categoryId != null) {
        byCat[tx.categoryId!] = (byCat[tx.categoryId!] ?? 0) + tx.amount;
      }
    }

    // Cari kategori yang ≥ 80% anggaran, urut rasio tertinggi.
    final alerts = <({String name, int spent, int budget, double ratio, Color color})>[];
    for (final b in budgets) {
      final spent = byCat[b.categoryId] ?? 0;
      final ratio = b.monthlyAmount > 0 ? spent / b.monthlyAmount : 0.0;
      if (ratio >= 0.8) {
        alerts.add((
          name: b.categoryName,
          spent: spent,
          budget: b.monthlyAmount,
          ratio: ratio,
          color: categoryColor(b.categoryId),
        ));
      }
    }
    if (alerts.isEmpty) return const SizedBox.shrink();
    alerts.sort((a, b) => b.ratio.compareTo(a.ratio));

    final worst = alerts.first;
    final over = worst.ratio >= 1.0;
    final color = over ? D.expense : D.amber;
    final pct = (worst.ratio * 100).round();

    return Padding(
      padding: const EdgeInsets.only(top: D.s3),
      child: GestureDetector(
        onTap: () => ref.read(navIndexProvider.notifier).state = 1,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(D.s3 + 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(D.rMd),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(
                over ? Icons.warning_rounded : Icons.trending_up_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: D.s2 + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      over
                          ? 'Anggaran terlampaui!'
                          : 'Hampir capai anggaran',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${worst.name} · ${formatRupiah(worst.spent)} / ${formatRupiah(worst.budget)} ($pct%)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (alerts.length > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: D.s2, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(D.rSm),
                  ),
                  child: Text(
                    '+${alerts.length - 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              const SizedBox(width: D.s2),
              Icon(Icons.chevron_right_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mini bar 7 hari ────────────────────────────────────────────────

class _WeekBars extends ConsumerWidget {
  const _WeekBars();

  static const _dayInitials = ['Sn', 'Sl', 'Rb', 'Km', 'Jm', 'Sb', 'Mg'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(last7DaysExpenseProvider).valueOrNull;
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
      child: daily == null
          ? const SizedBox(height: 100)
          : Builder(builder: (context) {
              final maxV = daily.fold<int>(0, (a, b) => b > a ? b : a);
              final weekTotal = daily.fold<int>(0, (a, b) => a + b);
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    reduced ? Duration.zero : const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(weekTotal == 0 ? 'Belum ada pengeluaran' : 'Total',
                            style: const TextStyle(
                                fontSize: 12, color: D.inkMuted)),
                        if (weekTotal > 0)
                          Text(formatRupiah(weekTotal),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: D.s3),
                    SizedBox(
                      height: 70,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: _WeekBar(
                                amount: (daily[i] / (maxV == 0 ? 1 : maxV)) *
                                    t,
                                isToday: i == 6,
                                day: today.subtract(Duration(days: 6 - i)),
                                label: _dayInitials[
                                    today.subtract(Duration(days: 6 - i)).weekday - 1],
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

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.amount,
    required this.isToday,
    required this.label,
    required this.day,
  });

  final double amount; // 0..1 (relatif hari terboros)
  final bool isToday;
  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final color = amount <= 0
        ? D.line
        : isToday
            ? D.cobalt
            : D.cobalt.withValues(alpha: 0.28);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDayExpensesSheet(context, day),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: amount <= 0 ? 0.07 : 0.14 + 0.86 * amount,
                child: Container(
                  width: 14,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
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

// ── Bottom sheet pengeluaran satu hari ─────────────────────────────

void showDayExpensesSheet(BuildContext context, DateTime day) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (_, controller) =>
          _DayExpensesSheet(day: day, scrollController: controller),
    ),
  );
}

class _DayExpensesSheet extends ConsumerWidget {
  const _DayExpensesSheet({required this.day, required this.scrollController});
  final DateTime day;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(dayExpensesProvider(day)).valueOrNull ?? [];
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
          const Padding(
            padding: EdgeInsets.all(D.s6),
            child: Text('Tidak ada pengeluaran hari ini',
                style: TextStyle(fontSize: 13, color: D.inkMuted)),
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

// ── Hero saldo + proyeksi (swipe) ──────────────────────────────────

class _HeroCard extends ConsumerStatefulWidget {
  const _HeroCard({
    required this.totalBalance,
    required this.walletCount,
    required this.unpaidBills,
    required this.animate,
  });

  final int? totalBalance;
  final int walletCount;
  final int unpaidBills;
  final bool animate;

  @override
  ConsumerState<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends ConsumerState<_HeroCard> {
  int _page = 0;

  static const _monthsAhead = 12; // 1 (saldo) + 12 (proyeksi) = 13 halaman

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(D.s6),
      decoration: BoxDecoration(
        color: D.cobaltDeep,
        borderRadius: BorderRadius.circular(D.rLg),
        boxShadow: widget.animate
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
        children: [
          SizedBox(
            height: 124,
            child: PageView.builder(
              itemCount: 1 + _monthsAhead,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (ctx, p) =>
                  p == 0 ? _balancePage() : _projectionPage(p - 1),
            ),
          ),
          const SizedBox(height: D.s2),
          // Dots indicator: 13 titik, aktif lebih terang.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 1 + _monthsAhead; i++)
                AnimatedContainer(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
                  width: i == _page ? 16 : 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: i == _page
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    )
        .animate(target: widget.animate ? 1 : 0)
        .shimmer(
          delay: 900.ms,
          duration: 600.ms,
          color: Colors.white.withValues(alpha: 0.18),
        ); // sweep 1× saat count-up selesai, lalu berhenti
  }

  // ── Halaman 0: Total Saldo ──

  Widget _balancePage() {
    final balance = widget.totalBalance ?? 0;
    final includePlans = ref.watch(includePlansInProjectionProvider);
    final plans = ref.watch(plansStreamProvider).valueOrNull ?? [];
    final plansTotal =
        includePlans ? plans.fold<int>(0, (a, p) => a + p.amount) : 0;
    final commitment = widget.unpaidBills + plansTotal;
    final sisa = balance - commitment;
    final commitLabel =
        includePlans && plansTotal > 0 ? 'tagihan & rencana' : 'tagihan';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Total Saldo · ${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            // Toggle Rencana: pill translusen, ikut dipakai halaman proyeksi.
            GestureDetector(
              onTap: () => ref
                  .read(includePlansInProjectionProvider.notifier)
                  .state = !includePlans,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: D.s2, vertical: 3),
                decoration: BoxDecoration(
                  color: includePlans
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(D.rSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_rounded,
                        size: 12,
                        color: includePlans
                            ? Colors.white
                            : Colors.white60),
                    const SizedBox(width: 3),
                    Text('Rencana',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: includePlans
                              ? Colors.white
                              : Colors.white60,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: D.s1),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: balance.toDouble()),
          duration: widget.animate ? 900.ms : Duration.zero,
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
          '${widget.walletCount} wallet terdaftar',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (commitment > 0) ...[
          const SizedBox(height: D.s1 + 2),
          Text(
            sisa < 0
                ? 'Kurang ${formatRupiah(-sisa)} untuk $commitLabel'
                : 'Setelah $commitLabel: ${formatRupiah(sisa)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: sisa < 0 ? const Color(0xFFFFC9C9) : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ── Halaman 1–12: proyeksi bulan ke-m ──

  Widget _projectionPage(int m) {
    final entries = ref.watch(billProjectionProvider).valueOrNull;
    final balance = widget.totalBalance;
    final includePlans = ref.watch(includePlansInProjectionProvider);
    final plans = ref.watch(plansStreamProvider).valueOrNull ?? [];
    final plansTotal =
        includePlans ? plans.fold<int>(0, (a, p) => a + p.amount) : 0;

    final now = DateTime.now();
    final month = DateTime(now.year, now.month + m);
    final monthName = DateFormat('MMMM yyyy', 'id_ID').format(month);
    final shortName = DateFormat('MMM', 'id_ID').format(month);
    final monthBills = entries == null ? null : billsForMonth(entries, m);
    final through = entries == null ? null : billsThroughMonth(entries, m);
    final projection = balance == null || through == null
        ? null
        : balance - through - plansTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          m == 0 ? 'Proyeksi · $monthName · bulan ini' : 'Proyeksi · $monthName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: D.s1),
        // Format sama dengan halaman Total Saldo: angka besar = saldo akhir.
        Text(
          projection == null ? '…' : formatRupiah(projection),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: D.s2),
        Text(
          entries == null
              ? 'Memuat tagihan…'
              : 'Tagihan s/d $shortName: ${formatRupiah(through!)} · ${monthBills!.count} tagihan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (includePlans && plansTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Rencana: ${formatRupiah(plansTotal)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ),
        if (projection != null && projection < 0) ...[
          const SizedBox(height: D.s1 + 2),
          Text(
            'Kurang ${formatRupiah(-projection)} untuk ${includePlans && plansTotal > 0 ? 'tagihan & rencana' : 'tagihan'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFC9C9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
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

    return Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AccountDetailScreen(accountId: account.id)),
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
            WalletBadge(account: account, size: 22),
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

// ── Chip rencana di rail ──────────────────────────────────────────

class _PlanChip extends ConsumerWidget {
  const _PlanChip({required this.plan});
  final Plan? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() => Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PlansScreen()));

    final p = plan;
    if (p == null) {
      return GestureDetector(
        onTap: open,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: D.s4),
          decoration: BoxDecoration(
            color: D.surface,
            borderRadius: BorderRadius.circular(D.rMd),
            border: Border.all(color: D.line),
          ),
          child: const Text('Kelola →',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      );
    }

    final balance = p.accountId == null
        ? ref.watch(totalBalanceProvider).valueOrNull
        : ref.watch(accountBalanceProvider(p.accountId!)).valueOrNull;
    final short = planShortfall(p, balance);

    return GestureDetector(
      onTap: open,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(D.s3),
        decoration: BoxDecoration(
          color: D.card,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(color: D.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (short != null)
              Text(
                short > 0
                    ? 'Kurang ${formatRupiah(short)}'
                    : 'Siap! Sisa ${formatRupiah(-short)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: short > 0 ? D.expense : D.income,
                ),
              ),
          ],
        ),
      ),
    );
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
          const Text('Belum ada transaksi hari ini',
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
