import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_icons.dart';

/// Satu pilihan ikon di grid form kategori.

/// Form tambah/edit kategori (halaman penuh, meniru AccountFormScreen).
/// Tipe dikunci saat edit kategori yang sudah dipakai transaksi/tagihan.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<CategoryFormScreen> createState() =>
      _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _type = 'expense';
  String _icon = 'more_horiz';
  bool _isLoading = false;
  bool _loadingExisting = false;

  /// Jumlah pemakaian kategori yang sedang diedit — bila > 0,
  /// tipe dikunci agar laporan tidak rusak.
  int _usageCount = 0;

  bool get _isEditing => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _load();
  }

  Future<void> _load() async {
    setState(() => _loadingExisting = true);
    final db = ref.read(dbProvider);
    final all = await db.allCategories();
    final cat = all.where((c) => c.id == widget.categoryId).firstOrNull;
    var usage = 0;
    if (cat != null) {
      final (txCount, billCount) = await db.categoryUsage(cat.id);
      usage = txCount + billCount;
    }
    if (!mounted) return;
    setState(() {
      if (cat != null) {
        _nameController.text = cat.name;
        _type = cat.type;
        _icon = categoryIcons.containsKey(cat.icon) ? cat.icon : 'more_horiz';
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final db = ref.read(dbProvider);
    final name = _nameController.text.trim();

    // Nama unik per tipe (abaikan diri sendiri saat edit).
    final siblings = (await db.allCategories()).where(
      (c) => c.type == _type && c.id != widget.categoryId,
    );
    if (siblings.any(
        (c) => c.name.trim().toLowerCase() == name.toLowerCase())) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama kategori sudah dipakai')),
        );
      }
      return;
    }

    if (_isEditing) {
      await db.updateCategory(CategoriesCompanion(
        id: Value(widget.categoryId!),
        name: Value(name),
        type: Value(_type),
        icon: Value(_icon),
      ));
    } else {
      await db.insertCategory(CategoriesCompanion.insert(
        id: 'cat_${const Uuid().v4()}',
        name: name,
        type: Value(_type),
        icon: Value(_icon),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final typeLocked = _isEditing && _usageCount > 0;
    return Scaffold(
      appBar: AppBar(
          title: Text(_isEditing ? 'Edit Kategori' : 'Tambah Kategori')),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
              padding: const EdgeInsets.all(D.s4),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama kategori',
                      hintText: 'Jajan, bensin…',
                    ),
                    textCapitalization: TextCapitalization.words,
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
                          value: 'expense', label: Text('Pengeluaran')),
                      ButtonSegment(
                          value: 'income', label: Text('Pemasukan')),
                    ],
                    selected: {_type},
                    onSelectionChanged: typeLocked
                        ? null
                        : (s) => setState(() => _type = s.first),
                    showSelectedIcon: false,
                  ),
                  if (typeLocked)
                    const Padding(
                      padding: EdgeInsets.only(top: D.s2),
                      child: Text(
                        'Jenis dikunci karena kategori ini sudah dipakai.',
                        style: TextStyle(
                            fontSize: 11.5, color: D.inkMuted),
                      ),
                    ),
                  const SizedBox(height: D.s4),
                  const Text('Ikon',
                      style: TextStyle(
                          fontSize: 12.5, color: D.inkMuted)),
                  const SizedBox(height: D.s2),
                  // Wrap (bukan GridView): tanpa Scrollable bersarang agar
                  // ensureVisible/scroll form luar bekerja normal.
                  Wrap(
                    spacing: D.s2,
                    runSpacing: D.s2,
                    children: [
                      for (final key in categoryIcons.keys)
                        _IconOption(
                          iconKey: key,
                          selected: key == _icon,
                          onTap: () => setState(() => _icon = key),
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

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.iconKey,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? D.cobalt.withValues(alpha: 0.12) : D.card,
          borderRadius: BorderRadius.circular(D.rSm),
          border: Border.all(
            color: selected ? D.cobalt : D.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Icon(getIcon(iconKey),
            size: 22, color: selected ? D.cobalt : D.inkMuted),
      ),
    );
  }
}
