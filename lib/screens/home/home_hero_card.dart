import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';

// ── Hero saldo + proyeksi (swipe) ──────────────────────────────────

class HeroCard extends ConsumerStatefulWidget {
  const HeroCard({
    super.key,
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
  ConsumerState<HeroCard> createState() => HeroCardState();
}

class HeroCardState extends ConsumerState<HeroCard> {
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
                  duration:
                      reduced ? Duration.zero : const Duration(milliseconds: 180),
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
    final commitment = widget.unpaidBills;
    final sisa = balance - commitment;

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
          ],
        ),
        const SizedBox(height: D.s1),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TweenAnimationBuilder<double>(
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
            ),
            // Mata privasi: sembunyikan nominal uang di Beranda.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setPrivacyMode(ref, !privacy),
              child: Semantics(
                label: privacy ? 'Tampilkan nominal' : 'Sembunyikan nominal',
                button: true,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(D.rSm),
                  ),
                  child: Icon(
                    privacy
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 22,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: D.s2),
        Text(
          '${widget.walletCount} dompet terdaftar',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        if (commitment > 0 && !privacy) ...[
          const SizedBox(height: D.s1 + 2),
          Text(
            sisa < 0
                ? 'Kurang ${formatRupiah(-sisa)} untuk tagihan'
                : 'Setelah tagihan: ${formatRupiah(sisa)}',
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

    final now = DateTime.now();
    final month = DateTime(now.year, now.month + m);
    final monthName = DateFormat('MMMM yyyy', 'id_ID').format(month);
    final shortName = DateFormat('MMM', 'id_ID').format(month);
    final monthBills = entries == null ? null : billsForMonth(entries, m);
    final through = entries == null ? null : billsThroughMonth(entries, m);
    final projection = balance == null || through == null
        ? null
        : balance - through;

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
        if (!privacy && projection != null && projection < 0) ...[
          const SizedBox(height: D.s1 + 2),
          Text(
            'Kurang ${formatRupiah(-projection)} untuk tagihan',
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
