import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

// ─── Tables ────────────────────────────────────────────────────────

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('cash'))();
  TextColumn get color => text().withDefault(const Constant('#4CAF50'))();
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

// ─── Database ──────────────────────────────────────────────────────

@DriftDatabase(tables: [Accounts, Categories, Transactions, Bills, BillPayments])
class MyDuitDatabase extends _$MyDuitDatabase {
  MyDuitDatabase() : super(_openConnection());

  MyDuitDatabase.testing() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

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

  Future<int> totalBalance() async {
    final all = await allAccounts();
    int total = 0;
    for (final a in all) {
      total += await accountBalance(a.id);
    }
    return total;
  }

  // ─── Bill queries ──────────────────────────────────────────────

  Stream<List<Bill>> watchActiveBills() =>
      (select(bills)..where((b) => b.active.equals(true))..orderBy([(b) => OrderingTerm.asc(b.dueDay)])).watch();

  Future<void> insertBill(BillsCompanion entry) => into(bills).insert(entry);

  Future<void> updateBill(BillsCompanion entry) => into(bills).insertOnConflictUpdate(entry);

  Future<void> deactivateBill(String id) =>
      (update(bills)..where((b) => b.id.equals(id))).write(BillsCompanion(active: const Value(false)));

  Future<void> payBill(BillPayment payment) async {
    await into(billPayments).insert(payment);
  }

  Stream<List<BillPayment>> watchPaymentsForBill(String billId) =>
      (select(billPayments)
            ..where((bp) => bp.billId.equals(billId))
            ..orderBy([(bp) => OrderingTerm.desc(bp.paidAt)]))
          .watch();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File('${dbFolder.path}/myduit.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
