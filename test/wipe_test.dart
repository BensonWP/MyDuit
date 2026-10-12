import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  test('wipeAllData: kosongkan data user, seed ulang kategori & brand bawaan',
      () async {
    final now = DateTime.now().toIso8601String();

    // ── Isi data user ──
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cash',
          createdAt: now,
          initialBalance: const Value(100000),
        ));
    await db.insertCategory(CategoriesCompanion.insert(
          id: 'cat_custom',
          name: 'Kopi',
          icon: const Value('coffee'),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          accountId: 'acc1',
          amount: const Value(15000),
          date: now,
        ));
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'bill1',
          name: 'Internet',
          accountId: 'acc1',
          amount: const Value(300000),
          dueDay: const Value(5),
          createdAt: now,
        ));
    await db.setBudget('cat_custom', 200000);
    await db.into(db.customBrands).insert(CustomBrandsCompanion.insert(
          id: 'brand_custom',
          name: 'Bankku',
          createdAt: now,
        ));

    // Sanity: data ada.
    expect(await db.allAccounts(), isNotEmpty);
    expect((await db.allCategories()).length, greaterThan(11));

    // ── Wipe ──
    await db.wipeAllData();

    // ── Data user hilang ──
    expect(await db.allAccounts(), isEmpty);
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.bills).get(), isEmpty);
    expect(await db.select(db.billPayments).get(), isEmpty);
    expect(await db.select(db.budgets).get(), isEmpty);

    // Kategori custom hilang, kategori bawaan ter-seed ulang.
    final cats = await db.allCategories();
    final catIds = cats.map((c) => c.id).toSet();
    expect(catIds, isNot(contains('cat_custom')));
    expect(catIds, containsAll(['cat_food', 'cat_other', 'cat_other_income']));
    expect(cats.length, 11);

    // Brand custom hilang, brand bawaan ada.
    final brandIds =
        (await db.watchCustomBrands().first).map((b) => b.id).toSet();
    expect(brandIds, isNot(contains('brand_custom')));
    expect(brandIds, containsAll(['gopay', 'bca', 'visa']));

    // Fallback form transaksi tetap hidup.
    expect(catIds, containsAll(['cat_other', 'cat_other_income']));
  });
}
