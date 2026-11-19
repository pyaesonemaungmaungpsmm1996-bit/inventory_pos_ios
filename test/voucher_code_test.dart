import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/voucher_code.dart';
import 'package:inventory_pos/voucher_resolver.dart';
import 'package:inventory_pos/sale_return_print_snapshot.dart';

Map<String, Object?> voucher(String kind) => {
  'document_prefix': kind,
  'id': 42,
  'branch_id': 1,
  'invoice_date': '2026-11-13',
  'confirmed_at': '2026-11-13T05:00:00Z',
  'currency_code': 'MMK',
  'total': 900,
  'customer_name': 'PRIVATE_CUSTOMER',
  'customer_phone': 'PRIVATE_PHONE',
  'paid': 0,
  'balance_due': 900,
  'status': 'posted',
  'items': [
    {'item_code': 'AS01', 'item_name': 'Computer', 'qty': 3, 'amount': 900},
  ],
};
void main() {
  test(
    'QR opens the exact type/id and contains no raw customer details',
    () async {
      for (final kind in ['INV', 'RET', 'PUR']) {
        final saved = voucher(kind), code = VoucherCode.encode(voucher(kind));
        expect(code, isNot(contains('PRIVATE_')));
        var reads = 0;
        final result = await VoucherResolver.resolve(code, (type, id) async {
          reads++;
          expect(type, kind);
          expect(id, 42);
          return saved;
        });
        expect(identical(saved, result), isTrue);
        expect(reads, 1);
      }
    },
  );
  test(
    'payments and voiding keep lookup identity; another voucher does not',
    () async {
      final original = voucher('INV'),
          ref = VoucherCode.parse(VoucherCode.encode(voucher('INV')));
      expect(
        ref.matches({
          ...original,
          'paid': 900,
          'balance_due': 0,
          'status': 'void',
        }),
        isTrue,
      );
      expect(ref.matches({...original, 'document_prefix': 'PUR'}), isFalse);
      expect(ref.matches({...original, 'total': 901}), isFalse);
      expect(ref.matches({...original, 'branch_id': 2}), isFalse);
      await expectLater(
        VoucherResolver.resolve(
          VoucherCode.encode(original),
          (_, _) async => voucher('PUR'),
        ),
        throwsFormatException,
      );
    },
  );
  test('invalid QR is rejected before reading data', () async {
    for (final value in [
      'INV-000042',
      'https://example.org',
      'TPV2:INV:42:abc',
      'TPV1:INV:0:${'a' * 64}',
    ]) {
      await expectLater(
        VoucherResolver.resolve(
          value,
          (_, _) async => throw StateError('Must not read'),
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'return projection preserves exact refunds without inventing unit price',
    () {
      final result = saleReturnPrintSnapshot({
        'id': 1,
        'sale_id': 42,
        'return_date': '2026-11-13',
        'total': 100,
        'created_at': '2026-11-13T05:00:00Z',
        'items': [
          {'qty': 3, 'refund_amount': 100},
        ],
      });
      expect(result['document_prefix'], 'RET');
      expect(result['total'], 100);
      expect(result['paid'], 100);
      final row = (result['items'] as List).single as Map;
      expect(row['amount'], 100);
      expect(row['price'], isNull);
    },
  );
}
