import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/voucher_code.dart';

void main() {
  test(
    'synced vouchers with overlapping local numbers keep distinct labels',
    () {
      final local = {'id': 21, 'branch_id': 4, 'branch_code_snapshot': 'PZD'};
      final remote = {
        'branch_id': 4,
        'live_number': 'PZD-000021',
        'live_voucher': '01abcdefabcdefabcdefabcdefabcdef',
      };
      String number(Map<String, Object?> row) =>
          row['live_number'] as String? ?? VoucherCode.displayNumber(row);

      final rows = VoucherCode.markReferenceCollisions([local, remote], number);

      expect(
        VoucherCode.displayReference(rows[0], number(rows[0])),
        'PZD-000021',
      );
      expect(
        VoucherCode.displayReference(rows[1], number(rows[1])),
        'PZD-000021 · Sync 01ABCDEF',
      );
      expect(remote['live_number'], 'PZD-000021');
    },
  );
}
