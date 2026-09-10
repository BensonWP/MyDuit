import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/app_icons.dart';
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
    final totalBalance = ref.watch(totalBalanceProvider).valueOrNull;
    final unpaidBills = ref.watch(unpaidBillsTotalProvider);
    final plans = ref.watch(plansStreamProvider).valueOrNull ?? [];
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
            // ── Hero saldo ──
            _HeroCard(
              totalBalance: totalBalance,
              walletCount: accounts.length,
              unpaidBills: unpaidBills,
              animate: !reducedMotion,
              privacy: privacy,
            ),
            const SizedBox(height: D.s6),

            // ── Tagihan belum dibayar ──
            _UnpaidBillsCard(reducedMotion: reducedMotion, privacy: privacy),

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
                    privacy: privacy,
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
                      ? _PlanChip(plan: plans[i], privacy: privacy)
                      : const _PlanChip(plan: null),
                ),
              ),
            ],

            // ── Arus 7 hari ──
            const SizedBox(height: D.s6),
            _SectionHeader(title: 'Arus 7 Hari', trailing: const FlowToggle()),
            const SizedBox(height: D.s3),
            _WeekBars(privacy: privacy),

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
                    hideAmount: privacy,
                  )),
          ],
        ),
      ),
    );
  }
}

// ── Tagihan bulan terpilih di hero (yang lunas bulan itu hilang) ───

class _UnpaidBillsCard extends ConsumerWidget {
  const _UnpaidBillsCard({required this.reducedMotion, required this.privacy});
  final bool reducedMotion;
  final bool privacy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(homeMonthOffsetProvider);
    final bills = ref.watch(monthBillsProvider(offset));
    if (bills.isEmpty) return const SizedBox.shrink();
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? const [];
    final now = DateTime.now();
    final title = offset == 0
        ? 'Tagihan'
        : 'Tagihan · ${DateFormat('MMM yyyy', 'id_ID').format(DateTime(now.year, now.month + offset))}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title),
        const SizedBox(height: D.s3),
        for (var i = 0; i < bills.length; i++)
          _UnpaidBillTile(
            bill: bills[i],
            accountName: accounts
                    .where((a) => a.id == bills[i].accountId)
                    .firstOrNull
                    ?.name ??
                '-',
            index: i,
            animate: !reducedMotion,
            payable: offset == 0,
            privacy: privacy,
          ),
      ],
    );
  }
}

class _UnpaidBillTile extends ConsumerStatefulWidget {
  const _UnpaidBillTile({
    required this.bill,
    required this.accountName,
    required this.index,
    required this.animate,
    required this.payable,
    required this.privacy,
  });

  final Bill bill;
  final String accountName;
  final int index;
  final bool animate;

  /// false = bulan proyeksi: pratinjau saja, tanpa H-N dan tombol Bayar.
  final bool payable;

  final bool privacy;

  @override
  ConsumerState<_UnpaidBillTile> createState() => _UnpaidBillTileState();
}

class _UnpaidBillTileState extends ConsumerState<_UnpaidBillTile> {
  bool _paying = false;

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final payable = widget.payable;
    final daysLeft = daysUntilDue(bill.dueDay);
    final urgent = payable && daysLeft <= 3;
    // Kurang berapa vs wallet yang akan di-debit (bukan total saldo).
    final walletBalance =
        ref.watch(accountBalanceProvider(bill.accountId)).valueOrNull;
    final short = walletBalance == null ? 0 : bill.amount - walletBalance;
    final amountText =
        widget.privacy ? formatMasked() : formatRupiah(bill.amount);

    return Container(
      margin: const EdgeInsets.only(bottom: D.s3),
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(
            color: urgent ? D.amber.withValues(alpha: 0.5) : D.line),
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
                Text(bill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Tgl ${bill.dueDay} · ${widget.accountName}',
                    style: const TextStyle(fontSize: 11.5, color: D.inkMuted)),
                if (!widget.privacy && short > 0)
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
              Text(amountText,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              if (payable) ...[
                const SizedBox(height: D.s1 + 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: D.s2, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        urgent ? D.expense.withValues(alpha: 0.1) : D.surface,
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
                  onTap: _paying
                      ? null
                      : () async {
                          // Guard double-tap: dialog kedua = pembayaran ganda.
                          if (_paying) return;
                          setState(() => _paying = true);
                          try {
                            await confirmAndPayBill(
                                context, ref, bill, widget.accountName);
                          } finally {
                            if (mounted) setState(() => _paying = false);
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: D.s3, vertical: 5),
                    decoration: BoxDecoration(
                      color: D.cobalt.withValues(alpha: _paying ? 0.4 : 1.0),
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
        .animate(target: widget.animate ? 1 : 0)
        .fade(duration: 300.ms, delay: (60 * widget.index).clamp(0, 400).ms)
        .slideY(begin: 0.06, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

// ── Mini bar 7 hari ────────────────────────────────────────────────

class _WeekBars extends ConsumerWidget {
  const _WeekBars({required this.privacy});
  final bool privacy;

  static const _dayInitials = ['Sn', 'Sl', 'Rb', 'Km', 'Jm', 'Sb', 'Mg'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(last7DaysFlowProvider).valueOrNull;
    // Filter OFF → chart default ke Keluar; daftar di bawah yang
    // mengikuti pilihan OFF (semua).
    final out = ref.watch(flowOutProvider) ?? true;
    final values = flow == null ? null : (out ? flow.expense : flow.income);
    final color = out ? D.cobalt : D.income;
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
      child: values == null
          ? const SizedBox(height: 100)
          : Builder(builder: (context) {
              final maxV = values.fold<int>(0, (a, b) => b > a ? b : a);
              final total = values.fold<int>(0, (a, b) => a + b);
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration:
                    reduced ? Duration.zero : const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (total == 0)
                      const Text('Belum ada transaksi',
                          style:
                              TextStyle(fontSize: 12, color: D.inkMuted))
                    else
                      _FlowLegend(
                          color: color,
                          label: out ? 'Keluar' : 'Masuk',
                          value:
                              privacy ? formatMasked() : formatRupiah(total)),
                    const SizedBox(height: D.s3),
                    SizedBox(
                      height: 70,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 7; i++)
                            Expanded(
                              child: _WeekBar(
                                value: (values[i] /
                                        (maxV == 0 ? 1 : maxV)) *
                                    t,
                                color: color,
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

class _FlowLegend extends StatelessWidget {
  const _FlowLegend(
      {required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: D.s1 + 2),
        Text('$label ',
            style: const TextStyle(fontSize: 12, color: D.inkMuted)),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.value,
    required this.color,
    required this.isToday,
    required this.label,
    required this.day,
  });

  final double value; // 0..1 (relatif hari terbesar)
  final Color color;
  final bool isToday;
  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final dim = isToday ? 1.0 : 0.28;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showDayTransactionsSheet(context, day),      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: value <= 0 ? 0.07 : 0.14 + 0.86 * value,
                child: Container(
                  width: 8,
                  decoration: BoxDecoration(
                    color: value <= 0
                        ? D.line
                        : color.withValues(alpha: dim),
                    borderRadius: BorderRadius.circular(3),
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

void showDayTransactionsSheet(BuildContext context, DateTime day) {
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

// ── Hero saldo + proyeksi (swipe) ──────────────────────────────────

class _HeroCard extends ConsumerStatefulWidget {
  const _HeroCard({
    required this.totalBalance,
    required this.walletCount,
    required this.unpaidBills,
    required this.animate,
    required this.privacy,
  });

  final int? totalBalance;
  final int walletCount;
  final int unpaidBills;
  final bool animate;
  final bool privacy;

  @override
  ConsumerState<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends ConsumerState<_HeroCard> {
  late int _page;
  late final PageController _controller;

  static const _monthsAhead = 12; // 1 (saldo) + 12 (proyeksi) = 13 halaman

  @override
  void initState() {
    super.initState();
    // Remount (mis. setelah layar kunci) → mulai dari bulan terakhir.
    _page = ref.read(homeMonthOffsetProvider);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
              controller: _controller,
              itemCount: 1 + _monthsAhead,
              onPageChanged: (p) {
                setState(() => _page = p);
                ref.read(homeMonthOffsetProvider.notifier).state = p;
              },
              itemBuilder: (ctx, p) =>
                  p == 0 ? _balancePage() : _projectionPage(p),
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
    final privacy = widget.privacy;
    String money(int v) => privacy ? formatMasked() : formatRupiah(v);
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
            const SizedBox(width: D.s2),
            // Mata privasi: sembunyikan nominal uang di Beranda.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setPrivacyMode(ref, !privacy),
              child: Semantics(
                label: privacy ? 'Tampilkan nominal' : 'Sembunyikan nominal',
                button: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: D.s2, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(D.rSm),
                  ),
                  child: Icon(
                    privacy
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 15,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: D.s1),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: balance.toDouble()),
          duration: widget.animate && !privacy ? 900.ms : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => Text(
            money(value.round()),
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
        if (commitment > 0 && !privacy) ...[
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

  // ── Halaman 1–12: proyeksi bulan ke-m (m ≥ 1) ──

  Widget _projectionPage(int m) {
    final entries = ref.watch(activeBillsDetailedProvider).valueOrNull;
    final balance = widget.totalBalance;
    final privacy = widget.privacy;
    String money(int v) => privacy ? formatMasked() : formatRupiah(v);
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
          'Proyeksi · $monthName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: D.s1),
        // Tanpa minus: proyeksi negatif → tampilkan saldo total saat ini,
        // kekurangannya di baris merah bawah.
        Text(
          projection == null
              ? '…'
              : money(projection < 0 ? balance! : projection),
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
              : privacy
                  ? '${monthBills!.count} tagihan'
                  : 'Tagihan s/d $shortName: ${formatRupiah(through!)} · ${monthBills!.count} tagihan',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (includePlans && plansTotal > 0 && !privacy)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Rencana: ${formatRupiah(plansTotal)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ),
        if (!privacy && projection != null && projection < 0) ...[
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
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Pilihan arus kartu tren (dipakai Beranda & Laporan).
/// null = filter OFF — klik segmen aktif lagi untuk mematikan.
class FlowToggle extends ConsumerWidget {
  const FlowToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final out = ref.watch(flowOutProvider);
    return SegmentedButton<bool>(
      selected: {if (out != null) out},
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      segments: const [
        ButtonSegment(value: true, label: Text('Keluar')),
        ButtonSegment(value: false, label: Text('Masuk')),
      ],
      // Segmen aktif diklik lagi → selection kosong → filter OFF.
      onSelectionChanged: (s) =>
          ref.read(flowOutProvider.notifier).state = s.isEmpty ? null : s.first,
    );
  }
}

// ── Wallet chip di rail ────────────────────────────────────────────

class _WalletChip extends ConsumerWidget {
  const _WalletChip({
    required this.account,
    required this.index,
    required this.animate,
    required this.privacy,
  });

  final Account account;
  final int index;
  final bool animate;
  final bool privacy;

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
              privacy ? formatMasked() : formatRupiah(balance),
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
  const _PlanChip({required this.plan, this.privacy = false});
  final Plan? plan;
  final bool privacy;

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
            if (!privacy && short != null)
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
