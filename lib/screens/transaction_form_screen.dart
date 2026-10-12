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

/// Format "10 Sep 2026 · 14:30" untuk picker tanggal+jam di form.
String _formatDateTime(DateTime d) =>
    '${formatDate(d.toIso8601String())} · ${formatTime(d.toIso8601String())}';

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
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _isLoading = false;

  /// Pesan inline saldo kurang — dipakai menggantikan Snackbar yang
  /// tertutup modal bottom sheet pada mode Tambah.
  String? _balanceError;

  void _deny(String msg) {
    if (mounted) setState(() => _balanceError = msg);
  }

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    if (tx != null) {
      _type = tx.type;
      _accountId = tx.accountId;
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

  String _walletName([String? id]) {
    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final target = id ?? _accountId;
    return accounts.where((a) => a.id == target).firstOrNull?.name ??
        'dompet';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      _snack('Pilih dompet terlebih dahulu');
      return;
    }

    setState(() {
      _isLoading = true;
      _balanceError = null;
    });
    try {
      final db = ref.read(dbProvider);
      final amount = int.tryParse(parseCurrency(_amountController.text)) ?? 0;
      final id = _isEditing ? widget.existing!.id : const Uuid().v4();

      // Cegah saldo minus: cek cepat sebelum tulis DB (dana tersedia =
      // saldo saat ini dikurangi kontribusi tx lama bila mode edit).
      if (_type == 'expense') {
        final balance = await db.accountBalance(_accountId!);
        var available = balance;
        final old = widget.existing;
        if (old != null) {
          if (old.accountId == _accountId) {
            available += old.type == 'income' ? -old.amount : old.amount;
          } else if (old.toAccountId == _accountId) {
            available -= old.amount;
          }
        }
        if (available < amount) {
          _deny(
              'Saldo ${_walletName()} tidak cukup · kurang ${formatRupiah(amount - available)}');
          return;
        }
      }

      final entry = TransactionsCompanion.insert(
        id: id,
        accountId: _accountId!,
        // Fallback per jenis: income tanpa kategori → cat_other_income
        // (bukan cat_other yang expense) agar laporan tak tercampur.
        categoryId:
            Value(_categoryId ?? (_type == 'income' ? 'cat_other_income' : 'cat_other')),
        type: Value(_type),
        amount: Value(amount),
        note: Value(_noteController.text.trim()),
        date: _date.toIso8601String(),
      );

      // Jaring pengaman: guard DB menolak bila hasil akhir bikin
      // wallet mana pun minus (mis. pindah wallet atau race).
      try {
        if (_isEditing) {
          await db.updateTransaction(entry);
        } else {
          await db.insertTransaction(entry);
        }
      } on InsufficientBalanceException catch (e) {
        _deny(
            'Saldo ${_walletName(e.accountId)} tidak cukup · kurang ${formatRupiah(e.short)}');
        return;
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      'Hapus transaksi ini?',
      description:
          'Transaksi dihapus permanen dan saldo dompet dihitung ulang.',
    );
    if (!confirmed || !mounted) return;

    final db = ref.read(dbProvider);
    // Snapshot dulu agar bisa diurungkan lewat snackbar di layar sebelumnya.
    final undo = await db.captureTransactionUndo(widget.existing!.id);
    await db.deleteTransactionCascade(widget.existing!.id);
    // Snackbar sebelum pop — context form sudah tidak valid setelahnya.
    if (undo != null && mounted) {
      showUndoBar(context, 'Transaksi dihapus',
          () => db.restoreTransactionUndo(undo));
    }
    if (mounted) Navigator.pop(context);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(activeCategoriesProvider).valueOrNull ?? [];
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
            _balanceError = null;
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
        onChanged: (_) {
          if (_balanceError != null) setState(() => _balanceError = null);
        },
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
        decoration: const InputDecoration(labelText: 'Dompet'),
        items: accounts
            .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
            .toList(),
        onChanged: (v) => setState(() {
          _accountId = v;
          _balanceError = null;
        }),
      ),
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
        title: const Text('Tanggal & Jam', style: TextStyle(fontSize: 14)),
        subtitle: Text(_formatDateTime(_date),
            style: const TextStyle(fontSize: 12.5)),
        contentPadding: EdgeInsets.zero,
        trailing: TextButton(
          onPressed: () {
            final now = DateTime.now();
            setState(() => _date = now);
          },
          child: const Text('Sekarang'),
        ),
        onTap: () async {
          // Alur berurutan: pilih tanggal, lalu jam. Batal di salah satu
          // tahap mempertahankan nilai lama.
          final pickedDate = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (pickedDate == null || !context.mounted) return;

          final pickedTime = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_date),
          );
          if (!context.mounted) return;

          setState(() => _date = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime?.hour ?? _date.hour,
                pickedTime?.minute ?? _date.minute,
              ));
        },
      ),
      const SizedBox(height: D.s2),
      if (_balanceError != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(D.s3),
          decoration: BoxDecoration(
            color: D.expense.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(D.rMd),
            border: Border.all(color: D.expense.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: D.expense, size: 20),
              const SizedBox(width: D.s2),
              Expanded(
                child: Text(
                  _balanceError!,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: D.expense),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: D.s2),
      ],
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
