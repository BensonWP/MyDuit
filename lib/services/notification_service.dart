import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../db/database.dart';
import '../utils/currency.dart';

/// Pengingat jatuh tempo tagihan, pukul 08:00 di hari jatuh tempo.
///
/// Pola: idempoten — setiap perubahan data tagihan memanggil
/// [rescheduleAll] (cancelAll lalu jadwalkan ulang semua tagihan aktif).
/// Bulanan via matchDateTimeComponents: dayOfMonthAndTime.
/// ponytail: inexact alarm (tanpa izin SCHEDULE_EXACT_ALARM di Android 14+);
/// jika pengguna mengeluh pengingat molor menit, baru minta exact.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initFuture;

  /// Idempoten & aman dipanggil bersamaan (main + listener tagihan).
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    // ponytail: nama zona persis (IANA) butuh paket flutter_timezone;
    // Indonesia bebas DST jadi offset perangkat sudah cukup akurat.
    // Upgrade jika ada pengguna di luar WIB/WITA/WIT.
    final offset = DateTime.now().timeZoneOffset;
    final zoneName = offset.isNegative
        ? 'Etc/GMT+${offset.inHours.abs()}'
        : 'Etc/GMT-${offset.inHours}';
    tz.setLocalLocation(tz.getLocation(zoneName));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Android 13+: izin notifikasi diminta runtime.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// Batalkan semua lalu jadwalkan ulang tiap tagihan aktif pada pukul 08:00
  /// tanggal jatuh tempo. Dipanggil saat app dibuka dan tiap tagihan berubah.
  Future<void> rescheduleAll(List<Bill> bills) async {
    await init();
    await _plugin.cancelAll();

    final now = DateTime.now();
    for (final bill in bills) {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'bill_reminders',
          'Pengingat Tagihan',
          channelDescription: 'Pengingat jatuh tempo tagihan rutin',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
      );

      await _plugin.zonedSchedule(
        // ID notifikasi 32-bit; hash tagihan supaya tiap tagihan unik.
        bill.id.hashCode & 0x7FFFFFFF,
        'Tagihan: ${bill.name}',
        '${formatRupiah(bill.amount)} jatuh tempo tanggal ${bill.dueDay}.',
        _nextDueDate(now, bill.dueDay),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
    }
  }

  /// Jatuh tempo berikutnya pukul 08:00, ketat di masa depan.
  /// Tgl 29–31 mengikuti panjang bulan (tgl 30 di Feb → 28/29),
  /// konsisten dengan daysUntilDue di dates.dart. Jadwal bulanan
  /// (matchDateTimeComponents) dikoreksi sendiri oleh rescheduleAll
  /// setiap app dibuka.
  tz.TZDateTime _nextDueDate(DateTime now, int dueDay) {
    for (var m = 0; m < 3; m++) {
      final first = DateTime(now.year, now.month + m);
      final lastDay = DateTime(first.year, first.month + 1, 0).day;
      final day = dueDay > lastDay ? lastDay : dueDay;
      final due = tz.TZDateTime(tz.local, first.year, first.month, day, 8);
      if (due.isAfter(now)) return due;
    }
    // Tak terjangkau (klem selalu valid, bulan ke-1 pasti masa depan) —
    // jaring pengaman agar analyzer puas.
    final first = DateTime(now.year, now.month + 3);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return tz.TZDateTime(tz.local, first.year, first.month,
        dueDay > lastDay ? lastDay : dueDay, 8);
  }
}
