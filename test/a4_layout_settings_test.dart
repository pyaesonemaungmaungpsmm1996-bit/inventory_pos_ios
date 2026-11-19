import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/a4_layout_settings.dart';
import 'package:inventory_pos/invoice_print_settings.dart';

void main() {
  test(
    'A4 customization persists and old print preferences retain defaults',
    () {
      final old = const InvoicePrintSettings().toJson()..remove('a4');
      expect(InvoicePrintSettings.fromJson(old).a4.logoWidthMm, 48);
      const custom = InvoicePrintSettings(
        paper: 'a4',
        a4: A4LayoutSettings(
          heading: 'Shop',
          subtitle: 'Sale & Service Centre',
          leftBranch: 'Yangon\nAddress\nPhone',
          rightBranch: 'Mandalay\nAddress\nPhone',
          logoWidthMm: 50,
          remarkHeightMm: 30,
          totalsPercent: 35,
        ),
      );
      final restored = InvoicePrintSettings.fromJson(
        jsonDecode(jsonEncode(custom.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), custom.toJson());
      expect(restored.a4.rightBranch, contains('Mandalay'));
      expect(
        const InvoicePrintSettings().pageFormat.width,
        closeTo(80 * 72 / 25.4, .01),
      );
    },
  );
  test('A4 controls reject invalid dimensions and overlong text', () {
    for (final values in <Map<String, Object>>[
      {'logoWidthMm': double.nan},
      {'totalsPercent': 99},
      {'remarkHeightMm': -1},
      {'heading': 'x' * 101},
    ]) {
      expect(
        () => const A4LayoutSettings().withValues(values),
        throwsFormatException,
      );
    }
  });
}
