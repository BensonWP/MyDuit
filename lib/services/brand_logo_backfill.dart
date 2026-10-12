import 'package:flutter/services.dart' show rootBundle;
import '../db/database.dart';
import '../utils/brand_logo.dart';
import '../utils/wallet_brand.dart';

/// Backfill logo brand bawaan dari asset ke blob DB.
///
/// Migrasi DB tak bisa `rootBundle` (berjalan di Dart murni), jadi seed
/// hanya mengisi baris brand (logo null). Fungsi ini dipanggil sekali
/// setelah DB dibuka di app: untuk tiap brand bawaan tanpa logo yang
/// punya asset, baca → normalisasi 192px → simpan blob. Idempotent &
/// aman-gagal (asset hilang → lewati). Dilewati di test (tak ada bundle).
Future<void> backfillBuiltinBrandLogos(MyDuitDatabase db) async {
  final brands = await db.watchCustomBrands().first;
  final byId = {for (final b in brands) b.id: b};
  for (final seed in WalletBrand.seed) {
    if (seed.asset == null) continue;
    final row = byId[seed.id];
    if (row == null || row.logo != null) continue;
    try {
      final data = await rootBundle.load(seed.asset!);
      final normalized = normalizeLogoBytes(data.buffer.asUint8List());
      if (normalized != null) {
        await db.setBrandLogo(seed.id, normalized);
      }
    } catch (_) {
      // Asset hilang / rusak → biarkan placeholder inisial.
    }
  }
}
