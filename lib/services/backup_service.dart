import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../providers/database_provider.dart';

/// Hasil pulihkan: [restored] = sukses; [error] = pesan kegagalan
/// (null saat batal, berisi alasan saat file tidak valid).
typedef RestoreResult = ({bool restored, String? error});

/// Exception dengan pesan siap-tampil ke pengguna.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Service backup/restore/export SQLite database.
class BackupService {
  BackupService._();

  /// Jalankan WAL checkpoint agar file yang disalin lengkap
  /// (wal + shm sudah flush ke db utama).
  static Future<void> _checkpoint(MyDuitDatabase db,
      {String mode = 'FULL'}) async {
    try {
      await db.customStatement('PRAGMA wal_checkpoint($mode)');
    } catch (_) {
      // WAL mode mungkin belum aktif — abaikan.
    }
  }

  /// Stamp nama file dengan jam: dua backup/ekspor dalam satu hari
  /// tidak saling menimpa.
  static String _stamp() {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${p(now.month)}-${p(now.day)}-${p(now.hour)}${p(now.minute)}';
  }

  // ── BACKUP ──────────────────────────────────────────────────────

  /// Backup database ke lokasi pilihan user via SAF.
  /// Return: path file yang tersimpan, atau null jika batal.
  /// file_picker 10.x MEWAJIBKAN `bytes` di Android/iOS — tanpa itu
  /// ArgumentError dilempar sebelum dialog muncul. Plugin yang menulis
  /// data (SAF di Android, dialog+write di desktop).
  static Future<String?> backupToLocation(MyDuitDatabase db) async {
    await _checkpoint(db);

    final dbFolder = await getApplicationDocumentsDirectory();
    final srcFile = File('${dbFolder.path}/myduit.sqlite');
    if (!srcFile.existsSync()) {
      throw BackupException('Database belum ada — catat transaksi dulu');
    }
    final bytes = await srcFile.readAsBytes();

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan backup MyDuit',
      fileName: 'myduit-backup-${_stamp()}.sqlite',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
      bytes: bytes,
    );
    return result;
  }

  // ── VALIDATE ────────────────────────────────────────────────────

  /// Validasi file backup: header SQLite + tabel wajib ada.
  /// Return null jika valid, pesan error jika tidak.
  static String? validateBackupFile(List<int> bytes) {
    // Cek header "SQLite format 3\0"
    if (bytes.length < 16) return 'File terlalu kecil';
    final header = String.fromCharCodes(bytes.sublist(0, 15));
    if (header != 'SQLite format 3') return 'Bukan file SQLite';

    try {
      // Salin bytes ke file sementara untuk dibuka via sqlite3
      final tmpDir = Directory.systemTemp;
      final tmpFile = File('${tmpDir.path}/myduit_validate_${DateTime.now().millisecondsSinceEpoch}.sqlite');
      tmpFile.writeAsBytesSync(bytes);

      final validated = sqlite3.open(tmpFile.path);
      try {
        final tables = validated
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name'] as String)
            .toSet();

        const required = {'accounts', 'transactions', 'bills'};
        final missing = required.difference(tables);
        if (missing.isNotEmpty) {
          return 'Tabel tidak lengkap: ${missing.join(', ')}';
        }

        // Drift selalu mengisi user_version dengan versi skema. 0 = DB
        // buatan lain; di atas skema app = backup dari versi lebih baru
        // (drift akan gagal buka → app tampak kosong). Versi lebih lama
        // lolos — migrasi otomatis saat dibuka.
        final uv =
            validated.select('PRAGMA user_version').first['user_version']
                as int;
        if (uv == 0) return 'Bukan backup MyDuit';
        if (uv > MyDuitDatabase.currentSchemaVersion) {
          return 'Backup dibuat dari versi MyDuit yang lebih baru — '
              'perbarui aplikasi dulu';
        }

        final integrity = validated.select('PRAGMA integrity_check');
        if (integrity.isNotEmpty &&
            integrity.first['integrity_check'] != 'ok') {
          return 'Integrity check gagal';
        }
      } finally {
        validated.dispose();
        tmpFile.deleteSync();
      }
    } catch (e) {
      return 'Gagal membuka file: $e';
    }
    return null;
  }

  // ── RESTORE ─────────────────────────────────────────────────────

  /// Restore database dari file pilihan user via SAF.
  /// Batal → (restored: false, error: null).
  /// File tidak valid → error berisi pesan validasi.
  static Future<RestoreResult> restoreFromFile(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih file backup MyDuit',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );

    if (result == null || result.files.isEmpty) {
      return (restored: false, error: null);
    }

    final pickedFile = result.files.first;
    final bytes = pickedFile.bytes ?? await File(pickedFile.path!).readAsBytes();

    // Validasi SEBELUM menyentuh DB aktif.
    final error = validateBackupFile(bytes);
    if (error != null) return (restored: false, error: error);

    // Flush WAL ke file utama agar snapshot pra-restore tidak kehilangan
    // transaksi yang masih tertahan di WAL.
    final db = ref.read(dbProvider);
    await _checkpoint(db, mode: 'TRUNCATE');
    try {
      await db.close();
    } catch (_) {
      // Sudah tertutup — abaikan.
    }

    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File('${dbFolder.path}/myduit.sqlite');
    // Snapshot data saat ini sebelum ditimpa — kalau salah pilih file,
    // pengguna masih bisa pulih dari berkas ini.
    snapshotCurrentDb(dbFolder);
    // WAL/SHM sisa koneksi lama WAJIB dibuang — WAL lama yang masih berisi
    // halaman database bisa diterapkan ke file backup yang baru dan
    // mengkorupsi datanya.
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${dbFile.path}$suffix');
      if (sidecar.existsSync()) sidecar.deleteSync();
    }
    await dbFile.writeAsBytes(bytes, flush: true);

    // Buat koneksi baru
    ref.invalidate(dbProvider);

    return (restored: true, error: null);
  }

  /// Salin DB saat ini ke `myduit_pre_restore_<stamp>.sqlite`, ganti snapshot
  /// lama (cukup satu — yang terbaru yang berguna). Return null bila DB
  /// belum ada (install pertama).
  static File? snapshotCurrentDb(Directory folder) {
    final dbFile = File('${folder.path}/myduit.sqlite');
    if (!dbFile.existsSync()) return null;
    for (final old in folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('_pre_restore_'))) {
      old.deleteSync();
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 19)
        .replaceAll(':', '')
        .replaceAll('T', '_');
    final snap = File('${folder.path}/myduit_pre_restore_$stamp.sqlite');
    dbFile.copySync(snap.path);
    return snap;
  }
}
