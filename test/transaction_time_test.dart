import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_datetime.dart';
import 'package:inventory_pos/invoice_print_model.dart';
import 'package:inventory_pos/invoice_print_settings.dart';

void main() {
  setUpAll(() {
    AppDateTime.configure('Asia/Yangon');
  });
  test(
    'UTC timestamp displays Myanmar business time without seconds or offset',
    () {
      expect(
        AppDateTime.format(
          '2026-10-27T03:29:17.123456Z',
          offset: const Duration(hours: 6, minutes: 30),
        ),
        '2026-10-27 09:59 am',
      );
      expect(
        AppDateTime.parse('2026-10-27T09:59:17+06:30'),
        DateTime.utc(2026, 10, 27, 3, 29, 17),
      );
    },
  );
  test(
    'time-zone conversion handles previous/next dates and negative offsets',
    () {
      expect(
        AppDateTime.format(
          '2026-10-26T20:30:05Z',
          offset: const Duration(hours: 6, minutes: 30),
        ),
        '2026-10-27 03:00 am',
      );
      expect(
        AppDateTime.format(
          '2026-10-27T02:05:06Z',
          offset: const Duration(hours: -5),
        ),
        '2026-10-26 09:05 pm',
      );
      expect(
        AppDateTime.format('2026-10-27T02:05:06Z', offset: Duration.zero),
        '2026-10-27 02:05 am',
      );
    },
  );
  test('business zone changes the displayed local date and observes DST', () {
    AppDateTime.configure('Asia/Yangon');
    expect(AppDateTime.format('2026-10-27T03:29:17Z'), '2026-10-27 09:59 am');
    AppDateTime.configure('America/New_York');
    expect(AppDateTime.format('2026-07-01T16:00:00Z'), '2026-07-01 12:00 pm');
    expect(AppDateTime.format('2026-01-01T16:00:00Z'), '2026-01-01 11:00 am');
    AppDateTime.configure('Asia/Yangon');
  });
  test('missing or date-only values never invent an event time', () {
    for (final value in [
      null,
      '',
      '2026-10-27',
      'now',
      '2026-02-30T01:02:03Z',
      '2026-10-27T24:00:00Z',
      '2026-10-27T12:00:00',
      '2026-10-27T12:00:00+25:00',
    ]) {
      expect(AppDateTime.parse(value), isNull, reason: '$value');
      expect(AppDateTime.format(value), '—');
    }
  });
  test('reprinting preserves original confirmation instant independently of backdated invoice date', () {
    const confirmed = '2026-10-27T03:29:17.123456Z';
    const received = '2026-10-28T04:30:22Z';
    final sale = <String, Object?>{
      'id': 1,
      'currency_code': 'MMK',
      'currency_digits': 0,
      'business_name': 'Business',
      'branch_name_snapshot': 'Branch',
      'branch_code_snapshot': 'PZD',
      'invoice_date': '2026-10-25',
      'confirmed_at': confirmed,
      'customer_name': 'Customer',
      'employee_name': 'Employee',
      'items': [
        {
          'item_code': 'ITEM-000001',
          'item_name': 'Coffee',
          'qty': 1,
          'price': 3000,
          'amount': 3000,
        },
      ],
      'subtotal': 3000,
      'discount_amount': 0,
      'total': 3000,
      'paid': 1500,
      'balance_due': 1500,
      'payments': [
        {
          'payment_date': '2026-10-25',
          'created_at': confirmed,
          'account_name': 'Cash',
          'amount': 1000,
        },
      ],
      'collections': [
        {
          'receipt_id': 1,
          'payment_date': '2026-10-26',
          'received_at': received,
          'status': 'posted',
          'amount': 500,
        },
      ],
    };
    final before = jsonEncode(sale);
    final rows = invoicePrintRows(
      sale,
      const InvoicePrintSettings(),
      myanmar: false,
    );
    final text = rows.expand((r) => r.cells).join('\n');
    expect(
      rows
          .where(
            (r) =>
                r.cells.length == 1 &&
                r.cells.first.startsWith('Invoice date:'),
          )
          .length,
      1,
    );
    expect(
      text,
      contains(
        'Invoice date: 2026-10-25 · Confirmed: ${AppDateTime.format(confirmed)}',
      ),
    );
    expect(text, isNot(contains('Recorded at:')));
    expect(
      (sale['collections'] as List).cast<Map>().single['received_at'],
      received,
    );
    expect(text, contains('Credit due: 1,500 Ks'));
    expect(jsonEncode(sale), before);
    final again = invoicePrintRows(
      sale,
      const InvoicePrintSettings(),
      myanmar: false,
    ).expand((r) => r.cells).join('\n');
    expect(again, text);
  });
  test(
    'invoice and confirmation on the same local day occupy one print row',
    () {
      final sale = <String, Object?>{
        'id': 2,
        'invoice_date': '2026-10-26',
        'confirmed_at': '2026-10-26T10:15:33+06:30',
        'currency_code': 'MMK',
        'currency_digits': 0,
        'items': <Object>[],
        'payments': <Object>[],
        'collections': <Object>[],
        'subtotal': 0,
        'discount_amount': 0,
        'total': 0,
        'paid': 0,
        'balance_due': 0,
      };
      // The test runner's timezone can differ from the invoice's original timezone.
      // Use its actual local date to verify grouping while retaining the saved instant.
      final localDate = AppDateTime.format(sale['confirmed_at'])
          .substring(0, 10);
      sale['invoice_date'] = localDate;
      final rows = invoicePrintRows(
        sale,
        const InvoicePrintSettings(),
        myanmar: false,
      );
      expect(
        rows
            .where(
              (r) =>
                  r.cells.length == 1 &&
                  r.cells.first.startsWith('Invoice date/time:'),
            )
            .length,
        1,
      );
      expect(
        rows.expand((r) => r.cells).join('\n'),
        isNot(contains('Sale confirmed at:')),
      );
    },
  );
}
