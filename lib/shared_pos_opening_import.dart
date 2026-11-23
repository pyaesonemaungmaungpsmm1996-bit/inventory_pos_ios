import 'app_database.dart';
import 'branch_records_sync.dart';
import 'product_tracking.dart';
import 'voucher_code.dart';

class SharedPosOpeningImport {
  static Future<Map<String, Object?>> prepare(String branchCode) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final branches = await txn.query(
        'branches',
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [branchCode],
      );
      if (branches.length != 1) {
        throw StateError('Windows and cloud branch codes must match.');
      }
      final branchId = branches.single['id'];
      final profile = (await txn.query(
        'business_profile',
        columns: ['currency_code', 'currency_digits'],
        where: 'id = 1',
      )).single;
      if (profile['currency_code'] != 'MMK' ||
          profile['currency_digits'] != 0) {
        throw StateError('This opening import requires MMK without decimals.');
      }
      final products = await txn.rawQuery(
        '''SELECT p.id, p.item_code, p.name, p.price, p.tracking,
                  COALESCE(s.stock, 0) AS quantity
           FROM products p LEFT JOIN branch_stocks s
             ON s.product_id = p.id AND s.branch_id = ?
           ORDER BY p.id''',
        [branchId],
      );
      final availableLots = await txn.query(
        'stock_lots',
        columns: ['product_id', 'serial', 'available'],
        where: 'branch_id = ? AND available > 0',
        whereArgs: [branchId],
        orderBy: 'id',
      );
      final lots = <int, List<Map<String, Object?>>>{};
      for (final lot in availableLots) {
        (lots[lot['product_id'] as int] ??= []).add(lot);
      }
      final stock = <Map<String, Object?>>[];
      for (final product in products) {
        final mode = product['tracking'];
        final code = product['item_code'];
        if (mode != 'serial' && mode != 'none') {
          throw StateError('Unsupported tracking mode for item $code ($mode).');
        }
        final quantity = product['quantity'] as int;
        final itemLots = lots[product['id']] ?? [];
        final serials = [
          for (final lot in itemLots)
            if (lot['available'] == 1 && lot['serial'] is String)
              (lot['serial'] as String).trim().toUpperCase(),
        ];
        if (mode == 'serial'
            ? quantity != serials.length ||
                  itemLots.length != serials.length ||
                  serials.toSet().length != serials.length ||
                  serials.any((serial) => serial.isEmpty || serial.length > 100)
            : itemLots.isNotEmpty) {
          throw StateError('Stock and serials do not match for item $code.');
        }
        stock.add({
          'code': code,
          'name': product['name'],
          'price': product['price'],
          'quantity': quantity,
          'serial_tracking': mode == 'serial',
          if (mode == 'serial') 'serials': serials,
        });
      }
      final accounts = await txn.rawQuery(
        '''SELECT a.name, a.type AS kind, COALESCE(SUM(e.amount), 0) AS balance
           FROM money_accounts a LEFT JOIN money_entries e ON e.account_id = a.id
           WHERE a.branch_id = ? GROUP BY a.id ORDER BY a.id''',
        [branchId],
      );
      for (final account in accounts) {
        if (!const ['cash', 'bank', 'wallet'].contains(account['kind']) ||
            (account['balance'] as int) < 0) {
          throw StateError('Unsupported opening account: ${account['name']}.');
        }
      }
      final history = <Map<String, Object?>>[];
      for (final (table, kind, prefix) in [
        ('sale_invoices', 'sale', 'INV'),
        ('purchase_invoices', 'purchase', 'PUR'),
      ]) {
        final documentId = kind == 'sale' ? 'sale_id' : 'purchase_id';
        final lineTable = kind == 'sale' ? 'sale_items' : 'purchase_items';
        final unitPrice = kind == 'sale' ? 'price' : 'purchase_price';
        final voucherLines = await txn.rawQuery(
          '''SELECT i.$documentId AS voucher, i.item_code, i.item_name,
                    i.qty, i.$unitPrice AS unit_price, i.amount, i.tracking_json
             FROM $lineTable i JOIN $table v ON v.id = i.$documentId
             WHERE v.branch_id = ? ORDER BY i.id''',
          [branchId],
        );
        final linesByVoucher = <int, List<Map<String, Object?>>>{};
        for (final line in voucherLines) {
          (linesByVoucher[line['voucher'] as int] ??= []).add({
            for (final key in [
              'item_code',
              'item_name',
              'qty',
              'unit_price',
              'amount',
            ])
              key: line[key],
            'tracking': ProductTracking.decode(line['tracking_json']),
          });
        }
        final vouchers = await txn.query(
          table,
          columns: [
            'id',
            'branch_id',
            'invoice_date',
            'status',
            'total',
            'paid',
            'balance_due',
            'currency_code',
            if (kind == 'sale') 'branch_code_snapshot',
          ],
          where: 'branch_id = ?',
          whereArgs: [branchId],
          orderBy: 'id',
        );
        for (final row in vouchers) {
          if (row['currency_code'] != 'MMK') {
            throw StateError('Archived vouchers use different currencies.');
          }
          history.add({
            'kind': kind,
            'number': VoucherCode.displayNumber({
              ...row,
              'document_prefix': prefix,
            }),
            'invoice_date': row['invoice_date'],
            'status': row['status'],
            'total': row['total'],
            'paid': row['paid'],
            'due': row['balance_due'],
            'lines': linesByVoucher[row['id']] ?? const [],
          });
        }
      }
      return {
        'branch_code': branchCode,
        'currency': 'MMK',
        'products': stock,
        'accounts': accounts,
        'history': history,
      };
    });
  }

  static Future<bool> upload(
    BranchRecordsSync connection,
    Map<String, Object?> document,
  ) async {
    final result = await connection.client.rpc(
      'tp_stock_sync_import_opening',
      params: {
        'shop': connection.shop,
        'device': connection.device,
        'secret': connection.secret,
        'document': document,
      },
    );
    return result as bool;
  }
}
