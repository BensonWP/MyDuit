import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/db/database.dart';
import 'package:myduit/utils/report_math.dart';

Transaction _tx(String id, String type, int amount, [String? cat]) =>
    Transaction(
      id: id,
      accountId: 'acc1',
      categoryId: cat,
      type: type,
      amount: amount,
      note: '',
      date: DateTime.now().toIso8601String(),
    );

void main() {
  group('computeReportTotals', () {
    test('agregat income/expense + hitungan transaksi', () {
      final t = computeReportTotals([
        _tx('a', 'expense', 100, 'c1'),
        _tx('b', 'expense', 50, 'c1'),
        _tx('c', 'income', 900, 'c9'),
        _tx('d', 'transfer', 7, 'c1'), // tipe lain diabaikan
      ]);
      expect(t.expense, 150);
      expect(t.income, 900);
      expect(t.expenseCount, 2);
      expect(t.incomeCount, 1);
    });

    test('kategori expense diurut total menurun + jumlah', () {
      final t = computeReportTotals([
        _tx('a', 'expense', 30, 'c1'),
        _tx('b', 'expense', 30, 'c1'),
        _tx('c', 'expense', 90, 'c2'),
        _tx('d', 'expense', 10, null), // tanpa kategori: masuk total, bukan baris
      ]);
      expect(t.expense, 160);
      expect(t.expenseByCategory.map((r) => r.id).toList(), ['c2', 'c1']);
      expect(t.expenseByCategory.first.total, 90);
      expect(t.expenseByCategory.first.count, 1);
      expect(t.expenseByCategory.last.total, 60);
      expect(t.expenseByCategory.last.count, 2);
    });

    test('kategori income dipisah dari expense', () {
      final t = computeReportTotals([
        _tx('a', 'income', 700, 'c9'),
        _tx('b', 'income', 300, 'c9'),
        _tx('c', 'expense', 500, 'c9'), // id sama, arus beda
      ]);
      expect(t.incomeByCategory.single.id, 'c9');
      expect(t.incomeByCategory.single.total, 1000);
      expect(t.incomeByCategory.single.count, 2);
      expect(t.expenseByCategory.single.total, 500);
    });

    test('daftar kosong → semua nol', () {
      final t = computeReportTotals(const []);
      expect(t.income, 0);
      expect(t.expense, 0);
      expect(t.incomeCount, 0);
      expect(t.expenseCount, 0);
      expect(t.expenseByCategory, isEmpty);
      expect(t.incomeByCategory, isEmpty);
    });
  });

  group('monthShortName', () {
    test('nama singkat Indonesia', () {
      expect(monthShortName(1), 'Jan');
      expect(monthShortName(5), 'Mei');
      expect(monthShortName(8), 'Agu');
      expect(monthShortName(12), 'Des');
    });
  });

  group('expenseDeltaText', () {
    test('bulan lalu belum termuat', () {
      expect(expenseDeltaText(100, null, DateTime(2025, 1)),
          'memuat perbandingan…');
    });

    test('pembanding nol', () {
      expect(expenseDeltaText(0, 0, DateTime(2025, 1)),
          'belum ada pengeluaran');
      expect(expenseDeltaText(50, 0, DateTime(2025, 1)),
          'mulai tercatat bulan ini');
    });

    test('naik/turun/sama', () {
      expect(expenseDeltaText(123, 100, DateTime(2025, 1)), '▲ 23% vs Jan');
      expect(expenseDeltaText(90, 100, DateTime(2025, 2)), '▼ 10% vs Feb');
      expect(expenseDeltaText(100, 100, DateTime(2025, 3)),
          'sama dengan Mar');
    });
  });
}
