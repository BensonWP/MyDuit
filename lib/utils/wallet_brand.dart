import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/database.dart';
import '../providers/database_provider.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';

/// Brand wallet bawaan — HANYA daftar seed "top" (4 e-wallet + 4 bank +
/// 5 kartu). Runtime membaca semua brand (bawaan + custom) dari tabel DB
/// lewat provider; `seed` dipakai migrasi & backfill logo asset. User
/// menambah brand lain (mis. LinkAja, BSI, Bank Jago) via Kelola Brand.
/// Logo bawaan: file `assets/wallets/{id}.png` bila tersedia (di-backfill
/// jadi blob DB saat app pertama dibuka).
class WalletBrand {
  const WalletBrand._({
    required this.id,
    required this.label,
    required this.hex,
    required this.kind,
    this.asset,
  });
  final String id;
  final String label;
  final String hex;

  /// 'ewallet', 'bank', atau 'card'.
  final String kind;

  /// Path PNG di assets, null = pakai placeholder inisial.
  final String? asset;

  static const seed = <WalletBrand>[
    // ── E-Wallet (top) ──
    WalletBrand._(id: 'gopay', label: 'GoPay', hex: '#00AED6', kind: 'ewallet', asset: 'assets/wallets/gopay.png'),
    WalletBrand._(id: 'ovo', label: 'OVO', hex: '#4C3494', kind: 'ewallet', asset: 'assets/wallets/ovo.png'),
    WalletBrand._(id: 'dana', label: 'DANA', hex: '#118EEA', kind: 'ewallet', asset: 'assets/wallets/dana.png'),
    WalletBrand._(id: 'shopeepay', label: 'ShopeePay', hex: '#EE4D2D', kind: 'ewallet', asset: 'assets/wallets/shopeepay.png'),

    // ── Bank (top) ──
    WalletBrand._(id: 'bca', label: 'BCA', hex: '#0060AF', kind: 'bank', asset: 'assets/wallets/bca.png'),
    WalletBrand._(id: 'bri', label: 'BRI', hex: '#00529C', kind: 'bank', asset: 'assets/wallets/bri.png'),
    WalletBrand._(id: 'mandiri', label: 'Mandiri', hex: '#0B3B8C', kind: 'bank', asset: 'assets/wallets/mandiri.png'),
    WalletBrand._(id: 'bni', label: 'BNI', hex: '#F26F21', kind: 'bank', asset: 'assets/wallets/bni.png'),

    // ── Kartu ──
    WalletBrand._(id: 'visa', label: 'Visa', hex: '#1A1F71', kind: 'card', asset: 'assets/wallets/visa.png'),
    WalletBrand._(id: 'mastercard', label: 'Mastercard', hex: '#EB001B', kind: 'card', asset: 'assets/wallets/mastercard.png'),
    WalletBrand._(id: 'jcb', label: 'JCB', hex: '#0E4C92', kind: 'card'),
    WalletBrand._(id: 'gpn', label: 'GPN', hex: '#E4002B', kind: 'card'),
    WalletBrand._(id: 'amex', label: 'Amex', hex: '#006FCF', kind: 'card'),
  ];

  static WalletBrand? seedById(String? id) =>
      id == null ? null : seed.where((b) => b.id == id).firstOrNull;
}

/// Gambar pilihan tipe (tanpa brand) untuk form.
const walletTypeImages = {
  'cash': 'assets/wallets/cash.png',
  'bank': 'assets/wallets/bank.png',
  'ewallet': 'assets/wallets/ewallet.png',
  'card': 'assets/wallets/card.png',
};

/// Opsi brand (dari DB) untuk picker form wallet.
typedef BrandOption = ({
  String id,
  String label,
  String hex,
  String kind,
  Uint8List? logo,
});

/// Konversi baris brand DB → opsi form (fungsi murni — unit-testable).
List<BrandOption> mergeBrandOptions(List<CustomBrand> brands) {
  return [
    for (final b in brands)
      (
        id: b.id,
        label: b.name,
        hex: b.hex,
        kind: b.kind,
        logo: b.logo,
      ),
  ];
}

/// Logo wallet: logo blob brand (DB) bila ada, else placeholder inisial
/// berwarna, else gambar tipe generik, else ikon Material.
class WalletBadge extends ConsumerWidget {
  const WalletBadge({super.key, required this.account, this.size = 38});
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(brandsProvider).valueOrNull ?? const [];
    final brand = brands.where((b) => b.id == account.brand).firstOrNull;
    return BrandLogo(brand: brand, type: account.type, size: size);
  }
}

/// Inti tampilan logo brand — dipisah agar mudah dipakai/diuji tanpa
/// provider (mis. di form brand & pratinjau).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.brand,
    required this.type,
    this.size = 38,
  });

  /// Baris brand (dari DB), null bila wallet lama tak ber-brand.
  final CustomBrand? brand;

  /// Tipe wallet — untuk fallback gambar tipe bila brand null.
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = brand;
    if (b != null) {
      if (b.logo != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 3),
          child: Image.memory(b.logo!,
              width: size, height: size, fit: BoxFit.cover),
        );
      }
      return BrandInitial(label: b.name, hex: b.hex, size: size);
    }
    final asset = walletTypeImages[type];
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: Image.asset(asset,
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: D.surface,
        borderRadius: BorderRadius.circular(size / 3),
        border: Border.all(color: D.line),
      ),
      child: Icon(Icons.account_balance_wallet_rounded,
          size: size * 0.55, color: D.inkMuted),
    );
  }
}

/// Placeholder logo: kotak warna brand + inisial putih.
/// Dipakai saat brand belum punya logo blob (mis. brand baru tanpa gambar).
class BrandInitial extends StatelessWidget {
  const BrandInitial(
      {super.key,
      required this.label,
      required this.hex,
      required this.size});
  final String label;
  final String hex;
  final double size;

  String get _initials {
    final words =
        label.split(RegExp(r'[\s]+')).where((w) => w.isNotEmpty);
    final letters = words.map((w) => w[0].toUpperCase()).take(2).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hexToColor(hex),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
