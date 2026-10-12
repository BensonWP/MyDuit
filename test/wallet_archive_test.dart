import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/providers/database_provider.dart';
import 'package:myduit/screens/accounts_screen.dart';
import 'package:myduit/theme/app_theme.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedWallet(String id, String name, int initial) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(
        id: id,
        name: name,
        createdAt: DateTime.now().toIso8601String(),
        initialBalance: Value(initial),
      ));

  test('arsip: hilang dari daftar + total, saldo terakhir tetap terbaca',
      () async {
    await seedWallet('acc1', 'Cash', 50000);
    await seedWallet('acc2', 'Bank', 30000);
    expect(await db.totalBalance(), 80000);

    await db.archiveAccount('acc1');

    expect((await db.allAccounts()).map((a) => a.id), ['acc2']);
    expect(
        (await db.watchArchivedAccounts().first).map((a) => a.id), ['acc1']);
    expect(await db.totalBalance(), 30000);
    // Saldo terakhir untuk baris arsip.
    expect(await db.accountBalance('acc1'), 50000);

    await db.unarchiveAccount('acc1');
    expect(
      (await db.allAccounts()).map((a) => a.id).toSet(),
      {'acc1', 'acc2'},
    );
    expect(await db.totalBalance(), 80000);
  });

  test('transaksi wallet arsip tetap utuh', () async {
    await seedWallet('acc1', 'Cash', 100000);
    final now = DateTime.now().toIso8601String();
    await db.insertTransaction(TransactionsCompanion.insert(
      id: 'tx1',
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(20000),
      date: now,
    ));

    await db.archiveAccount('acc1');
    expect((await db.select(db.transactions).get()).length, 1);

    await db.unarchiveAccount('acc1');
    expect(await db.accountBalance('acc1'), 80000);
  });

  Widget wrap(Widget child) => ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildTheme(), home: child),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('Diarsipkan: Aktifkan lagi mengembalikan wallet ke grid',
      (tester) async {
    await seedWallet('acc1', 'Cash', 50000);
    await seedWallet('acc2', 'Bank', 30000);
    await db.archiveAccount('acc2');
    try {
      await tester.pumpWidget(wrap(const AccountsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('DIARSIPKAN'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);

      await tester.tap(find.text('Aktifkan lagi'));
      await tester.pumpAndSettle();

      expect(find.text('DIARSIPKAN'), findsNothing);
      expect(find.text('Bank'), findsOneWidget);
      expect(await db.totalBalance(), 80000);
    } finally {
      await unmount(tester);
    }
  });
}
