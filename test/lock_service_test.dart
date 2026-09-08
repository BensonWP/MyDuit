import 'package:flutter_test/flutter_test.dart';
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
}
