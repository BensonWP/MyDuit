import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/providers/database_provider.dart';
import 'package:myduit/screens/category_form_screen.dart';
import 'package:myduit/theme/app_theme.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedAccount() => db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cash',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

  test('tambah kategori: masuk daftar aktif', () async {
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_jajan',
      name: 'Jajan',
      type: const Value('expense'),
      icon: const Value('coffee'),
    ));

    final active = await db.watchActiveCategories().first;
    expect(active.map((c) => c.id), contains('cat_jajan'));
    final cat = active.firstWhere((c) => c.id == 'cat_jajan');
    expect(cat.name, 'Jajan');
    expect(cat.type, 'expense');
    expect(cat.icon, 'coffee');
    expect(cat.archived, isFalse);
  });

  test('ubah kategori: nama dan ikon tersimpan', () async {
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_x',
      name: 'Lama',
      icon: const Value('coffee'),
    ));
    await db.updateCategory(const CategoriesCompanion(
      id: Value('cat_x'),
      name: Value('Baru'),
      icon: Value('flight'),
    ));

    final all = await db.allCategories();
    final cat = all.firstWhere((c) => c.id == 'cat_x');
    expect(cat.name, 'Baru');
    expect(cat.icon, 'flight');
  });

  test('arsip: hilang dari aktif, nama riwayat tetap teresolusi', () async {
    await seedAccount();
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_old',
      name: 'Kuno',
    ));
    final now = DateTime.now().toIso8601String();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx1',
      accountId: 'acc1',
      categoryId: const Value('cat_old'),
      date: now,
    ));

    await db.archiveCategory('cat_old');

    final active = await db.watchActiveCategories().first;
    expect(active.map((c) => c.id), isNot(contains('cat_old')));
    // Daftar penuh tetap punya — nama transaksi lama bisa ditampilkan.
    final all = await db.allCategories();
    expect(all.firstWhere((c) => c.id == 'cat_old').archived, isTrue);

    await db.unarchiveCategory('cat_old');
    expect(
      (await db.watchActiveCategories().first).map((c) => c.id),
      contains('cat_old'),
    );
  });

  test('cat_other menolak diarsipkan', () async {
    // DB testing ikut seed kategori bawaan (onCreate) — cat_other ada.
    expect(
      (await db.watchActiveCategories().first).map((c) => c.id),
      contains('cat_other'),
    );
    await expectLater(db.archiveCategory('cat_other'),
        throwsA(isA<ArgumentError>()));
    expect(
      (await db.watchActiveCategories().first).map((c) => c.id),
      contains('cat_other'),
    );
  });

  test('seed bawaan: gaji/sampingan income + fallback per jenis', () async {
    final all = await db.allCategories();
    final byId = {for (final c in all) c.id: c};
    expect(byId['cat_salary']!.type, 'income');
    expect(byId['cat_sidejob']!.type, 'income');
    expect(byId['cat_other']!.type, 'expense');
    expect(byId['cat_other_income']!.type, 'income');
    final active = await db.watchActiveCategories().first;
    expect(active.where((c) => c.type == 'income').map((c) => c.id),
        containsAll(['cat_salary', 'cat_sidejob', 'cat_other_income']));
  });

  test('cat_other_income menolak diarsipkan', () async {
    await expectLater(db.archiveCategory('cat_other_income'),
        throwsA(isA<ArgumentError>()));
    expect(
      (await db.watchActiveCategories().first).map((c) => c.id),
      contains('cat_other_income'),
    );
  });

  test('categoryUsage: hitung transaksi + tagihan', () async {
    await seedAccount();
    final now = DateTime.now().toIso8601String();
    await db.insertCategory(CategoriesCompanion.insert(
      id: 'cat_u',
      name: 'Dipakai',
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx1',
      accountId: 'acc1',
      categoryId: const Value('cat_u'),
      date: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx2',
      accountId: 'acc1',
      categoryId: const Value('cat_u'),
      date: now,
    ));
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill1',
      name: 'Langganan',
      accountId: 'acc1',
      categoryId: const Value('cat_u'),
      createdAt: now,
    ));

    expect(await db.categoryUsage('cat_u'), (2, 1));
    expect(await db.categoryUsage('cat_tak_ada'), (0, 0));
  });

  Widget wrap(Widget child) => ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildTheme(), home: child),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('Tambah kategori via form tersimpan di DB', (tester) async {
    try {
      await tester.pumpWidget(wrap(const CategoryFormScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'Jajan');
      await tester.ensureVisible(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final all = await db.allCategories();
      expect(all.map((c) => c.name), contains('Jajan'));
      final cat = all.firstWhere((c) => c.name == 'Jajan');
      expect(cat.type, 'expense');
    } finally {
      await unmount(tester);
    }
  });
}
