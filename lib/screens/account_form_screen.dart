import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../utils/app_icons.dart';
import '../providers/database_provider.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _balanceController;
  String _selectedType = 'cash';
  String _selectedColor = '#4CAF50';
  bool _isLoading = false;

  static const _colors = [
    '#4CAF50', '#2196F3', '#FF9800', '#E91E63',
    '#9C27B0', '#00BCD4', '#795548', '#607D8B',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _balanceController = TextEditingController(text: '0');
    if (widget.accountId != null) _loadAccount();
  }

  Future<void> _loadAccount() async {
    final db = ref.read(dbProvider);
    final accounts = await db.allAccounts();
    final acc = accounts.where((a) => a.id == widget.accountId).firstOrNull;
    if (acc != null) {
      _nameController.text = acc.name;
      _balanceController.text = acc.initialBalance.toString();
      _selectedType = acc.type;
      _selectedColor = acc.color;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final db = ref.read(dbProvider);
    final id = widget.accountId ?? const Uuid().v4();

    final entry = AccountsCompanion.insert(
      id: id,
      name: _nameController.text.trim(),
      type: Value(_selectedType),
      color: Value(_selectedColor),
      initialBalance: Value(int.tryParse(_balanceController.text) ?? 0),
      createdAt: DateTime.now().toIso8601String(),
    );

    if (widget.accountId != null) {
      await db.updateAccount(entry);
    } else {
      await db.insertAccount(entry);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountId != null ? 'Edit Wallet' : 'Tambah Wallet'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Wallet',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _balanceController,
              decoration: const InputDecoration(
                labelText: 'Saldo Awal',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            const Text('Tipe', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _typeChip('cash', 'Cash'),
                _typeChip('bank', 'Bank'),
                _typeChip('ewallet', 'E-Wallet'),
                _typeChip('card', 'Kartu'),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Warna', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _colors
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: hexToColor(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == c ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: _selectedColor == c
                                ? [BoxShadow(color: Colors.black26, blurRadius: 4)]
                                : null,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 32),
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

  Widget _typeChip(String value, String label) {
    final selected = _selectedType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedType = value),
      avatar: Icon(getAccountIcon(value), size: 18),
    );
  }
}
