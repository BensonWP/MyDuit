# MyDuit

Aplikasi pencatat keuangan pribadi, lokal-first: semua data tersimpan di perangkat (SQLite), tanpa akun, tanpa server.

## Fitur

- **Wallet** — cash, bank, e-wallet, kartu; logo brand otomatis (GoPay, OVO, DANA, BCA, dll.)
- **Transaksi** — pemasukan/pengeluaran per wallet, format rupiah otomatis
- **Tagihan & cicilan** — tagihan bulanan berulang atau cicilan N bulan, pengingat notifikasi pukul 08:00 di hari jatuh tempo
- **Rencana** — target belanja, ikut dalam proyeksi saldo (opsional)
- **Beranda** — saldo total, proyeksi saldo hingga 12 bulan ke depan, grafik arus 7 hari (keluar/masuk)
- **Laporan** — ringkasan bulanan per kategori (donut + breakdown), tren 6 bulan / 7 hari dengan pilihan arus
- **Keamanan** — kunci app dengan sidik jari/PIN, terkunci otomatis saat ditinggal
- **Data** — backup/restore database (dengan snapshot aman sebelum restore)

## Teknologi

Flutter · Drift (SQLite) · Riverpod · flutter_local_notifications · local_auth

## Build APK

```bash
flutter pub get
flutter build apk --release
```

APK tersedia di `build/app/outputs/flutter-apk/app-release.apk`.

## Pengembangan

```bash
flutter test        # 31 test (unit + widget)
flutter analyze
```

Migrasi skema database via Drift `schemaVersion` (saat ini v6) — tabel lama tidak pernah di-drop, hanya kolom/tabel baru.
