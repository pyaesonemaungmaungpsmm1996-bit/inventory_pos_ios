import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_currency.dart';
import 'package:inventory_pos/money_ledger_repository.dart';

void main() {
  setUp(() => AppCurrency.current.value = 'MMK');
  final accounts = <Map<String, Object?>>[
    {'id': 1, 'name': 'Cash', 'type': 'cash', 'account_number': '', 'branch_name': 'A', 'opening_balance': 1000},
    {'id': 2, 'name': 'Bank', 'type': 'bank', 'account_number': '001', 'branch_name': 'A', 'opening_balance': 200},
  ];
  Map<String, Object?> entry(int id, int account, int amount, String note, {String status = 'posted'}) => {
    'id': id, 'account_id': account, 'amount': amount, 'note': note, 'voucher_status': status,
    'entry_date': '2026-10-29', 'created_at': '2026-10-29T00:00:00Z',
    'branch_name': 'A', 'account_name': account == 1 ? 'Cash' : 'Bank',
    'account_type': account == 1 ? 'cash' : 'bank', 'kind': 'adjustment',
  };
  test('Transfer and VOID reversal preserve separate and combined balances', () {
    final report = buildMoneyLedgerReport(accounts: accounts, entries: [
      entry(1, 1, -300, 'Transfer out'), entry(2, 2, 300, 'Transfer in'),
      entry(3, 1, -100, 'Expense', status: 'void'), entry(4, 1, 100, 'Void expense', status: 'void'),
    ], business: 'Test', filters: 'All');
    final summary = report.tables[0].rows;
    expect(summary[0][1], 1200);
    expect(summary[1][1], 400);
    expect(summary[2][1], 400);
    expect(summary[4][1], 1200);
    final balances = report.tables[1].rows;
    expect(balances[0][7], 700);
    expect(balances[1][7], 500);
    final details = report.tables[2].rows;
    expect(details.length, 4);
    expect(details[0][11], 700);
    expect(details[0][12], 900);
    expect(details.last[12], 1200);
  });
  test('Text search leaves balances unchanged and preserves running history', () {
    final report = buildMoneyLedgerReport(accounts: accounts,
      entries: [entry(1, 1, 500, 'Sale'), entry(2, 1, -200, 'Transport')],
      business: 'Test', filters: 'All', search: 'Transport');
    expect(report.tables[0].rows[4][1], 1500);
    final details = report.tables[2].rows;
    expect(details.length, 1);
    expect(details.single[11], 1300);
    expect(details.single[12], 1500);
  });
  test('Empty period retains each account opening balance', () {
    final report = buildMoneyLedgerReport(accounts: accounts, entries: [], business: 'Test', filters: 'Empty');
    expect(report.tables[0].rows[4][1], 1200);
    expect(report.tables[2].rows, isEmpty);
  });
}
