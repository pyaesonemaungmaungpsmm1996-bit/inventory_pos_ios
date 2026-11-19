import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Keep receipt text legible while bounding offline database storage.
Future<Uint8List> prepareExpenseReceiptPhoto(Uint8List source) async {
  if (source.isEmpty || source.length > 12000000) {
    throw const FormatException('Choose a receipt photo under 12 MB.');
  }
  return compute(_resizeReceiptPhoto, source);
}

Uint8List _resizeReceiptPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not open the receipt photo.');
  }
  var oriented = img.bakeOrientation(decoded);
  for (final side in [1800, 1500, 1200, 960]) {
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final scale = longest > side ? side / longest : 1.0;
    final width = (oriented.width * scale).round().clamp(1, side).toInt();
    final height = (oriented.height * scale).round().clamp(1, side).toInt();
    final sized = scale < 1
        ? img.copyResize(
            oriented,
            width: width,
            height: height,
            interpolation: img.Interpolation.linear,
          )
        : oriented;
    final jpg = Uint8List.fromList(img.encodeJpg(sized, quality: 82));
    if (jpg.length <= 2000000) return jpg;
    oriented = sized;
  }
  throw const FormatException(
    'Photo is too large. Retake it closer to the receipt.',
  );
}
