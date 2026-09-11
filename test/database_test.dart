import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/providers/database_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  test('balance calculation: initial + income - expense + transfer', () async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    // Create two accounts
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(100000),
    ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc2',
      name: 'Bank',
      createdAt: now,
    ));

    // Income: +50000 to acc1
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('income'),
      amount: const Value(50000),
      date: now,
    ));

    // Expense: -30000 from acc1
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(30000),
      date: now,
    ));

    // Transfer: 20000 from acc1 to acc2
    final transferId = uuid.v4();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: transferId,
      accountId: 'acc1',
      toAccountId: const Value('acc2'),
      type: const Value('transfer'),
      amount: const Value(20000),
      date: now,
    ));

    // acc1: 100000 + 50000 - 30000 - 20000 = 100000
    final balance1 = await db.accountBalance('acc1');
    expect(balance1, 100000);

    // acc2: 0 + 20000 = 20000
    final balance2 = await db.accountBalance('acc2');
    expect(balance2, 20000);

    // Total: 100000 + 20000 = 120000
    final total = await db.totalBalance();
    expect(total, 120000);
  });

  test('balance is 0 for non-existent account', () async {
    final balance = await db.accountBalance('no_such_account');
    expect(balance, 0);
  });

  test('balance ignores transactions from other accounts', () async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(10000),
    ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc2',
      name: 'Bank',
      createdAt: now,
    ));

    // Income goes to acc2, not acc1
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc2',
      type: const Value('income'),
      amount: const Value(500000),
      date: now,
    ));

    // acc1 still 10000
    final balance = await db.accountBalance('acc1');
    expect(balance, 10000);
  });

  test('payBillWithTransaction: expense + payment record atomically', () async {
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(100000),
    ));
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill1',
      name: 'Listrik',
      accountId: 'acc1',
      amount: const Value(15000),
      createdAt: now,
    ));

    final bill = await (db.select(db.bills)..where((b) => b.id.equals('bill1'))).getSingle();
    await db.payBillWithTransaction(bill);

    // acc1: 100000 - 15000 = 85000
    final balance = await db.accountBalance('acc1');
    expect(balance, 85000);

    // Payment recorded, linked to an expense transaction
    final payments = await db.select(db.billPayments).get();
    expect(payments.length, 1);
    expect(payments.first.billId, 'bill1');

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(payments.first.transactionId)))
        .getSingleOrNull();
    expect(tx, isNotNull);
    expect(tx!.type, 'expense');
    expect(tx.amount, 15000);
    expect(tx.note, 'Listrik');
  });

  test('insertTransaction: expense melebihi saldo ditolak, income lolos',
      () async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(10000),
    ));

    // Income selalu lolos: 10000 + 5000 = 15000.
    await db.insertTransaction(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('income'),
      amount: const Value(5000),
      date: now,
    ));
    expect(await db.accountBalance('acc1'), 15000);

    // Expense pas-pasan lolos: 15000 - 15000 = 0.
    await db.insertTransaction(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(15000),
      date: now,
    ));
    expect(await db.accountBalance('acc1'), 0);

    // Expense Rp1 saat saldo 0 ditolak — wallet tidak boleh minus.
    await expectLater(
      db.insertTransaction(TransactionsCompanion.insert(
        id: uuid.v4(),
        accountId: 'acc1',
        type: const Value('expense'),
        amount: const Value(1),
        date: now,
      )),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await db.accountBalance('acc1'), 0);
    expect((await db.select(db.transactions).get()).length, 2);
  });

  test('updateTransaction: edit yang bikin saldo minus ditolak', () async {
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(10000),
    ));
    await db.insertTransaction(TransactionsCompanion.insert(
      id: 'tx1',
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(4000),
      date: now,
    ));
    expect(await db.accountBalance('acc1'), 6000);

    // Naikkan jadi 20000 (saldo tersedia 10000) → ditolak.
    await expectLater(
      db.updateTransaction(TransactionsCompanion.insert(
        id: 'tx1',
        accountId: 'acc1',
        type: const Value('expense'),
        amount: const Value(20000),
        date: now,
      )),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(await db.accountBalance('acc1'), 6000);

    // Turunkan jadi 2000 → lolos, saldo 8000.
    await db.updateTransaction(TransactionsCompanion.insert(
      id: 'tx1',
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(2000),
      date: now,
    ));
    expect(await db.accountBalance('acc1'), 8000);
  });

  test('payBillWithTransaction: saldo kurang ditolak secara atomik', () async {
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
      initialBalance: const Value(10000),
    ));
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill1',
      name: 'Listrik',
      accountId: 'acc1',
      amount: const Value(15000),
      createdAt: now,
    ));

    final bill = await (db.select(db.bills)
          ..where((b) => b.id.equals('bill1')))
        .getSingle();
    await expectLater(
      db.payBillWithTransaction(bill),
      throwsA(isA<InsufficientBalanceException>()),
    );

    // Atomik: tidak ada transaksi maupun pembayaran yang tercatat.
    expect(await db.accountBalance('acc1'), 10000);
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.billPayments).get(), isEmpty);
  });

  test('watchTransactionsFiltered: filter jenis + cari catatan di SQL', () async {
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('expense'),
      amount: const Value(10000),
      note: const Value('makan siang'),
      date: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: uuid.v4(),
      accountId: 'acc1',
      type: const Value('income'),
      amount: const Value(500000),
      note: const Value('gaji bulanan'),
      date: now,
    ));

    final onlyExpense =
        await db.watchTransactionsFiltered(type: 'expense').first;
    expect(onlyExpense.length, 1);
    expect(onlyExpense.first.type, 'expense');

    final search =
        await db.watchTransactionsFiltered(search: 'gaji').first;
    expect(search.length, 1);
    expect(search.first.note, 'gaji bulanan');

    final all = await db.watchTransactionsFiltered().first;
    expect(all.length, 2);
  });

  test('search: wildcard LIKE di-escape, %/_ dicari literal', () async {
    final now = DateTime.now().toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1',
      name: 'Cash',
      createdAt: now,
    ));
    Future<void> addTx(String id, String note) =>
        db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: id,
              accountId: 'acc1',
              date: now,
              note: Value(note),
            ));
    await addTx('tx1', 'bonus 100%');
    await addTx('tx2', 'transfer_bca');

    // '%' tanpa escape berarti "semua baris" — kini dicari literal.
    final pct = await db.watchTransactionsFiltered(search: '%').first;
    expect(pct.single.note, 'bonus 100%');

    final underscore = await db.watchTransactionsFiltered(search: '_').first;
    expect(underscore.single.note, 'transfer_bca');

    final bonus = await db.watchTransactionsFiltered(search: 'bonus').first;
    expect(bonus.single.note, 'bonus 100%');
  });

  test('cicilan lunas: pembayaran ke-N nonaktif+completed, durasi 0 tetap aktif',
      () async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1', name: 'Cash', createdAt: now,
    ));
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill3x', name: 'Cicilan HP', accountId: 'acc1',
      durationMonths: const Value(3), createdAt: now,
    ));
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'billLangganan', name: 'Internet', accountId: 'acc1', createdAt: now,
    ));

    for (var i = 0; i < 2; i++) {
      final bill =
          await (db.select(db.bills)..where((b) => b.id.equals('bill3x')))
              .getSingle();
      await db.payBillWithTransaction(bill);
    }
    var cicilan =
        await (db.select(db.bills)..where((b) => b.id.equals('bill3x')))
            .getSingle();
    expect(cicilan.active, true);
    expect(cicilan.completed, false);

    await db.payBillWithTransaction(cicilan);
    cicilan = await (db.select(db.bills)..where((b) => b.id.equals('bill3x')))
        .getSingle();
    expect(cicilan.active, false);
    expect(cicilan.completed, true);
    expect(
        (await db.watchCompletedBills().first).map((b) => b.id), ['bill3x']);

    var langganan = await (db.select(db.bills)
          ..where((b) => b.id.equals('billLangganan')))
        .getSingle();
    await db.payBillWithTransaction(langganan);
    langganan = await (db.select(db.bills)
          ..where((b) => b.id.equals('billLangganan')))
        .getSingle();
    expect(langganan.active, true);
    expect(langganan.completed, false);
  });

  test('deleteAccountCascade: semua jejak wallet hilang, akun lain utuh',
      () async {
    final now = DateTime.now().toIso8601String();

    // acc1 = target hapus, acc2 = pembanding
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1', name: 'GoPay', createdAt: now,
    ));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc2', name: 'Cash', createdAt: now,
    ));

    // acc1: tagihan + pembayaran + transaksi + transfer keluar dari acc2
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill1', name: 'Listrik', accountId: 'acc1', createdAt: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx-pay', accountId: 'acc1', type: const Value('expense'),
      amount: const Value(5000), date: now,
    ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
      id: 'pay1', billId: 'bill1', transactionId: 'tx-pay', paidAt: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx-transfer', accountId: 'acc2',
      toAccountId: const Value('acc1'), type: const Value('transfer'),
      amount: const Value(10000), date: now,
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx-other', accountId: 'acc2', type: const Value('expense'),
      amount: const Value(2000), date: now,
    ));

    final (txCount, billCount) = await db.accountUsage('acc1');
    expect(txCount, 2); // tx-pay + tx-transfer
    expect(billCount, 1);

    await db.deleteAccountCascade('acc1');

    expect(await db.accountUsage('acc1'), (0, 0));
    // Semua baris terkait acc1 lenyap…
    expect(
        await (db.select(db.transactions)
              ..where((t) => t.id.isIn(['tx-pay', 'tx-transfer'])))
            .get(),
        isEmpty);
    expect(
        await (db.select(db.bills)..where((b) => b.id.equals('bill1'))).get(),
        isEmpty);
    expect(
        await (db.select(db.billPayments)
              ..where((p) => p.id.equals('pay1')))
            .get(),
        isEmpty);
    expect(
        await (db.select(db.accounts)..where((a) => a.id.equals('acc1')))
            .get(),
        isEmpty);
    // …dan acc2 kehilangan hanya transfer-nya, transaksi miliknya utuh.
    final acc2Txs = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals('acc2')))
        .get();
    expect(acc2Txs.map((t) => t.id), ['tx-other']);
  });

  test('deleteTransactionCascade: pembayaran cicilan dibatalkan → bill aktif lagi',
      () async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
      id: 'acc1', name: 'Cash', createdAt: now,
    ));

    // Cicilan 2× bulan; bill completed (2 pembayaran tercatat).
    await db.into(db.bills).insert(BillsCompanion.insert(
      id: 'bill1', name: 'HP', accountId: 'acc1',
      amount: const Value(100000), durationMonths: const Value(2),
      createdAt: now,
    ));
    for (var i = 0; i < 2; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 'tx-pay$i', accountId: 'acc1',
        type: const Value('expense'), amount: const Value(100000),
        date: now,
      ));
      await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'pay$i', billId: 'bill1', transactionId: 'tx-pay$i', paidAt: now,
      ));
    }
    await (db.update(db.bills)..where((b) => b.id.equals('bill1'))).write(
      const BillsCompanion(active: Value(false), completed: Value(true)),
    );

    // Batalkan pembayaran terakhir → payment hilang + bill hidup kembali.
    await db.deleteTransactionCascade('tx-pay1');

    expect(
      await (db.select(db.billPayments)
            ..where((p) => p.id.equals('pay1')))
          .getSingleOrNull(),
      isNull,
    );
    final bill = await (db.select(db.bills)
          ..where((b) => b.id.equals('bill1')))
        .getSingle();
    expect(bill.active, isTrue);
    expect(bill.completed, isFalse);

    // Transaksi biasa (bukan pembayaran tagihan) tetap terhapus bersih.
    await db.deleteTransactionCascade('tx-pay1'); // sudah tidak ada — aman
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      id: 'tx-plain', accountId: 'acc1', type: const Value('expense'),
      amount: const Value(9000), date: now,
    ));
    await db.deleteTransactionCascade('tx-plain');
    expect(
      await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx-plain')))
          .getSingleOrNull(),
      isNull,
    );
  });

  test('billHitsMonth: bayar bulan ini hilang, cicilan habis tak muncul',
      () async {
    final now = DateTime.now();
    final iso = now.toIso8601String();
    final m1 = DateTime(now.year, now.month - 1).toIso8601String();
    final m2 = DateTime(now.year, now.month - 2).toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cash',
          createdAt: iso,
        ));
    // Langganan selamanya.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b1',
          name: 'Netflix',
          accountId: 'acc1',
          amount: const Value(50000),
          dueDay: const Value(10),
          createdAt: iso,
        ));
    // Cicilan 3×, dibayar 2× (2 & 1 bulan lalu) → bulan ini ke-3,
    // bulan depan jatah habis.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b2',
          name: 'Cicilan HP',
          accountId: 'acc1',
          amount: const Value(100000),
          dueDay: const Value(15),
          durationMonths: const Value(3),
          createdAt: iso,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          accountId: 'acc1',
          type: const Value('expense'),
          amount: const Value(100000),
          date: iso,
        ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p1', billId: 'b2', transactionId: 'tx1', paidAt: m2));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p2', billId: 'b2', transactionId: 'tx1', paidAt: m1));
    // Listrik, sudah dibayar bulan ini → hilang dari m=0, muncul lagi m=1.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b3',
          name: 'Listrik',
          accountId: 'acc1',
          amount: const Value(200000),
          dueDay: const Value(20),
          createdAt: iso,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          accountId: 'acc1',
          type: const Value('expense'),
          amount: const Value(200000),
          date: iso,
        ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p3', billId: 'b3', transactionId: 'tx2', paidAt: iso));

    final rows = await db.watchActiveBillsDetailed().first;
    List<String> due(int m) =>
        [for (final r in rows) if (billHitsMonth(r, m)) r.bill.id];

    expect(due(0), ['b1', 'b2']);
    expect(due(1), ['b1', 'b3']);
    // Listrik langganan → terus muncul; cicilan HP tetap habis.
    expect(due(2), ['b1', 'b3']);
  });

  test('7 hari: transaksi hari ini (dengan jam) hanya masuk saat to=besok',
      () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today
        .subtract(const Duration(days: 6))
        .toIso8601String()
        .substring(0, 10);
    final toToday = today.toIso8601String().substring(0, 10);
    final toTomorrow = today
        .add(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);

    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cash',
          createdAt: now.toIso8601String(),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-today',
          accountId: 'acc1',
          type: const Value('expense'),
          amount: const Value(25000),
          date: now.toIso8601String(), // ada komponen jam
        ));

    // Bug lama: to=tanggal hari ini → "…T14:30" > "…" string, hilang.
    expect(await db.watchTransactionsByDateRange(from, toToday).first, isEmpty);
    // Fix: to=besok.
    final got = await db.watchTransactionsByDateRange(from, toTomorrow).first;
    expect(got.map((t) => t.id), ['tx-today']);
  });

  test('watchActiveBillsDetailed + billsForMonth: cicilan & bayar bulan ini',
      () async {
    final now = DateTime.now();
    final iso = now.toIso8601String();
    final m1 = DateTime(now.year, now.month - 1).toIso8601String();
    final m2 = DateTime(now.year, now.month - 2).toIso8601String();

    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Cash',
          createdAt: iso,
        ));
    // Langganan, belum pernah dibayar.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b1',
          name: 'Netflix',
          accountId: 'acc1',
          amount: const Value(50000),
          createdAt: iso,
        ));
    // Cicilan 3 bulan, dibayar 2 bulan lalu & bulan lalu (belum bln ini).
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b2',
          name: 'Cicilan HP',
          accountId: 'acc1',
          amount: const Value(100000),
          durationMonths: const Value(3),
          createdAt: iso,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          accountId: 'acc1',
          type: const Value('expense'),
          amount: const Value(100000),
          date: iso,
        ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p1', billId: 'b2', transactionId: 'tx1', paidAt: m2));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p2', billId: 'b2', transactionId: 'tx1', paidAt: m1));
    // Sudah dibayar bulan ini.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'b3',
          name: 'Listrik',
          accountId: 'acc1',
          amount: const Value(200000),
          createdAt: iso,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx2',
          accountId: 'acc1',
          type: const Value('expense'),
          amount: const Value(200000),
          date: iso,
        ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
        id: 'p3', billId: 'b3', transactionId: 'tx2', paidAt: iso));

    final entries = await db.watchActiveBillsDetailed().first;
    expect(entries.length, 3);
    final byAmount = {for (final e in entries) e.bill.amount: e};
    expect(byAmount[50000]!.bill.durationMonths, 0);
    expect(byAmount[50000]!.paidThisMonth, false);
    expect(byAmount[100000]!.paidMonths, 2);
    expect(byAmount[100000]!.paidThisMonth, false);
    expect(byAmount[200000]!.paidThisMonth, true);

    // Bulan ini: Netflix + Cicilan (cicilan ke-3), Listrik sudah → 150000.
    expect(billsForMonth(entries, 0).total, 150000);
    // Bulan depan: Netflix + Listrik; jatah cicilan sudah habis → 250000.
    expect(billsForMonth(entries, 1).total, 250000);
    expect(billsForMonth(entries, 1).count, 2);
    // Kumulatif s/d bulan depan.
    expect(billsThroughMonth(entries, 1), 400000);
  });

  test('undo transaksi: capture → hapus → restore kembalikan semua state',
      () async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1', name: 'Cash', createdAt: now,
        ));
    // Cicilan 2× yang sudah lunas + transaksi biasa.
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'bill1', name: 'HP', accountId: 'acc1',
          amount: const Value(100000), durationMonths: const Value(2),
          createdAt: now,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-plain', accountId: 'acc1', type: const Value('expense'),
          amount: const Value(9000), date: now,
        ));
    for (var i = 0; i < 2; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx-pay$i', accountId: 'acc1',
            type: const Value('expense'), amount: const Value(100000),
            date: now,
          ));
      await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
            id: 'pay$i', billId: 'bill1', transactionId: 'tx-pay$i',
            paidAt: now,
          ));
    }
    await (db.update(db.bills)..where((b) => b.id.equals('bill1'))).write(
      const BillsCompanion(active: Value(false), completed: Value(true)),
    );

    // Undo transaksi pembayaran terakhir.
    final undo = await db.captureTransactionUndo('tx-pay1');
    expect(undo, isNotNull);
    expect(undo!.payments.map((p) => p.id), ['pay1']);
    expect(undo.billStates['bill1']!.active, isFalse);
    expect(undo.billStates['bill1']!.completed, isTrue);

    await db.deleteTransactionCascade('tx-pay1');
    // Habis dari DB…
    expect(
        await (db.select(db.transactions)
              ..where((t) => t.id.equals('tx-pay1')))
            .getSingleOrNull(),
        isNull);

    // …lalu dikembalikan persis seperti semula.
    await db.restoreTransactionUndo(undo);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-pay1')))
        .getSingle();
    expect(tx.amount, 100000);
    expect(
        await (db.select(db.billPayments)
              ..where((p) => p.id.equals('pay1')))
            .getSingleOrNull(),
        isNotNull);
    final bill = await (db.select(db.bills)
          ..where((b) => b.id.equals('bill1')))
        .getSingle();
    expect(bill.active, isFalse);
    expect(bill.completed, isTrue);

    // capture transaksi yang tidak ada → null.
    expect(await db.captureTransactionUndo('nope'), isNull);
  });

  test('undo tagihan: capture → hapus → restore beserta pembayaran', () async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1', name: 'Cash', createdAt: now,
        ));
    await db.into(db.bills).insert(BillsCompanion.insert(
          id: 'bill1', name: 'Listrik', accountId: 'acc1',
          amount: const Value(15000), createdAt: now,
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-pay', accountId: 'acc1', type: const Value('expense'),
          amount: const Value(15000), date: now,
        ));
    await db.into(db.billPayments).insert(BillPaymentsCompanion.insert(
          id: 'pay1', billId: 'bill1', transactionId: 'tx-pay', paidAt: now,
        ));

    final undo = await db.captureBillUndo('bill1');
    expect(undo, isNotNull);
    expect(undo!.bill.name, 'Listrik');
    expect(undo.payments.map((p) => p.id), ['pay1']);

    await db.deleteBillCascade('bill1');
    expect(
        await (db.select(db.bills)..where((b) => b.id.equals('bill1')))
            .getSingleOrNull(),
        isNull);
    expect(
        await (db.select(db.billPayments)
              ..where((p) => p.id.equals('pay1')))
            .getSingleOrNull(),
        isNull);

    await db.restoreBillUndo(undo);
    final bill = await (db.select(db.bills)
          ..where((b) => b.id.equals('bill1')))
        .getSingle();
    expect(bill.amount, 15000);
    expect(
        await (db.select(db.billPayments)
              ..where((p) => p.id.equals('pay1')))
            .getSingleOrNull(),
        isNotNull);

    // capture tagihan yang tidak ada → null.
    expect(await db.captureBillUndo('nope'), isNull);
  });

  Transaction mkTx(String id, String type, int amount, String date) =>
      Transaction(
        id: id,
        accountId: 'acc1',
        type: type,
        amount: amount,
        note: '',
        date: date,
      );

  test('monthTrendBuckets: 6 bar berakhir di bulan anchor', () {
    final txs = [
      mkTx('a', 'expense', 10, '2026-04-15T10:00:00'),
      mkTx('b', 'expense', 20, '2026-09-02T10:00:00'),
      mkTx('c', 'expense', 5, '2026-09-30T10:00:00'),
      mkTx('d', 'income', 999, '2026-09-05T10:00:00'), // masuk, bukan keluar
      mkTx('e', 'expense', 7, '2026-03-31T10:00:00'), // sebelum jendela
    ];
    final flow = monthTrendBuckets(txs, DateTime(2026, 9));
    expect(flow.expense.length, 6);
    expect(flow.income.length, 6);
    // first = anchor - 5 = April → indeks 0=Apr … 5=Sep.
    expect(flow.expense[0], 10); // Apr
    expect(flow.expense[5], 25); // Sep = 20 + 5
    // Pemasukan terpisah: hanya Sep, tidak menodai expense.
    expect(flow.income[5], 999);
    expect(flow.income[0], 0);
  });
}
