import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Normalisasi logo brand ke PNG square [size]×[size] (contain di atas
/// kanvas transparan) — mirror `tools/normalize_wallets.ps1` (96px),
/// tapi 192px untuk ketajaman logo custom. Return null bila bytes
/// bukan gambar valid.
Uint8List? normalizeLogoBytes(Uint8List bytes, {int size = 192}) {
  img.Image? src;
  try {
    src = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (src == null) return null;

  final scale = size / (src.width > src.height ? src.width : src.height);
  final w = (src.width * scale).round().clamp(1, size);
  final h = (src.height * scale).round().clamp(1, size);
  final resized = img.copyResize(src, width: w, height: h);

  // 4 channel agar sudut kanvas benar-benar transparan.
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    canvas,
    resized,
    dstX: (size - w) ~/ 2,
    dstY: (size - h) ~/ 2,
  );
  return img.encodePng(canvas);
}
