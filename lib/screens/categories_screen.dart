import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_icons.dart';
import '../utils/category_color.dart';
import '../widgets/confirm_dialog.dart';
import 'category_form_screen.dart';

/// Daftar master kategori: aktif per jenis + arsip.
/// Entri dari tile "Kelola kategori" di Profil.
/// Dua card di atas memilih jenis (Pengeluaran/Pemasukan) yang ditampilkan.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  /// Jenis yang sedang ditampilkan.
  String _type = 'expense';

  Future<void> _archive(WidgetRef ref, Category cat) async {
    final db = ref.read(dbProvider);
    final (txCount, billCount) = await db.categoryUsage(cat.id);
    final used = txCount + billCount;
    if (!mounted) return;
    final confirmed = await confirmDelete(
      context,
      'Arsipkan ${cat.name}?',
      description: used > 0
          ? 'Dipakai $txCount transaksi dan $billCount tagihan. '
              'Riwayat tetap utuh, kategori hilang dari form.'
          : 'Kategori akan disembunyikan dari form dan bisa diaktifkan lagi.',
      confirmLabel: 'Arsipkan',
    );
    if (!confirmed) return;
    await db.archiveCategory(cat.id);
  }

  Future<void> _unarchive(WidgetRef ref, Category cat) async {
    await ref.read(dbProvider).unarchiveCategory(cat.id);
  }

  void _openForm([String? categoryId]) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CategoryFormScreen(categoryId: categoryId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    final expenseActive =
        all.where((c) => !c.archived && c.type == 'expense').toList();
    final incomeActive =
        all.where((c) => !c.archived && c.type == 'income').toList();
    final expenseArchived =
        all.where((c) => c.archived && c.type == 'expense').toList();
    final incomeArchived =
        all.where((c) => c.archived && c.type == 'income').toList();

    final isExpense = _type == 'expense';
    final active = isExpense ? expenseActive : incomeActive;
    final archived = isExpense ? expenseArchived : incomeArchived;
    final fallbackId = isExpense ? 'cat_other' : 'cat_other_income';

    return Scaffold(
      appBar: AppBar(title: const Text('Kategori')),
      body: ListView(
        padding: const EdgeInsets.all(D.s4),
        children: [
          // Dua card pemilih jenis.
          Row(
            children: [
              Expanded(
                child: _TypeCard(
                  label: 'Pengeluaran',
                  count: expenseActive.length,
                  icon: Icons.trending_down_rounded,
                  color: D.expense,
                  selected: isExpense,
                  onTap: () => setState(() => _type = 'expense'),
                ),
              ),
              const SizedBox(width: D.s3),
              Expanded(
                child: _TypeCard(
                  label: 'Pemasukan',
                  count: incomeActive.length,
                  icon: Icons.trending_up_rounded,
                  color: D.income,
                  selected: !isExpense,
                  onTap: () => setState(() => _type = 'income'),
                ),
              ),
            ],
          ),
          const SizedBox(height: D.s6),
          _SectionHeader('${isExpense ? 'Pengeluaran' : 'Pemasukan'} '
              '(${active.length})'),
          ...active.map((c) => _CategoryTile(
                category: c,
                onEdit: () => _openForm(c.id),
                // cat_other/_income adalah fallback form — jangan diarsipkan.
                onArchive: c.id == fallbackId
                    ? null
                    : () => _archive(ref, c),
              )),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: D.s4),
            _SectionHeader('Diarsipkan (${archived.length})'),
            ...archived.map((c) => _CategoryTile(
                  category: c,
                  dimmed: true,
                  onRestore: () => _unarchive(ref, c),
                )),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

/// Card pemilih jenis kategori — terpilih ditandai border & tint warna jenis.
class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(D.s3),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : D.card,
          borderRadius: BorderRadius.circular(D.rMd),
          border: Border.all(
            color: selected ? color : D.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: selected ? color : D.inkMuted),
            const SizedBox(height: D.s3),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: selected ? D.ink : D.inkMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count kategori',
              style: const TextStyle(fontSize: 11.5, color: D.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: D.s1, bottom: D.s2),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: D.inkMuted,
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    this.dimmed = false,
    this.onEdit,
    this.onArchive,
    this.onRestore,
  });

  final Category category;
  final bool dimmed;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category.id);
    return Card(
      margin: const EdgeInsets.only(bottom: D.s2),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(getIcon(category.icon), color: color, size: 20),
        ),
        title: Text(
          category.name,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: dimmed ? D.inkMuted : D.ink,
          ),
        ),
        trailing: onRestore != null
            ? TextButton(
                onPressed: onRestore,
                child: const Text('Aktifkan lagi'),
              )
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: D.inkMuted),
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'archive') onArchive?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit', child: Text('Ubah')),
                  if (onArchive != null)
                    const PopupMenuItem(
                        value: 'archive', child: Text('Arsipkan')),
                ],
              ),
      ),
    );
  }
}
