import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
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
}
