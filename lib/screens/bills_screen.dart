import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(activeBillsStreamProvider).valueOrNull ?? [];
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan Rutin')),
      body: bills.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Belum ada tagihan', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bills.length,
              itemBuilder: (ctx, i) {
                final bill = bills[i];
                final accountName = accounts.where((a) => a.id == bill.accountId).firstOrNull?.name ?? '-';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      child: const Icon(Icons.receipt, color: Colors.orange),
                    ),
                    title: Text(bill.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Jatuh tempo: tgl ${bill.dueDay} · $accountName'),
                    trailing: Text(formatRupiah(bill.amount)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBill(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddBill(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddBillSheet(ref: ref),
    );
  }
}

class _AddBillSheet extends ConsumerStatefulWidget {
  const _AddBillSheet({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends ConsumerState<_AddBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  int _dueDay = 1;
  String? _accountId;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih wallet')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final db = ref.read(dbProvider);

    await db.insertBill(BillsCompanion.insert(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      accountId: _accountId!,
      amount: Value(int.tryParse(parseCurrency(_amountController.text)) ?? 0),
      dueDay: Value(_dueDay),
      createdAt: DateTime.now().toIso8601String(),
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tambah Tagihan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Tagihan',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Jumlah',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Wajib diisi';
                final n = int.tryParse(parseCurrency(v));
                if (n == null || n <= 0) return 'Harus angka';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _accountId,
              decoration: const InputDecoration(
                labelText: 'Wallet',
                border: OutlineInputBorder(),
              ),
              items: accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Tanggal Jatuh Tempo: '),
                const Spacer(),
                DropdownButton<int>(
                  value: _dueDay,
                  items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (v) => setState(() => _dueDay = v ?? 1),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
