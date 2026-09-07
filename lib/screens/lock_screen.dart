import 'package:flutter/material.dart';

import '../services/lock_service.dart';
import '../theme/app_theme.dart';

/// Gerbang penuh saat app terkunci: logo + prompt biometrik otomatis.
/// Gagal → pesan + tombol coba lagi (fallback PIN/pattern perangkat).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await LockService.authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlock();
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
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
            Text(
              _failed
                  ? 'Verifikasi gagal — coba lagi'
                  : 'Verifikasi untuk melihat data keuanganmu',
              style: const TextStyle(fontSize: 13, color: D.inkMuted),
            ),
            const SizedBox(height: D.s6),
            if (_busy)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Buka app'),
              ),
          ],
        ),
      ),
    );
  }
}
