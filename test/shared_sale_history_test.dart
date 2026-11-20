import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/live_sale_sync.dart';
import 'package:inventory_pos/sale_invoice_history_page.dart';

void main() {
  test(
    'standard history merges same-account vouchers by identity and branch',
    () {
      final previous = LiveSaleSync.feed.value;
      addTearDown(() => LiveSaleSync.feed.value = previous);
      Map<String, dynamic> sale(
        String voucher,
        String branch,
        String status, {
        String? code,
      }) => {
        'voucher_id': voucher,
        'updated_at': '2026-11-20T10:00:00Z',
        'payload': {
          'number': 'PZD-000001',
          'branch': branch,
          'branch_code': code,
          'status': status,
          'total': 1000,
        },
      };
      LiveSaleSync.feed.value = (
        account: 'member',
        unavailable: false,
        rows: [
          sale('local', 'Pazundaung', 'posted'),
          sale('other-device', 'Old branch name', 'posted', code: 'pzd'),
          sale('legacy', 'Mandalay', 'draft'),
          sale('deleted', 'Pazundaung', 'removed'),
        ],
      );

      final rows = SaleInvoiceHistoryRepository.mergeSales(
        [
          {
            'id': 1,
            'live_identity': jsonEncode({
              'account': 'member',
              'voucher': 'local',
            }),
          },
        ],
        [
          {'id': 7, 'name': 'Pazundaung', 'code': 'PZD'},
          {'id': 8, 'name': 'Mandalay', 'code': 'MDY'},
        ],
      );

      expect(rows.where((row) => row['id'] == 1), hasLength(1));
      expect(rows.where((row) => row['live_voucher'] == 'local'), isEmpty);
      expect(rows.where((row) => row['live_voucher'] == 'deleted'), isEmpty);
      expect(
        rows.singleWhere(
          (row) => row['live_voucher'] == 'other-device',
        )['branch_id'],
        7,
      );
      expect(
        rows.singleWhere((row) => row['live_voucher'] == 'legacy')['branch_id'],
        8,
      );
    },
  );
}
