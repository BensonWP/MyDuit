import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import 'transaction_form_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final transactions = ref.watch(recentTransactionsProvider).valueOrNull ?? [];
    final totalBalance = ref.watch(totalBalanceProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Total Saldo',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatRupiah(totalBalance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: const Text('MyDuit'),
            ),
          ),

          // Account list
          if (accounts.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: accounts.length,
                  itemBuilder: (ctx, i) => _AccountCard(account: accounts[i]),
                ),
              ),
            ),
          ],

          // Recent transactions
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Transaksi Terakhir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          if (transactions.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _TransactionTile(
                  transaction: transactions[i],
                  accountName: accounts.where((a) => a.id == transactions[i].accountId).firstOrNull?.name ?? '-',
                ),
                childCount: transactions.length,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(accountBalanceProvider(account.id)).valueOrNull ?? 0;
    final color = hexToColor(account.color);

    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(getAccountIcon(account.type), size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  account.name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            formatRupiah(balance),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.transaction, required this.accountName});
  final Transaction transaction;
  final String accountName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = transaction.type == 'expense';
    final color = isExpense ? Colors.red : transaction.type == 'income' ? Colors.green : Colors.blue;
    final prefix = isExpense ? '-' : transaction.type == 'income' ? '+' : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(
          isExpense ? Icons.arrow_upward : transaction.type == 'income' ? Icons.arrow_downward : Icons.swap_horiz,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        transaction.note.isEmpty ? transaction.type.toUpperCase() : transaction.note,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(accountName, style: const TextStyle(fontSize: 12)),
      trailing: Text(
        '$prefix${formatRupiah(transaction.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color,
          fontSize: 14,
        ),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TransactionFormScreen(existing: transaction)),
      ),
      onLongPress: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus Transaksi?'),
            content: const Text('Tindakan ini tidak bisa dibatalkan.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Hapus'),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await ref.read(dbProvider).deleteTransaction(transaction.id);
        }
      },
    );
  }
}
