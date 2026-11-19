import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inventory_pos/product_photo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('picked photo is resized, JPEG encoded, and bounded for SQLite backup', () async {
    final original = img.Image(width: 1200, height: 800);
    final result = await prepareProductPhoto(Uint8List.fromList(img.encodePng(original)));
    final decoded = img.decodeJpg(result)!;
    expect(decoded.width, 960);
    expect(decoded.height, 640);
    expect(result.length, lessThanOrEqualTo(750000));
    expect(result[0], 0xff);
    expect(result[1], 0xd8);
  });

  test('invalid and oversized photos cannot enter a product', () async {
    await expectLater(prepareProductPhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    await expectLater(prepareProductPhoto(Uint8List(10000001)), throwsFormatException);
  });
}
