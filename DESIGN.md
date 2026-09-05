# MyDuit — Design System

Identitas visual aplikasi keuangan pribadi MyDuit. Semua keputusan visual harus bisa dirujuk ke dokumen ini.

## Prinsip

1. **Uang adalah tokohnya.** Angka saldo adalah satu-satunya elemen hero; sisanya pendukung yang tenang.
2. **Hierarki, bukan keseragaman.** Elemen utama lebih berat visual daripada pendukung; tidak semua kartu diperlakukan sama.
3. **Motion punya alasan.** Animasi menuntun perhatian ke perubahan state, bukan dekorasi berulang.

## Warna (R-01, I-1)

Cobalt dalam — biru yang dipilih user, dengan karakter lebih gelap & jenuh daripada biru default framework.

| Peran | Token | Nilai |
|---|---|---|
| Primary / brand | `cobalt` | `#1A3A6B` |
| Primary container (hero saldo) | `cobaltDeep` | `#122A52` |
| Surface | `surface` | `#F7F8FB` |
| Surface card | `card` | `#FFFFFF` |
| Teks utama | `ink` | `#101828` |
| Teks sekunder | `inkMuted` | `#667085` |
| Garis pemisah | `line` | `#EAECF0` |
| Aksen CTA | `amber` | `#F5A524` — hanya di FAB "Tambah" |
| Income (semantik angka) | `income` | `#0E9F6E` |
| Expense (semantik angka) | `expense` | `#E02D3C` |
| Transfer (semantik angka) | `transfer` | `#1A3A6B` |

Aturan: 2 warna inti (cobalt + netral) + 1 aksen (amber, FAB saja). Hijau/merah **hanya** untuk angka transaksi & indikator semantik — bukan dekorasi. Tagihan jatuh tempo memakai warna semantik `expense`.

## Tipografi (R-06)

**Plus Jakarta Sans** (google_fonts) — rancangan desainer Indonesia, selaras identitas "duit" lokal.

- Saldo hero: 34 / w800 / `-1` letterspacing
- Judul section: 15 / w700
- Angka transaksi: 14.5 / w700 / tabular figures
- Body/label: 13–14 / w400–w600

## Radius (D-1)

- 8 — chip, input kecil
- 16 — kartu, list item, field form
- 24 — hero saldo, bottom sheet, FAB

## Spacing (I-2)

Skala tunggal: 4 / 8 / 12 / 16 / 24 / 32 / 48. Tidak ada nilai ad-hoc di luar skala.

## Elevasi (D-6)

Default semua permukaan **datar**. Bayangan hanya pada:
- Hero saldo (1 kartu paling penting)
- FAB

List & kartu biasa dibatasi border 1px `line`, tanpa shadow.

## Motion (R-19, F-1–F-6)

| Efek | Spesifikasi | Alasan |
|---|---|---|
| Count-up saldo | 900 ms, easeOutCubic, sekali saat load | Angka paling penting; memberi rasa "saldo hidup" |
| Entrance list | stagger 40 ms, fade+slide 12 px, sekali per load | Menunjukkan urutan, tidak berulang |
| Tekan kartu | spring scale 0.96→1 | Feedback sentuhan pada elemen interaktif |
| Transisi tab | fade-through 250 ms | Perubahan konteks halaman |
| Selector jenis transaksi | slide indikator 200 ms | Menegaskan pilihan yang berubah |
| Shine sweep hero | 1× saat count-up selesai | Menandai momen angka final; tidak loop |

Larangan: loop tanpa henti, pulse CTA, glow, glassmorphism massal, parallax semua-elemen.
Reduced motion: semua animasi dimatikan bila `MediaQuery.disableAnimations` aktif.

## Komponen kunci

- **Hero saldo**: kartu cobaltDeep r24, label "Total Saldo" + angka w800 putih; jumlah wallet kecil di bawah.
- **Kartu wallet**: warna identitas sebagai tint latar + ikon; nama & saldo. Grid 2 kolom di halaman Wallet, rail horizontal di Beranda.
- **Baris transaksi**: lingkaran ikon semantik (income/expense/transfer), kategori sebagai judul, catatan & wallet sebagai subjudul, angka kanan berwarna semantik. Dikelompokkan per tanggal dengan header sticky-ish sederhana.
- **Tagihan**: daftar urut jatuh tempo terdekat; chip "H-3" merah / "H+2" abu menandai urgensi (informasi, bukan dekorasi).
- **Form**: modal bottom sheet r24 + drag handle, muncul dari FAB.
