import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../utils/currency.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';

Future<void> showPlanSheet(BuildContext context, {Plan? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PlanSheet(existing: existing),
  );
}

/// Isi list rencana — dipakai tab "Rencana" (BillsScreen) & layar push.
class PlansTab extends ConsumerWidget {
  const PlansTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansStreamProvider).valueOrNull ?? [];
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    if (plans.isEmpty) return _EmptyPlans(reducedMotion: reducedMotion);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(D.s4, D.s2, D.s4, 96),
      itemCount: plans.length,
      itemBuilder: (ctx, i) => _PlanCard(
        plan: plans[i],
        index: i,
        animate: !reducedMotion,
      ),
    );
  }
}

/// Layar penuh dengan AppBar sendiri — di-push dari rail Beranda.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rencana')),
      body: const PlansTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showPlanSheet(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

// ── Selisih saldo vs target ────────────────────────────────────────

/// null saat saldo masih dimuat.
int? planShortfall(Plan plan, int? balance) {
  if (balance == null) return null;
  return plan.amount - balance;
}

// ── Kartu rencana ──────────────────────────────────────────────────

class _PlanCard extends ConsumerWidget {
  const _PlanCard({
    required this.plan,
    required this.index,
    required this.animate,
  });

  final Plan plan;
  final int index;
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final balance = plan.accountId == null
        ? ref.watch(totalBalanceProvider).valueOrNull
        : ref.watch(accountBalanceProvider(plan.accountId!)).valueOrNull;
    final short = planShortfall(plan, balance);
    final walletName = plan.accountId == null
        ? 'semua wallet'
        : accounts.where((a) => a.id == plan.accountId).firstOrNull?.name ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: D.s3),
      padding: const EdgeInsets.all(D.s4),
      decoration: BoxDecoration(
        color: D.card,
        borderRadius: BorderRadius.circular(D.rMd),
        border: Border.all(color: D.line),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showPlanSheet(context, existing: plan),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: D.cobalt.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(D.rSm + 2),
              ),
              child: const Icon(Icons.flag_rounded,
                  color: D.cobalt, size: 20),
            ),
            const SizedBox(width: D.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Target ${formatRupiah(plan.amount)} · $walletName',
                      style: const TextStyle(
                          fontSize: 12, color: D.inkMuted)),
                  if (short != null)
                    Text(
                      short > 0
                          ? 'Kurang ${formatRupiah(short)}'
                          : 'Siap! Sisa ${formatRupiah(-short)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: short > 0 ? D.expense : D.income,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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

// ── Bottom sheet tambah/edit rencana ───────────────────────────────

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({this.existing});
  final Plan? existing;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  String? _accountId;
  bool _isLoading = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _nameController.text = p.name;
      _amountController.text = p.amount.toString();
      _accountId = p.accountId;
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

    setState(() => _isLoading = true);
    await ref.read(dbProvider).upsertPlan(PlansCompanion.insert(
          id: widget.existing?.id ?? const Uuid().v4(),
          name: _nameController.text.trim(),
          amount:
              Value(int.tryParse(parseCurrency(_amountController.text)) ?? 0),
          accountId: Value(_accountId),
          createdAt:
              widget.existing?.createdAt ?? DateTime.now().toIso8601String(),
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await confirmDelete(
      context,
      'Hapus ${widget.existing!.name}?',
      description: 'Rencana ini dihapus permanen.',
    );
    if (!confirmed) return;

    await ref.read(dbProvider).deletePlan(widget.existing!.id);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEditing ? 'Edit Rencana' : 'Rencana Baru',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: D.s4),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama rencana',
                  hintText: 'Beli laptop, liburan, kamera…',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: D.s3),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Harga target',
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
              DropdownButtonFormField<String?>(
                // Wallet bisa saja diarsipkan sejak rencana dibuat —
                // nilainya diturunkan ke null agar dropdown tetap valid.
                value: _accountId == null ||
                        accounts.any((a) => a.id == _accountId)
                    ? _accountId
                    : null,
                decoration: const InputDecoration(labelText: 'Wallet'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Semua wallet (total saldo)')),
                  ...accounts.map((a) => DropdownMenuItem<String?>(
                      value: a.id, child: Text(a.name))),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: D.s6),
              FilledButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Simpan Perubahan' : 'Simpan Rencana'),
              ),
              if (_isEditing) ...[
                const SizedBox(height: D.s2),
                Center(
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(foregroundColor: D.expense),
                    child: const Text('Hapus rencana'),
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

// ── Empty state ────────────────────────────────────────────────────

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans({required this.reducedMotion});
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(D.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_rounded, size: 48, color: D.inkMuted),
            const SizedBox(height: D.s4),
            const Text('Belum ada rencana',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: D.s2),
            const Text(
              'Simpan target belanja seperti "laptop baru" agar tahu kurang berapa dari saldo.',
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
