import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/lock_service.dart';
import '../theme/app_theme.dart';

/// Gerbang penuh saat app terkunci: logo + prompt biometrik otomatis.
/// Sukses → logo/teks tersingkap digantikan ceklis hijau besar yang
/// beranimasi (momen "berhasil") sebelum [onUnlock] (lalu LockGate mem-fade
/// layar ini). Gagal → shake + tombol coba lagi (fallback PIN/pattern).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock, this.authenticate});

  final VoidCallback onUnlock;

  /// Seam uji: default [LockService.authenticate] (biometrik asli).
  /// Test menginjek `() async => false/true` karena channel
  /// platform menggantung di flutter_test.
  final Future<bool> Function()? authenticate;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  bool _busy = false;
  bool _success = false;

  /// Durasi tontonan ceklis sebelum lepas ke app (dipadu durasi animasi).
  static const _successHold = Duration(milliseconds: 900);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_busy || _success) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await (widget.authenticate ?? LockService.authenticate)();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _succeed();
    } else {
      setState(() => _failed = true);
    }
  }

  /// Ceklis hijau besar beranimasi, ditonton sejenak sebelum lepas ke app.
  Future<void> _succeed() async {
    final reduced = MediaQuery.of(context).disableAnimations;
    setState(() => _success = true);
    await Future.delayed(reduced
        ? const Duration(milliseconds: 250)
        : _successHold);
    if (!mounted) return;
    widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _success
            ? _SuccessCheck(reduced: reduced)
            : _LockedPrompt(
                failed: _failed,
                busy: _busy,
                onRetry: _authenticate,
                reduced: reduced,
              ),
      ),
    );
  }
}

/// Konten saat terkunci: logo + judul + prompt/tombol. Tersingkap (fade +
/// slide) sekali saat muncul — replika entrance yang lama, dipindah ke
/// widget sendiri agar transisi ke [_SuccessCheck] bersih.
class _LockedPrompt extends StatelessWidget {
  const _LockedPrompt({
    required this.failed,
    required this.busy,
    required this.onRetry,
    required this.reduced,
  });

  final bool failed;
  final bool busy;
  final VoidCallback onRetry;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/branding/app_logo.png', width: 110),
        const SizedBox(height: D.s4),
        const Text(
          'MyDuit terkunci',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: D.ink,
          ),
        ),
        const SizedBox(height: D.s1),
        // Gagal → instance baru tiap toggle → shake main sekali.
        failed
            ? const Text(
                'Verifikasi gagal — coba lagi',
                style: TextStyle(fontSize: 13, color: D.expense),
              ).animate().shake(duration: 400.ms, hz: 4)
            : const Text(
                'Verifikasi untuk melihat data keuanganmu',
                style: TextStyle(fontSize: 13, color: D.inkMuted),
              ),
        const SizedBox(height: D.s6),
        if (busy)
          const CircularProgressIndicator()
        else
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Buka app'),
          ),
      ],
    )
        .animate(target: reduced ? 0 : 1)
        .fade(duration: 300.ms)
        .slideY(begin: 0.08, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }
}

/// Momen sukses: ceklis hijau besar menggantikan logo, dengan ring yang
/// mengembang, glow halus, dan ceklis yang "tumbuh" + shimmer sekali.
/// Semua sekali main (bukan loop) — sesuai aturan motion DESIGN.md.
class _SuccessCheck extends StatelessWidget {
  const _SuccessCheck({required this.reduced});

  final bool reduced;

  static const _icon = 132.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 340,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Gelombang ring yang mengembang lalu memudar (satu kali).
          if (!reduced)
            _RippleRing(size: _icon + 36).animate().scale(
              begin: const Offset(0.6, 0.6),
              end: const Offset(1.7, 1.7),
              duration: 700.ms,
              curve: Curves.easeOutCubic,
            ).fadeIn(duration: 120.ms).fadeOut(
                  delay: 260.ms,
                  duration: 440.ms,
                ),
          // Lingkaran hijau + glow lembut, muncul overshoot.
          Container(
            width: _icon,
            height: _icon,
            decoration: BoxDecoration(
              color: D.income,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: D.income.withValues(alpha: 0.35),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: _icon * 0.56,
            )
                // Ceklis "tumbuh" sedikit setelah lingkaran mendarat.
                .animate(target: reduced ? 0 : 1)
                .scale(
                  begin: const Offset(0.4, 0.4),
                  end: const Offset(1, 1),
                  delay: 160.ms,
                  duration: 320.ms,
                  curve: Curves.easeOutBack,
                ),
          )
              .animate(target: reduced ? 0 : 1)
              .scale(
                begin: const Offset(0.3, 0.3),
                end: const Offset(1, 1),
                duration: 420.ms,
                curve: Curves.easeOutBack,
              )
              .fadeIn(duration: 180.ms)
              // Kilap singkat menandai angka/momen final.
              .then()
              .shimmer(duration: 500.ms, color: Colors.white),
        ],
      ),
    );
  }
}

/// Ring tipis hijau semi-transparan untuk efek gelombang sukses.
class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: D.income.withValues(alpha: 0.5),
          width: 3,
        ),
      ),
    );
  }
}
