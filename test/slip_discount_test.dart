import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/invoice_pdf.dart';
import 'package:inventory_pos/invoice_print_settings.dart';
import 'package:inventory_pos/voucher_code.dart';

import 'print_layout_revision_test.dart' show sample;

void main() {
  testWidgets(
    '58/80mm slips and A4 preserve saved invoice-level discounts and QR identity',
    (tester) async {
      await tester.runAsync(() async {
        final sale = sample(count: 1)
          ..addAll({
            'subtotal': 3150000,
            'discount_amount': 360000,
            'total': 2790000,
            'paid': 2790000,
            'balance_due': 0,
          });
        ((sale['items'] as List).single as Map).addAll(<String, Object>{
          'price': 3150000,
          'amount': 3150000,
        });
        final original = jsonEncode(sale), qr = VoucherCode.encode(sale);
        for (final paper in ['receipt80', 'receipt58', 'a4']) {
          final result = await buildInvoicePdf(
            sale: sale,
            settings: InvoicePrintSettings(paper: paper, showLogo: false),
            myanmar: false,
          );
          expect(ascii.decode(result.bytes.sublist(0, 5)), '%PDF-');
          expect(
            result.format.width,
            closeTo(
              paper == 'a4'
                  ? 595.2756
                  : (paper == 'receipt80' ? 80 : 58) * 72 / 25.4,
              .01,
            ),
          );
          expect(
            RegExp(r'/Type\s*/Page\b')
                .allMatches(latin1.decode(result.bytes))
                .length,
            1,
          );
        }
        expect(jsonEncode(sale), original);
        expect(VoucherCode.encode(sale), qr);
      });
    },
  );
}
