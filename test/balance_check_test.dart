import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/balance_check_repository.dart';
import 'package:inventory_pos/money_posting.dart';

void main() {
  Map<String, Object?> check(String status, int account, int book, int actual, String day) => {
    'status': status, 'account_id': account, 'book_balance': book, 'actual_balance': actual,
    'difference': balanceCheckDifference(book, actual), 'check_date': day,
  };
  test('Saving an open check never posts money, including zero actual balance', () {
    expect(balanceCheckDifference(100, 0), -100);
    expect(balanceCheckPlan(after: check('open', 1, 100, 0, '2026-10-01'), today: '2026-10-30'), isEmpty);
    expect(() => balanceCheckDifference(100, -1), throwsArgumentError);
  });
  test('Apply posts actual minus book; matched balances post nothing', () {
    final old = check('open', 1, 1000, 950, '2026-10-01');
    final legs = balanceCheckPlan(before: old, after: {...old, 'status': 'adjusted'}, today: '2026-10-30');
    expect(moneyPostingNet(legs), {1: -50});
    expect(legs.single.date, '2026-10-01');
    expect(balanceCheckPlan(after: check('adjusted', 1, 100, 100, '2026-10-01'), today: '2026-10-30'), isEmpty);
  });
  test('Editing an applied count reverses the old adjustment and posts the new one', () {
    final old = check('adjusted', 1, 1000, 950, '2026-10-01');
    final legs = balanceCheckPlan(before: old, after: check('adjusted', 1, 1000, 970, '2026-10-05'), today: '2026-10-30');
    expect(moneyPostingNet(legs), {1: 20});
    expect(legs.first.date, '2026-10-01');
    expect(legs.last.date, '2026-10-05');
    expect(balanceCheckPlan(before: old, after: {...old, 'note': 'Changed'}, today: '2026-10-30'), isEmpty);
  });
  test('Moving the applied count to another account restores the original account', () {
    final legs = balanceCheckPlan(before: check('adjusted', 1, 1000, 950, '2026-10-01'),
      after: check('adjusted', 2, 200, 210, '2026-10-05'), today: '2026-10-30');
    expect(moneyPostingNet(legs), {1: 50, 2: 10});
  });
  test('VOID reverses only applied money on its action date', () {
    expect(balanceCheckPlan(before: check('open', 1, 100, 90, '2026-10-01'), today: '2026-10-30'), isEmpty);
    final legs = balanceCheckPlan(before: check('adjusted', 1, 200, 210, '2026-10-01'), today: '2026-10-30');
    expect(moneyPostingNet(legs), {1: -10});
    expect(legs.single.date, '2026-10-30');
  });
  test('Snapshot guard rejects net-unchanged new entries as well as changed balances', () {
    requireBalanceSnapshot(storedBook: 1000, storedEntry: 5, currentBook: 1000, currentEntry: 5);
    expect(() => requireBalanceSnapshot(storedBook: 1000, storedEntry: 5, currentBook: 990, currentEntry: 6), throwsStateError);
    expect(() => requireBalanceSnapshot(storedBook: 1000, storedEntry: 5, currentBook: 1000, currentEntry: 7), throwsStateError);
  });
}
