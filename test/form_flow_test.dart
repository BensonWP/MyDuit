import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/providers/database_provider.dart';
import 'package:myduit/screens/account_form_screen.dart';
import 'package:myduit/screens/transaction_form_screen.dart';
import 'package:myduit/theme/app_theme.dart';

void main() {
  late MyDuitDatabase db;

  setUpAll(() {
    initializeDateFormatting('id_ID');
    Intl.defaultLocale = 'id_ID';
  });

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async => db.close());

  Widget wrap(Widget child) => ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: buildTheme(), home: child),
      );

  // Unmount eksplisit lalu flush: pembatalan stream query drift menaruh
  // Timer(0) saat ProviderScope disposed — tanpa pump susulan, flutter_test
  // gagal dengan "A Timer is still pending".
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('Tambah wallet: brand GoPay tersimpan dengan nama otomatis',
      (tester) async {
    try {
      await tester.pumpWidget(wrap(const AccountFormScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('E-Wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GoPay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final accounts = await db.select(db.accounts).get();
      expect(accounts.single.name, 'GoPay');
      expect(accounts.single.brand, 'gopay');
      expect(accounts.single.type, 'ewallet');
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('Tambah transaksi: pengeluaran mengurangi saldo wallet',
      (tester) async {
    try {
      final now = DateTime.now().toIso8601String();
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: 'acc1',
            name: 'Cash',
            createdAt: now,
            initialBalance: const Value(100000),
          ));

      await tester.pumpWidget(wrap(const TransactionForm()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '25000');
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final txs = await db.select(db.transactions).get();
      expect(txs.single.type, 'expense');
      expect(txs.single.amount, 25000);
      expect(await db.accountBalance('acc1'), 75000);
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('Tambah transaksi: pemasukan tanpa kategori pakai fallback income',
      (tester) async {
    try {
      final now = DateTime.now().toIso8601String();
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: 'acc1',
            name: 'Cash',
            createdAt: now,
            initialBalance: const Value(0),
          ));

      await tester.pumpWidget(wrap(const TransactionForm()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pemasukan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '50000');
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final txs = await db.select(db.transactions).get();
      expect(txs.single.type, 'income');
      // Bukan cat_other (expense) — fallback per jenis.
      expect(txs.single.categoryId, 'cat_other_income');
      expect(await db.accountBalance('acc1'), 50000);
    } finally {
      await unmount(tester);
    }
  });

  testWidgets('Tambah transaksi: expense melebihi saldo tampil pesan inline',
      (tester) async {
    try {
      final now = DateTime.now().toIso8601String();
      await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: 'acc1',
            name: 'Cash',
            createdAt: now,
            initialBalance: const Value(200),
          ));

      await tester.pumpWidget(wrap(const TransactionForm()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '250');
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      // Pastikan tombol Simpan terlihat (scroll bila perlu).
      await tester.ensureVisible(find.text('Simpan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      // Sheet tidak tertutup, pesan inline tampil, DB tidak berubah.
      expect(find.text('Simpan'), findsOneWidget);
      expect(find.textContaining('tidak cukup'), findsOneWidget);
      expect(find.textContaining('kurang'), findsOneWidget);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.accountBalance('acc1'), 200);
    } finally {
      await unmount(tester);
    }
  });
}
