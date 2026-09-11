import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/services/backup_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('validateBackupFile', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('backup_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('file kosong → gagal', () {
      expect(BackupService.validateBackupFile([]), isNotNull);
    });

    test('file non-SQLite → gagal', () {
      final bytes = List<int>.filled(100, 0x41); // 'A' repeated
      expect(BackupService.validateBackupFile(bytes), isNotNull);
    });

    test('SQLite valid tanpa tabel wajib → gagal', () {
      // Buat SQLite in-memory, export bytes-nya
      final tempDb = sqlite3.openInMemory();
      tempDb.execute('CREATE TABLE dummy (id INTEGER)');
      tempDb.execute('PRAGMA database_list');
      // Salin ke file via .export
      final filePath = '${tmpDir.path}/empty.sqlite';
      tempDb.execute("VACUUM INTO '$filePath'");
      tempDb.dispose();

      final bytes = File(filePath).readAsBytesSync();
      expect(BackupService.validateBackupFile(bytes), isNotNull);
    });

    /// SQLite dengan tabel wajib + user_version tertentu.
    File writeFixture(String name, int userVersion) {
      final tempDb = sqlite3.openInMemory();
      tempDb.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY)');
      tempDb.execute(
          'CREATE TABLE transactions (id TEXT PRIMARY KEY, account_id TEXT)');
      tempDb.execute(
          'CREATE TABLE bills (id TEXT PRIMARY KEY, account_id TEXT)');
      if (userVersion > 0) {
        tempDb.execute('PRAGMA user_version = $userVersion');
      }
      final filePath = '${tmpDir.path}/$name';
      tempDb.execute("VACUUM INTO '$filePath'");
      tempDb.dispose();
      return File(filePath);
    }

    test('SQLite valid dengan tabel lengkap + user_version → lolos', () {
      final bytes =
          writeFixture('valid.sqlite', MyDuitDatabase.currentSchemaVersion)
              .readAsBytesSync();
      expect(BackupService.validateBackupFile(bytes), isNull);
    });

    test('user_version 0 (bukan backup drift) → gagal', () {
      final bytes =
          writeFixture('uv0.sqlite', 0).readAsBytesSync();
      expect(BackupService.validateBackupFile(bytes), 'Bukan backup MyDuit');
    });

    test('user_version lebih baru dari app → gagal', () {
      final bytes = writeFixture('uv99.sqlite', 99).readAsBytesSync();
      expect(BackupService.validateBackupFile(bytes), contains('lebih baru'));
    });

    test('user_version lebih lama → lolos (migrasi otomatis)', () {
      final bytes = writeFixture('uv5.sqlite', 5).readAsBytesSync();
      expect(BackupService.validateBackupFile(bytes), isNull);
    });
  });

  group('snapshotCurrentDb', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('snapshot_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('DB belum ada → null, tanpa file', () {
      expect(BackupService.snapshotCurrentDb(tmpDir), isNull);
    });

    test('DB ada → tersalin, snapshot lama dibuang', () async {
      File('${tmpDir.path}/myduit.sqlite').writeAsBytesSync([1, 2, 3]);
      final old = File('${tmpDir.path}/myduit_pre_restore_lama.sqlite')
        ..writeAsBytesSync([0]);

      final snap = BackupService.snapshotCurrentDb(tmpDir);
      expect(snap, isNotNull);
      expect(snap!.readAsBytesSync(), [1, 2, 3]);
      expect(old.existsSync(), isFalse);
      expect(
          tmpDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('_pre_restore_'))
              .length,
          1);
    });
  });
}
