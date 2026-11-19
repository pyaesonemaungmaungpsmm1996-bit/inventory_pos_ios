import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/account_transfer_repository.dart';

void main() {
  Map<String, Object?> transfer(int from, int to, int amount, String date) => {
    'from_account_id': from, 'to_account_id': to, 'amount': amount, 'transfer_date': date,
  };
  test('New transfer posts equal out/in legs on the selected business date', () {
    final legs = accountTransferPlan(after: transfer(1, 2, 100, '2026-10-01'), today: '2026-10-30');
    expect(legs.length, 2);
    expect(accountTransferNet(legs), {1: -100, 2: 100});
    expect(legs.map((l) => l.date), everyElement('2026-10-01'));
  });
  test('Editing amount checks only net balance change but retains reversal history', () {
    final legs = accountTransferPlan(before: transfer(1, 2, 100, '2026-10-01'),
      after: transfer(1, 2, 200, '2026-10-01'), today: '2026-10-30');
    expect(legs.length, 4);
    expect(accountTransferNet(legs), {1: -100, 2: 100});
  });
  test('Changing the destination restores the old destination and credits the new one', () {
    final legs = accountTransferPlan(before: transfer(1, 2, 100, '2026-10-01'),
      after: transfer(1, 3, 100, '2026-10-05'), today: '2026-10-30');
    expect(accountTransferNet(legs), {1: 0, 2: -100, 3: 100});
    expect(legs.take(2).map((l) => l.date), everyElement('2026-10-01'));
    expect(legs.skip(2).map((l) => l.date), everyElement('2026-10-05'));
  });
  test('Notes alone do not post any money entries', () {
    final old = transfer(1, 2, 100, '2026-10-01');
    expect(accountTransferPlan(before: {...old, 'note': 'Old'}, after: {...old, 'note': 'New'}, today: '2026-10-30'), isEmpty);
  });
  test('VOID reverses the latest transfer on action date', () {
    final legs = accountTransferPlan(before: transfer(1, 2, 200, '2026-10-01'), today: '2026-10-30');
    expect(accountTransferNet(legs), {1: 200, 2: -200});
    expect(legs.map((l) => l.date), everyElement('2026-10-30'));
  });
}
