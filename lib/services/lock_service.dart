import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Metode verifikasi yang dipakai saat membuka app. App TIDAK menyimpan
/// PIN/secret — semua kredensial milik OS (biometrik / PIN perangkat).
enum LockMode {
  /// Biometrik dengan fallback PIN/pattern perangkat (default, teraman).
  both,

  /// Biometrik saja — tanpa fallback. Butuh perangkat berbiometrik.
  biometric,

  /// PIN/pattern perangkat saja, tanpa biometrik.
  deviceCredential;

  static LockMode fromPref(String? value) => switch (value) {
        'biometric' => LockMode.biometric,
        'deviceCredential' => LockMode.deviceCredential,
        _ => LockMode.both,
      };

  String get pref => switch (this) {
        LockMode.biometric => 'biometric',
        LockMode.deviceCredential => 'deviceCredential',
        LockMode.both => 'both',
      };

  String get label => switch (this) {
        LockMode.both => 'Biometrik + PIN perangkat',
        LockMode.biometric => 'Biometrik saja',
        LockMode.deviceCredential => 'PIN/pattern perangkat saja',
      };
}

/// Kunci biometrik: gerbang UX di atas data app.
/// Bukan enkripsi — SQLite tetap terbaca di HP rooted (wajar untuk layer ini).
class LockService {
  LockService._();

  static const _prefKey = 'biometric_lock_enabled';
  static const _modeKey = 'lock_mode';

  /// Grace period resume: di background ≤30 dtk tidak mengunci ulang.
  static const graceDuration = Duration(seconds: 30);

  static final _auth = LocalAuthentication();

  // ── Keputusan (fungsi murni — di-test) ──────────────────────────

  /// App harus terkunci? Kunci saat app baru dibuka (belum pernah ke
  /// background → [backgroundedAt] null), atau kembali dari background
  /// setelah lebih dari [graceDuration].
  static bool shouldLock({
    required bool enabled,
    DateTime? backgroundedAt,
    DateTime? now,
  }) {
    if (!enabled) return false;
    now ??= DateTime.now();
    if (backgroundedAt == null) return true;
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

  /// Perangkat punya biometrik terdaftar (sidik jari/wajah/iris).
  static Future<bool> hasBiometric() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Guard murni (di-test): mode `biometric` hanya boleh bila perangkat
  /// benar-benar punya biometrik — kalau tidak, user bisa terkunci total
  /// (tak ada fallback PIN).
  static bool isModeAllowed(LockMode mode, {required bool hasBiometric}) =>
      mode != LockMode.biometric || hasBiometric;

  /// Munculkan prompt verifikasi perangkat. [mode] null → pakai mode
  /// tersimpan. Return sukses?
  static Future<bool> authenticate({LockMode? mode}) async {
    final effective = mode ?? await getMode();
    try {
      return await _auth.authenticate(
        localizedReason: 'Buka MyDuit untuk melihat data keuanganmu',
        options: AuthenticationOptions(
          // Hanya mode `biometric` yang mengunci ke biometrik murni;
          // `both` & `deviceCredential` membiarkan fallback PIN/pattern OS.
          biometricOnly: effective == LockMode.biometric,
          stickyAuth: true, // lanjut walau app pindah background sesaat
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

  static Future<LockMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return LockMode.fromPref(prefs.getString(_modeKey));
  }

  static Future<void> setMode(LockMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.pref);
  }
}
