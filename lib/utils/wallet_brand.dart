import 'package:flutter/material.dart';
import '../db/database.dart';
import '../theme/app_theme.dart';
import 'app_icons.dart';

/// Identitas brand wallet: label, warna, aset logo (opsional), kategori.
/// Logo: file `assets/wallets/{id}.png` bila tersedia — bila [asset] null,
/// tampil placeholder inisial ([BrandInitial]) berwarna [hex].
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

  /// 'ewallet' atau 'bank'.
  final String kind;

  /// Path PNG di assets, null = pakai placeholder inisial.
  final String? asset;

  static const all = <WalletBrand>[
    // ── E-Wallet ──
    WalletBrand._(id: 'gopay', label: 'GoPay', hex: '#00AED6', kind: 'ewallet', asset: 'assets/wallets/gopay.png'),
    WalletBrand._(id: 'ovo', label: 'OVO', hex: '#4C3494', kind: 'ewallet', asset: 'assets/wallets/ovo.png'),
    WalletBrand._(id: 'dana', label: 'DANA', hex: '#118EEA', kind: 'ewallet', asset: 'assets/wallets/dana.png'),
    WalletBrand._(id: 'shopeepay', label: 'ShopeePay', hex: '#EE4D2D', kind: 'ewallet', asset: 'assets/wallets/shopeepay.png'),
    WalletBrand._(id: 'linkaja', label: 'LinkAja', hex: '#F84712', kind: 'ewallet', asset: 'assets/wallets/linkaja.png'),
    WalletBrand._(id: 'astrapay', label: 'AstraPay', hex: '#1B4E9B', kind: 'ewallet', asset: 'assets/wallets/astrapay.png'),
    WalletBrand._(id: 'isaku', label: 'i.Saku', hex: '#E23A3A', kind: 'ewallet'),
    WalletBrand._(id: 'doku', label: 'DOKU', hex: '#E1251B', kind: 'ewallet', asset: 'assets/wallets/doku.png'),
    WalletBrand._(id: 'sakuku', label: 'Sakuku', hex: '#F26522', kind: 'ewallet'),

    // ── Bank ──
    WalletBrand._(id: 'bca', label: 'BCA', hex: '#0060AF', kind: 'bank', asset: 'assets/wallets/bca.png'),
    WalletBrand._(id: 'bri', label: 'BRI', hex: '#00529C', kind: 'bank', asset: 'assets/wallets/bri.png'),
    WalletBrand._(id: 'mandiri', label: 'Mandiri', hex: '#0B3B8C', kind: 'bank', asset: 'assets/wallets/mandiri.png'),
    WalletBrand._(id: 'bni', label: 'BNI', hex: '#F26F21', kind: 'bank', asset: 'assets/wallets/bni.png'),
    WalletBrand._(id: 'cimb', label: 'CIMB Niaga', hex: '#B3122F', kind: 'bank'),
    WalletBrand._(id: 'danamon', label: 'Danamon', hex: '#009FE3', kind: 'bank'),
    WalletBrand._(id: 'permata', label: 'Permata', hex: '#00A0DF', kind: 'bank', asset: 'assets/wallets/permata.png'),
    WalletBrand._(id: 'btn', label: 'BTN', hex: '#C99C33', kind: 'bank', asset: 'assets/wallets/btn.png'),
    WalletBrand._(id: 'bsi', label: 'BSI', hex: '#1B7B4B', kind: 'bank'),
    WalletBrand._(id: 'jago', label: 'Bank Jago', hex: '#EE3124', kind: 'bank', asset: 'assets/wallets/jago.png'),
    WalletBrand._(id: 'jenius', label: 'Jenius', hex: '#15B5BE', kind: 'bank', asset: 'assets/wallets/jenius.png'),
    WalletBrand._(id: 'seabank', label: 'SeaBank', hex: '#00AEEF', kind: 'bank', asset: 'assets/wallets/seabank.png'),
    WalletBrand._(id: 'blu', label: 'Blu by BCA', hex: '#00B0C7', kind: 'bank', asset: 'assets/wallets/blu.png'),
    WalletBrand._(id: 'bnc', label: 'BNC', hex: '#0E4C92', kind: 'bank', asset: 'assets/wallets/bnc.png'),
  ];

  static WalletBrand? byId(String? id) =>
      id == null ? null : all.where((b) => b.id == id).firstOrNull;

  /// Semua brand dalam satu kategori ('ewallet' | 'bank').
  static List<WalletBrand> byKind(String kind) =>
      all.where((b) => b.kind == kind).toList();
}

/// Gambar pilihan tipe (tanpa brand) untuk form.
const walletTypeImages = {
  'cash': 'assets/wallets/cash.png',
  'bank': 'assets/wallets/bank.png',
  'ewallet': 'assets/wallets/ewallet.png',
  'card': 'assets/wallets/card.png',
};

/// Logo wallet: PNG brand bila ada, placeholder inisial bila tidak,
/// fallback gambar tipe generik, lalu ikon Material sebagai pengaman terakhir.
class WalletBadge extends StatelessWidget {
  const WalletBadge({super.key, required this.account, this.size = 38});
  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = WalletBrand.byId(account.brand);
    if (brand?.asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: Image.asset(brand!.asset!,
            width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (brand != null) {
      return BrandInitial(brand: brand, size: size);
    }
    final asset = walletTypeImages[account.type];
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

/// Placeholder logo: lingkaran warna brand + inisial putih.
/// Dipakai saat logo PNG belum tersedia; tinggal isi [WalletBrand.asset]
/// nanti untuk menggantinya.
class BrandInitial extends StatelessWidget {
  const BrandInitial({super.key, required this.brand, required this.size});
  final WalletBrand brand;
  final double size;

  String get _initials {
    final words =
        brand.label.split(RegExp(r'[\s]+')).where((w) => w.isNotEmpty);
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
        color: hexToColor(brand.hex),
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
