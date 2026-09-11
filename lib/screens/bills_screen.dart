import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../utils/dates.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';

/// Apakah tagihan ini sudah dibayar di bulan berjalan.
bool paidThisMonth(List<BillPayment> payments) {
  final monthKey = DateTime.now().toIso8601String().substring(0, 7);
  return payments.any((p) => p.paidAt.substring(0, 7) == monthKey);
}

/// Konfirmasi + bayar tagihan (transaksi otomatis). Dipakai di
/// kartu tagihan dan kartu "Tagihan Berikutnya" di Beranda.
Future<void> confirmAndPayBill(
  BuildContext context,
  WidgetRef ref,
  Bill bill,
  String accountName,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Bayar ${bill.name}?'),
      content: Text(
          '${formatRupiah(bill.amount)} akan dicatat dari wallet $accountName.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: D.cobalt),
          child: const Text('Bayar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final db = ref.read(dbProvider);
  try {
    await db.payBillWithTransaction(bill);
  } on InsufficientBalanceException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Saldo $accountName tidak cukup · kurang ${formatRupiah(e.short)}')),
    );
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final fresh = await (db.select(db.bills)
        ..where((b) => b.id.equals(bill.id)))
      .getSingleOrNull();
  final lunas = fresh != null && fresh.completed;
  messenger.showSnackBar(
    SnackBar(
        content: Text(lunas
            ? '${bill.name} lunas — cicilan selesai!'
            : '${bill.name} dibayar · ${formatRupiah(bill.amount)}')),
  );
}

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan')),
      body: const _BillsTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showBillSheet(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _BillsTab extends ConsumerWidget {
  const _BillsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(activeBillsProvider);
    final completed = ref.watch(completedBillsStreamProvider).valueOrNull ?? [];
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return bills.isEmpty && completed.isEmpty
        ? _EmptyBills(reducedMotion: reducedMotion)
        : ListView(
            padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
            children: [
              for (var i = 0; i < bills.length; i++)
                _BillTile(
                  bill: bills[i],
                  accountName: accounts
                          .where((a) => a.id == bills[i].accountId)
                          .firstOrNull
                          ?.name ??
                      '-',
                  index: i,
                  animate: !reducedMotion,
                ),
              if (completed.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: D.s4, bottom: D.s2),
                  child: Text('Lunas',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                for (final bill in completed)
                  _CompletedBillTile(
                    bill: bill,
                    accountName: accounts
                            .where((a) => a.id == bill.accountId)
                            .firstOrNull
                            ?.name ??
                        '-',
                  ),
              ],
            ],
          );
  }
}

Future<void> showBillSheet(BuildContext context, {Bill? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BillSheet(existing: existing),
  );
}

// ── Kartu tagihan ──────────────────────────────────────────────────

class _BillTile extends ConsumerStatefulWidget {
  const _BillTile({
    required this.bill,
    required this.accountName,
    required this.index,
    required this.animate,
  });

  final Bill bill;
  final String accountName;
  final int index;
  final bool animate;

  @override
  ConsumerState<_BillTile> createState() => _BillTileState();
}

class _BillTileState extends ConsumerState<_BillTile> {
  bool _paying = false;

  Bill get bill => widget.bill;
  String get accountName => widget.accountName;
  int get index => widget.index;
  bool get animate => widget.animate;

  /// Selisih hari ke jatuh tempo berikutnya (0 = hari ini).
  int get _daysUntil => daysUntilDue(bill.dueDay);

  ({Color color, Color bg, String label}) get _urgency {
    final d = _daysUntil;
    if (d <= 3) {
      return (color: D.expense, bg: D.expense.withValues(alpha: 0.1), label: 'H-$d');
    }
    return (color: D.inkMuted, bg: D.surface, label: 'H-$d');
  }

  Future<void> _pay() async {
    if (_paying) return; // guard double-tap
    setState(() => _paying = true);
    try {
      await confirmAndPayBill(context, ref, bill, accountName);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _urgency;
    // Cek pembayaran bulan ini → tombol Bayar berubah chip hijau.
    final payments =
        ref.watch(billPaymentsProvider(bill.id)).valueOrNull ?? [];
    final paidThisMonthFlag = paidThisMonth(payments);
    final paidCount = payments.length;
    // Kurang berapa vs wallet yang akan di-debit.
    final walletBalance =
        ref.watch(accountBalanceProvider(bill.accountId)).valueOrNull;
    final short = walletBalance == null ? 0 : bill.amount - walletBalance;

    return Container(
      margin: const EdgeInsets.only(bottom: D.s3),
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showBillSheet(context, existing: bill),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: D.cobalt.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(D.rSm + 2),
              ),
              child: const Icon(Icons.receipt_rounded, color: D.cobalt, size: 20),
            ),
          ),
          const SizedBox(width: D.s3),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showBillSheet(context, existing: bill),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Tgl ${bill.dueDay} · $accountName'
                    '${bill.durationMonths > 0 ? ' · ${paidCount.clamp(0, bill.durationMonths)}/${bill.durationMonths} dibayar' : ''}',
                    style: const TextStyle(fontSize: 12, color: D.inkMuted),
                  ),
                  if (paidThisMonthFlag && payments.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Dibayar ${formatDate(payments.first.paidAt)} · ${formatTime(payments.first.paidAt)}',
                      style: const TextStyle(
                          fontSize: 11, color: D.income, fontWeight: FontWeight.w600),
                    ),
                  ],
                  if (!paidThisMonthFlag && short > 0)
                    Text('Kurang ${formatRupiah(short)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: D.expense)),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatRupiah(bill.amount),
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3)),
              const SizedBox(height: D.s2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: D.s2, vertical: 2),
                    decoration: BoxDecoration(
                      color: u.bg,
                      borderRadius: BorderRadius.circular(D.rSm),
                    ),
                    child: Text(
                      u.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: u.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: D.s2),
                  if (paidThisMonthFlag)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: D.s3, vertical: 4),
                      decoration: BoxDecoration(
                        color: D.income.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(D.rSm),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 13, color: D.income),
                          SizedBox(width: 2),
                          Text(
                            'Dibayar',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: D.income,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _paying ? null : _pay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: D.s3, vertical: 4),
                        decoration: BoxDecoration(
                          color: D.cobalt,
                          borderRadius: BorderRadius.circular(D.rSm),
                        ),
                        child: const Text(
                          'Bayar',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    )
        .animate(target: animate ? 1 : 0)
        .fade(duration: 300.ms, delay: (50 * index).clamp(0, 400).ms)
        .slideY(
          begin: 0.1,
          end: 0,
          duration: 300.ms,
          delay: (50 * index).clamp(0, 400).ms,
          curve: Curves.easeOutCubic,
        );
  }
}

// ── Kartu tagihan lunas (histori) ──────────────────────────────────

class _CompletedBillTile extends ConsumerWidget {
  const _CompletedBillTile({required this.bill, required this.accountName});
  final Bill bill;
  final String accountName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments =
        ref.watch(billPaymentsProvider(bill.id)).valueOrNull ?? [];
    final lastPaid = payments.isNotEmpty ? payments.first.paidAt : null;

    return Container(
      margin: const EdgeInsets.only(bottom: D.s3),
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.surface,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: D.income.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(D.rSm + 2),
            ),
            child: const Icon(Icons.check_rounded, color: D.income, size: 20),
          ),
          const SizedBox(width: D.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bill.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: D.inkMuted)),
                const SizedBox(height: 2),
                Text(
                  '${bill.durationMonths}/${bill.durationMonths} dibayar · $accountName',
                  style: const TextStyle(fontSize: 12, color: D.inkMuted),
                ),
                if (lastPaid != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Selesai ${formatDate(lastPaid)} · ${formatTime(lastPaid)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: D.income,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: D.s3, vertical: 4),
            decoration: BoxDecoration(
              color: D.income.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(D.rSm),
            ),
            child: const Text('Lunas',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: D.income)),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet tambah/edit tagihan ───────────────────────────────

class _BillSheet extends ConsumerStatefulWidget {
  const _BillSheet({this.existing});
  final Bill? existing;

  @override
  ConsumerState<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends ConsumerState<_BillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  int _dueDay = 1;
  int _durationMonths = 0;
  String? _accountId;
  String? _categoryId;
  bool _isLoading = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _nameController.text = b.name;
      _amountController.text = b.amount.toString();
      _dueDay = b.dueDay;
      _durationMonths = b.durationMonths;
      _accountId = b.accountId;
      _categoryId = b.categoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih wallet')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final db = ref.read(dbProvider);

    final entry = BillsCompanion.insert(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      accountId: _accountId!,
      categoryId: Value(_categoryId),
      amount: Value(int.tryParse(parseCurrency(_amountController.text)) ?? 0),
      dueDay: Value(_dueDay),
      durationMonths: Value(_durationMonths),
      createdAt: widget.existing?.createdAt ?? DateTime.now().toIso8601String(),
    );

    if (_isEditing) {
      await db.updateBill(entry);
    } else {
      await db.insertBill(entry);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _deactivate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nonaktifkan tagihan?'),
        content: const Text(
            'Tagihan berhenti muncul dan tidak lagi dikirim pengingat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: D.expense),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await ref.read(dbProvider).deactivateBill(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      'Hapus ${widget.existing!.name}?',
      description:
          'Tagihan dan seluruh riwayat pembayarannya dihapus permanen. '
          'Transaksi yang sudah tercatat tidak terpengaruh.',
    );
    if (!confirmed || !mounted) return;

    final db = ref.read(dbProvider);
    // Snapshot dulu agar bisa diurungkan lewat snackbar di layar sebelumnya.
    final undo = await db.captureBillUndo(widget.existing!.id);
    await db.deleteBillCascade(widget.existing!.id);
    // Snackbar sebelum pop — context form sudah tidak valid setelahnya.
    if (undo != null && mounted) {
      showUndoBar(
          context, 'Tagihan dihapus', () => db.restoreBillUndo(undo));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final expenseCategories =
        categories.where((c) => c.type == 'expense').toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        D.s4,
        0,
        D.s4,
        MediaQuery.of(context).viewInsets.bottom + D.s4,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEditing ? 'Edit Tagihan' : 'Tambah Tagihan',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: D.s4),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama tagihan',
                  hintText: 'Listrik, internet, langganan…',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: D.s3),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Jumlah',
                  prefixText: 'Rp ',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [CurrencyInputFormatter()],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Wajib diisi';
                  final n = int.tryParse(parseCurrency(v));
                  if (n == null || n <= 0) return 'Harus lebih dari 0';
                  return null;
                },
              ),
              const SizedBox(height: D.s3),
              DropdownButtonFormField<String>(
                // Wallet bisa saja diarsipkan sejak bill dibuat —
                // nilainya diturunkan ke null agar dropdown tetap valid.
                value: accounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                decoration: const InputDecoration(labelText: 'Wallet'),
                items: accounts
                    .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: D.s3),
              DropdownButtonFormField<String>(
                value: expenseCategories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : null,
                decoration:
                    const InputDecoration(labelText: 'Kategori (opsional)'),
                items: expenseCategories
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: D.s3),
              const Text('Tanggal jatuh tempo tiap bulan',
                  style: TextStyle(fontSize: 12.5, color: D.inkMuted)),
              const SizedBox(height: D.s2),
              _BillDayGrid(
                selected: _dueDay,
                onChanged: (d) => setState(() => _dueDay = d),
              ),
              const SizedBox(height: D.s2),
              const Text(
                'Tgl 29–31 otomatis menyesuaikan bulan pendek '
                '(tgl 30 di Feb → 28/29).',
                style: TextStyle(fontSize: 11.5, color: D.inkMuted),
              ),
              const SizedBox(height: D.s3),
              DropdownButtonFormField<int>(
                value: _durationMonths,
                decoration: const InputDecoration(
                    labelText: 'Durasi cicilan (opsional)'),
                items: const [
                  DropdownMenuItem(
                      value: 0, child: Text('Berulang (tanpa batas)')),
                  DropdownMenuItem(value: 1, child: Text('1× (sekali bayar)')),
                  DropdownMenuItem(value: 2, child: Text('2× bulan')),
                  DropdownMenuItem(value: 3, child: Text('3× bulan')),
                  DropdownMenuItem(value: 6, child: Text('6× bulan')),
                  DropdownMenuItem(value: 12, child: Text('12× bulan')),
                ],
                onChanged: (v) => setState(() => _durationMonths = v ?? 0),
              ),
              const SizedBox(height: D.s6),
              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Simpan Perubahan' : 'Simpan Tagihan'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: D.s2),
                Center(
                  child: TextButton(
                    onPressed: _deactivate,
                    style: TextButton.styleFrom(foregroundColor: D.inkMuted),
                    child: const Text('Nonaktifkan tagihan ini'),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(foregroundColor: D.expense),
                    child: const Text('Hapus permanen'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Kalender pemilih tanggal jatuh tempo ───────────────────────────

class _BillDayGrid extends StatelessWidget {
  const _BillDayGrid({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Selalu 1–31 agar tgl 29–31 tetap bisa dipilih kapan pun;
    // tanggal efektifnya mengikuti panjang tiap bulan (Feb → 28/29).
    return Container(
      padding: const EdgeInsets.all(D.s3),
      decoration: BoxDecoration(
        color: D.surface,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 2,
        childAspectRatio: 1.25,
        children: [
          for (var d = 1; d <= 31; d++)
            _DayCell(
                day: d,
                selected: selected == d,
                onTap: () => onChanged(d)),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.onTap});
  final int day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? D.cobalt : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text('$day',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? Colors.white : D.ink,
              )),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyBills extends StatelessWidget {
  const _EmptyBills({required this.reducedMotion});
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(D.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_rounded, size: 48, color: D.inkMuted),
            const SizedBox(height: D.s4),
            const Text('Belum ada tagihan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: D.s2),
            const Text(
              'Daftarkan tagihan rutin seperti listrik atau langganan agar tidak terlewat.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: D.inkMuted, height: 1.5),
            ),
          ],
        ),
      )
          .animate(target: reducedMotion ? 0 : 1)
          .fade(duration: 400.ms)
          .slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
    );
  }
}
