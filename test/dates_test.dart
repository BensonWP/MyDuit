import 'package:flutter_test/flutter_test.dart';
import 'package:myduit/utils/dates.dart';

void main() {
  group('nextMidnight', () {
    test('siang hari → tengah malam besok', () {
      expect(
        nextMidnight(DateTime(2026, 9, 10, 15, 30)),
        DateTime(2026, 9, 11),
      );
    });

    test('tepat tengah malam → tengah malam berikutnya', () {
      expect(
        nextMidnight(DateTime(2026, 9, 10)),
        DateTime(2026, 9, 11),
      );
    });

    test('23:59:59 → tengah malam besok', () {
      expect(
        nextMidnight(DateTime(2026, 9, 10, 23, 59, 59)),
        DateTime(2026, 9, 11),
      );
    });

    test('lintas bulan pendek', () {
      expect(
        nextMidnight(DateTime(2026, 2, 28, 12)),
        DateTime(2026, 3, 1),
      );
    });

    test('lintas tahun', () {
      expect(
        nextMidnight(DateTime(2026, 12, 31, 12)),
        DateTime(2027, 1, 1),
      );
    });
  });
}
