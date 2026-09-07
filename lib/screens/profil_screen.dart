import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_provider.dart';
import '../services/backup_service.dart';
import '../services/lock_service.dart';
import '../theme/app_theme.dart';

class ProfilScreen extends ConsumerStatefulWidget {
  const ProfilScreen({super.key});

  @override
  ConsumerState<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends ConsumerState<ProfilScreen> {
  bool _biometricEnabled = false;
  bool _canAuthenticate = false;
  bool _checkingBiometric = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final enabled = await LockService.isEnabled();
    final can = await LockService.canAuthenticate();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _canAuthenticate = can;
      _checkingBiometric = false;
    });
  }

  Future<void> _toggleBiometric(bool value) async {
    // Menyalakan: wajib autentikasi dulu (anti-prank).
    if (value) {
      final ok = await LockService.authenticate();
      if (!ok || !mounted) return;
    }
    await LockService.setEnabled(value);
    if (!mounted) return;
    setState(() => _biometricEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: D.s4,
          vertical: D.s3,
        ),
        children: [
          // ── Data ──
          _SectionHeader('Data'),
          _ActionTile(
            icon: Icons.cloud_upload_outlined,
            title: 'Backup ke penyimpanan',
            subtitle: 'Simpan salinan database ke Drive / folder lokal',
            onTap: () => _doBackup(context),
          ),
          _ActionTile(
            icon: Icons.cloud_download_outlined,
            title: 'Pulihkan dari backup',
            subtitle: 'Timpa data saat ini dengan file cadangan',
            onTap: () => _doRestore(context),
          ),
          _ActionTile(
            icon: Icons.table_chart_outlined,
            title: 'Ekspor CSV',
            subtitle: 'Semua transaksi dalam format spreadsheet',
            onTap: () => _doExportCsv(context),
          ),

          // ── Keamanan ──
          const SizedBox(height: D.s6),
          _SectionHeader('Keamanan'),
          if (_checkingBiometric)
            const Padding(
              padding: EdgeInsets.all(D.s4),
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: D.s1,
                vertical: D.s1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(D.rSm),
              ),
              child: ListTile(
                leading: const Icon(Icons.fingerprint_rounded, color: D.cobalt),
                title: const Text(
                  'Kunci app dengan sidik jari/PIN',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _canAuthenticate
                      ? 'App terkunci saat dibuka & saat ditinggal >30 dtk'
                      : 'Perangkat tidak mendukung biometrik/PIN',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Switch(
                  value: _biometricEnabled,
                  onChanged: _canAuthenticate ? _toggleBiometric : null,
                ),
              ),
            ),

          // ── Tentang ──
          const SizedBox(height: D.s6),
          _SectionHeader('Tentang'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: D.s4,
              vertical: D.s3,
            ),
            child: Text(
              'MyDuit v1.1.0',
              style: TextStyle(
                fontSize: 14,
                color: D.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doBackup(BuildContext context) async {
    final db = ref.read(dbProvider);
    final path = await BackupService.backupToLocation(db);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null ? 'Backup tersimpan' : 'Backup dibatalkan'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _doRestore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pulihkan data?'),
        content: const Text(
          'Semua data saat ini akan DIGANTikan dengan isi file backup. '
          'Tindakan ini tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: D.expense,
            ),
            child: const Text('Ya, pulihkan'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    final success = await BackupService.restoreFromFile(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Data berhasil dipulihkan'
            : 'Pulihkan dibatalkan atau file tidak valid'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _doExportCsv(BuildContext context) async {
    final db = ref.read(dbProvider);
    final path = await BackupService.exportCsv(db);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null ? 'CSV tersimpan' : 'Ekspor dibatalkan'),
        duration: const Duration(seconds: 2),
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
      padding: const EdgeInsets.only(
        left: D.s4,
        top: D.s4,
        bottom: D.s1,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: D.inkMuted,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: D.s1,
        vertical: D.s1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(D.rSm),
      ),
      child: ListTile(
        leading: Icon(icon, color: D.cobalt),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: D.inkMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}
