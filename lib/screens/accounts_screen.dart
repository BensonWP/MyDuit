import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_provider.dart';
import '../utils/app_icons.dart';
import 'account_form_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: accounts.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.account_balance_wallet, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Belum ada wallet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length,
              itemBuilder: (ctx, i) {
                final account = accounts[i];
                final color = hexToColor(account.color);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(getAccountIcon(account.type), color: color),
                    ),
                    title: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(account.type.toUpperCase(), style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccountFormScreen(accountId: account.id),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AccountFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
