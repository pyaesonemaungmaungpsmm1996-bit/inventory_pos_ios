import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/barcode_rules.dart';

void main() {
  test('blank code keeps original automatic numbering', () {
    expect(BarcodeRules.forItemCode('', 7), 'ITEM-000007');
    expect(BarcodeRules.forItemCode(null, 1000000), 'ITEM-1000000');
  });
  test('custom code becomes the default scannable barcode', () {
    expect(BarcodeRules.forItemCode('  PSM-CF01  ', 7), 'PSM-CF01');
    expect(BarcodeRules.forProduct('', 7, itemCodeValue: 'PSM-CF01'), 'PSM-CF01');
    expect(BarcodeRules.forProduct('MY-BAR', 7, itemCodeValue: 'PSM-CF01'), 'MY-BAR');
  });
  test('invalid and reserved codes cannot be assigned to another product', () {
    for (final code in ['a b', 'မြန်မာ', 'A/B', '', List.filled(33, 'A').join()]) {
      expect(BarcodeRules.validItemCode(code), isFalse);
    }
    expect(() => BarcodeRules.forItemCode('ITEM-000008', 7), throwsStateError);
    expect(() => BarcodeRules.forItemCode('item-000008', 7), throwsStateError);
    expect(() => BarcodeRules.forItemCode('ITEM-000007', 7), returnsNormally);
  });
}
