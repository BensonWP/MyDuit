import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myduit/db/database.dart';
import 'package:myduit/utils/brand_logo.dart';
import 'package:myduit/utils/wallet_brand.dart';

void main() {
  late MyDuitDatabase db;

  setUp(() {
    db = MyDuitDatabase.testing();
  });

  tearDown(() async {
    await db.close();
  });

  CustomBrandsCompanion brand(String id, String name,
      {String kind = 'bank', String hex = '#123456', Uint8List? logo}) {
    return CustomBrandsCompanion.insert(
      id: id,
      name: name,
      kind: Value(kind),
      hex: Value(hex),
      logo: Value(logo),
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  test('seed bawaan ada di DB untuk bank, e-wallet & kartu', () async {
    final all = await db.watchCustomBrands().first;
    final ids = all.map((b) => b.id).toSet();
    // Id lama dipertahankan agar wallet lama tetap cocok.
    expect(ids, containsAll(['gopay', 'bni', 'bca']));
    // Jenis kartu ada (baru di v11).
    expect(all.where((b) => b.kind == 'card').map((b) => b.id),
        containsAll(['visa', 'mastercard', 'jcb', 'gpn', 'amex']));
    expect(all.every((b) => b.builtin), isTrue);
  });

  test('tambah + ubah brand custom', () async {
    await db.insertBrand(brand('brand_x', 'Bank X'));
    var all = await db.watchCustomBrands().first;
    expect(all.map((b) => b.id), contains('brand_x'));

    await db.updateBrand(const CustomBrandsCompanion(
      id: Value('brand_x'),
      name: Value('Bank X Baru'),
      hex: Value('#654321'),
    ));
    final b = (await db.watchCustomBrands().first)
        .firstWhere((c) => c.id == 'brand_x');
    expect(b.name, 'Bank X Baru');
    expect(b.hex, '#654321');
    expect(b.kind, 'bank');
    expect(b.builtin, isFalse);
  });

  test('hapus brand tak dipakai lolos, dipakai ditolak', () async {
    await db.insertBrand(brand('brand_free', 'Bebas'));
    await db.insertBrand(brand('brand_used', 'Dipakai'));

    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc1',
          name: 'Tabunganku',
          createdAt: now,
          brand: const Value('brand_used'),
        ));
    expect(await db.brandUsage('brand_used'), 1);
    expect(await db.brandUsage('brand_free'), 0);

    await expectLater(
        db.deleteBrand('brand_used'), throwsA(isA<ArgumentError>()));

    await db.deleteBrand('brand_free');
    expect(
      (await db.watchCustomBrands().first).map((b) => b.id),
      contains('brand_used'),
    );
    expect((await db.watchCustomBrands().first).map((b) => b.id),
        isNot(contains('brand_free')));
  });

  test('brand bawaan bisa dihapus bila tak dipakai wallet', () async {
    await db.deleteBrand('visa');
    expect((await db.watchCustomBrands().first).map((b) => b.id),
        isNot(contains('visa')));
  });

  test('brandWallets: pemakai + saldo', () async {
    final now = DateTime.now().toIso8601String();
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'acc_bca',
          name: 'BCA Utama',
          createdAt: now,
          brand: const Value('bca'),
          initialBalance: const Value(150000),
        ));
    final rows = await db.brandWallets('bca');
    expect(rows.length, 1);
    expect(rows.single.$1.name, 'BCA Utama');
    expect(rows.single.$2, 150000);
  });

  test('logo blob round-trip + setBrandLogo (backfill)', () async {
    final logo = Uint8List.fromList(List.generate(256, (i) => i % 256));
    await db.insertBrand(brand('brand_logo', 'Berlogo', logo: logo));
    var all = await db.watchCustomBrands().first;
    expect(all.firstWhere((b) => b.id == 'brand_logo').logo, logo);

    // setBrandLogo mengisi blob tanpa menyentuh kolom wajib lain.
    final bniLogo = Uint8List.fromList(List.generate(64, (i) => 255 - i));
    await db.setBrandLogo('bni', bniLogo);
    all = await db.watchCustomBrands().first;
    expect(all.firstWhere((b) => b.id == 'bni').logo, bniLogo);
    expect(all.firstWhere((b) => b.id == 'bni').name, 'BNI');
  });

  test('watchBrandsByKind memfilter per jenis', () async {
    final banks = await db.watchBrandsByKind('bank').first;
    expect(banks.every((b) => b.kind == 'bank'), isTrue);
    expect(banks.map((b) => b.id), contains('bni'));
    final cards = await db.watchBrandsByKind('card').first;
    expect(cards.map((b) => b.id), containsAll(['visa', 'amex']));
  });

  test('normalizeLogoBytes: non-square jadi PNG 192 transparan', () async {
    final src = img.Image(width: 300, height: 100);
    img.fill(src, color: img.ColorRgba8(255, 0, 0, 255));
    final normalized = normalizeLogoBytes(img.encodePng(src));
    expect(normalized, isNotNull);

    final out = img.decodeImage(normalized!);
    expect(out, isNotNull);
    expect(out!.width, 192);
    expect(out.height, 192);
    expect(out.getPixel(0, 0).a, 0);
    expect(out.getPixel(96, 96).a, 255);
  });

  test('normalizeLogoBytes: bukan gambar → null', () async {
    expect(
      normalizeLogoBytes(Uint8List.fromList([1, 2, 3, 4])),
      isNull,
    );
  });

  test('mergeBrandOptions memetakan baris DB → opsi form', () async {
    final brands = await db.watchCustomBrands().first;
    final opts = mergeBrandOptions(
        brands.where((b) => b.kind == 'card').toList());
    expect(opts.map((o) => o.id), containsAll(['visa', 'amex']));
    final visa = opts.firstWhere((o) => o.id == 'visa');
    expect(visa.label, 'Visa');
    expect(visa.kind, 'card');
    expect(visa.logo, isNull);
  });
}
