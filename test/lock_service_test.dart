import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/screens/lock_screen.dart';
import 'package:myduit/services/lock_service.dart';

void main() {
  final now = DateTime(2026, 9, 7, 12, 0, 0);

  test('shouldLock: fitur mati → tidak pernah kunci', () {
    expect(
      LockService.shouldLock(enabled: false, backgroundedAt: now),
      isFalse,
    );
  });

  test('shouldLock: baru dibuka (belum pernah background) → kunci', () {
    expect(
      LockService.shouldLock(enabled: true),
      isTrue,
    );
  });

  test('shouldLock: resume <30 dtk → tidak kunci', () {
    expect(
      LockService.shouldLock(
        enabled: true,
        backgroundedAt: now.subtract(const Duration(seconds: 10)),
        now: now,
      ),
      isFalse,
    );
  });

  test('shouldLock: resume >30 dtk → kunci', () {
    expect(
      LockService.shouldLock(
        enabled: true,
        backgroundedAt: now.subtract(const Duration(seconds: 31)),
        now: now,
      ),
      isTrue,
    );
  });

  test('shouldLock: tepat 30 dtk → tidak kunci (batas inklusif)', () {
    expect(
      LockService.shouldLock(
        enabled: true,
        backgroundedAt: now.subtract(LockService.graceDuration),
        now: now,
      ),
      isFalse,
    );
  });

  test('LockMode.fromPref: mapping + default both', () {
    expect(LockMode.fromPref('biometric'), LockMode.biometric);
    expect(LockMode.fromPref('deviceCredential'), LockMode.deviceCredential);
    expect(LockMode.fromPref('both'), LockMode.both);
    expect(LockMode.fromPref(null), LockMode.both);
    expect(LockMode.fromPref('sampah'), LockMode.both);
  });

  test('LockMode.pref: round-trip enum → string → enum', () {
    for (final mode in LockMode.values) {
      expect(LockMode.fromPref(mode.pref), mode);
    }
  });

  test('isModeAllowed: biometric butuh perangkat berbiometrik', () {
    expect(LockService.isModeAllowed(LockMode.biometric, hasBiometric: false),
        isFalse);
    expect(LockService.isModeAllowed(LockMode.biometric, hasBiometric: true),
        isTrue);
    // Mode lain selalu boleh (selalu ada fallback kredensial perangkat).
    for (final mode in [LockMode.both, LockMode.deviceCredential]) {
      expect(LockService.isModeAllowed(mode, hasBiometric: false), isTrue);
      expect(LockService.isModeAllowed(mode, hasBiometric: true), isTrue);
    }
  });

  testWidgets('LockScreen: gagal verifikasi tampil pesan, tetap terkunci',
      (tester) async {
    var unlocked = false;
    await tester.pumpWidget(MaterialApp(
        home: LockScreen(
            onUnlock: () => unlocked = true,
            authenticate: () async => false)));
    await tester.pumpAndSettle();

    expect(find.text('MyDuit terkunci'), findsOneWidget);
    expect(find.text('Verifikasi gagal — coba lagi'), findsOneWidget);
    expect(unlocked, isFalse);

    // Retry juga gagal — tetap di layar kunci.
    await tester.tap(find.text('Buka app'));
    await tester.pumpAndSettle();
    expect(find.text('Verifikasi gagal — coba lagi'), findsOneWidget);
    expect(unlocked, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('LockScreen: sukses morph cek lalu unlock', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(MaterialApp(
        home: LockScreen(
            onUnlock: () => unlocked = true,
            authenticate: () async => true)));
    await tester.pump(); // postFrame → auth sukses → morph cek
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(unlocked, isFalse);

    // Ceklis ditonton sejenak (hold 900ms) sebelum lepas ke app.
    await tester.pump(const Duration(milliseconds: 950));
    expect(unlocked, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
