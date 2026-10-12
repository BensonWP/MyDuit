import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../utils/wallet_brand.dart';
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
  String _selectedColor = _typeColors['cash']!;
  String? _selectedBrand;
  String? _createdAt;
  bool _isLoading = false;

  static const _typeColors = {
    'cash': '#4CAF50',
    'bank': '#2196F3',
    'ewallet': '#00BCD4',
    'card': '#607D8B',
  };

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
      _selectedBrand = acc.brand;
      _createdAt = acc.createdAt;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  /// Ganti tipe: brand dibuang bila tak berlaku di tipe baru,
  /// warna otomatis mengikuti tipe.
  void _onTypeChanged(String type) {
    setState(() {
      _selectedType = type;
      _selectedColor = _typeColors[type] ?? _selectedColor;
      final validIds = {
        for (final b in ref.read(brandOptionsProvider(type))) b.id,
      };
      if (!validIds.contains(_selectedBrand)) {
        _selectedBrand = null;
      }
    });
  }

  /// Pilih brand bank/e-wallet/kartu: nama terisi otomatis hanya bila
  /// kosong / masih label brand lain, warna identitas ikut brand.
  void _onBrandSelected(BrandOption brand) {
    final current = _nameController.text.trim();
    final known = {
      for (final b in ref.read(brandOptionsProvider(_selectedType)))
        b.label,
    };
    final isAutoName = current.isEmpty || known.contains(current);
    setState(() {
      _selectedBrand = brand.id;
      if (isAutoName) _nameController.text = brand.label;
      _selectedColor = brand.hex;
    });
  }

  /// Cash tanpa nama: otomatis "Cash", "Cash 2", … bila sudah dipakai.
  String _autoCashName() {
    final taken = (ref.read(accountsStreamProvider).valueOrNull ?? const [])
        .map((a) => a.name)
        .toSet();
    if (!taken.contains('Cash')) return 'Cash';
    var n = 2;
    while (taken.contains('Cash $n')) {
      n++;
    }
    return 'Cash $n';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final db = ref.read(dbProvider);
    final id = widget.accountId ?? const Uuid().v4();
    final name = _selectedType == 'cash' && widget.accountId == null
        ? _autoCashName()
        : _nameController.text.trim();

    final hasBrand = _selectedType != 'cash';
    final entry = AccountsCompanion.insert(
      id: id,
      name: name,
      type: Value(_selectedType),
      color: Value(_selectedColor),
      brand: Value(hasBrand ? _selectedBrand : null),
      initialBalance: Value(int.tryParse(parseCurrency(_balanceController.text)) ?? 0),
      createdAt: _createdAt ?? DateTime.now().toIso8601String(),
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
    final hasBrandPicker = _selectedType == 'ewallet' ||
        _selectedType == 'bank' ||
        _selectedType == 'card';
    // Opsi gabungan bawaan + custom (Kelola Brand).
    final brandOptions = hasBrandPicker
        ? ref.watch(brandOptionsProvider(_selectedType))
        : const <BrandOption>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accountId != null ? 'Edit Dompet' : 'Tambah Dompet'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_selectedType != 'cash') ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Dompet',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _balanceController,
              decoration: const InputDecoration(
                labelText: 'Saldo Awal',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
            ),
            const SizedBox(height: 16),
            const Text('Tipe', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final (type, label) in const [
                  ('cash', 'Cash'),
                  ('bank', 'Bank'),
                  ('ewallet', 'E-Wallet'),
                  ('card', 'Kartu'),
                ])
                  _typeImage(type, label),
              ],
            ),
            // Baris brand untuk Bank & E-Wallet.
            AnimatedSize(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: hasBrandPicker
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              switch (_selectedType) {
                                'bank' => 'Pilih Bank',
                                'card' => 'Pilih Kartu',
                                _ => 'Pilih Brand',
                              },
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              for (final brand in brandOptions)
                                _brandImage(brand),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
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

  Widget _typeImage(String type, String label) {
    final selected = _selectedType == type;
    return _ImageOption(
      asset: walletTypeImages[type]!,
      label: label,
      selected: selected,
      onTap: () => _onTypeChanged(type),
    );
  }

  Widget _brandImage(BrandOption brand) {
    return _ImageOption(
      logo: brand.logo,
      hex: brand.hex,
      label: brand.label,
      selected: _selectedBrand == brand.id,
      onTap: () => _onBrandSelected(brand),
    );
  }
}

/// Kotak pilihan bergambar: 56×56 + label, ring cobalt saat terpilih.
/// [asset] null + [logo] null → placeholder inisial warna [hex].
class _ImageOption extends StatelessWidget {
  const _ImageOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.asset,
    this.logo,
    this.hex,
  });

  final String? asset;
  final Uint8List? logo;
  final String? hex;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final logoWidget = asset != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child:
                Image.asset(asset!, width: 48, height: 48, fit: BoxFit.cover))
        : logo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(logo!,
                    width: 48, height: 48, fit: BoxFit.cover))
            : BrandInitial(label: label, hex: hex ?? '#607D8B', size: 48);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        width: 68,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? D.cobalt.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(
            color: selected ? D.cobalt : D.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            logoWidget,
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? D.cobalt : D.ink,
                )),
          ],
        ),
      ),
    );
  }
}
