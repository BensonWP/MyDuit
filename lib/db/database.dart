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

/// Snapshot untuk urungkan hapus transaksi (lihat captureTransactionUndo).
typedef TransactionUndo = ({
  Transaction tx,
  List<BillPayment> payments,
  Map<String, ({bool active, bool completed})> billStates,
});

/// Snapshot untuk urungkan hapus tagihan (lihat captureBillUndo).
typedef BillUndo = ({Bill bill, List<BillPayment> payments});

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

  /// Ringkasan pemakaian wallet — untuk dialog konfirmasi hapus.
  Future<(int txCount, int billCount, int planCount)> accountUsage(
      String accountId) async {
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
    final planRow = await customSelect(
      'SELECT COUNT(*) AS c FROM plans WHERE account_id = ?1',
      variables: [Variable.withString(accountId)],
      readsFrom: {plans},
    ).getSingle();
    return (
      txRow.data['c'] as int,
      billRow.data['c'] as int,
      planRow.data['c'] as int,
    );
  }

  /// Hapus wallet + seluruh jejaknya (transaksi, transfer, tagihan,
  /// pembayaran, rencana terikat) dalam SATU transaksi DB —
  /// urutan FK-aman.
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
      // Rencana terikat wallet ikut terhapus (FK plans.account_id).
      await customStatement(
        'DELETE FROM plans WHERE account_id = ?1',
        [accountId],
      );
      await (delete(accounts)..where((a) => a.id.equals(accountId))).go();
    });
  }

  // ─── Category queries ─────────────────────────────────────────

  Future<List<Category>> allCategories() => select(categories).get();

  Stream<List<Category>> watchAllCategories() => select(categories).watch();

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
