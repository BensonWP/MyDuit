import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../db/database.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency.dart';
import '../../utils/dates.dart';
import '../../widgets/section_header.dart';
import '../bills_screen.dart';

// ── Tagihan bulan terpilih di hero (yang lunas bulan itu hilang) ───
class UnpaidBillsCard extends ConsumerWidget {
  const UnpaidBillsCard({
    super.key,
    required this.reducedMotion,
    required this.privacy,
  });
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
        SectionHeader(title: title),
        const SizedBox(height: D.s3),
        for (var i = 0; i < bills.length; i++)
          UnpaidBillTile(
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

class UnpaidBillTile extends ConsumerStatefulWidget {
  const UnpaidBillTile({
    super.key,
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
  ConsumerState<UnpaidBillTile> createState() => UnpaidBillTileState();
}

class UnpaidBillTileState extends ConsumerState<UnpaidBillTile> {
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
    final payments =
        ref.watch(billPaymentsProvider(bill.id)).valueOrNull ?? [];
    final paidFlag = payments.isNotEmpty &&
        payments.first.paidAt.substring(0, 7) ==
            DateTime.now().toIso8601String().substring(0, 7);
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
                if (paidFlag && payments.isNotEmpty)
                  Text(
                    'Dibayar ${formatDate(payments.first.paidAt)} · ${formatTime(payments.first.paidAt)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: D.income,
                        fontWeight: FontWeight.w600),
                  ),
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
