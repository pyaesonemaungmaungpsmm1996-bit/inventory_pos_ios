import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/money_posting.dart';
import 'package:inventory_pos/other_money_repository.dart';

void main() {
  Map<String, Object?> voucher(int account, String direction, int amount, String date) => {
    'account_id': account, 'direction': direction, 'amount': amount, 'entry_date': date,
    'category': 'Other', 'description': '',
  };
  test('Money in and out post exact signed amounts', () {
    expect(moneyPostingNet(otherMoneyPlan(after: voucher(1, 'in', 125, '2026-10-01'), today: '2026-10-30')), {1: 125});
    expect(moneyPostingNet(otherMoneyPlan(after: voucher(1, 'out', 125, '2026-10-01'), today: '2026-10-30')), {1: -125});
  });
  test('Edit amount, account and direction produces the correct net changes', () {
    final old = voucher(1, 'in', 100, '2026-10-01');
    expect(moneyPostingNet(otherMoneyPlan(before: old, after: voucher(1, 'in', 80, '2026-10-01'), today: '2026-10-30')), {1: -20});
    expect(moneyPostingNet(otherMoneyPlan(before: old, after: voucher(2, 'in', 100, '2026-10-02'), today: '2026-10-30')), {1: -100, 2: 100});
    expect(moneyPostingNet(otherMoneyPlan(before: old, after: voucher(1, 'out', 100, '2026-10-01'), today: '2026-10-30')), {1: -200});
  });
  test('Only category/description changes do not post money', () {
    final old = voucher(1, 'in', 100, '2026-10-01');
    expect(otherMoneyPlan(before: old, after: {...old, 'category': 'Capital', 'description': 'Changed'}, today: '2026-10-30'), isEmpty);
  });
  test('VOID restores money out, or removes money in, on the action date', () {
    final out = otherMoneyPlan(before: voucher(1, 'out', 100, '2026-10-01'), today: '2026-10-30');
    expect(moneyPostingNet(out), {1: 100});
    expect(out.single.date, '2026-10-30');
    final income = otherMoneyPlan(before: voucher(1, 'in', 100, '2026-10-01'), today: '2026-10-30');
    expect(moneyPostingNet(income), {1: -100});
    expect(() => checkedMoneyBalance(50, income.single.amount, 'Cash'), throwsStateError);
  });
  test('Current limits and historical balances reject invalid postings', () {
    expect(checkedMoneyBalance(100, -80, 'Cash'), 20);
    expect(() => checkedMoneyBalance(9000000000000, 1, 'Cash'), throwsStateError);
    expect(() => validateMoneyPostingHistory(daily: {'2026-10-20': 500},
      changes: {'2026-10-10': -100}, accountName: 'Cash'), throwsStateError);
    expect(() => validateMoneyPostingHistory(daily: {'2026-10-10': 100, '2026-10-15': -50},
      changes: {'2026-10-10': -100, '2026-10-20': 100}, accountName: 'Cash'), throwsStateError);
    validateMoneyPostingHistory(daily: {'2026-10-01': 500}, changes: {'2026-10-10': -100}, accountName: 'Cash');
  });
}
