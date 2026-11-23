import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_datetime.dart';

/// All allocations are applied inside the same transaction as aggregate stock.
class ProductTracking {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE product_brands(id INTEGER PRIMARY KEY AUTOINCREMENT,category_id INTEGER NOT NULL REFERENCES product_categories(id),name TEXT NOT NULL COLLATE NOCASE CHECK(length(trim(name)) BETWEEN 1 AND 100),active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),UNIQUE(category_id,name))''',
    );
    for (final sql in [
      'ALTER TABLE products ADD COLUMN brand_id INTEGER REFERENCES product_brands(id)',
      "ALTER TABLE products ADD COLUMN color TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE products ADD COLUMN size TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE products ADD COLUMN tracking TEXT NOT NULL DEFAULT 'none' CHECK(tracking IN ('none','batch','serial','imei','both'))",
      'ALTER TABLE products ADD COLUMN warranty_days INTEGER NOT NULL DEFAULT 0 CHECK(warranty_days BETWEEN 0 AND 36500)',
      "ALTER TABLE sale_draft_items ADD COLUMN tracking_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE sale_items ADD COLUMN tracking_json TEXT NOT NULL DEFAULT '[]'",
      "ALTER TABLE purchase_items ADD COLUMN tracking_json TEXT NOT NULL DEFAULT '[]'",
    ]) {
      await db.execute(sql);
    }
    await db.execute(
      '''CREATE TABLE stock_lots(id INTEGER PRIMARY KEY AUTOINCREMENT,product_id INTEGER NOT NULL REFERENCES products(id),branch_id INTEGER NOT NULL REFERENCES branches(id),purchase_id INTEGER NOT NULL REFERENCES purchase_invoices(id),serial TEXT COLLATE NOCASE,imei TEXT,expires_on TEXT,received_qty INTEGER NOT NULL CHECK(received_qty>0),available INTEGER NOT NULL CHECK(available>=0 AND available<=received_qty),warranty_days INTEGER NOT NULL DEFAULT 0 CHECK(warranty_days BETWEEN 0 AND 36500),CHECK(serial IS NULL OR received_qty=1),CHECK(imei IS NULL OR received_qty=1))''',
    );
    await db.execute(
      'CREATE UNIQUE INDEX stock_serial_unique ON stock_lots(serial) WHERE serial IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX stock_imei_unique ON stock_lots(imei) WHERE imei IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX stock_lot_available ON stock_lots(branch_id,product_id,available,expires_on)',
    );
    await db.execute(
      '''CREATE TABLE sale_lot_allocations(sale_item_id INTEGER NOT NULL REFERENCES sale_items(id),lot_id INTEGER NOT NULL REFERENCES stock_lots(id),quantity INTEGER NOT NULL CHECK(quantity>0),warranty_until TEXT,PRIMARY KEY(sale_item_id,lot_id))''',
    );
    await db.execute(
      '''CREATE TABLE return_lot_allocations(return_id INTEGER NOT NULL REFERENCES sale_returns(id),sale_item_id INTEGER NOT NULL REFERENCES sale_items(id),lot_id INTEGER NOT NULL REFERENCES stock_lots(id),quantity INTEGER NOT NULL CHECK(quantity>0),PRIMARY KEY(return_id,sale_item_id,lot_id))''',
    );
  }

  static List<Map<String, dynamic>> decode(Object? value) {
    if (value == null) return [];
    final raw = value is String ? jsonDecode(value) : value;
    if (raw is! List || raw.length > 500) {
      throw const FormatException('Invalid lot allocations');
    }
    return raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  static bool tracked(Map row) =>
      row['tracking'] != null && row['tracking'] != 'none';
  static String today() =>
      AppDateTime.today().toIso8601String().substring(0, 10);
  static bool date(String s) {
    final d = DateTime.tryParse(s);
    return s.length == 10 &&
        d != null &&
        d.toIso8601String().substring(0, 10) == s;
  }

  static Future<void> brand(DatabaseExecutor db, int? id, int category) async {
    if (id != null &&
        (await db.query(
          'product_brands',
          where: 'id=? AND category_id=? AND active=1',
          whereArgs: [id, category],
        )).isEmpty) {
      throw StateError('Choose an active brand in this category');
    }
  }

  static Future<bool> canEnableSerial(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      '''SELECT 1 FROM products p
      WHERE p.id = ? AND p.tracking = 'none'
        AND NOT EXISTS (SELECT 1 FROM branch_stocks s
                        WHERE s.product_id = p.id AND s.stock <> 0)
        AND NOT EXISTS (SELECT 1 FROM stock_movements m WHERE m.product_id = p.id)
        AND NOT EXISTS (SELECT 1 FROM stock_lots l WHERE l.product_id = p.id)''',
      [id],
    );
    return rows.isNotEmpty;
  }

  static Future<void> validatePurchasePolicy(
    DatabaseExecutor db,
    int id,
    Map item,
  ) async {
    final p = (await db.query(
      'products',
      where: 'id=?',
      whereArgs: [id],
    )).single;
    final enableSerial =
        item['enable_serial_on_existing'] == true &&
        item['tracking'] == 'serial' &&
        await canEnableSerial(db, id);
    if (!enableSerial &&
            item['tracking'] != null &&
            item['tracking'] != p['tracking'] ||
        item['color'] != null && item['color'] != p['color'] ||
        item['size'] != null && item['size'] != p['size']) {
      throw StateError(
        'Tracking or variant policy changed. Reopen this purchase line and create a separate item code.',
      );
    }
    final days = item['warranty_days'];
    if (days != null &&
        (days is! int ||
            days < 0 ||
            days > 36500 ||
            !enableSerial && p['tracking'] == 'none' && days > 0)) {
      throw ArgumentError('Check tracking mode and warranty days');
    }
    if (enableSerial) {
      await db.update(
        'products',
        {'tracking': 'serial'},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  static Future<void> receive(
    DatabaseExecutor db,
    int productId,
    int branchId,
    int purchaseId,
    Map item, {
    int? replacingPurchaseId,
  }) async {
    final product = (await db.query(
      'products',
      where: 'id=?',
      whereArgs: [productId],
    )).single;
    final lots = decode(item['lots']);
    if (!tracked(product)) {
      if (lots.isNotEmpty) {
        throw StateError('This product does not use lot tracking');
      }
      return;
    }
    final mode = product['tracking'];
    final qty = item['qty'] as int;
    if (lots.isEmpty) {
      throw StateError('Enter serial/IMEI or batch details for this product');
    }
    var total = 0;
    for (final lot in lots) {
      final n = lot['qty'];
      if (n is! int || n <= 0) throw ArgumentError('Invalid lot quantity');
      total += n;
      final serial = '${lot['serial'] ?? ''}'.trim();
      final imei = '${lot['imei'] ?? ''}'.trim();
      final expiry = '${lot['expires_on'] ?? ''}'.trim();
      if ((mode == 'serial' || mode == 'both') &&
          (serial.isEmpty || serial.length > 100)) {
        throw ArgumentError('Serial number is required');
      }
      if ((mode == 'imei' || mode == 'both') &&
          !RegExp(r'^[0-9]{15}$').hasMatch(imei)) {
        throw ArgumentError('IMEI must contain 15 digits');
      }
      if (mode != 'batch' && n != 1) {
        throw ArgumentError('Each serial/IMEI must have quantity one');
      }
      if (expiry.isNotEmpty &&
          (!date(expiry) || expiry.compareTo(today()) < 0)) {
        throw ArgumentError('Choose a valid unexpired date');
      }
      if (replacingPurchaseId != null &&
          (serial.isNotEmpty || imei.isNotEmpty)) {
        final old = await db.query(
          'stock_lots',
          where: "purchase_id=? AND product_id=? AND branch_id=? AND available=0 AND ((?<>'' AND serial=? COLLATE NOCASE) OR (?<>'' AND imei=?))",
          whereArgs: [
            replacingPurchaseId,
            productId,
            branchId,
            serial,
            serial,
            imei,
            imei,
          ],
        );
        if (old.length == 1) {
          await db.update(
            'stock_lots',
            {
              'purchase_id': purchaseId,
              'serial': serial.isEmpty ? null : serial,
              'imei': imei.isEmpty ? null : imei,
              'received_qty': n,
              'available': n,
              'expires_on': expiry.isEmpty ? null : expiry,
              'warranty_days': product['warranty_days'],
            },
            where: 'id=?',
            whereArgs: [old.single['id']],
          );
          continue;
        }
      }
      if (serial.isNotEmpty &&
          (await db.query(
            'stock_lots',
            columns: ['id'],
            where: 'serial=? COLLATE NOCASE',
            whereArgs: [serial],
            limit: 1,
          )).isNotEmpty) {
        throw StateError(
          'Serial already registered: $serial. Check the original purchase.',
        );
      }
      if (imei.isNotEmpty &&
          (await db.query(
            'stock_lots',
            columns: ['id'],
            where: 'imei=?',
            whereArgs: [imei],
            limit: 1,
          )).isNotEmpty) {
        throw StateError(
          'IMEI already registered: $imei. Check the original purchase.',
        );
      }
      await db.insert('stock_lots', {
        'product_id': productId,
        'branch_id': branchId,
        'purchase_id': purchaseId,
        'serial': serial.isEmpty ? null : serial,
        'imei': imei.isEmpty ? null : imei,
        'expires_on': expiry.isEmpty ? null : expiry,
        'received_qty': n,
        'available': n,
        'warranty_days': product['warranty_days'],
      });
    }
    if (total != qty) {
      throw ArgumentError(
        'Serial/lot quantity is $total, but purchase quantity is $qty. Reopen this item and enter matching quantities.',
      );
    }
  }

  static Future<String> sell(
    DatabaseExecutor db,
    int product,
    int branch,
    int qty,
    Object? selection,
    int saleItem,
    String invoiceDate,
  ) async {
    final p = (await db.query(
      'products',
      where: 'id=?',
      whereArgs: [product],
    )).single;
    final allocations = decode(selection);
    if (!tracked(p)) {
      if (allocations.isNotEmpty) throw StateError('Unexpected lot selection');
      return '[]';
    }
    var count = 0;
    final seen = <int>{};
    final snapshot = <Map<String, Object?>>[];
    for (final a in allocations) {
      final id = a['lot_id'], n = a['qty'];
      if (id is! int || n is! int || n <= 0 || !seen.add(id)) {
        throw ArgumentError('Invalid selected lots');
      }
      final rows = await db.query(
        'stock_lots',
        where: 'id=? AND product_id=? AND branch_id=? AND available>=?',
        whereArgs: [id, product, branch, n],
      );
      if (rows.isEmpty) {
        throw StateError('Selected serial/IMEI/batch is no longer in stock');
      }
      final lot = rows.single;
      final expiry = lot['expires_on'] as String?;
      if (expiry != null &&
          (expiry.compareTo(today()) < 0 ||
              expiry.compareTo(invoiceDate) < 0)) {
        throw StateError('Expired items cannot be sold');
      }
      final changed = await db.rawUpdate(
        'UPDATE stock_lots SET available=available-? WHERE id=? AND available>=?',
        [n, id, n],
      );
      if (changed != 1) throw StateError('Selected item was already sold');
      final days = lot['warranty_days'] as int;
      final until = days == 0
          ? null
          : DateTime.parse(invoiceDate)
                .add(Duration(days: days))
                .toIso8601String()
                .substring(0, 10);
      await db.insert('sale_lot_allocations', {
        'sale_item_id': saleItem,
        'lot_id': id,
        'quantity': n,
        'warranty_until': until,
      });
      snapshot.add({
        'lot_id': id,
        'qty': n,
        'serial': lot['serial'],
        'imei': lot['imei'],
        'expires_on': expiry,
        'warranty_until': until,
        'color': p['color'],
        'size': p['size'],
      });
      count += n;
    }
    if (count != qty) {
      throw StateError(
        'Select the exact serial/IMEI or batch quantity before confirming the invoice',
      );
    }
    return jsonEncode(snapshot);
  }

  static Future<void> requireLotAtTransactionBranch(
    DatabaseExecutor db,
    Object? lot,
    String table,
    int record,
  ) async {
    if ((await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='transfer_voucher_lots'",
    )).isEmpty) {
      return;
    }
    final pending = await db.rawQuery(
      "SELECT 1 FROM transfer_voucher_lots a JOIN transfer_voucher_items i ON i.id=a.item_id JOIN transfer_vouchers v ON v.id=i.voucher_id WHERE (a.lot_id=? OR a.destination_lot_id=?) AND v.status='posted' AND v.received_at IS NULL LIMIT 1",
      [lot, lot],
    );
    final location = await db.rawQuery(
      'SELECT 1 FROM stock_lots l JOIN $table v ON v.branch_id=l.branch_id WHERE l.id=? AND v.id=?',
      [lot, record],
    );
    if (pending.isNotEmpty || location.isEmpty) {
      throw StateError(
        'The tracked item is in transit or another branch. Reverse its transfer first.',
      );
    }
  }

  static Future<void> requireNoActiveTransfer(
    DatabaseExecutor db,
    Object? lot,
  ) async {
    if ((await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='transfer_voucher_lots'",
    )).isEmpty) {
      return;
    }
    if ((await db.rawQuery(
      "SELECT 1 FROM transfer_voucher_lots a JOIN transfer_voucher_items i ON i.id=a.item_id JOIN transfer_vouchers v ON v.id=i.voucher_id WHERE (a.lot_id=? OR a.destination_lot_id=?) AND v.status='posted' LIMIT 1",
      [lot, lot],
    )).isNotEmpty) {
      throw StateError(
        'Reverse the related stock transfer before reversing this tracked transaction.',
      );
    }
  }

  static Future<void> reverseSale(
    DatabaseExecutor db,
    int sale, {
    Set<int> excluding = const {},
  }) async {
    final rows = await db.rawQuery(
      'SELECT a.* FROM sale_lot_allocations a JOIN sale_items i ON i.id=a.sale_item_id WHERE i.sale_id=?',
      [sale],
    );
    for (final a in rows) {
      if (excluding.contains(a['sale_item_id'])) continue;
      await requireLotAtTransactionBranch(
        db,
        a['lot_id'],
        'sale_invoices',
        sale,
      );
      final changed = await db.rawUpdate(
        'UPDATE stock_lots SET available=available+? WHERE id=? AND available+?<=received_qty',
        [a['quantity'], a['lot_id'], a['quantity']],
      );
      if (changed != 1) throw StateError('Tracked stock cannot be restored');
    }
  }

  static Future<void> reversePurchase(DatabaseExecutor db, int purchase) async {
    final rows = await db.query(
      'stock_lots',
      where: 'purchase_id=?',
      whereArgs: [purchase],
    );
    for (final lot in rows) {
      await requireNoActiveTransfer(db, lot['id']);
      if (lot['available'] != lot['received_qty']) {
        throw StateError(
          'A serial/IMEI or batch from this purchase has already been sold',
        );
      }
    }
    // Retain identity records and history. A voided receipt is never available.
    await db.update(
      'stock_lots',
      {'available': 0},
      where: 'purchase_id=?',
      whereArgs: [purchase],
    );
  }

  static Future<void> returnItems(
    DatabaseExecutor db,
    int returnId,
    int saleItem,
    int qty,
    Object? selected,
  ) async {
    final item = (await db.query(
      'sale_items',
      where: 'id=?',
      whereArgs: [saleItem],
    )).single;
    final p = (await db.query(
      'products',
      where: 'id=?',
      whereArgs: [item['product_id']],
    )).single;
    if (!tracked(p)) return;
    var sum = 0;
    final seen = <int>{};
    for (final choice in decode(selected)) {
      final lot = choice['lot_id'], n = choice['qty'];
      if (lot is! int || n is! int || n <= 0 || !seen.add(lot)) {
        throw ArgumentError('Choose valid returned serial/IMEI/batches');
      }
      final original = await db.query(
        'sale_lot_allocations',
        where: 'sale_item_id=? AND lot_id=?',
        whereArgs: [saleItem, lot],
      );
      final prior = await db.rawQuery(
        "SELECT COALESCE(SUM(a.quantity),0) n FROM return_lot_allocations a JOIN sale_returns r ON r.id=a.return_id WHERE r.status='posted' AND a.sale_item_id=? AND a.lot_id=?",
        [saleItem, lot],
      );
      if (original.isEmpty ||
          n + (prior.single['n'] as int) >
              (original.single['quantity'] as int)) {
        throw StateError(
          'This serial/IMEI was not sold on this invoice or was already returned',
        );
      }
      final changed = await db.rawUpdate(
        'UPDATE stock_lots SET available=available+? WHERE id=? AND branch_id=? AND available+?<=received_qty',
        [
          n,
          lot,
          (await db.query(
            'sale_returns',
            where: 'id=?',
            whereArgs: [returnId],
          )).single['branch_id'],
          n,
        ],
      );
      if (changed != 1) throw StateError('Returned lot stock is inconsistent');
      await db.insert('return_lot_allocations', {
        'return_id': returnId,
        'sale_item_id': saleItem,
        'lot_id': lot,
        'quantity': n,
      });
      sum += n;
    }
    if (sum != qty) {
      throw StateError(
        'Select the exact serial/IMEI or batch quantity being returned',
      );
    }
  }

  static Future<void> reverseReturn(DatabaseExecutor db, int id) async {
    for (final a in await db.query(
      'return_lot_allocations',
      where: 'return_id=?',
      whereArgs: [id],
    )) {
      await requireLotAtTransactionBranch(db, a['lot_id'], 'sale_returns', id);
      final n = await db.rawUpdate(
        'UPDATE stock_lots SET available=available-? WHERE id=? AND available>=?',
        [a['quantity'], a['lot_id'], a['quantity']],
      );
      if (n != 1) {
        throw StateError('The returned serial/IMEI or batch was already used');
      }
    }
  }

  static Future<void> requireUntracked(DatabaseExecutor db, Object? id) async {
    if ((await db.query(
      'products',
      columns: ['id'],
      where: "id=? AND tracking<>'none'",
      whereArgs: [id],
    )).isNotEmpty) {
      throw StateError(
        'This action needs serial/batch handling. Use Purchase and Sale for tracked items; void the full invoice to reverse a tracked sale.',
      );
    }
  }
}
