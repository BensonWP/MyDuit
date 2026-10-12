import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../utils/wallet_brand.dart';
import '../widgets/confirm_dialog.dart';
import 'brand_form_screen.dart';

/// Label jenis brand (dipakai halaman pilih jenis & judul daftar).
String brandKindLabel(String kind) => switch (kind) {
      'bank' => 'Bank',
      'ewallet' => 'E-Wallet',
      'card' => 'Kartu',
      _ => 'Brand',
    };

/// Halaman awal Kelola Brand: pilih jenis dulu agar mudah dicari.
/// Tiap kartu menampilkan jumlah brand jenis itu; tap → daftar tersaring.
class BrandKindScreen extends ConsumerWidget {
  const BrandKindScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(brandsProvider).valueOrNull ?? const [];
    int count(String kind) =>
        brands.where((b) => b.kind == kind).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Kelola brand bank & e-wallet')),
      body: ListView(
        padding: const EdgeInsets.all(D.s4),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: D.s1, bottom: D.s4),
            child: Text(
              'Pilih jenis brand yang ingin diatur.',
              style: TextStyle(fontSize: 13, color: D.inkMuted, height: 1.4),
            ),
          ),
          _KindCard(
            kind: 'bank',
            icon: Icons.account_balance_rounded,
            color: const Color(0xFF2196F3),
            count: count('bank'),
          ),
          _KindCard(
            kind: 'ewallet',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFF00BCD4),
            count: count('ewallet'),
          ),
          _KindCard(
            kind: 'card',
            icon: Icons.credit_card_rounded,
            color: const Color(0xFF607D8B),
            count: count('card'),
          ),
          const SizedBox(height: D.s4),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const BrandListScreen()),
            ),
            icon: const Icon(Icons.list_rounded, size: 18),
            label: Text('Lihat semua brand (${brands.length})'),
          ),
        ],
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.icon,
    required this.color,
    required this.count,
  });

  final String kind;
  final IconData icon;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: D.s3),
      child: InkWell(
        borderRadius: BorderRadius.circular(D.rMd),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BrandListScreen(kind: kind)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(D.s4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: D.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brandKindLabel(kind),
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count brand',
                      style: const TextStyle(
                          fontSize: 12.5, color: D.inkMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: D.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Daftar brand master. Bila [kind] diisi → tersaring satu jenis (dengan
/// judul sesuai), else semua jenis dalam seksi. Tambah/ubah/hapus di sini.
/// Entri dari tile "Kelola brand" di Profil.
class BrandListScreen extends ConsumerWidget {
  const BrandListScreen({super.key, this.kind});

  /// 'bank' | 'ewallet' | 'card' — null = semua jenis.
  final String? kind;

  /// Hapus brand: blokir bila masih dipakai wallet. Warning menampilkan
  /// daftar wallet pemakai beserta saldonya.
  Future<void> _delete(
      BuildContext context, WidgetRef ref, CustomBrand brand) async {
    final db = ref.read(dbProvider);
    final wallets = await db.brandWallets(brand.id);
    if (!context.mounted) return;

    if (wallets.isNotEmpty) {
      final lines = wallets
          .map((w) => '• ${w.$1.name} (${formatRupiah(w.$2)})')
          .join('\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Tidak bisa hapus ${brand.name}'),
          content: Text(
            'Brand ini masih dipakai ${wallets.length} dompet:\n\n$lines\n\n'
            'Hapus atau pindahkan dompet tersebut dulu di layar Dompet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await confirmDelete(
      context,
      'Hapus ${brand.name}?',
      description: brand.builtin
          ? 'Brand bawaan ini dihapus dari daftar. Dompet baru tak bisa '
              'memilihnya lagi.'
          : 'Brand ini dihapus permanen.',
    );
    if (!confirmed) return;
    try {
      await db.deleteBrand(brand.id);
    } on ArgumentError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(brandsProvider).valueOrNull ?? const [];
    final filtered =
        kind == null ? all : all.where((b) => b.kind == kind).toList();

    return Scaffold(
      appBar: AppBar(
          title: Text(kind == null ? 'Semua Brand' : brandKindLabel(kind!))),
      body: filtered.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(D.s8),
              child: Center(
                child: Text(
                  'Belum ada brand ${kind == null ? '' : brandKindLabel(kind!)}.\n'
                  'Tambahkan dengan tombol +.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: D.inkMuted, height: 1.5),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(D.s4),
              children: [
                if (kind != null)
                  ...filtered.map((b) => _BrandTile(
                        brand: b,
                        onEdit: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  BrandFormScreen(brandId: b.id)),
                        ),
                        onDelete: () => _delete(context, ref, b),
                      ))
                else ...[
                  ..._section(context, ref, 'Bank', 'bank', all),
                  ..._section(context, ref, 'E-Wallet', 'ewallet', all),
                  ..._section(context, ref, 'Kartu', 'card', all),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => BrandFormScreen(initialKind: kind)),
        ),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  List<Widget> _section(BuildContext context, WidgetRef ref, String title,
      String kind, List<CustomBrand> all) {
    final items = all.where((b) => b.kind == kind).toList();
    if (items.isEmpty) return const [];
    return [
      _SectionHeader('$title (${items.length})'),
      ...items.map((b) => _BrandTile(
            brand: b,
            onEdit: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BrandFormScreen(brandId: b.id)),
            ),
            onDelete: () => _delete(context, ref, b),
          )),
      const SizedBox(height: D.s4),
    ];
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

class _BrandTile extends StatelessWidget {
  const _BrandTile({
    required this.brand,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomBrand brand;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: D.s2),
      child: ListTile(
        leading: brand.logo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(brand.logo!,
                    width: 40, height: 40, fit: BoxFit.cover),
              )
            : BrandInitial(label: brand.name, hex: brand.hex, size: 40),
        title: Row(
          children: [
            Flexible(
              child: Text(
                brand.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (brand.builtin) ...[
              const SizedBox(width: D.s2),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: D.cobalt.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Bawaan',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: D.cobalt,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: D.inkMuted),
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Ubah')),
            PopupMenuItem(value: 'delete', child: Text('Hapus')),
          ],
        ),
      ),
    );
  }
}
