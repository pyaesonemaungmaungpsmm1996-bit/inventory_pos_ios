import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'product_tracking.dart';
import 'sale_invoice_details.dart';
import 'stock_sync.dart';
import 'voucher_code.dart';

/// Explicit binding for an approved device, its local branch and its catalog.
class StockSyncCheckout {
  final OfflineStockStore store;
  final int localBranchId;
  final Map<int, String> products;
  final Map<int, String> cashAccounts;

  StockSyncCheckout({
    required this.store,
    required this.localBranchId,
    required Map<int, String> products,
    required Map<int, String> cashAccounts,
  }) : products = Map.unmodifiable(products),
       cashAccounts = Map.unmodifiable(cashAccounts) {
    if (products.values.toSet().length != products.length ||
        cashAccounts.values.toSet().length != cashAccounts.length) {
      throw ArgumentError('Stock sync mappings must be one-to-one.');
    }
  }

  Future<void> stage(
    Transaction txn, {
    required int saleId,
    required Map<String, Object?> invoice,
    required List<Map<String, Object?>> items,
    required List<Map<String, int>> payments,
  }) async {
    final snapshot = await store.cachedSnapshot(txn);
    if (invoice['branch_id'] != localBranchId ||
        snapshot == null ||
        invoice['currency_code'] != 'MMK' ||
        invoice['currency_digits'] != 0 ||
        snapshot['currency'] != 'MMK') {
      throw StateError(
        'The sale does not match the approved sync branch and currency.',
      );
    }

    final total = invoice['total'] as int;
    if (invoice['balance_due'] != 0) {
      throw StateError('The offline sync pilot requires full cash payment.');
    }
    final nets = SaleInvoiceDetails.lineNets(items, total);
    final lines = <String, Map<String, Object>>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (ProductTracking.decode(item['tracking_json']).isNotEmpty) {
        throw StateError(
          'Serial and lot items are outside the offline sync pilot.',
        );
      }
      final id = products[item['product_id']];
      if (id == null) {
        throw StateError('Sync mapping is missing for ${item['item_name']}.');
      }
      final quantity = item['qty'] as int;
      final price = item['price'] as int;
      final previous = lines[id];
      lines[id] = {
        'product_id': id,
        'quantity': quantity + (previous?['quantity'] as int? ?? 0),
        'unit_minor': max(price, previous?['unit_minor'] as int? ?? 0),
        'line_minor': nets[index] + (previous?['line_minor'] as int? ?? 0),
      };
    }
    if (lines.values.fold<int>(
          0,
          (sum, line) => sum + (line['line_minor'] as int),
        ) !=
        total) {
      throw StateError('Sync sale total does not match the printed voucher.');
    }

    final settlements = <Map<String, Object>>[];
    for (final payment in payments) {
      final account = cashAccounts[payment['account_id']];
      if (account == null) {
        throw StateError('Choose a mapped cash account for offline checkout.');
      }
      settlements.add({
        'account_id': account,
        'amount_minor': payment['amount']!,
      });
    }

    final operation = newStockSyncId();
    await store.stageSale(
      txn,
      operation: operation,
      command: {
        'kind': 'sale',
        'offline': true,
        'occurred_at': invoice['confirmed_at'],
        'counterparty': invoice['customer_name'],
        'voucher': VoucherCode.displayNumber({...invoice, 'id': saleId}),
        'lines': lines.values.toList(),
        'payments': settlements,
      },
    );
    await txn.insert('app_settings', {
      'key': 'tp_sync_sale:$saleId',
      'value': operation,
    });
  }

  static Future<void> requireLocalVoucher(
    DatabaseExecutor db,
    int saleId,
  ) async {
    final marker = await db.query(
      'app_settings',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: ['tp_sync_sale:$saleId'],
      limit: 1,
    );
    if (marker.isNotEmpty) {
      throw StateError(
        'This synced test voucher can be viewed or printed. Reversals are not enabled.',
      );
    }
  }
}
