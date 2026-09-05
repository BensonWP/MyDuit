import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../theme/app_theme.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(activeBillsStreamProvider).valueOrNull ?? [];
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan Rutin')),
      body: bills.isEmpty
          ? _EmptyBills(reducedMotion: reducedMotion)
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
              itemCount: bills.length,
              itemBuilder: (ctx, i) => _BillTile(
                bill: bills[i],
                accountName:
                    accounts.where((a) => a.id == bills[i].accountId).firstOrNull?.name ?? '-',
                index: i,
                animate: !reducedMotion,
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBill(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  void _showAddBill(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddBillSheet(ref: ref),
    );
  }
}

// ── Kartu tagihan ──────────────────────────────────────────────────

class _BillTile extends StatelessWidget {
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

  /// Selisih hari ke jatuh tempo berikutnya (0 = hari ini).
  int get _daysUntil {
    final now = DateTime.now();
    var due = DateTime(now.year, now.month, bill.dueDay);
    if (due.isBefore(DateTime(now.year, now.month, now.day))) {
      due = DateTime(now.year, now.month + 1, bill.dueDay);
    }
    return due.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  ({Color color, Color bg, String label}) get _urgency {
    final d = _daysUntil;
    if (d <= 3) {
      return (color: D.expense, bg: D.expense.withValues(alpha: 0.1), label: 'H-$d');
    }
    return (color: D.inkMuted, bg: D.surface, label: 'H-$d');
  }

  @override
  Widget build(BuildContext context) {
    final u = _urgency;

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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: D.cobalt.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(D.rSm + 2),
            ),
            child: const Icon(Icons.receipt_rounded, color: D.cobalt, size: 20),
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
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  'Tgl ${bill.dueDay} · $accountName',
                  style: const TextStyle(fontSize: 12, color: D.inkMuted),
                ),
              ],
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
              const SizedBox(height: D.s1 + 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: D.s2, vertical: 2),
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

// ── Bottom sheet tambah tagihan ────────────────────────────────────

class _AddBillSheet extends ConsumerStatefulWidget {
  const _AddBillSheet({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_AddBillSheet> createState() => _AddBillSheetState();
}

class _AddBillSheetState extends ConsumerState<_AddBillSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  int _dueDay = 1;
  String? _accountId;
  bool _isLoading = false;

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

    await db.insertBill(BillsCompanion.insert(
      id: const Uuid().v4(),
      name: _nameController.text.trim(),
      accountId: _accountId!,
      amount: Value(int.tryParse(parseCurrency(_amountController.text)) ?? 0),
      dueDay: Value(_dueDay),
      createdAt: DateTime.now().toIso8601String(),
    ));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        D.s4,
        0,
        D.s4,
        MediaQuery.of(context).viewInsets.bottom + D.s4,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tambah Tagihan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
              value: _accountId,
              decoration: const InputDecoration(labelText: 'Wallet'),
              items: accounts
                  .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: D.s3),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 28,
                separatorBuilder: (_, _) => const SizedBox(width: D.s1 + 2),
                itemBuilder: (ctx, i) {
                  final day = i + 1;
                  final selected = _dueDay == day;
                  return ChoiceChip(
                    label: Text('$day'),
                    selected: selected,
                    onSelected: (_) => setState(() => _dueDay = day),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: D.s6),
            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Simpan Tagihan'),
            ),
          ],
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
