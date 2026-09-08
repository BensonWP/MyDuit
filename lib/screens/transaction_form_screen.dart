import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';

/// Form transaksi.
/// - Tambah: tampil sebagai modal bottom sheet lewat [showAddSheet].
/// - Edit: tampil sebagai halaman penuh lewat [TransactionForm.existing].
class TransactionForm extends ConsumerStatefulWidget {
  const TransactionForm(
      {super.key, this.existing, this.inSheet = false, this.initialAccountId});

  final Transaction? existing;
  final bool inSheet;
  final String? initialAccountId;

  static Future<void> showAddSheet(BuildContext context,
      {String? initialAccountId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: TransactionForm(
          inSheet: true,
          initialAccountId: initialAccountId,
        ),
      ),
    );
  }

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
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
    final tx = widget.existing;
    if (tx != null) {
      _type = tx.type;
      _accountId = tx.accountId;
      _toAccountId = tx.toAccountId;
      _categoryId = tx.categoryId;
      _date = DateTime.parse(tx.date);
      _amountController.text = tx.amount.toString();
      _noteController.text = tx.note;
    } else {
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
      _snack('Pilih wallet terlebih dahulu');
      return;
    }
    if (_type == 'transfer' && (_toAccountId == null || _toAccountId == _accountId)) {
      _snack('Wallet asal dan tujuan harus berbeda');
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
    final confirmed = await confirmDelete(
      context,
      'Hapus transaksi ini?',
      description:
          'Transaksi dihapus permanen dan saldo wallet dihitung ulang.',
    );
    if (!confirmed) return;

    await ref.read(dbProvider).deleteTransactionCascade(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final filteredCategories =
        categories.where((c) => c.type == _type).toList();

    final fields = <Widget>[
      _TypeSelector(
        selected: _type,
        onChanged: (v) {
          if (v == _type) return;
          setState(() {
            _type = v;
            // Kategori terikat jenis — buang nilai lama agar dropdown valid.
            _categoryId = null;
            if (v != 'transfer') _toAccountId = null;
          });
        },
      ),
      const SizedBox(height: D.s4),
      TextFormField(
        controller: _amountController,
        decoration: const InputDecoration(
          labelText: 'Jumlah',
          prefixText: 'Rp ',
          hintStyle: TextStyle(color: D.inkMuted),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [CurrencyInputFormatter()],
        autofocus: !widget.inSheet && !_isEditing,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Wajib diisi';
          final n = int.tryParse(parseCurrency(v));
          if (n == null || n <= 0) return 'Harus lebih dari 0';
          return null;
        },
      ),
      const SizedBox(height: D.s3),
      DropdownButtonFormField<String>(
        // Guard: wallet/kategori yang diarsipkan tak boleh jadi value
        // dropdown (assert Flutter menuntut value ∈ items).
        value: accounts.any((a) => a.id == _accountId) ? _accountId : null,
        decoration: const InputDecoration(labelText: 'Wallet'),
        items: accounts
            .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
            .toList(),
        onChanged: (v) => setState(() {
          _accountId = v;
          // Wallet tujuan tak boleh sama dengan asal.
          if (_toAccountId == v) _toAccountId = null;
        }),
      ),
      if (_type == 'transfer') ...[
        const SizedBox(height: D.s3),
      DropdownButtonFormField<String>(
        value:
            accounts.any((a) => a.id == _toAccountId) ? _toAccountId : null,
        decoration: const InputDecoration(labelText: 'Ke Wallet'),
        items: accounts
            .where((a) => a.id != _accountId)
            .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
            .toList(),
        onChanged: (v) => setState(() => _toAccountId = v),
      ),
      ],
      if (_type != 'transfer') ...[
        const SizedBox(height: D.s3),
        DropdownButtonFormField<String>(
          value: filteredCategories.any((c) => c.id == _categoryId)
              ? _categoryId
              : null,
          decoration: const InputDecoration(labelText: 'Kategori'),
          items: filteredCategories
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Row(
                      children: [
                        Icon(getIcon(c.icon), size: 18, color: D.inkMuted),
                        const SizedBox(width: D.s2),
                        Text(c.name),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _categoryId = v),
        ),
      ],
      const SizedBox(height: D.s3),
      TextFormField(
        controller: _noteController,
        decoration: const InputDecoration(
          labelText: 'Catatan (opsional)',
          hintText: 'Makan siang, bensin…',
        ),
      ),
      const SizedBox(height: D.s2),
      ListTile(
        leading: const Icon(Icons.calendar_today_rounded,
            size: 20, color: D.inkMuted),
        title: const Text('Tanggal', style: TextStyle(fontSize: 14)),
        subtitle: Text(formatDate(_date.toIso8601String()),
            style: const TextStyle(fontSize: 12.5)),
        contentPadding: EdgeInsets.zero,
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
          );
          if (picked != null) setState(() => _date = picked);
        },
      ),
      const SizedBox(height: D.s2),
      FilledButton(
        onPressed: _isLoading ? null : _save,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(_isEditing ? 'Simpan Perubahan' : 'Simpan'),
      ),
    ];

    if (widget.inSheet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s4),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'Transaksi Baru',
                    style: Theme.of(context).appBarTheme.titleTextStyle,
                  ),
                ),
                const SizedBox(height: D.s4),
                ...fields,
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Transaksi' : 'Transaksi Baru'),
        actions: _isEditing
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: D.expense),
                  onPressed: _delete,
                ),
              ]
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(D.s4),
          children: fields,
        ),
      ),
    );
  }
}

// ── Selector jenis transaksi dengan indikator geser ────────────────

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('expense', 'Pengeluaran'),
    ('income', 'Pemasukan'),
    ('transfer', 'Transfer'),
  ];

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final selectedIdx = _options.indexWhere((o) => o.$1 == selected);

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      const padding = 4.0;
      final segW = (w - padding * 2) / _options.length;

      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: D.surface,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(color: D.line),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration:
                  reduced ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              left: padding + segW * selectedIdx,
              top: padding,
              bottom: padding,
              width: segW,
              child: Container(
                decoration: BoxDecoration(
                  color: D.cobalt,
                  borderRadius: BorderRadius.circular(D.rMd - 4),
                ),
              ),
            ),
            Row(
              children: _options.map((o) {
                final isSelected = o.$1 == selected;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(o.$1),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? Colors.white : D.inkMuted,
                        ),
                        child: Text(o.$2),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );
    });
  }
}
