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

  /// Brand e-wallet: 'gopay'|'ovo'|'dana'|'shopeepay'|'linkaja'.
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

class Plans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amount => integer().withDefault(const Constant(0))();

  /// null = dibandingkan total saldo semua wallet.
  TextColumn get accountId => text().nullable().references(Accounts, #id)();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Baris hasil watchBillProjection — bukan tabel, hanya DTO query.
class BillProjection {
  const BillProjection({
    required this.amount,
    required this.durationMonths,
    required this.paidMonths,
    required this.paidThisMonth,
  });

  final int amount;
  final int durationMonths; // 0 = berulang selamanya
  final int paidMonths; // jumlah bulan berbeda yang sudah dibayar
  final bool paidThisMonth;
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
  Plans
])
class MyDuitDatabase extends _$MyDuitDatabase {
  MyDuitDatabase() : super(_openConnection());

  MyDuitDatabase.testing() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedCategories();
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
          if (from < 6) {
            await m.createTable(plans);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedCategories() async {
    final presets = [
      (id: 'cat_food', name: 'Makanan', icon: 'restaurant'),
      (id: 'cat_transport', name: 'Transportasi', icon: 'directions_car'),
      (id: 'cat_bills', name: 'Tagihan', icon: 'receipt'),
      (id: 'cat_shopping', name: 'Belanja', icon: 'shopping_bag'),
      (id: 'cat_health', name: 'Kesehatan', icon: 'local_hospital'),
      (id: 'cat_education', name: 'Pendidikan', icon: 'school'),
      (id: 'cat_entertainment', name: 'Hiburan', icon: 'movie'),
      (id: 'cat_salary', name: 'Gaji', icon: 'work'),
      (id: 'cat_sidejob', name: 'Pekerjaan Sampingan', icon: 'laptop'),
      (id: 'cat_other', name: 'Lainnya', icon: 'more_horiz'),
    ];
    await batch((b) {
      b.insertAll(
        categories,
        presets
            .map((c) => CategoriesCompanion.insert(
                  id: c.id,
                  name: c.name,
                  type: const Value('expense'),
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

  Future<void> archiveAccount(String id) =>
      (update(accounts)..where((a) => a.id.equals(id))).write(AccountsCompanion(archived: const Value(true)));

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
    return (txRow.data['c'] as int, billRow.data['c'] as int);
  }

  /// Hapus wallet + seluruh jejaknya (transaksi, transfer, tagihan,
  /// pembayaran) dalam SATU transaksi DB — urutan FK-aman.
  Future<void> deleteAccountCascade(String accountId) async {
    await transaction(() async {
      await customStatement(
        'DELETE FROM bill_payments WHERE bill_id IN '
        '(SELECT id FROM bills WHERE account_id = ?1)',
        [accountId],
      );
      await (delete(bills)..where((b) => b.accountId.equals(accountId))).go();
      // Transfer keluar dari wallet lain juga menyinggung wallet ini.
      await customStatement(
        'DELETE FROM transactions WHERE account_id = ?1 OR to_account_id = ?1',
        [accountId],
      );
      await (delete(accounts)..where((a) => a.id.equals(accountId))).go();
    });
  }

  // ─── Category queries ─────────────────────────────────────────

  Future<List<Category>> allCategories() => select(categories).get();

  Stream<List<Category>> watchAllCategories() => select(categories).watch();

  Future<void> insertCategory(CategoriesCompanion entry) => into(categories).insert(entry);

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
              exprs.add(t.note.like('%$search%'));
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

  Future<void> insertTransaction(TransactionsCompanion entry) => into(transactions).insert(entry);

  Future<void> updateTransaction(TransactionsCompanion entry) =>
      into(transactions).insertOnConflictUpdate(entry);

  Future<void> deleteTransaction(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  Future<int> accountBalance(String accountId) async {
    final account = await (select(accounts)..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) return 0;

    final incomeSum = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE account_id = ?1 AND type = ?2',
      variables: [Variable.withString(accountId), Variable.withString('income')],
      readsFrom: {transactions},
    ).getSingleOrNull();

    final expenseSum = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE account_id = ?1 AND type = ?2',
      variables: [Variable.withString(accountId), Variable.withString('expense')],
      readsFrom: {transactions},
    ).getSingleOrNull();

    final transferIn = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE to_account_id = ?1 AND type = ?2',
      variables: [Variable.withString(accountId), Variable.withString('transfer')],
      readsFrom: {transactions},
    ).getSingleOrNull();

    final transferOut = await customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM transactions WHERE account_id = ?1 AND type = ?2',
      variables: [Variable.withString(accountId), Variable.withString('transfer')],
      readsFrom: {transactions},
    ).getSingleOrNull();

    return account.initialBalance +
        (incomeSum?.data['total'] as int? ?? 0) -
        (expenseSum?.data['total'] as int? ?? 0) +
        (transferIn?.data['total'] as int? ?? 0) -
        (transferOut?.data['total'] as int? ?? 0);
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

  Stream<List<Bill>> watchActiveBills() =>
      (select(bills)..where((b) => b.active.equals(true))..orderBy([(b) => OrderingTerm.asc(b.dueDay)])).watch();

  /// Tagihan cicilan yang sudah lunas — dipakai untuk section histori.
  /// Nonaktif manual tetap tidak muncul (perilaku lama).
  Stream<List<Bill>> watchCompletedBills() =>
      (select(bills)
            ..where((b) => b.active.equals(false) & b.completed.equals(true))
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .watch();

  /// Total tagihan aktif yang belum dibayar pada bulan berjalan.
  /// Bulan dibandingkan sebagai prefix 'YYYY-MM' dari paidAt (ISO lokal) —
  /// sama persis dengan logika paidThisMonth. Month-key dihitung di Dart,
  /// bukan strftime('now','localtime'), karena dukungan timezone SQLite
  /// tidak dijamin di semua build (mengembalikan NULL → filter bocor).
  Stream<int> watchUnpaidBillsTotalThisMonth() {
    final monthKey = DateTime.now().toIso8601String().substring(0, 7);
    return customSelect(
      '''
      SELECT COALESCE(SUM(b.amount), 0) AS total
      FROM bills b
      WHERE b.active = 1
        AND NOT EXISTS (
          SELECT 1 FROM bill_payments p
          WHERE p.bill_id = b.id
            AND substr(p.paid_at, 1, 7) = ?1
        )
      ''',
      variables: [Variable.withString(monthKey)],
      readsFrom: {bills, billPayments},
    ).watchSingle().map((row) => row.data['total'] as int);
  }

  /// Bahan proyeksi bulanan, per tagihan aktif: nominal, lama cicilan
  /// (0 = selamanya), jumlah bulan berbeda yang sudah dibayar, dan
  /// status sudah dibayar bulan berjalan. Month-key dari Dart (lihat
  /// watchUnpaidBillsTotalThisMonth untuk alasannya).
  Stream<List<BillProjection>> watchBillProjection() {
    final monthKey = DateTime.now().toIso8601String().substring(0, 7);
    return customSelect(
      '''
      SELECT b.amount AS amount,
             b.duration_months AS durationMonths,
             COUNT(DISTINCT substr(p.paid_at, 1, 7)) AS paidMonths,
             MAX(CASE WHEN substr(p.paid_at, 1, 7) = ?1 THEN 1 ELSE 0 END) AS paidNow
      FROM bills b
      LEFT JOIN bill_payments p ON p.bill_id = b.id
      WHERE b.active = 1
      GROUP BY b.id
      ''',
      variables: [Variable.withString(monthKey)],
      readsFrom: {bills, billPayments},
    ).watch().map((rows) => rows
        .map((r) => BillProjection(
              amount: r.read<int>('amount'),
              durationMonths: r.read<int>('durationMonths'),
              paidMonths: r.read<int>('paidMonths'),
              paidThisMonth: r.read<int>('paidNow') == 1,
            ))
        .toList());
  }

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
  Future<void> payBillWithTransaction(Bill bill) async {
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

  // ─── Budget queries ────────────────────────────────────────────

  /// Anggaran aktif + info kategorinya (join).
  Stream<List<({String id, String categoryId, String categoryName, String categoryIcon, int monthlyAmount})>>
      watchBudgets() {
    final query = select(budgets).join([
      innerJoin(categories, categories.id.equalsExp(budgets.categoryId)),
    ]);
    return query.watch().map((rows) => rows
        .map((r) => (
              id: r.readTable(budgets).id,
              categoryId: r.readTable(budgets).categoryId,
              categoryName: r.readTable(categories).name,
              categoryIcon: r.readTable(categories).icon,
              monthlyAmount: r.readTable(budgets).monthlyAmount,
            ))
        .toList());
  }

  /// Set anggaran kategori (upsert). amount <= 0 → hapus anggaran.
  Future<void> setBudget(String categoryId, int amount) async {
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

  // ─── Plan queries ──────────────────────────────────────────────

  Stream<List<Plan>> watchPlans() =>
      (select(plans)..orderBy([(p) => OrderingTerm.desc(p.createdAt)])).watch();

  Future<void> upsertPlan(PlansCompanion entry) =>
      into(plans).insertOnConflictUpdate(entry);

  Future<void> deletePlan(String id) =>
      (delete(plans)..where((p) => p.id.equals(id))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/myduit.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
