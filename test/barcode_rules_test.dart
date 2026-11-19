import 'package:barcode/barcode.dart' as bc;
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/barcode_rules.dart';

void main() {
  test('generated codes are stable and preserve the invoice item-code convention', () {
    expect(BarcodeRules.itemCode(1), 'ITEM-000001');
    expect(BarcodeRules.itemCode(1000000), 'ITEM-1000000');
    expect(BarcodeRules.forProduct('', 1), 'ITEM-000001');
    expect(BarcodeRules.forProduct(null, 1), 'ITEM-000001');
    expect(BarcodeRules.forProduct('ITEM-000001', 1), 'ITEM-000001');
    expect(() => BarcodeRules.forProduct('ITEM-000002', 1), throwsStateError);
    expect(() => BarcodeRules.forProduct('item-000002', 1), throwsStateError);
  });
  test('leading zeroes and case remain significant except UPC-A/EAN-13 equivalents', () {
    expect(BarcodeRules.forProduct(' 0012345 ', 1), '0012345');
    expect(BarcodeRules.lookupKey('0012345'), '0012345');
    expect(BarcodeRules.lookupKey('0123456789012'), '123456789012');
    expect(BarcodeRules.lookupKey('123456789012'), '123456789012');
    expect(BarcodeRules.lookupKey('1234567890123'), '1234567890123');
    expect(BarcodeRules.lookupKey('000000000001'), '000000000001');
    expect(BarcodeRules.lookupKey('AbC-001'), 'AbC-001');
  });
  test('invalid and oversized codes are rejected without modifying their payload', () {
    for (final value in ['', 'A B', '\n', 'မြန်မာ', '漢字', List.filled(33, 'A').join()]) {
      expect(BarcodeRules.valid(value), isFalse, reason: value);
    }
    expect(BarcodeRules.valid('AbC-001_+/'), isTrue);
  });
  test('generated label payloads are Code 128 encodable with printable quiet zones', () {
    final encoding = bc.Barcode.code128();
    for (final code in ['ITEM-000001', '0012345', '123456789012', 'AbC-001_+/']) {
      expect(encoding.isValid(code), isTrue);
      final ratio = BarcodeRules.narrowBarRatio(code);
      expect(ratio, greaterThan(0));
      final minimumWidth = BarcodeRules.minimumLabelWidthMm(code);
      // Same geometry used by PDF: 1.5mm margins + 10-module quiet zones.
      final bars = (minimumWidth - 3) / (1 + 20 * ratio);
      expect(bars * ratio, closeTo(0.25, 0.000001));
      expect(encoding.toSvg(code, drawText: false), contains('<svg'));
    }
    expect(BarcodeRules.minimumLabelWidthMm('ITEM-000001'), lessThanOrEqualTo(50));
  });
}
