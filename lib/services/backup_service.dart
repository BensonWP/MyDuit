import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../providers/database_provider.dart';

/// Service backup/restore/export SQLite database.
class BackupService {
  BackupService._();

  /// Jalankan WAL checkpoint agar file yang disalin lengkap
  /// (wal + shm sudah flush ke db utama).
  static Future<void> _checkpoint(MyDuitDatabase db) async {
    try {
      await db.customStatement('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {
      // WAL mode mungkin belum aktif — abaikan.
    }
  }

  // ── BACKUP ──────────────────────────────────────────────────────

  /// Backup database ke lokasi pilihan user via SAF.
  /// Return: path file yang tersimpan, atau null jika batal.
  static Future<String?> backupToLocation(MyDuitDatabase db) async {
    await _checkpoint(db);

    final dbFolder = await getApplicationDocumentsDirectory();
    final srcFile = File('${dbFolder.path}/myduit.sqlite');
    if (!srcFile.existsSync()) return null;

    final now = DateTime.now();
    final fileName =
        'myduit-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.sqlite';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan backup MyDuit',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );

    if (result == null) return null;

    final destFile = File(result);
    await destFile.writeAsBytes(await srcFile.readAsBytes(), flush: true);
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
  /// Return: true jika berhasil, false jika batal/gagal.
  static Future<bool> restoreFromFile(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pilih file backup MyDuit',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );

    if (result == null || result.files.isEmpty) return false;

    final pickedFile = result.files.first;
    final bytes = pickedFile.bytes ?? await File(pickedFile.path!).readAsBytes();

    // Validasi
    final error = validateBackupFile(bytes);
    if (error != null) return false;

    // Tutup koneksi DB aktif
    final db = ref.read(dbProvider);
    try {
      await db.close();
    } catch (_) {
      // Sudah tertutup — abaikan.
    }

    // Timpa file DB
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File('${dbFolder.path}/myduit.sqlite');
    await dbFile.writeAsBytes(bytes, flush: true);

    // Buat koneksi baru
    ref.invalidate(dbProvider);

    return true;
  }

  // ── CSV EXPORT ──────────────────────────────────────────────────

  /// Escape nilai CSV: bungkus kutip jika ada koma/newline/kutip.
  static String csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('\n') ||
        value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Ekspor semua transaksi ke CSV, simpan via SAF.
  /// Return: path file tersimpan, atau null jika batal.
  static Future<String?> exportCsv(MyDuitDatabase db) async {
    final txs = await db.watchTransactionsFiltered().first;
    final accounts = await db.select(db.accounts).get();
    final accountMap = {for (final a in accounts) a.id: a.name};

    final buf = StringBuffer();
    buf.writeln('Tanggal,Jenis,Jumlah,Wallet,Catatan');

    for (final tx in txs) {
      final date = tx.date.substring(0, 10); // YYYY-MM-DD
      final type = tx.type == 'income'
          ? 'Pemasukan'
          : tx.type == 'expense'
              ? 'Pengeluaran'
              : 'Transfer';
      final amount = tx.amount.toString();
      final wallet = csvEscape(accountMap[tx.accountId] ?? tx.accountId);
      final note = csvEscape(tx.note);
      buf.writeln('$date,$type,$amount,$wallet,$note');
    }

    final now = DateTime.now();
    final fileName =
        'myduit-transaksi-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Ekspor transaksi MyDuit',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null) return null;

    await File(result).writeAsString(buf.toString(), flush: true);
    return result;
  }
}
