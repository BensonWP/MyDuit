import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../utils/tx_grouping.dart';
import '../widgets/transaction_tile.dart';

/// Rentang waktu cepat untuk filter transaksi.
enum _TimeMode { all, thisMonth, lastMonth, last12 }

class HistoryTab extends ConsumerStatefulWidget {
  const HistoryTab({super.key});

  @override
  HistoryTabState createState() => HistoryTabState();
}

class HistoryTabState extends ConsumerState<HistoryTab> {
  final _searchController = TextEditingController();
  String? _type;
  String? _accountId;
  String? _categoryId;
  _TimeMode _time = _TimeMode.all;

  /// Kustom dari tap legenda Laporan: rentang bulan laporan aktif,
  /// menimpa [_time] sampai pengguna memilih opsi dropdown lagi.
  String? _customFrom;
  String? _customTo;
  String? _customLabel;

  static const _typeOptions = [
    (null, 'Semua'),
    ('expense', 'Pengeluaran'),
    ('income', 'Pemasukan'),
  ];

  static const _timeLabels = {
    _TimeMode.all: 'Semua waktu',
    _TimeMode.thisMonth: 'Bulan ini',
    _TimeMode.lastMonth: 'Bulan lalu',
    _TimeMode.last12: '12 bulan terakhir',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Dipanggil dari Laporan: tampilkan transaksi [categoryId] pada
  /// bulan laporan aktif ([from], [to], [label] untuk dropdown).
  void applyCategoryFilter(
    String categoryId, {
    required String from,
    required String to,
    required String label,
  }) {
    setState(() {
      _categoryId = categoryId;
      _type = 'expense'; // donut = pengeluaran
      _customFrom = from;
      _customTo = to;
      _customLabel = label;
    });
  }

  ({String? from, String? to, String label}) get _timeRange {
    if (_customFrom != null) {
      return (from: _customFrom, to: _customTo, label: _customLabel ?? 'Bulan laporan');
    }
    final now = DateTime.now();
    switch (_time) {
      case _TimeMode.all:
        return (from: null, to: null, label: _timeLabels[_TimeMode.all]!);
      case _TimeMode.thisMonth:
        final r = monthRange(DateTime(now.year, now.month));
        return (from: r.from, to: r.to, label: _timeLabels[_TimeMode.thisMonth]!);
      case _TimeMode.lastMonth:
        final r = monthRange(DateTime(now.year, now.month - 1));
        return (from: r.from, to: r.to, label: _timeLabels[_TimeMode.lastMonth]!);
      case _TimeMode.last12:
        final r = monthRange(DateTime(now.year, now.month - 11));
        return (from: r.from, to: null, label: _timeLabels[_TimeMode.last12]!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final catMap = <String, String>{
      for (final c
          in ref.watch(categoriesStreamProvider).valueOrNull ?? const [])
        c.id: c.name,
    };
    final time = _timeRange;
    final txs = ref
            .watch(historyProvider(HistoryFilter(
              type: _type,
              accountId: _accountId,
              categoryId: _categoryId,
              search: _searchController.text,
              from: time.from,
              to: time.to,
            )))
            .valueOrNull ??
        [];

    // Ringkasan hasil filter — dihitung di Dart dari list yang ada.
    final masuk = txs
        .where((t) => t.type == 'income')
        .fold<int>(0, (a, t) => a + t.amount);
    final keluar = txs
        .where((t) => t.type == 'expense')
        .fold<int>(0, (a, t) => a + t.amount);

    final selectedAccount = _accountId == null
        ? null
        : accounts.where((a) => a.id == _accountId).firstOrNull;

    final hasFilter = _type != null ||
        _accountId != null ||
        _categoryId != null ||
        _searchController.text.isNotEmpty ||
        time.from != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Cari catatan…',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: D.s4, vertical: D.s1),
            children: [
              for (final (value, label) in _typeOptions)
                Padding(
                  padding: const EdgeInsets.only(right: D.s2),
                  child: ChoiceChip(
                    label: Text(label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _type == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _type == value ? Colors.white : D.ink,
                        )),
                    selected: _type == value,
                    onSelected: (_) => setState(() => _type = value),
                    selectedColor: D.cobalt,
                    backgroundColor: D.card,
                    side: BorderSide(
                        color: _type == value ? D.cobalt : D.line),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    labelPadding:
                        const EdgeInsets.symmetric(horizontal: D.s3),
                  ),
                ),
              PopupMenuButton<String?>(
                initialValue: _accountId,
                onSelected: (v) => setState(() => _accountId = v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Semua Wallet')),
                  ...accounts.map((a) =>
                      PopupMenuItem(value: a.id, child: Text(a.name))),
                ],
                child: _FilterPill(
                  icon: Icons.account_balance_wallet_rounded,
                  label: selectedAccount?.name ?? 'Semua Wallet',
                  active: _accountId != null,
                ),
              ),
              const SizedBox(width: D.s2),
              PopupMenuButton<_TimeMode>(
                initialValue: _customFrom == null ? _time : null,
                onSelected: (v) => setState(() {
                  _time = v;
                  _customFrom = _customTo = _customLabel = null;
                }),
                itemBuilder: (_) => _TimeMode.values
                    .map((m) => PopupMenuItem(
                        value: m, child: Text(_timeLabels[m]!)))
                    .toList(),
                child: _FilterPill(
                  icon: Icons.date_range_rounded,
                  label: time.label,
                  active: time.from != null,
                ),
              ),
              if (_categoryId != null) ...[
                const SizedBox(width: D.s2),
                GestureDetector(
                  onTap: () => setState(() => _categoryId = null),
                  child: _FilterPill(
                    icon: Icons.label_rounded,
                    label: catMap[_categoryId] ?? 'Kategori',
                    active: true,
                    trailing: Icons.close_rounded,
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(D.s4, D.s1, D.s4, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: D.s3, vertical: D.s2 + 2),
            decoration: BoxDecoration(
              color: D.card,
              borderRadius: BorderRadius.circular(D.rMd),
              border: Border.all(color: D.line),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text('Masuk ${formatRupiah(masuk)}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: D.income)),
                Container(width: 1, height: 14, color: D.line),
                Text('Keluar ${formatRupiah(keluar)}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: D.expense)),
              ],
            ),
          ),
        ),
        Expanded(
          child: txs.isEmpty
              ? _EmptyHistory(hasFilter: hasFilter)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
                  itemCount: txs.length,
                  itemBuilder: (ctx, i) {
                    final accountName = accounts
                        .where((a) => a.id == txs[i].accountId)
                        .firstOrNull
                        ?.name;
                    // Header hari saat tanggal berubah
                    final showHeader = i == 0 ||
                        txs[i].date.substring(0, 10) !=
                            txs[i - 1].date.substring(0, 10);
                    final dayKey = txs[i].date.substring(0, 10);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Padding(
                            padding: const EdgeInsets.only(top: D.s2, bottom: D.s1),
                            child: Text(
                              dayLabel(dayKey),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: D.inkMuted),
                            ),
                          ),
                        TransactionTile(
                          transaction: txs[i],
                          accountName: accountName ?? '-',
                          categoryName:
                              txs[i].categoryId == null
                                  ? null
                                  : catMap[txs[i].categoryId],
                          index: i,
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.active,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool active;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: D.s3),
      decoration: BoxDecoration(
        color: active ? D.cobalt.withValues(alpha: 0.1) : D.card,
        borderRadius: BorderRadius.circular(D.rSm + 4),
        border: Border.all(color: active ? D.cobalt.withValues(alpha: 0.4) : D.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15, color: active ? D.cobalt : D.inkMuted),
          const SizedBox(width: D.s1 + 2),
          Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? D.cobalt : D.inkMuted,
              )),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 14, color: D.cobalt),
          ],
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.hasFilter});
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(D.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 44, color: D.inkMuted),
            const SizedBox(height: D.s4),
            Text(
              hasFilter
                  ? 'Tidak ada transaksi yang cocok'
                  : 'Belum ada transaksi',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: D.s2),
            Text(
              hasFilter
                  ? 'Coba ubah kata kunci atau hapus filter di atas.'
                  : 'Transaksi yang dicatat akan tampil di sini.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: D.inkMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
