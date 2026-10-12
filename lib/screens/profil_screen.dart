import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/database_provider.dart';
import '../services/backup_service.dart';
import '../services/lock_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_info.dart';
import '../widgets/confirm_dialog.dart';
import 'categories_screen.dart';
import 'brand_list_screen.dart';

class ProfilScreen extends ConsumerStatefulWidget {
  const ProfilScreen({super.key});

  @override
  ConsumerState<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends ConsumerState<ProfilScreen> {
  bool _biometricEnabled = false;
  bool _canAuthenticate = false;
  bool _hasBiometric = false;
  bool _checkingBiometric = true;
  LockMode _lockMode = LockMode.both;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final enabled = await LockService.isEnabled();
    final can = await LockService.canAuthenticate();
    final hasBio = await LockService.hasBiometric();
    final mode = await LockService.getMode();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
      _canAuthenticate = can;
      _hasBiometric = hasBio;
      _lockMode = mode;
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
            icon: Icons.label_rounded,
            title: 'Kelola kategori',
            subtitle: 'Tambah, ubah, dan arsipkan kategori',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CategoriesScreen()),
            ),
          ),
          _ActionTile(
            icon: Icons.account_balance_rounded,
            title: 'Kelola brand bank & e-wallet',
            subtitle: 'Atur pilihan bank, e-wallet & kartu',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const BrandKindScreen()),
            ),
          ),

          // ── Keamanan & Privasi ──
          const SizedBox(height: D.s6),
          _SectionHeader('Keamanan & Privasi'),
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
          Card(
            margin: const EdgeInsets.symmetric(
              horizontal: D.s1,
              vertical: D.s1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(D.rSm),
            ),
            child: ListTile(
              leading: const Icon(Icons.visibility_off_rounded, color: D.cobalt),
              title: const Text(
                'Mode privasi',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Sembunyikan nominal uang di Beranda',
                style: TextStyle(fontSize: 12),
              ),
              trailing: Switch(
                value: ref.watch(privacyModeProvider),
                onChanged: (value) => setPrivacyMode(ref, value),
              ),
            ),
          ),
          // Metode kunci hanya relevan saat kunci app aktif.
          if (_biometricEnabled) ...[
            _ActionTile(
              icon: Icons.lock_outline_rounded,
              title: 'Metode kunci',
              subtitle: _lockMode.label,
              onTap: () => _pickLockMode(context),
            ),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              title: 'PIN & sidik jari perangkat',
              subtitle: 'Diatur di Pengaturan Keamanan HP',
              onTap: () => _showDeviceCredentialInfo(context),
            ),
          ],
          _ActionTile(
            icon: Icons.settings_backup_restore_rounded,
            title: 'Reset pengaturan',
            subtitle: 'Matikan mode privasi & kunci app',
            danger: true,
            onTap: () => _doResetSettings(context),
          ),

          // ── Hapus data ──
          const SizedBox(height: D.s6),
          _SectionHeader('Hapus data'),
          _ActionTile(
            icon: Icons.delete_forever_rounded,
            title: 'Hapus semua data',
            subtitle: 'Transaksi, tagihan, wallet & brand custom',
            danger: true,
            onTap: () => _doWipe(context),
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
              'MyDuit v$appVersion',
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
    String? path;
    String? error;
    try {
      path = await BackupService.backupToLocation(db);
    } on BackupException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Gagal menyimpan backup';
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            path != null ? 'Backup tersimpan' : (error ?? 'Backup dibatalkan')),
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
          'Semua data saat ini akan DIGANTI dengan isi file backup. '
          'Salinan data sekarang otomatis dibuat untuk jaga-jaga.',
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

    RestoreResult result;
    try {
      result = await BackupService.restoreFromFile(ref);
    } catch (_) {
      result = (restored: false, error: 'Gagal memulihkan data');
    }
    if (!context.mounted) return;
    final message = result.restored
        ? 'Data berhasil dipulihkan'
        : result.error ?? 'Pulihkan dibatalkan';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Hapus SEMUA data: konfirmasi ganda (dialog + ketik "HAPUS"),
  /// snapshot pra-wipe otomatis, lalu seed ulang bawaan.
  Future<void> _doWipe(BuildContext context) async {
    // Konfirmasi 1: dialog gaya bahaya.
    final ok = await confirmDelete(
      context,
      'Hapus SEMUA data?',
      description: 'Transaksi, tagihan, wallet, anggaran, dan brand custom '
          'akan dihapus permanen. Kategori & brand bawaan dipulihkan. '
          'Salinan cadangan otomatis dibuat untuk jaga-jaga.',
      confirmLabel: 'Lanjut',
    );
    if (!ok || !context.mounted) return;

    // Konfirmasi 2: ketik HAPUS.
    final typed = await _promptTypeToConfirm(context);
    if (typed != true || !context.mounted) return;

    final db = ref.read(dbProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final folder = await getApplicationDocumentsDirectory();
      BackupService.snapshotBeforeWipe(folder);
      await db.wipeAllData();
      ref.invalidate(dbProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Semua data dihapus'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gagal menghapus data'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Dialog kedua: pengguna wajib mengetik "HAPUS" untuk melanjutkan.
  Future<bool?> _promptTypeToConfirm(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final matches = controller.text.trim() == 'HAPUS';
            return AlertDialog(
              title: const Text('Konfirmasi terakhir'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ketik HAPUS untuk mengonfirmasi.',
                    style: TextStyle(fontSize: 13, color: D.inkMuted),
                  ),
                  const SizedBox(height: D.s3),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: 'HAPUS',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed:
                      matches ? () => Navigator.pop(ctx, true) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: D.expense,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Hapus permanen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Reset pengaturan: mode privasi + kunci biometrik. Mematikan kunci
  /// wajib autentikasi dulu (anti-prank, konsisten dengan toggle).
  Future<void> _doResetSettings(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset pengaturan?'),
        content: const Text(
          'Mode privasi dan kunci biometrik akan dimatikan. '
          'Data keuangan tidak terpengaruh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: D.expense),
            child: const Text('Ya, reset'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Anti-prank: minta auth bila kunci sedang aktif.
    if (_biometricEnabled) {
      final ok = await LockService.authenticate();
      if (!ok || !mounted) return;
    }

    await setPrivacyMode(ref, false);
    await LockService.setEnabled(false);
    await LockService.setMode(LockMode.both);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = false;
      _lockMode = LockMode.both;
    });
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Pengaturan direset'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Bottom sheet pilih metode kunci. Opsi `biometric` disembunyikan
  /// (nonaktif) bila perangkat tak punya biometrik — cegah terkunci total.
  Future<void> _pickLockMode(BuildContext context) async {
    final selected = await showModalBottomSheet<LockMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(D.s4, 0, D.s4, D.s2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Metode kunci',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final mode in LockMode.values)
              Builder(
                builder: (_) {
                  final allowed = LockService.isModeAllowed(
                    mode,
                    hasBiometric: _hasBiometric,
                  );
                  return RadioListTile<LockMode>(
                    value: mode,
                    groupValue: _lockMode,
                    onChanged: allowed
                        ? (v) => Navigator.pop(ctx, v)
                        : null,
                    title: Text(mode.label),
                    subtitle: allowed
                        ? null
                        : const Text(
                            'Perangkat belum terdaftar biometrik',
                            style: TextStyle(fontSize: 12, color: D.inkMuted),
                          ),
                  );
                },
              ),
            const SizedBox(height: D.s3),
          ],
        ),
      ),
    );

    if (selected == null || selected == _lockMode) return;
    await LockService.setMode(selected);
    if (!mounted) return;
    setState(() => _lockMode = selected);
  }

  /// Jelaskan bahwa PIN/fingerprint milik OS, bukan disimpan app.
  Future<void> _showDeviceCredentialInfo(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN & sidik jari perangkat'),
        content: const Text(
          'MyDuit tidak menyimpan PIN atau data sidik jari. Verifikasi '
          'memakai keamanan HP-mu (sidik jari/PIN/pattern). Untuk mengubah '
          'atau menambahnya, buka Pengaturan HP → Keamanan → Kunci layar.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
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
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? D.expense : D.cobalt;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: D.s1,
        vertical: D.s1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(D.rSm),
      ),
      child: ListTile(
        leading: Icon(icon, color: tint),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: danger ? D.expense : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: danger ? D.expense : D.inkMuted,
        ),
        onTap: onTap,
      ),
    );
  }
}
