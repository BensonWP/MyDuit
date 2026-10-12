import '../db/database.dart';

/// Baris agregat per kategori di tab Ringkasan Laporan:
/// total nominal + jumlah transaksi.
class CategoryTotal {
  const CategoryTotal({
    required this.id,
    required this.total,
    required this.count,
  });

  final String id;
  final int total;
  final int count;
}

/// Hasil agregasi transaksi sebulan (murni, tanpa widget/SQL).
class ReportTotals {
  const ReportTotals({
    required this.income,
    required this.expense,
    required this.incomeCount,
    required this.expenseCount,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  final int income;
  final int expense;
  final int incomeCount;
  final int expenseCount;

  /// Baris kategori pengeluaran, urut total menurun.
  final List<CategoryTotal> expenseByCategory;

  /// Baris kategori pemasukan, urut total menurun.
  final List<CategoryTotal> incomeByCategory;
}

/// Agregasi transaksi (income/expense) per kategori dalam satu lintasan.
/// Data sebulan kecil, jadi hitung di Dart — tak perlu SQL tambahan.
ReportTotals computeReportTotals(List<Transaction> txs) {
  var income = 0, expense = 0, incomeCount = 0, expenseCount = 0;
  final byCategory = <String, int>{};
  final byCategoryCount = <String, int>{};
  final byIncomeCategory = <String, int>{};
  final byIncomeCategoryCount = <String, int>{};

  for (final tx in txs) {
    if (tx.type == 'income') {
      income += tx.amount;
      incomeCount++;
      if (tx.categoryId != null) {
        final id = tx.categoryId!;
        byIncomeCategory[id] = (byIncomeCategory[id] ?? 0) + tx.amount;
        byIncomeCategoryCount[id] = (byIncomeCategoryCount[id] ?? 0) + 1;
      }
    } else if (tx.type == 'expense') {
      expense += tx.amount;
      expenseCount++;
      if (tx.categoryId != null) {
        final id = tx.categoryId!;
        byCategory[id] = (byCategory[id] ?? 0) + tx.amount;
        byCategoryCount[id] = (byCategoryCount[id] ?? 0) + 1;
      }
    }
  }

  return ReportTotals(
    income: income,
    expense: expense,
    incomeCount: incomeCount,
    expenseCount: expenseCount,
    expenseByCategory: _rows(byCategory, byCategoryCount),
    incomeByCategory: _rows(byIncomeCategory, byIncomeCategoryCount),
  );
}

List<CategoryTotal> _rows(
  Map<String, int> totals,
  Map<String, int> counts,
) =>
    totals.entries
        .map((e) => CategoryTotal(
            id: e.key, total: e.value, count: counts[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];

/// Nama bulan singkat Indonesia (1 = Jan).
String monthShortName(int month) => _monthShort[month - 1];

/// "▲ 23% vs Jan" / "▼ 10% vs Jan" / teks khusus saat data
/// bulan lalu belum termuat atau nol.
String expenseDeltaText(int expense, int? prevExpense, DateTime prevMonth) {
  if (prevExpense == null) return 'memuat perbandingan…';
  if (prevExpense == 0) {
    return expense > 0 ? 'mulai tercatat bulan ini' : 'belum ada pengeluaran';
  }
  final pct = ((expense - prevExpense) / prevExpense * 100).round();
  final name = _monthShort[prevMonth.month - 1];
  if (pct == 0) return 'sama dengan $name';
  return pct > 0 ? '▲ $pct% vs $name' : '▼ ${-pct}% vs $name';
}
