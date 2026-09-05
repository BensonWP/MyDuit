import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.initialAccountId, this.initialType, this.existing});

  final String? initialAccountId;
  final String? initialType;
  final Transaction? existing;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _type = 'expense';
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final tx = widget.existing!;
      _type = tx.type;
      _accountId = tx.accountId;
      _toAccountId = tx.toAccountId;
      _categoryId = tx.categoryId;
      _date = DateTime.parse(tx.date);
      _amountController.text = tx.amount.toString();
      _noteController.text = tx.note;
    } else {
      _type = widget.initialType ?? 'expense';
      _accountId = widget.initialAccountId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih wallet terlebih dahulu')),
      );
      return;
    }
    if (_type == 'transfer' && (_toAccountId == null || _toAccountId == _accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wallet asal dan tujuan harus berbeda')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final db = ref.read(dbProvider);
    final amount = int.tryParse(parseCurrency(_amountController.text)) ?? 0;

    final id = _isEditing ? widget.existing!.id : const Uuid().v4();

    final entry = TransactionsCompanion.insert(
      id: id,
      accountId: _accountId!,
      categoryId: Value(_categoryId),
      toAccountId: Value(_toAccountId),
      type: Value(_type),
      amount: Value(amount),
      note: Value(_noteController.text.trim()),
      date: _date.toIso8601String(),
    );

    if (_isEditing) {
      await db.updateTransaction(entry);
    } else {
      await db.insertTransaction(entry);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
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
    if (confirm == true && mounted) {
      await ref.read(dbProvider).deleteTransaction(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];

    final filteredCategories = categories.where((c) => c.type == _type).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaksi' : 'Tambah Transaksi'),
        actions: _isEditing
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _delete,
                ),
              ]
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _typeButton('expense', 'Pengeluaran', Colors.red),
                const SizedBox(width: 8),
                _typeButton('income', 'Pemasukan', Colors.green),
                const SizedBox(width: 8),
                _typeButton('transfer', 'Transfer', Colors.blue),
              ],
            ),
            const SizedBox(height: 16),

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
                if (n == null || n <= 0) return 'Harus lebih dari 0';
                return null;
              },
            ),
            const SizedBox(height: 16),

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
            const SizedBox(height: 16),

            if (_type == 'transfer') ...[
              DropdownButtonFormField<String>(
                value: _toAccountId,
                decoration: const InputDecoration(
                  labelText: 'Ke Wallet',
                  border: OutlineInputBorder(),
                ),
                items: accounts
                    .where((a) => a.id != _accountId)
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() => _toAccountId = v),
              ),
              const SizedBox(height: 16),
            ],

            if (_type != 'transfer')
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Kategori',
                  border: OutlineInputBorder(),
                ),
                items: filteredCategories
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Row(
                            children: [
                              Icon(getIcon(c.icon), size: 18),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            if (_type != 'transfer') const SizedBox(height: 16),

            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Tanggal'),
              subtitle: Text(formatDate(_date.toIso8601String())),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Simpan Perubahan' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeButton(String type, String label, Color color) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.2) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? color : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
