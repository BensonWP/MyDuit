import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kunci biometrik: gerbang UX di atas data app.
/// Bukan enkripsi — SQLite tetap terbaca di HP rooted (wajar untuk layer ini).
class LockService {
  LockService._();

  static const _prefKey = 'biometric_lock_enabled';

  /// Grace period resume: di background ≤30 dtk tidak mengunci ulang.
  static const graceDuration = Duration(seconds: 30);

  static final _auth = LocalAuthentication();

  // ── Keputusan (fungsi murni — di-test) ──────────────────────────

  /// App harus terkunci? Terkunci saat baru dibuka, atau kembali dari
  /// background setelah lebih dari [graceDuration].
  static bool shouldLock({
    required bool enabled,
    required bool firstResume,
    DateTime? backgroundedAt,
    DateTime? now,
  }) {
    if (!enabled) return false;
    now ??= DateTime.now();
    if (firstResume || backgroundedAt == null) return true;
    return now.difference(backgroundedAt) > graceDuration;
  }

  // ── Perangkat ───────────────────────────────────────────────────

  /// Perangkat punya biometrik terdaftar ATAU credential PIN/pattern.
  static Future<bool> canAuthenticate() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Munculkan prompt biometrik/PIN perangkat. Return sukses?
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Buka MyDuit untuk melihat data keuanganmu',
        options: const AuthenticationOptions(
          biometricOnly: false, // fallback PIN/pattern perangkat
          stickyAuth: true,     // lanjut walau app pindah background sesaat
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ── Pengaturan ──────────────────────────────────────────────────

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }
}
