import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

part 'database.g.dart';

// ─── Tables ────────────────────────────────────────────────────────

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();
  TextColumn get color => text().withDefault(const Constant('#4CAF50'))();

  /// Brand e-wallet: 'gopay'|'ovo'|'dana'|'shopeepay' (sisanya via Kelola Brand).
  /// Null untuk tipe lain / wallet lama → tampil ikon generik.
  TextColumn get brand => text().nullable()();
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  TextColumn get icon => text().withDefault(const Constant('category'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Index hot path: filter rentang tanggal (chart 7 hari, laporan) dan
/// saldo per wallet. ponytail: FK child lain (bill_payments.bill_id,
/// budgets.category_id) belum diindex — jumlah barisnya kecil.
@TableIndex(name: 'idx_transactions_date', columns: {#date})
@TableIndex(name: 'idx_transactions_account', columns: {#accountId})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get toAccountId => text().nullable().references(Accounts, #id)();
  TextColumn get type => text().withDefault(const Constant('expense'))();
  IntColumn get amount => integer().withDefault(const Constant(0))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get date => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get accountId => text().references(Accounts, #id)();
  IntColumn get amount => integer().withDefault(const Constant(0))();
  IntColumn get dueDay => integer().withDefault(const Constant(1))();

  /// Lama tagihan dalam berapa kali pembayaran bulanan.
  /// 0 = berulang tanpa batas (langganan). N = cicilan N bulan →
  /// otomatis nonaktif saat pembayaran ke-N (jadi histori).
  IntColumn get durationMonths => integer().withDefault(const Constant(0))();

  /// True saat pembayaran ke-N (cicilan lunas) — pembeda dari
  /// nonaktif manual. Histori: tetap tersimpan, tak jadi tagihan lagi.
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class BillPayments extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get paidAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().unique().references(Categories, #id)();
  IntColumn get monthlyAmount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Master brand wallet — SEMUA brand (bawaan & custom) ada di sini.
/// Bawaan di-seed sekali saat migrasi v11 ([builtin] = 1, logo null lalu
/// di-backfill dari asset di layer app) sehingga bisa diedit/dihapus seperti
/// custom. Logo opsional disimpan blob PNG 192px (bukan file lepas) agar
/// backup/restore file-level tetap utuh otomatis.
class CustomBrands extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('bank'))();
  TextColumn get hex => text().withDefault(const Constant('#607D8B'))();
  BlobColumn get logo => blob().nullable()();

  /// 1 = hasil seed brand bawaan (untuk badge & backfill logo asset).
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();

  /// Urutan tampil (bawaan diberi nomor; custom 0 = urut nama).
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Baris hasil watchActiveBillsDetailed — bukan tabel, hanya DTO query.
/// Tagihan aktif + status bayar dari SATU query: daftar tagihan dan
/// proyeksi tak bisa lagi melihat data beda frame.
class ActiveBillRow {
  const ActiveBillRow({
    required this.bill,
    required this.paidMonths,
    required this.paidThisMonth,
  });

  final Bill bill;
  final int paidMonths; // jumlah bulan berbeda yang sudah dibayar
  final bool paidThisMonth;
}

/// Baris hasil watchBudgets — anggaran + info kategori (DTO query).
typedef BudgetInfo = ({
  String id,
  String categoryId,
  String name,
  String icon,
  String type,
  int monthlyAmount,
});

/// Snapshot untuk urungkan hapus transaksi (lihat captureTransactionUndo).
typedef TransactionUndo = ({
  Transaction tx,
  List<BillPayment> payments,
  Map<String, ({bool active, bool completed})> billStates,
});

/// Snapshot untuk urungkan hapus tagihan (lihat captureBillUndo).
typedef BillUndo = ({Bill bill, List<BillPayment> payments});

/// Dilempar saat pengeluaran/bayar tagihan ditolak karena saldo wallet
/// tidak cukup — wallet tidak boleh minus.
class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException({
    required this.accountId,
    required this.balance,
    required this.required,
  });

  final String accountId;
  final int balance;
  final int required;

  /// Selisih kurangnya (selalu > 0).
  int get short => required - balance;
}

// ─── Database ──────────────────────────────────────────────────────

@DriftDatabase(
    tables: [
  Accounts,
  Categories,
  Transactions,
  Bills,
  BillPayments,
  Budgets,
  CustomBrands
])
class MyDuitDatabase extends _$MyDuitDatabase {
  MyDuitDatabase() : super(_openConnection());

  MyDuitDatabase.testing() : super(NativeDatabase.memory());

  /// Versi skema saat ini — juga dibaca BackupService untuk menolak
  /// backup dari app yang lebih baru (lihat validateBackupFile).
  static const int currentSchemaVersion = 11;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
          await seedBuiltinBrands();
        },
        onUpgrade: (m, from, to) async {
          if (from == 1) {
            await customStatement(
              "UPDATE categories SET type = 'income' WHERE id IN ('cat_salary', 'cat_sidejob')",
            );
          }
          if (from < 3) {
            await m.createTable(budgets);
          }
          if (from < 4) {
            await m.addColumn(accounts, accounts.brand);
          }
          if (from < 5) {
            await m.addColumn(bills, bills.durationMonths);
            await m.addColumn(bills, bills.completed);
          }
          if (from < 7) {
            await m.createIndex(idxTransactionsDate);
            await m.createIndex(idxTransactionsAccount);
          }
          // v8: fitur Rencana dicabut — tabel dibuang, datanya hilang.
          if (from < 8) {
            await customStatement('DROP TABLE IF EXISTS plans');
          }
          // v9: master brand wallet buatan user.
          if (from < 9) {
            await m.createTable(customBrands);
          }
          // v10: kategori pemasukan diperbaiki. Install baru sebelumnya
          // men-seed semuanya sebagai expense (cat_salary/cat_sidejob
          // salah tipe, daftar income kosong) — perbaiki di sini agar
          // DB lama ikut sembuh, plus fallback income untuk form.
          if (from < 10) {
            await customStatement(
              "UPDATE categories SET type = 'income' WHERE id IN ('cat_salary', 'cat_sidejob')",
            );
            await customStatement(
              "INSERT OR IGNORE INTO categories(id, name, type, icon, archived) VALUES ('cat_other_income', 'Lainnya', 'income', 'more_horiz', 0)",
            );
            // Transaksi income yang terlanjur menunjuk fallback expense
            // (lihat TransactionForm sebelum v10) dipindah ke fallback income.
            await customStatement(
              "UPDATE transactions SET category_id = 'cat_other_income' WHERE type = 'income' AND category_id = 'cat_other'",
            );
          }
          // v11: Kelola Brand jadi master data penuh — semua brand (bawaan
          // & custom) pindah ke DB, plus jenis 'card'. Logo bawaan
          // di-backfill dari asset di layer app (DB tak bisa rootBundle).
          if (from < 11) {
            await m.addColumn(customBrands, customBrands.builtin);
            await m.addColumn(customBrands, customBrands.sortOrder);
            await seedBuiltinBrands();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedCategories() async {
    final presets = [
      (id: 'cat_food', name: 'Makanan', type: 'expense', icon: 'restaurant'),
      (id: 'cat_transport', name: 'Transportasi', type: 'expense', icon: 'directions_car'),
      (id: 'cat_bills', name: 'Tagihan', type: 'expense', icon: 'receipt'),
      (id: 'cat_shopping', name: 'Belanja', type: 'expense', icon: 'shopping_bag'),
      (id: 'cat_health', name: 'Kesehatan', type: 'expense', icon: 'local_hospital'),
      (id: 'cat_education', name: 'Pendidikan', type: 'expense', icon: 'school'),
      (id: 'cat_entertainment', name: 'Hiburan', type: 'expense', icon: 'movie'),
      (id: 'cat_salary', name: 'Gaji', type: 'income', icon: 'work'),
      (id: 'cat_sidejob', name: 'Pekerjaan Sampingan', type: 'income', icon: 'laptop'),
      (id: 'cat_other', name: 'Lainnya', type: 'expense', icon: 'more_horiz'),
      (id: 'cat_other_income', name: 'Lainnya', type: 'income', icon: 'more_horiz'),
    ];
    await batch((b) {
      b.insertAll(
        categories,
        presets
            .map((c) => CategoriesCompanion.insert(
                  id: c.id,
                  name: c.name,
                  type: Value(c.type),
                  icon: Value(c.icon),
                ))
            .toList(),
      );
    });
  }

  // ─── Account queries ───────────────────────────────────────────

  Future<List<Account>> allAccounts() => (select(accounts)..where((a) => a.archived.equals(false))).get();

  Stream<List<Account>> watchAllAccounts() =>
      (select(accounts)..where((a) => a.archived.equals(false))..orderBy([(a) => OrderingTerm.asc(a.name)])).watch();

  Stream<Account?> watchAccount(String id) =>
      (select(accounts)..where((a) => a.id.equals(id))).watchSingleOrNull();

  Future<void> insertAccount(AccountsCompanion entry) => into(accounts).insert(entry);

  Future<void> updateAccount(AccountsCompanion entry) => into(accounts).insertOnConflictUpdate(entry);

  /// Arsipkan wallet (soft delete): transaksi/tagihan tetap utuh, tapi
  /// wallet hilang dari daftar & total saldo. Reversibel — arsip adalah
  /// "undo" bawaan, jadi hapus-arsip tak perlu konfirmasi berat.
  Future<void> archiveAccount(String id) async {
    await (update(accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(archived: Value(true)));
  }

  Future<void> unarchiveAccount(String id) async {
    await (update(accounts)..where((a) => a.id.equals(id)))
        .write(const AccountsCompanion(archived: Value(false)));
  }

  /// Wallet arsip — untuk seksi Diarsipkan. Saldo terakhir tetap bisa
  /// dihitung via [accountBalance] (fitur untuk baris arsip, bukan bug).
  Stream<List<Account>> watchArchivedAccounts() =>
      (select(accounts)..where((a) => a.archived.equals(true))..orderBy([(a) => OrderingTerm.asc(a.name)])).watch();

  // ─── Brand queries (master: bawaan + custom) ──────────────────

  /// SEMUA brand (bawaan di-seed saat migrasi + tambahan user), urut
  /// sortOrder lalu nama.
  Stream<List<CustomBrand>> watchCustomBrands() => (select(customBrands)
        ..orderBy([
          (b) => OrderingTerm.asc(b.sortOrder),
          (b) => OrderingTerm.asc(b.name),
        ]))
      .watch();

  Stream<List<CustomBrand>> watchBrandsByKind(String kind) =>
      (select(customBrands)
            ..where((b) => b.kind.equals(kind))
            ..orderBy([
              (b) => OrderingTerm.asc(b.sortOrder),
              (b) => OrderingTerm.asc(b.name),
            ]))
          .watch();

  Future<void> insertBrand(CustomBrandsCompanion entry) =>
      into(customBrands).insert(entry);

  /// Update parsial via UPDATE…WHERE (bukan insertOnConflictUpdate yang
  /// menuntut kolom wajib seperti createdAt ikut dikirim).
  Future<void> updateBrand(CustomBrandsCompanion entry) =>
      (update(customBrands)..where((b) => b.id.equals(entry.id.value)))
          .write(entry);

  /// Set logo blob brand (dipakai backfill logo bawaan dari asset).
  Future<void> setBrandLogo(String id, Uint8List logo) =>
      (update(customBrands)..where((b) => b.id.equals(id)))
          .write(CustomBrandsCompanion(logo: Value(logo)));

  /// Seed brand bawaan "top" saja (4 e-wallet + 4 bank + 5 kartu; id lama
  /// dipertahankan agar wallet lama tetap cocok). Brand lain ditambah user
  /// via Kelola Brand. INSERT OR IGNORE → brand custom user (dan brand
  /// bawaan lama yang masih ada di DB pengguna lawas) tak tertimpa saat
  /// upgrade/restore. Logo diisi belakangan (backfill asset).
  Future<void> seedBuiltinBrands() async {
    final rows = [
      // ── E-Wallet ──
      ('gopay', 'GoPay', 'ewallet', '#00AED6'),
      ('ovo', 'OVO', 'ewallet', '#4C3494'),
      ('dana', 'DANA', 'ewallet', '#118EEA'),
      ('shopeepay', 'ShopeePay', 'ewallet', '#EE4D2D'),
      // ── Bank ──
      ('bca', 'BCA', 'bank', '#0060AF'),
      ('bri', 'BRI', 'bank', '#00529C'),
      ('mandiri', 'Mandiri', 'bank', '#0B3B8C'),
      ('bni', 'BNI', 'bank', '#F26F21'),
      // ── Kartu ──
      ('visa', 'Visa', 'card', '#1A1F71'),
      ('mastercard', 'Mastercard', 'card', '#EB001B'),
      ('jcb', 'JCB', 'card', '#0E4C92'),
      ('gpn', 'GPN', 'card', '#E4002B'),
      ('amex', 'Amex', 'card', '#006FCF'),
    ];
    final now = DateTime.now().toIso8601String();
    await batch((b) {
      for (var i = 0; i < rows.length; i++) {
        final (id, name, kind, hex) = rows[i];
        b.insert(
          customBrands,
          CustomBrandsCompanion.insert(
            id: id,
            name: name,
            kind: Value(kind),
            hex: Value(hex),
            builtin: const Value(true),
            sortOrder: Value(i),
            createdAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Hapus brand. Ditolak bila masih dipakai wallet — pindahkan atau hapus
  /// wallet-nya dulu (cek [brandUsage]).
  Future<void> deleteBrand(String id) async {
    if (await brandUsage(id) > 0) {
      throw ArgumentError('Brand masih dipakai dompet');
    }
    await (delete(customBrands)..where((b) => b.id.equals(id))).go();
  }

  /// Jumlah wallet yang memakai brand ini.
  Future<int> brandUsage(String brandId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM accounts WHERE brand = ?1',
      variables: [Variable.withString(brandId)],
      readsFrom: {accounts},
    ).getSingle();
    return row.data['c'] as int;
  }

  /// Wallet pemakai brand + saldo saat ini — untuk dialog peringatan hapus.
  Future<List<(Account account, int balance)>> brandWallets(
      String brandId) async {
    final accs = await (select(accounts)
          ..where((a) => a.brand.equals(brandId))
          ..orderBy([(a) => OrderingTerm.asc(a.name)]))
        .get();
    final out = <(Account, int)>[];
    for (final a in accs) {
      out.add((a, await accountBalance(a.id)));
    }
    return out;
  }

  /// Ringkasan pemakaian wallet — untuk dialog konfirmasi hapus.
  Future<(int txCount, int billCount)> accountUsage(String accountId) async {
    final txRow = await customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ?1 OR to_account_id = ?1',
      variables: [Variable.withString(accountId)],
      readsFrom: {transactions},
    ).getSingle();
    final billRow = await customSelect(
      'SELECT COUNT(*) AS c FROM bills WHERE account_id = ?1',
      variables: [Variable.withString(accountId)],
      readsFrom: {bills},
    ).getSingle();
    return (
      txRow.data['c'] as int,
      billRow.data['c'] as int,
    );
  }

  /// Hapus wallet + seluruh jejaknya (transaksi, tagihan,
  /// pembayaran) dalam SATU transaksi DB — urutan FK-aman.
  Future<void> deleteAccountCascade(String accountId) async {
    await transaction(() async {
      await customStatement(
        'DELETE FROM bill_payments WHERE bill_id IN '
        '(SELECT id FROM bills WHERE account_id = ?1)',
        [accountId],
      );
      await (delete(bills)..where((b) => b.accountId.equals(accountId))).go();
      // Kolom to_account_id hanya dipakai data transfer lama.
      await customStatement(
        'DELETE FROM transactions WHERE account_id = ?1 OR to_account_id = ?1',
        [accountId],
      );
      await (delete(accounts)..where((a) => a.id.equals(accountId))).go();
    });
  }

  /// Hapus SEMUA data user (transaksi, tagihan, wallet, budget, brand
  /// custom) lalu seed ulang kategori & brand bawaan. Dipakai fitur
  /// "Hapus semua data" di Profil.
  ///
  /// Urutan hapus anak→induk wajib: FK aktif tanpa ON DELETE cascade.
  /// Kategori dihapus total lalu di-seed ulang (insertAll tidak
  /// idempoten — PK conflict bila dijalankan dua kali pada baris ada).
  Future<void> wipeAllData() async {
    await transaction(() async {
      await customStatement('DELETE FROM bill_payments');
      await customStatement('DELETE FROM budgets');
      await customStatement('DELETE FROM transactions');
      await customStatement('DELETE FROM bills');
      await customStatement('DELETE FROM accounts');
      await customStatement('DELETE FROM categories');
      await customStatement('DELETE FROM custom_brands');
      await _seedCategories();
      await seedBuiltinBrands();
    });
  }

  // ─── Category queries ─────────────────────────────────────────

  Future<List<Category>> allCategories() => select(categories).get();

  Stream<List<Category>> watchAllCategories() => select(categories).watch();

  /// Kategori aktif (tidak diarsip) untuk picker form — urut nama.
  Stream<List<Category>> watchActiveCategories() =>
      (select(categories)
            ..where((c) => c.archived.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<void> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);

  Future<void> updateCategory(CategoriesCompanion entry) =>
      into(categories).insertOnConflictUpdate(entry);

  /// Arsipkan kategori (soft delete): transaksi/tagihan yang sudah
  /// memakai kategori ini tetap utuh. `cat_other`/`cat_other_income`
  /// adalah fallback form transaksi — menolak diarsipkan.
  Future<void> archiveCategory(String id) async {
    if (id == 'cat_other' || id == 'cat_other_income') {
      throw ArgumentError('Kategori "Lainnya" tidak bisa diarsipkan');
    }
    await (update(categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(archived: Value(true)));
  }

  Future<void> unarchiveCategory(String id) async {
    await (update(categories)..where((c) => c.id.equals(id)))
        .write(const CategoriesCompanion(archived: Value(false)));
  }

  /// Ringkasan pemakaian kategori — untuk dialog konfirmasi arsip.
  Future<(int txCount, int billCount)> categoryUsage(String categoryId) async {
    final txRow = await customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE category_id = ?1',
      variables: [Variable.withString(categoryId)],
      readsFrom: {transactions},
    ).getSingle();
    final billRow = await customSelect(
      'SELECT COUNT(*) AS c FROM bills WHERE category_id = ?1',
      variables: [Variable.withString(categoryId)],
      readsFrom: {bills},
    ).getSingle();
    return (
      txRow.data['c'] as int,
      billRow.data['c'] as int,
    );
  }

  // ─── Transaction queries ───────────────────────────────────────

  Stream<List<Transaction>> watchRecentTransactions({int limit = 20}) =>
      (select(transactions)..orderBy([(t) => OrderingTerm.desc(t.date)])..limit(limit)).watch();

  Stream<List<Transaction>> watchTransactionsByAccount(String accountId) =>
      (select(transactions)
            ..where((t) => t.accountId.equals(accountId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  Stream<List<Transaction>> watchTransactionsByDateRange(String from, String to) =>
      (select(transactions)
            ..where((t) => t.date.isBetweenValues(from, to))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  /// Semua transaksi dengan filter opsional (jenis/wallet/kategori,
  /// kata kunci catatan, rentang tanggal [from, to) ISO YYYY-MM-DD).
  /// Filter diterapkan di SQL, bukan di Dart.
  Stream<List<Transaction>> watchTransactionsFiltered({
    String? type,
    String? accountId,
    String? categoryId,
    String? search,
    String? from,
    String? to,
  }) {
    return (select(transactions)
          ..where((t) {
            final exprs = <Expression<bool>>[];
            if (type != null) exprs.add(t.type.equals(type));
            if (accountId != null) exprs.add(t.accountId.equals(accountId));
            if (categoryId != null) {
              exprs.add(t.categoryId.equals(categoryId));
            }
            if (search != null && search.isNotEmpty) {
              // Escape wildcard LIKE agar %/_ dicari sebagai karakter
              // biasa, bukan pola.
              final esc = search
                  .replaceAll(r'\', r'\\')
                  .replaceAll('%', r'\%')
                  .replaceAll('_', r'\_');
              exprs.add(t.note.like('%$esc%', escapeChar: r'\'));
            }
            if (from != null) exprs.add(t.date.isBiggerOrEqualValue(from));
            if (to != null) {
              exprs.add(t.date.isSmallerThanValue(to));
            }
            return exprs.isEmpty ? const Constant(true) : Expression.and(exprs);
          })
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  /// Efek satu transaksi terhadap saldo [accountId]:
  /// expense keluar = -nominal, income = +nominal. Cabang transfer hanya
  /// untuk data lama (UI transfer sudah dihapus): keluar = -nominal,
  /// masuk = +nominal.
  static int _balanceEffect({
    required String accountId,
    required String txAccountId,
    required String? txToAccountId,
    required String type,
    required int amount,
  }) {
    if (txAccountId == accountId) {
      return type == 'income' ? amount : -amount;
    }
    if (txToAccountId == accountId) return amount;
    return 0;
  }

  /// Pengeluaran baru: tolak bila saldo wallet kurang (tidak boleh minus).
  /// Pemasukan selalu lolos.
  Future<void> insertTransaction(TransactionsCompanion entry) async {
    if (entry.type.value == 'expense') {
      final balance = await accountBalance(entry.accountId.value);
      if (balance < entry.amount.value) {
        throw InsufficientBalanceException(
          accountId: entry.accountId.value,
          balance: balance,
          required: entry.amount.value,
        );
      }
    }
    await into(transactions).insert(entry);
  }

  /// Edit transaksi: tolak bila hasil akhirnya bikin wallet mana pun
  /// yang tersentuh jadi minus. Saldo saat ini sudah termasuk tx lama,
  /// jadi kontribusi lama dikembalikan dulu sebelum menerapkan yang baru.
  Future<void> updateTransaction(TransactionsCompanion entry) async {
    final old = await (select(transactions)
          ..where((t) => t.id.equals(entry.id.value)))
        .getSingleOrNull();
    if (old != null) {
      final newType = entry.type.value;
      final newAccountId = entry.accountId.value;
      final newToAccountId = entry.toAccountId.value;
      final newAmount = entry.amount.value;
      final touched = {
        old.accountId,
        if (old.toAccountId != null) old.toAccountId!,
        newAccountId,
        if (newToAccountId != null) newToAccountId,
      };
      for (final accountId in touched) {
        final balance = await accountBalance(accountId);
        final oldEffect = _balanceEffect(
          accountId: accountId,
          txAccountId: old.accountId,
          txToAccountId: old.toAccountId,
          type: old.type,
          amount: old.amount,
        );
        final newEffect = _balanceEffect(
          accountId: accountId,
          txAccountId: newAccountId,
          txToAccountId: newToAccountId,
          type: newType,
          amount: newAmount,
        );
        final projected = balance - oldEffect + newEffect;
        if (projected < 0) {
          // Dana tersedia bila tx lama diabaikan; kurangnya = defisit akhir.
          final available = balance - oldEffect;
          throw InsufficientBalanceException(
            accountId: accountId,
            balance: available,
            required: available - projected,
          );
        }
      }
    }
    await into(transactions).insertOnConflictUpdate(entry);
  }

  /// Hapus transaksi permanen secara ATOMIK. Bila transaksi ini adalah
  /// pembayaran tagihan (bill_payments.transaction_id → FK), baris
  /// pembayarannya ikut dihapus dan cicilan yang lunas karena pembayaran
  /// tsb diaktifkan kembali. Tanpa ini, FK constraint gagal → exception.
  Future<void> deleteTransactionCascade(String id) async {
    await transaction(() async {
      final payments = await (select(billPayments)
            ..where((bp) => bp.transactionId.equals(id)))
          .get();
      final billIds = payments.map((p) => p.billId).toSet();

      if (payments.isNotEmpty) {
        await (delete(billPayments)
              ..where((bp) => bp.transactionId.equals(id)))
            .go();
        for (final billId in billIds) {
          final bill = await (select(bills)
                ..where((b) => b.id.equals(billId)))
              .getSingleOrNull();
          if (bill != null && bill.completed) {
            await (update(bills)..where((b) => b.id.equals(billId))).write(
              const BillsCompanion(
                  active: Value(true), completed: Value(false)),
            );
          }
        }
      }

      await (delete(transactions)..where((t) => t.id.equals(id))).go();
    });
  }

  // ─── Undo hapus ────────────────────────────────────────────────

  /// Ambil snapshot transaksi SEBELUM [deleteTransactionCascade]:
  /// baris transaksi, baris bill_payments terkait, dan state
  /// active/completed tagihan yang akan diubah cascade. Null bila
  /// transaksi tidak ada.
  Future<TransactionUndo?> captureTransactionUndo(String id) async {
    final tx = await (select(transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (tx == null) return null;
    final payments = await (select(billPayments)
          ..where((p) => p.transactionId.equals(id)))
        .get();
    final billIds = payments.map((p) => p.billId).toSet();
    final affectedBills = billIds.isEmpty
        ? const <Bill>[]
        : await (select(bills)..where((b) => b.id.isIn(billIds))).get();
    return (
      tx: tx,
      payments: payments,
      billStates: {
        for (final b in affectedBills)
          b.id: (active: b.active, completed: b.completed),
      },
    );
  }

  /// Urungkan hapus: kembalikan transaksi, pembayaran, dan state tagihan
  /// persis seperti sebelum dihapus — dalam SATU transaksi DB.
  Future<void> restoreTransactionUndo(TransactionUndo undo) {
    return transaction(() async {
      await into(transactions).insert(undo.tx);
      for (final p in undo.payments) {
        await into(billPayments).insert(p);
      }
      for (final e in undo.billStates.entries) {
        await (update(bills)..where((b) => b.id.equals(e.key))).write(
          BillsCompanion(
            active: Value(e.value.active),
            completed: Value(e.value.completed),
          ),
        );
      }
    });
  }

  /// Ambil snapshot tagihan + seluruh pembayarannya SEBELUM
  /// [deleteBillCascade]. Null bila tagihan tidak ada.
  Future<BillUndo?> captureBillUndo(String billId) async {
    final bill = await (select(bills)..where((b) => b.id.equals(billId)))
        .getSingleOrNull();
    if (bill == null) return null;
    final payments = await (select(billPayments)
          ..where((p) => p.billId.equals(billId)))
        .get();
    return (bill: bill, payments: payments);
  }

  /// Urungkan hapus tagihan: kembalikan tagihan + riwayat pembayaran.
  /// Gagal bila transaksi pembayarannya sudah dihapus terpisah (FK).
  Future<void> restoreBillUndo(BillUndo undo) {
    return transaction(() async {
      await into(bills).insert(undo.bill);
      for (final p in undo.payments) {
        await into(billPayments).insert(p);
      }
    });
  }

  /// Saldo satu wallet dalam SATU query SQL (sebelumnya 4 query
  /// berurutan per wallet — hot path rail wallet di Beranda).
  Future<int> accountBalance(String accountId) async {
    final account = await (select(accounts)..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) return 0;

    final row = await customSelect(
      '''
      SELECT
        COALESCE((SELECT SUM(amount) FROM transactions WHERE account_id = ?1 AND type = 'income'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions WHERE account_id = ?1 AND type = 'expense'), 0)
        + COALESCE((SELECT SUM(amount) FROM transactions WHERE to_account_id = ?1 AND type = 'transfer'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions WHERE account_id = ?1 AND type = 'transfer'), 0)
        AS total
      ''',
      variables: [Variable.withString(accountId)],
      readsFrom: {transactions},
    ).getSingle();

    return account.initialBalance + (row.data['total'] as int);
  }

  /// Saldo gabungan semua wallet aktif dalam SATU query SQL.
  /// (Sebelumnya: 4 query per wallet — jadi sumber tekanan startup/ANR.)
  Future<int> totalBalance() async {
    final row = await customSelect(
      '''
      SELECT COALESCE(SUM(
        a.initial_balance
        + COALESCE((SELECT SUM(amount) FROM transactions t
                    WHERE t.account_id = a.id AND t.type = 'income'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions t
                    WHERE t.account_id = a.id AND t.type = 'expense'), 0)
        + COALESCE((SELECT SUM(amount) FROM transactions t
                    WHERE t.to_account_id = a.id AND t.type = 'transfer'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions t
                    WHERE t.account_id = a.id AND t.type = 'transfer'), 0)
      ), 0) AS total
      FROM accounts a
      WHERE a.archived = 0
      ''',
      readsFrom: {accounts, transactions},
    ).getSingle();
    return row.data['total'] as int;
  }

  // ─── Bill queries ──────────────────────────────────────────────

  /// Tagihan aktif + status bayar bulan berjalan dalam SATU query.
  /// Urut due_day asc — urutan ini dipakai daftar Tagihan & hero Beranda.
  /// Month-key dihitung di Dart, bukan strftime('now','localtime'), karena
  /// dukungan timezone SQLite tidak dijamin di semua build.
  Stream<List<ActiveBillRow>> watchActiveBillsDetailed() {
    final monthKey = DateTime.now().toIso8601String().substring(0, 7);
    return customSelect(
      '''
      SELECT b.*,
             COUNT(DISTINCT substr(p.paid_at, 1, 7)) AS paidMonths,
             MAX(CASE WHEN substr(p.paid_at, 1, 7) = ?1 THEN 1 ELSE 0 END) AS paidNow
      FROM bills b
      LEFT JOIN bill_payments p ON p.bill_id = b.id
      WHERE b.active = 1
      GROUP BY b.id
      ORDER BY b.due_day ASC
      ''',
      variables: [Variable.withString(monthKey)],
      readsFrom: {bills, billPayments},
    ).watch().map((rows) => rows
        .map((r) => ActiveBillRow(
              bill: bills.map(r.data),
              paidMonths: r.read<int>('paidMonths'),
              paidThisMonth: r.read<int>('paidNow') == 1,
            ))
        .toList());
  }

  /// Tagihan cicilan yang sudah lunas — dipakai untuk section histori.
  /// Nonaktif manual tetap tidak muncul (perilaku lama).
  Stream<List<Bill>> watchCompletedBills() =>
      (select(bills)
            ..where((b) => b.active.equals(false) & b.completed.equals(true))
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .watch();

  Future<void> insertBill(BillsCompanion entry) => into(bills).insert(entry);

  Future<void> updateBill(BillsCompanion entry) => into(bills).insertOnConflictUpdate(entry);

  Future<void> deactivateBill(String id) =>
      (update(bills)..where((b) => b.id.equals(id))).write(BillsCompanion(active: const Value(false)));

  /// Hapus tagihan permanen beserta riwayat pembayarannya (atomik).
  Future<void> deleteBillCascade(String billId) async {
    await transaction(() async {
      await (delete(billPayments)..where((bp) => bp.billId.equals(billId))).go();
      await (delete(bills)..where((b) => b.id.equals(billId))).go();
    });
  }

  /// Bayar tagihan secara ATOMIK: buat transaksi pengeluaran +
  /// catat ke bill_payments dalam satu database transaction.
  /// Ditolak ([InsufficientBalanceException]) bila saldo wallet kurang —
  /// wallet tidak boleh minus.
  Future<void> payBillWithTransaction(Bill bill) async {
    final balance = await accountBalance(bill.accountId);
    if (balance < bill.amount) {
      throw InsufficientBalanceException(
        accountId: bill.accountId,
        balance: balance,
        required: bill.amount,
      );
    }
    await transaction(() async {
      final now = DateTime.now();
      final txId = const Uuid().v4();

      await into(transactions).insert(TransactionsCompanion.insert(
        id: txId,
        accountId: bill.accountId,
        categoryId: Value(bill.categoryId),
        toAccountId: const Value(null),
        type: const Value('expense'),
        amount: Value(bill.amount),
        note: Value(bill.name),
        date: now.toIso8601String(),
      ));

      await into(billPayments).insert(BillPaymentsCompanion.insert(
        id: const Uuid().v4(),
        billId: bill.id,
        transactionId: txId,
        paidAt: now.toIso8601String(),
      ));

      // Cicilan lunas: pembayaran ke-N → tagihan jadi histori.
      if (bill.durationMonths > 0) {
        final paid = await customSelect(
          'SELECT COUNT(*) AS c FROM bill_payments WHERE bill_id = ?1',
          variables: [Variable.withString(bill.id)],
          readsFrom: {billPayments},
        ).getSingle();
        if ((paid.data['c'] as int) >= bill.durationMonths) {
          await (update(bills)..where((b) => b.id.equals(bill.id))).write(
            const BillsCompanion(
                active: Value(false), completed: Value(true)),
          );
        }
      }
    });
  }

  Stream<List<BillPayment>> watchPaymentsForBill(String billId) =>
      (select(billPayments)
            ..where((bp) => bp.billId.equals(billId))
            ..orderBy([(bp) => OrderingTerm.desc(bp.paidAt)]))
          .watch();

  // ─── Budget queries ──────────────────────────────────────────

  /// Anggaran aktif + info kategorinya (join). Anggaran milik kategori
  /// arsip disembunyikan dan muncul lagi bila kategorinya diaktifkan
  /// kembali — tanpa baris yatim.
  Stream<List<BudgetInfo>> watchBudgets() {
    final query = select(budgets).join([
      innerJoin(categories, categories.id.equalsExp(budgets.categoryId)),
    ]);
    return query.watch().map((rows) => rows
        .where((r) => !r.readTable(categories).archived)
        .map((r) => (
              id: r.readTable(budgets).id,
              categoryId: r.readTable(budgets).categoryId,
              name: r.readTable(categories).name,
              icon: r.readTable(categories).icon,
              type: r.readTable(categories).type,
              monthlyAmount: r.readTable(budgets).monthlyAmount,
            ))
        .toList());
  }

  /// Set/ubah anggaran kategori. Jumlah ≤ 0 = hapus barisnya.
  /// Hanya kategori expense yang bisa dianggarkan.
  Future<void> setBudget(String categoryId, int amount) async {
    final cat = await (select(categories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingleOrNull();
    if (cat == null) {
      throw ArgumentError('Kategori tidak ditemukan');
    }
    if (cat.type != 'expense') {
      throw ArgumentError('Hanya kategori pengeluaran yang bisa dianggarkan');
    }
    final existing = await (select(budgets)
          ..where((b) => b.categoryId.equals(categoryId)))
        .getSingleOrNull();
    if (existing == null) {
      if (amount <= 0) return;
      await into(budgets).insert(BudgetsCompanion.insert(
        id: const Uuid().v4(),
        categoryId: categoryId,
        monthlyAmount: amount,
      ));
    } else if (amount <= 0) {
      await (delete(budgets)..where((b) => b.id.equals(existing.id))).go();
    } else {
      await (update(budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(monthlyAmount: Value(amount)));
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/myduit.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
