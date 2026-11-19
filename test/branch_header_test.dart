import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/a4_layout_settings.dart';
import 'package:inventory_pos/invoice_branch_header.dart';
import 'package:inventory_pos/voucher_code.dart';

final savedBranches = <Map<String, Object?>>[
  {
    'id': 1,
    'name': 'Yangon',
    'address': 'New Yangon address',
    'phone': '091111',
  },
  {
    'id': 2,
    'name': 'Mandalay',
    'address': 'New Mandalay address',
    'phone': '092222',
  },
];
final invoice = <String, Object?>{
  'id': 42,
  'branch_id': 1,
  'branch_name_snapshot': 'Old Yangon',
  'branch_address_snapshot': 'Old address',
  'branch_phone_snapshot': '090000',
  'invoice_date': '2026-11-13',
  'total': 100,
  'items': [
    {'item_code': 'A', 'item_name': 'Item', 'qty': 1, 'amount': 100},
  ],
};
void main() {
  test('current contacts replace stale print addresses without changing saved vouchers', () {
    final before = jsonEncode(invoice), code = VoucherCode.encode(invoice);
    final one = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(),
      savedBranches.take(1).toList(),
    );
    expect(one.single, contains('New Yangon address'));
    expect(one.single, isNot(contains('Old address')));
    final two = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(),
      savedBranches,
    );
    expect(two.length, 2);
    expect(two.last, contains('New Mandalay address'));
    expect(jsonEncode(invoice), before);
    expect(VoucherCode.encode({...invoice, 'print_branch_blocks': two}), code);
  });
  test('one/two modes and selected branch order are respected', () {
    final one = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(branchMode: 'one', primaryBranchId: 2),
      savedBranches,
    );
    expect(one.length, 1);
    expect(one.single, startsWith('Mandalay'));
    final two = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(
        branchMode: 'two',
        primaryBranchId: 2,
        secondaryBranchId: 1,
      ),
      savedBranches,
    );
    expect(two.first, startsWith('Mandalay'));
    expect(two.last, startsWith('Yangon'));
    final fixedSecond = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(branchMode: 'two', secondaryBranchId: 1),
      savedBranches,
    );
    expect(fixedSecond.first, startsWith('Mandalay'));
    expect(fixedSecond.last, startsWith('Yangon'));
    expect(
      InvoiceBranchHeader.resolve(
        invoice,
        const A4LayoutSettings(branchMode: 'two'),
        savedBranches.take(1).toList(),
      ).length,
      1,
    );
  });
  test('custom, original snapshot and legacy preferences remain available', () {
    final legacy = A4LayoutSettings.fromJson({'leftBranch': 'Manual address'});
    expect(legacy.branchMode, 'custom');
    expect(InvoiceBranchHeader.resolve(invoice, legacy, savedBranches), [
      'Manual address',
    ]);
    final original = InvoiceBranchHeader.resolve(
      invoice,
      const A4LayoutSettings(branchMode: 'snapshot'),
      savedBranches,
    );
    expect(original.single, contains('Old address'));
    const selected = A4LayoutSettings(
      branchMode: 'two',
      primaryBranchId: 1,
      secondaryBranchId: 2,
    );
    expect(
      A4LayoutSettings.fromJson(selected.toJson()).toJson(),
      selected.toJson(),
    );
    expect(
      () => const A4LayoutSettings(
        primaryBranchId: 1,
        secondaryBranchId: 1,
      ).validate(),
      throwsFormatException,
    );
  });
}
