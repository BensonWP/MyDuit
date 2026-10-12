import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_icons.dart';
import '../utils/brand_logo.dart';
import '../utils/wallet_brand.dart';

/// Form tambah/edit brand wallet custom (halaman penuh).
/// Logo opsional dari galeri (dinormalisasi 192px, blob di DB).
class BrandFormScreen extends ConsumerStatefulWidget {
  const BrandFormScreen({super.key, this.brandId, this.initialKind});

  final String? brandId;

  /// Jenis terpilih awal saat tambah baru (mis. dari daftar tersaring).
  final String? initialKind;

  @override
  ConsumerState<BrandFormScreen> createState() => _BrandFormScreenState();
}

class _BrandFormScreenState extends ConsumerState<BrandFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late String _kind = widget.initialKind ?? 'bank';
  String _hex = '#607D8B';
  Uint8List? _logo;
  bool _isLoading = false;
  bool _loadingExisting = false;
  bool _pickingLogo = false;

  /// Jumlah wallet pemakai — bila > 0, kind dikunci.
  int _usageCount = 0;

  bool get _isEditing => widget.brandId != null;

  static const _presetColors = [
    '#E1251B',
    '#EE4D2D',
    '#F5A524',
    '#65A30D',
    '#0E9F6E',
    '#0D9488',
    '#0891B2',
    '#118EEA',
    '#1A3A6B',
    '#4C3494',
    '#7C3AED',
    '#DB2777',
    '#607D8B',
    '#1A1A1A',
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  Future<void> _load() async {
    setState(() => _loadingExisting = true);
    final db = ref.read(dbProvider);
    final existing = await (db.select(db.customBrands)
          ..where((b) => b.id.equals(widget.brandId!)))
        .getSingleOrNull();
    final usage =
        existing == null ? 0 : await db.brandUsage(existing.id);
    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _nameController.text = existing.name;
        _kind = existing.kind;
        _hex = existing.hex;
        _logo = existing.logo;
      }
      _usageCount = usage;
      _loadingExisting = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    setState(() => _pickingLogo = true);
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 512);
      if (picked == null) return;
      final normalized =
          normalizeLogoBytes(await picked.readAsBytes());
      if (!mounted) return;
      if (normalized == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gambar tidak valid')),
        );
        return;
      }
      setState(() => _logo = normalized);
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final db = ref.read(dbProvider);
    final name = _nameController.text.trim();

    // Nama unik per kind (abaikan diri sendiri saat edit) — termasuk
    // brand bawaan agar tak menimpa identitas brand resmi.
    final brands = await db.watchCustomBrands().first;
    final taken = brands
        .where((c) => c.kind == _kind && c.id != widget.brandId)
        .any((c) => c.name.toLowerCase() == name.toLowerCase());
    if (taken && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama brand sudah dipakai')),
      );
      return;
    }

    final now = DateTime.now().toIso8601String();
    if (_isEditing) {
      await db.updateBrand(CustomBrandsCompanion(
        id: Value(widget.brandId!),
        name: Value(name),
        kind: Value(_kind),
        hex: Value(_hex),
        logo: Value(_logo),
      ));
    } else {
      await db.insertBrand(CustomBrandsCompanion.insert(
        id: 'brand_${const Uuid().v4()}',
        name: name,
        kind: Value(_kind),
        hex: Value(_hex),
        logo: Value(_logo),
        createdAt: now,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kindLocked = _isEditing && _usageCount > 0;
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Edit Brand' : 'Tambah Brand')),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(D.s4),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Pratinjau logo.
                    Row(
                      children: [
                        _logo != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(_logo!,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover),
                              )
                            : BrandInitial(
                                label: _nameController.text.trim().isEmpty
                                    ? 'B'
                                    : _nameController.text.trim(),
                                hex: _hex,
                                size: 56,
                              ),
                        const SizedBox(width: D.s4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    _pickingLogo ? null : _pickLogo,
                                icon: const Icon(
                                    Icons.image_outlined,
                                    size: 18),
                                label: Text(_logo == null
                                    ? 'Pilih logo (opsional)'
                                    : 'Ganti logo'),
                              ),
                              if (_logo != null)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _logo = null),
                                  style: TextButton.styleFrom(
                                      foregroundColor: D.expense),
                                  child: const Text('Hapus logo'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: D.s4),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama brand',
                        hintText: 'mis. BSI, Bank Jago, LinkAja',
                      ),
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: D.s4),
                    const Text('Jenis',
                        style: TextStyle(
                            fontSize: 12.5, color: D.inkMuted)),
                    const SizedBox(height: D.s2),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'bank', label: Text('Bank')),
                        ButtonSegment(
                            value: 'ewallet', label: Text('E-Wallet')),
                        ButtonSegment(
                            value: 'card', label: Text('Kartu')),
                      ],
                      selected: {_kind},
                      onSelectionChanged: kindLocked
                          ? null
                          : (s) => setState(() => _kind = s.first),
                      showSelectedIcon: false,
                    ),
                    if (kindLocked)
                      const Padding(
                        padding: EdgeInsets.only(top: D.s2),
                        child: Text(
                          'Jenis dikunci karena brand ini sudah dipakai dompet.',
                          style: TextStyle(
                              fontSize: 11.5, color: D.inkMuted),
                        ),
                      ),
                    const SizedBox(height: D.s4),
                    const Text('Warna',
                        style: TextStyle(
                            fontSize: 12.5, color: D.inkMuted)),
                    const SizedBox(height: D.s2),
                    Wrap(
                      spacing: D.s2,
                      runSpacing: D.s2,
                      children: [
                        for (final hex in _presetColors)
                          GestureDetector(
                            onTap: () => setState(() => _hex = hex),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: hexToColor(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _hex == hex
                                      ? D.cobalt
                                      : D.line,
                                  width: _hex == hex ? 2.5 : 1,
                                ),
                              ),
                              child: _hex == hex
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 20)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: D.s6),
                    FilledButton(
                      onPressed: _isLoading ? null : _save,
                      child: Text(_isLoading ? 'Menyimpan…' : 'Simpan'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
