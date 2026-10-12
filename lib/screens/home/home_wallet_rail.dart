import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../db/database.dart';
import '../../providers/database_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_icons.dart';
import '../../utils/currency.dart';
import '../../utils/wallet_brand.dart';
import '../../widgets/transaction_tile.dart';
import '../account_detail_screen.dart';

// ── Wallet chip di rail ────────────────────────────────────────────

class WalletChip extends ConsumerWidget {
  const WalletChip({
    super.key,
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
