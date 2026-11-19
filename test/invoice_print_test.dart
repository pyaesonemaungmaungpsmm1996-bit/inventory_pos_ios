import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_currency.dart';
import 'package:inventory_pos/invoice_pdf.dart';
import 'package:inventory_pos/invoice_print_model.dart';
import 'package:inventory_pos/invoice_print_settings.dart';

Map<String, Object?> fixture({int items = 1}) => {
  'id': 1,
  'currency_code': 'MMK',
  'currency_digits': 0,
  'business_name': 'PSM',
  'branch_name_snapshot': 'Pazundaung',
  'branch_code_snapshot': 'PZD',
  'branch_phone_snapshot': '090000000',
  'branch_address_snapshot': 'Branch address',
  'invoice_date': '2026-10-27',
  'customer_name': 'Customer',
  'customer_phone': '091111111',
  'customer_company': 'Company',
  'customer_address': 'Customer address',
  'employee_name': 'Sale Person',
  'items': [
    for (int i = 0; i < items; i++)
      {
        'item_code': 'ITEM-${i + 1}',
        'item_name': 'Coffee $i',
        'qty': 1,
        'price': 3000,
        'amount': 3000,
        'stock': 'PRIVATE_STOCK_SENTINEL',
      },
  ],
  'subtotal': 3000 * items,
  'discount_amount': 100,
  'total': 3000 * items - 100,
  'paid': 2400,
  'balance_due': 3000 * items - 2500,
  'payments': [
    {'payment_date': '2026-10-27', 'account_name': 'Cash', 'amount': 2000},
  ],
  'collections': [
    {
      'payment_date': '2026-10-27',
      'receipt_id': 2,
      'status': 'posted',
      'amount': 400,
    },
    {
      'payment_date': '2026-10-27',
      'receipt_id': 3,
      'status': 'void',
      'amount': 300,
    },
  ],
};
String textOf(List<InvoicePrintRow> rows) =>
    rows.expand((r) => r.cells).join('\n');

void main() {
  tearDown(() => AppCurrency.current.value = 'MMK');
  test('every paper format and custom dimensions round-trip and validate', () {
    for (final paper in InvoicePrintSettings.papers.keys) {
      final settings = InvoicePrintSettings(
        paper: paper,
        language: 'my',
        footer: 'ကျေးဇူးတင်ပါသည်',
      );
      settings.validate();
      final copy = InvoicePrintSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
      );
      expect(copy.paper, paper);
      expect(copy.footer, 'ကျေးဇူးတင်ပါသည်');
      expect(copy.pageFormat.width, greaterThan(0));
      expect(copy.pageFormat.height, greaterThan(0));
    }
    expect(
      () => const InvoicePrintSettings(customWidthMm: double.nan).validate(),
      throwsFormatException,
    );
    expect(
      () => const InvoicePrintSettings(paper: 'unknown').validate(),
      throwsFormatException,
    );
    expect(
      () => const InvoicePrintSettings(customHeightMm: 50).validate(),
      throwsFormatException,
    );
  });
  test('customer projection omits stock, uses stored invoice currency and does not mutate the sale', () {
    final sale = fixture();
    final before = jsonEncode(sale);
    AppCurrency.current.value = 'USD';
    final rows = invoicePrintRows(
      sale,
      const InvoicePrintSettings(paper: 'a4'),
      myanmar: false,
    );
    final text = textOf(rows);
    expect(text, contains('3,000 Ks'));
    expect(text, isNot(contains('USD')));
    expect(text, isNot(contains('PRIVATE_STOCK_SENTINEL')));
    expect(text, contains('Customer address'));
    expect(text, contains('Branch address'));
    expect(text, isNot(contains('RCPT-000002')));
    expect(text, isNot(contains('RCPT-000003')));
    expect(text, contains('Credit due: 500 Ks'));
    expect(
      rows
          .where((r) => r.cells.any((s) => s.startsWith('Subtotal:')))
          .single
          .right,
      isTrue,
    );
    expect(
      rows
          .where((r) => r.cells.any((s) => s.startsWith('Credit due:')))
          .single
          .right,
      isTrue,
    );
    expect(jsonEncode(sale), before);
  });
  test('payment-history and sale-person switches do not hide payment totals or debt', () {
    final rows = invoicePrintRows(
      fixture(),
      const InvoicePrintSettings(showPayments: false, showSalePerson: false),
      myanmar: false,
    );
    final text = textOf(rows);
    expect(text, isNot(contains('Sale Person')));
    expect(text, isNot(contains('Cash')));
    expect(text, isNot(contains('RCPT-')));
    expect(text, contains('Paid: 2,400 Ks'));
    expect(text, contains('Credit due: 500 Ks'));
  });
  test(
    'Myanmar labels, walk-in customers and all 300 item rows are retained',
    () {
      final sale = fixture(items: 300)..['customer_name'] = '';
      final text = textOf(
        invoicePrintRows(sale, const InvoicePrintSettings(), myanmar: true),
      );
      expect(text, contains('အရောင်းဘောင်ချာ'));
      expect(text, contains('အမည်မမှတ်ထားသောဝယ်သူ'));
      expect(text, contains('Coffee 0'));
      expect(text, contains('Coffee 299'));
    },
  );
  testWidgets(
    'PDF renderer produces a multipage fixed-size receipt without stock leakage',
    (tester) async {
      await tester.runAsync(() async {
        const settings = InvoicePrintSettings(
          paper: 'custom',
          customWidthMm: 58,
          customHeightMm: 100,
        );
        final result = await buildInvoicePdf(
          sale: fixture(items: 20),
          settings: settings,
          myanmar: false,
          loadLogo: () async => null,
        );
        expect(ascii.decode(result.bytes.sublist(0, 5)), '%PDF-');
        expect(result.format.width, closeTo(settings.pageFormat.width, 0.001));
        expect(
          result.format.height,
          closeTo(settings.pageFormat.height, 0.001),
        );
        final raw = latin1.decode(result.bytes);
        expect(
          RegExp(r'/Type\s*/Page\b').allMatches(raw).length,
          greaterThan(1),
        );
        expect(raw, isNot(contains('PRIVATE_STOCK_SENTINEL')));
      });
    },
  );
}
