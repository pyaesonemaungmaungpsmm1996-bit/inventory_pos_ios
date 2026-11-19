import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_currency.dart';
import 'package:inventory_pos/supplier_ledger_repository.dart';

void main() {
  setUp(() => AppCurrency.current.value = 'MMK');
  Map<String, Object?> purchase(int id, int total, String day, {String? cancelled}) => {
    'id': id, 'total': total, 'invoice_date': day, 'confirmed_at': '${day}T09:00:00Z',
    'status': cancelled == null ? 'posted' : 'void', 'void_date': cancelled,
    'voided_at': cancelled == null ? null : '${cancelled}T12:00:00Z', 'void_reason': '',
    'branch_id': 1, 'supplier_id': 1, 'branch_name': 'A', 'supplier_name': 'Supplier',
    'current_supplier_name': 'Supplier', 'supplier_phone': '', 'supplier_address': '',
    'paid': 500, 'balance_due': total - 500, 'replacement_id': null,
  };
  Map<String, Object?> payment(int id, int purchase, int amount, String day, String note) => {
    'id': id, 'linked_purchase_id': purchase, 'amount': amount, 'entry_date': day,
    'created_at': '${day}T12:00:00Z', 'account_name': 'Cash', 'note': note,
    'supplier_settlement_id': null, 'voucher_status': 'posted',
  };
  final payments = [
    payment(1, 1, -200, '2026-09-01', 'Initial'),
    payment(2, 1, -300, '2026-10-10', 'Later payment'),
    payment(3, 2, -100, '2026-10-05', 'Initial second purchase'),
    payment(4, 2, 100, '2026-10-20', 'Void purchase refund'),
  ];
  final purchases = [purchase(1, 1000, '2026-09-01'), purchase(2, 600, '2026-10-05', cancelled: '2026-10-20')];
  test('Opening plus purchases minus cancellations/payments plus refunds reconciles', () {
    final report = buildSupplierLedgerReport(purchases: purchases, payments: payments, items: [],
      from: '2026-10-01', to: '2026-10-31', business: 'Test', filters: 'All');
    final summary = report.tables[0].rows;
    expect(summary.map((r) => r[1]).toList(), [800, 600, 600, 400, 100, 500]);
    expect(report.tables[2].rows.length, 2);
    expect(report.tables[2].rows.last[8], 0);
  });
  test('Historical cutoff before current VOID keeps old liability', () {
    final report = buildSupplierLedgerReport(purchases: purchases, payments: payments, items: [],
      from: '2026-10-01', to: '2026-10-15', business: 'Test', filters: 'Past');
    expect(report.tables[0].rows[5][1], 1000);
    expect(report.tables[2].rows.last[8], 500);
  });
  test('Search filters transaction detail without changing payable or running balance', () {
    final report = buildSupplierLedgerReport(purchases: purchases, payments: payments, items: [],
      from: '2026-10-01', to: '2026-10-31', business: 'Test', filters: 'All', search: 'Later payment');
    expect(report.tables[0].rows[5][1], 500);
    final rows = report.tables[3].rows;
    expect(rows.length, 1);
    expect(rows.single[9], 500);
    expect(rows.single[11], 1000);
  });
}
