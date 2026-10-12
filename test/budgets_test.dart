import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/providers/database_provider.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed() async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
    ));
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_jajan',
      name: 'Jajan',
      icon: const Value('coffee'),
    ));
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_gaji',
      name: 'Gaji',
      type: const Value('income'),
    ));
  }

  test('setBudget: tambah + ubah + info join kategori', () async {
    await seed();
    await db.setBudget('cat_jajan', 500000);

    var budgets = await db.watchBudgets().first;
    expect(budgets.length, 1);
    expect(budgets.single.categoryId, 'cat_jajan');
    expect(budgets.single.name, 'Jajan');
    expect(budgets.single.icon, 'coffee');
    expect(budgets.single.type, 'expense');
    expect(budgets.single.monthlyAmount, 500000);

    await db.setBudget('cat_jajan', 300000);
    budgets = await db.watchBudgets().first;
    expect(budgets.length, 1);
    expect(budgets.single.monthlyAmount, 300000);
  });

  test('setBudget: 0/negatif menghapus; 0 tanpa baris = no-op', () async {
    await seed();
    await db.setBudget('cat_jajan', 0);
    expect(await db.watchBudgets().first, isEmpty);

    await db.setBudget('cat_jajan', 100000);
    expect((await db.watchBudgets().first).length, 1);

    await db.setBudget('cat_jajan', -5);
    expect(await db.watchBudgets().first, isEmpty);
  });

  test('setBudget: income & kategori tak dikenal ditolak', () async {
    await seed();
    await expectLater(
        db.setBudget('cat_gaji', 100000), throwsA(isA<ArgumentError>()));
    await expectLater(
        db.setBudget('cat_tak_ada', 100000), throwsA(isA<ArgumentError>()));
    expect(await db.watchBudgets().first, isEmpty);
  });

  test('arsip kategori menyembunyikan anggarannya, batal-arsip mengembalikan',
      () async {
    await seed();
    await db.setBudget('cat_jajan', 200000);
    expect((await db.watchBudgets().first).length, 1);

    await db.archiveCategory('cat_jajan');
    expect(await db.watchBudgets().first, isEmpty);

    await db.unarchiveCategory('cat_jajan');
    final budgets = await db.watchBudgets().first;
    expect(budgets.length, 1);
    expect(budgets.single.monthlyAmount, 200000);
  });

  test('budgetState: ambang 80 % dan 100 %', () async {
    expect(budgetState(0, 100), BudgetState.ok);
    expect(budgetState(79, 100), BudgetState.ok);
    expect(budgetState(80, 100), BudgetState.warning);
    expect(budgetState(100, 100), BudgetState.warning);
    expect(budgetState(101, 100), BudgetState.over);
    expect(budgetState(999, 0), BudgetState.ok);
  });

  test('spentByCategory: hanya expense berkategori', () async {
    Transaction tx(String id, String type, int amount, String? cat) =>
        Transaction(
          id: id,
          accountId: 'acc1',
          categoryId: cat,
          type: type,
          amount: amount,
          note: '',
          date: DateTime.now().toIso8601String(),
        );
    final spent = spentByCategory([
      tx('a', 'expense', 10, 'cat_jajan'),
      tx('b', 'expense', 20, 'cat_jajan'),
      tx('c', 'expense', 5, null), // tanpa kategori → abaikan
      tx('d', 'income', 999, 'cat_jajan'), // pemasukan → abaikan
      tx('e', 'transfer', 7, 'cat_jajan'), // transfer lama → abaikan
    ]);
    expect(spent, {'cat_jajan': 30});
  });

  test('budgetAlerts: hitung waspada + jebol, income dilewati', () async {
    BudgetInfo b(String cat, int amount, [String type = 'expense']) => (
          id: 'b_$cat',
          categoryId: cat,
          name: cat,
          icon: 'more_horiz',
          type: type,
          monthlyAmount: amount,
        );
    final alerts = budgetAlerts(
      [b('a', 100), b('c', 100), b('d', 100), b('e', 100, 'income')],
      {'a': 85, 'c': 150, 'e': 9999},
    );
    expect(alerts.warning, 1); // a
    expect(alerts.over, 1); // c (d tanpa belanja = ok, e dilewati)
  });
}
