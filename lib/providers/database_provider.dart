import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';

final dbProvider = Provider<MyDuitDatabase>((ref) {
  final db = MyDuitDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// ─── Account providers ────────────────────────────────────────────

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(dbProvider).watchAllAccounts();
});

// ─── Category providers ──────────────────────────────────────────

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(dbProvider).watchAllCategories();
});

// ─── Transaction providers ────────────────────────────────────────

final recentTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  return ref.watch(dbProvider).watchRecentTransactions();
});

// ─── Bill providers ───────────────────────────────────────────────

final activeBillsStreamProvider = StreamProvider<List<Bill>>((ref) {
  return ref.watch(dbProvider).watchActiveBills();
});

// ─── Balance computation (manual state for total balance) ──────────

final totalBalanceProvider = FutureProvider<int>((ref) async {
  ref.watch(accountsStreamProvider);
  ref.watch(recentTransactionsProvider);
  return ref.watch(dbProvider).totalBalance();
});

final accountBalanceProvider = FutureProvider.family<int, String>((ref, accountId) async {
  ref.watch(recentTransactionsProvider);
  return ref.watch(dbProvider).accountBalance(accountId);
});
