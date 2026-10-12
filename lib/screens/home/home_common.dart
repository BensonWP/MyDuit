import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';

// ── Skeleton statis (tanpa loop) saat saldo/daftar wallet memuat ──

class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(D.s6),
      decoration: BoxDecoration(
        color: D.cobaltDeep,
        borderRadius: BorderRadius.circular(D.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBar(width: 140, height: 13),
          SizedBox(height: D.s3 + 2),
          SkeletonBar(width: 200, height: 34),
          SizedBox(height: D.s3),
          SkeletonBar(width: 110, height: 12),
        ],
      ),
    );
  }
}

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(D.rSm),
      ),
    );
  }
}

class RailSkeleton extends StatelessWidget {
  const RailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 84,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? D.s3 : 0),
                decoration: BoxDecoration(
                  color: D.card,
                  borderRadius: BorderRadius.circular(D.rMd),
                  border: Border.all(color: D.line),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Banner peringatan anggaran bulan berjalan ───────────────────
// Hanya hitungan kategori (tanpa nominal) → aman mode privasi.
// Tap pindah ke tab Laporan.
class BudgetBanner extends ConsumerWidget {
  const BudgetBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(budgetAlertsProvider);
    if (alerts.warning == 0 && alerts.over == 0) {
      return const SizedBox.shrink();
    }
    final over = alerts.over > 0;
    final accent = over ? D.expense : D.amber;
    final text = [
      if (over) '${alerts.over} anggaran melebihi batas',
      if (alerts.warning > 0) '${alerts.warning} mendekati batas',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: D.s6),
      child: GestureDetector(
        onTap: () => ref.read(navIndexProvider.notifier).state = 1,
        child: Container(
          padding: const EdgeInsets.all(D.s3 + 2),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(D.rMd),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(
                  over
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: accent,
                  size: 20),
              const SizedBox(width: D.s3),
              Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: D.inkMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────

class EmptyTransactions extends StatelessWidget {
  const EmptyTransactions({super.key, required this.reducedMotion});
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
