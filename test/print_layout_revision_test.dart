import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/barcode_label_page.dart';
import 'package:inventory_pos/invoice_pdf.dart';
import 'package:inventory_pos/invoice_print_settings.dart';

Map<String, Object?> sample({int count = 6}) => {
  'id': 42,
  'business_name': 'IT KINGDOMS - Sale & Service Centre',
  'invoice_date': '2026-11-13',
  'confirmed_at': '2026-11-13T04:00:00Z',
  'branch_name_snapshot': 'Yangon',
  'branch_code_snapshot': 'YGN',
  'branch_address_snapshot': 'အမှတ် ၁၂၃၊ ရန်ကုန်မြို့\n123 Main Road, Yangon',
  'branch_phone_snapshot': '09-791 249 999',
  'customer_name': 'Ko Kyaw Thura Tun',
  'customer_address': 'Customer address, Yangon',
  'customer_phone': '09 401 911 584',
  'employee_name': 'Hlaing Hlaing Aye',
  'remark': 'စမ်းသပ်မှတ်ချက် / Check accessories before delivery.',
  'currency_code': 'MMK',
  'currency_digits': 0,
  'subtotal': count * 3000000,
  'discount_amount': 0,
  'total': count * 3000000,
  'paid': count * 3000000,
  'balance_due': 0,
  'items': [
    for (var i = 0; i < count; i++)
      {
        'item_code': 'AS${i.toString().padLeft(4, '0')}',
        'item_name': 'Asus Vivobook 15 / Core i5 / RAM 16GB / SSD 512GB\nပစ္စည်း စမ်းသပ်စာသား',
        'qty': 1,
        'price': 3000000,
        'amount': 3000000,
        'tracking_json': '[{"serial":"W1N0CV12D161048"}]',
        'stock': 'PRIVATE_STOCK_SENTINEL',
      },
  ],
};

void main() {
  testWidgets(
    'A4 reference layout supports one page, many pages, and long tracking',
    (tester) async {
      await tester.runAsync(() async {
        Directory('build/layout_review').createSync(recursive: true);
        for (final count in [1, 6, 80]) {
          final sale = sample(count: count);
          final before = jsonEncode(sale);
          final pdf = await buildInvoicePdf(
            sale: sale,
            settings: const InvoicePrintSettings(paper: 'a4', showLogo: false),
            myanmar: false,
          );
          expect(pdf.format.width, closeTo(595.2756, .01));
          final raw = latin1.decode(pdf.bytes);
          final pages = RegExp(r'/Type\s*/Page\b').allMatches(raw).length;
          // Flutter test glyphs are wider than device fonts. A compact invoice
          // must fit one page; six detailed lines may paginate under test fonts.
          if (count == 1) {
            expect(pages, 1);
          } else if (count == 6) {
            expect(pages, inInclusiveRange(1, 2));
          } else {
            expect(pages, greaterThan(1));
          }
          expect(raw, isNot(contains('PRIVATE_STOCK_SENTINEL')));
          expect(jsonEncode(sale), before);
          File('build/layout_review/a4-$count.pdf').writeAsBytesSync(pdf.bytes);
        }
        final sale = sample(count: 1);
        ((sale['items'] as List).first as Map)['tracking_json'] = jsonEncode([
          for (var i = 0; i < 100; i++)
            {'serial': 'SERIAL-${i.toString().padLeft(5, '0')}'},
        ]);
        final pdf = await buildInvoicePdf(
          sale: sale,
          settings: const InvoicePrintSettings(paper: 'a4', showLogo: false),
          myanmar: true,
        );
        expect(
          RegExp(r'/Type\s*/Page\b')
              .allMatches(latin1.decode(pdf.bytes))
              .length,
          greaterThan(1),
        );
        File('build/layout_review/a4-long-tracking.pdf')
            .writeAsBytesSync(pdf.bytes);
        final receipt = await buildInvoicePdf(
          sale: sample(count: 2),
          settings: const InvoicePrintSettings(showLogo: false),
          myanmar: false,
        );
        File('build/layout_review/receipt80.pdf')
            .writeAsBytesSync(receipt.bytes);
        expect(receipt.format.width, closeTo(80 * 72 / 25.4, .01));
      });
    },
  );

  testWidgets(
    'labels support saved alignment choices and safe printer offsets',
    (tester) async {
      await tester.runAsync(() async {
        final product = <String, Object?>{
          'id': 1,
          'item_code': 'AS0001',
          'barcode': 'AS0001',
          'name': 'Asus Vivobook 15',
          'price': 3200000,
        };
        for (final align in ['left', 'center', 'right']) {
          final pdf = await buildBarcodeLabels(
            product: product,
            widthMm: 50,
            heightMm: 30,
            count: 2,
            showPrice: true,
            a4: false,
            nameAlign: align,
            barcodeAlign: align,
            bottomAlign: align,
            offsetXmm: align == 'right' ? 1 : 0,
          );
          expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
          File('build/layout_review/label-$align.pdf').writeAsBytesSync(pdf);
        }
        final qr = await buildBarcodeLabels(
          product: product,
          widthMm: 50,
          heightMm: 30,
          count: 20,
          showPrice: false,
          a4: true,
          qr: true,
          offsetYmm: -1,
        );
        File('build/layout_review/labels-a4-qr.pdf').writeAsBytesSync(qr);
        await expectLater(
          buildBarcodeLabels(
            product: product,
            widthMm: 50,
            heightMm: 30,
            count: 1,
            showPrice: true,
            a4: false,
            offsetXmm: double.nan,
          ),
          throwsArgumentError,
        );
      });
    },
  );
}
