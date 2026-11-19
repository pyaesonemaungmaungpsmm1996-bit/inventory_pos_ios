import 'activity_store.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'product_tracking.dart';

class TransferVoucherRepository {
  static Future<void> install(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE transfer_vouchers(id INTEGER PRIMARY KEY AUTOINCREMENT,request_key TEXT NOT NULL UNIQUE,request_payload TEXT NOT NULL,branch_id INTEGER NOT NULL REFERENCES branches(id),destination_branch_id INTEGER NOT NULL REFERENCES branches(id),transfer_date TEXT NOT NULL,note TEXT NOT NULL,transport_info TEXT NOT NULL,created_at TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted','void')),received_at TEXT,void_reason TEXT,CHECK(branch_id<>destination_branch_id))",
    );
    await db.execute(
      "CREATE TABLE transfer_voucher_items(id INTEGER PRIMARY KEY AUTOINCREMENT,voucher_id INTEGER NOT NULL REFERENCES transfer_vouchers(id),product_id INTEGER NOT NULL REFERENCES products(id),quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 2147483647),item_code TEXT NOT NULL,product_name TEXT NOT NULL,color TEXT NOT NULL,size TEXT NOT NULL,tracking TEXT NOT NULL)",
    );
    await db.execute(
      "CREATE TABLE transfer_voucher_lots(item_id INTEGER NOT NULL REFERENCES transfer_voucher_items(id),lot_id INTEGER NOT NULL REFERENCES stock_lots(id),quantity INTEGER NOT NULL CHECK(quantity>0),destination_lot_id INTEGER REFERENCES stock_lots(id),serial TEXT,imei TEXT,expires_on TEXT,PRIMARY KEY(item_id,lot_id))",
    );
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name'] as String).toSet();
    if (tables.contains('activity_events')) {
      for (final spec in [
        const ActivitySpec('transfer_vouchers', 'inventory', 'TRV'),
        const ActivitySpec(
          'transfer_voucher_items',
          'inventory',
          'TRV-ITEM',
          technical: true,
        ),
        const ActivitySpec(
          'transfer_voucher_lots',
          'inventory',
          'TRV-LOT',
          technical: true,
        ),
      ]) {
        for (final sql in ActivityStore.triggers(
          spec,
          await db.rawQuery('PRAGMA table_info("${spec.table}")'),
          tables,
        )) {
          await db.execute(sql);
        }
      }
    }
  }

  static Future<List<Map<String, Object?>>> list(
    DatabaseExecutor db,
    int branch,
  ) => db.rawQuery(
    'SELECT v.*,s.name source_name,d.name destination_name,(SELECT COUNT(*) FROM transfer_voucher_items i WHERE i.voucher_id=v.id) line_count,(SELECT SUM(quantity) FROM transfer_voucher_items i WHERE i.voucher_id=v.id) total_qty FROM transfer_vouchers v JOIN branches s ON s.id=v.branch_id JOIN branches d ON d.id=v.destination_branch_id WHERE v.branch_id=? OR v.destination_branch_id=? ORDER BY v.id DESC',
    [branch, branch],
  );
  static Future<List<Map<String, Object?>>> items(
    DatabaseExecutor db,
    int id,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final row in await db.query(
      'transfer_voucher_items',
      where: 'voucher_id=?',
      whereArgs: [id],
    )) {
      result.add({
        ...row,
        'lots': await db.query(
          'transfer_voucher_lots',
          where: 'item_id=?',
          whereArgs: [row['id']],
        ),
      });
    }
    return result;
  }

  static Future<void> stock(
    DatabaseExecutor db,
    int branch,
    int product,
    int qty,
    String note,
    String now,
  ) async {
    await db.rawInsert(
      'INSERT OR IGNORE INTO branch_stocks(branch_id,product_id,stock) VALUES(?,?,0)',
      [branch, product],
    );
    final changed = await db.rawUpdate(
      'UPDATE branch_stocks SET stock=stock+? WHERE branch_id=? AND product_id=? AND stock+? BETWEEN 0 AND 2147483647',
      [qty, branch, product, qty],
    );
    if (changed != 1) {
      throw StateError(
        'Stock changed or is insufficient. Refresh and try again. / လက်ကျန်မလုံလောက်ပါ။ ပြန်စစ်ပါ။',
      );
    }
    await db.insert('stock_movements', {
      'branch_id': branch,
      'product_id': product,
      'quantity': qty.abs(),
      'kind': qty > 0 ? 'in' : 'sale',
      'note': note,
      'created_at': now,
    });
  }

  static Future<int> post(
    Database db, {
    required String requestKey,
    required int source,
    required int destination,
    required String date,
    required String note,
    required String transport,
    required List<Map<String, Object?>> lines,
    int? replaceId,
    String? expectedPayload,
  }) => db.transaction((tx) async {
    if (requestKey.isEmpty ||
        source == destination ||
        lines.isEmpty ||
        lines.length > 200 ||
        !ProductTracking.date(date) ||
        date.compareTo(ProductTracking.today()) > 0 ||
        note.length > 500 ||
        transport.length > 500) {
      throw ArgumentError('Check branches, date and transfer items.');
    }
    final old = await tx.query(
      'transfer_vouchers',
      where: 'request_key=?',
      whereArgs: [requestKey],
    );
    final payload = jsonEncode({
      'source': source,
      'destination': destination,
      'date': date,
      'note': note.trim(),
      'transport': transport.trim(),
      'lines': lines,
    });
    if (old.isNotEmpty) {
      if (old.single['request_payload'] != payload) {
        throw StateError(
          'This transfer was already saved. Reopen the voucher list.',
        );
      }
      return old.single['id'] as int;
    }
    String? originalCreatedAt;
    if (replaceId != null) {
      final saved = await tx.query(
        'transfer_vouchers',
        where: 'id=?',
        whereArgs: [replaceId],
      );
      if (saved.isEmpty ||
          saved.single['status'] != 'posted' ||
          saved.single['received_at'] != null ||
          saved.single['request_payload'] != expectedPayload) {
        throw StateError(
          'Transfer changed or was received. Reload before editing.',
        );
      }
      originalCreatedAt = saved.single['created_at'] as String;
      if (saved.single['branch_id'] != source) {
        throw StateError('Transfer source cannot change');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      for (final item in await items(tx, replaceId)) {
        for (final lot in (item['lots'] as List).cast<Map>()) {
          if (await tx.rawUpdate(
                'UPDATE stock_lots SET available=available+? WHERE id=? AND branch_id=? AND available+?<=received_qty',
                [lot['quantity'], lot['lot_id'], source, lot['quantity']],
              ) !=
              1) {
            throw StateError('Source lot changed');
          }
        }
        await stock(
          tx,
          source,
          item['product_id'] as int,
          item['quantity'] as int,
          'Edit transfer #$replaceId reversal',
          now,
        );
        await tx.delete(
          'transfer_voucher_lots',
          where: 'item_id=?',
          whereArgs: [item['id']],
        );
      }
      await tx.delete(
        'transfer_voucher_items',
        where: 'voucher_id=?',
        whereArgs: [replaceId],
      );
      await tx.delete(
        'transfer_vouchers',
        where: 'id=?',
        whereArgs: [replaceId],
      );
    }
    if ((await tx.rawQuery('SELECT id FROM branches WHERE id IN (?,?)', [
          source,
          destination,
        ])).length !=
        2) {
      throw StateError('Branch missing');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await tx.insert('transfer_vouchers', {
      'id': ?replaceId,
      'request_key': requestKey,
      'request_payload': payload,
      'branch_id': source,
      'destination_branch_id': destination,
      'transfer_date': date,
      'note': note.trim(),
      'transport_info': transport.trim(),
      'created_at': originalCreatedAt ?? now,
    });
    final seen = <int>{};
    for (final line in lines) {
      final product = line['product_id'], qty = line['quantity'];
      if (product is! int ||
          qty is! int ||
          qty < 1 ||
          qty > 2147483647 ||
          !seen.add(product)) {
        throw ArgumentError(
          'Choose each Color/Size item once with a valid quantity.',
        );
      }
      final p = (await tx.query(
        'products',
        where: 'id=?',
        whereArgs: [product],
      )).single;
      if (line['color'] != p['color'] ||
          line['size'] != p['size'] ||
          line['tracking'] != p['tracking']) {
        throw StateError('Product variant changed; select the item again.');
      }
      final item = await tx.insert('transfer_voucher_items', {
        'voucher_id': id,
        'product_id': product,
        'quantity': qty,
        'item_code': p['item_code'],
        'product_name': p['name'],
        'color': p['color'],
        'size': p['size'],
        'tracking': p['tracking'],
      });
      final lots = ProductTracking.decode(line['lots']);
      var total = 0;
      final seenLots = <int>{};
      if (!ProductTracking.tracked(p) && lots.isNotEmpty) {
        throw StateError('Unexpected lot selection');
      }
      for (final choice in lots) {
        final lotId = choice['lot_id'], n = choice['qty'];
        if (lotId is! int || n is! int || n < 1 || !seenLots.add(lotId)) {
          throw StateError('Invalid or duplicate serial/lot');
        }
        final found = await tx.query(
          'stock_lots',
          where: 'id=? AND product_id=? AND branch_id=? AND available>=?',
          whereArgs: [lotId, product, source, n],
        );
        if (found.isEmpty) {
          throw StateError(
            'Selected serial/IMEI is no longer available in the source branch.',
          );
        }
        final lot = found.single;
        if ((lot['serial'] != null || lot['imei'] != null) && n != 1) {
          throw StateError('Serial/IMEI quantity must be one');
        }
        if (await tx.rawUpdate(
              'UPDATE stock_lots SET available=available-? WHERE id=? AND available>=?',
              [n, lotId, n],
            ) !=
            1) {
          throw StateError('Lot stock changed');
        }
        await tx.insert('transfer_voucher_lots', {
          'item_id': item,
          'lot_id': lotId,
          'quantity': n,
          'serial': lot['serial'],
          'imei': lot['imei'],
          'expires_on': lot['expires_on'],
        });
        total += n;
      }
      if (ProductTracking.tracked(p) && total != qty) {
        throw StateError(
          'Select serial/IMEI or batch quantities matching the transfer quantity.',
        );
      }
      await stock(
        tx,
        source,
        product,
        -qty,
        'Transfer voucher #$id dispatch',
        now,
      );
    }
    return id;
  });
  static Future<void> receive(Database db, int id, int branch) =>
      db.transaction((tx) async {
        final found = await tx.query(
          'transfer_vouchers',
          where: "id=? AND destination_branch_id=? AND status='posted' AND received_at IS NULL",
          whereArgs: [id, branch],
        );
        if (found.isEmpty) {
          throw StateError('Transfer already received, void or wrong branch.');
        }
        final v = found.single;
        final now = DateTime.now().toUtc().toIso8601String();
        for (final i in await items(tx, id)) {
          for (final a in (i['lots'] as List).cast<Map<String, Object?>>()) {
            final lot = (await tx.query(
              'stock_lots',
              where: 'id=?',
              whereArgs: [a['lot_id']],
            )).single;
            int target;
            if (a['serial'] != null || a['imei'] != null) {
              if (lot['branch_id'] != v['branch_id'] || lot['available'] != 0) {
                throw StateError('Serial location changed');
              }
              target = lot['id'] as int;
              await tx.update(
                'stock_lots',
                {'branch_id': branch, 'available': 1},
                where: 'id=?',
                whereArgs: [target],
              );
            } else {
              target = await tx.insert('stock_lots', {
                'product_id': i['product_id'],
                'branch_id': branch,
                'purchase_id': lot['purchase_id'],
                'expires_on': lot['expires_on'],
                'received_qty': a['quantity'],
                'available': a['quantity'],
                'warranty_days': lot['warranty_days'],
              });
            }
            await tx.update(
              'transfer_voucher_lots',
              {'destination_lot_id': target},
              where: 'item_id=? AND lot_id=?',
              whereArgs: [i['id'], a['lot_id']],
            );
          }
          await stock(
            tx,
            branch,
            i['product_id'] as int,
            i['quantity'] as int,
            'Transfer voucher #$id received',
            now,
          );
        }
        await tx.update(
          'transfer_vouchers',
          {'received_at': now},
          where: 'id=?',
          whereArgs: [id],
        );
      });
  static Future<void> voidVoucher(Database db, int id, String reason) =>
      db.transaction((tx) async {
        if (reason.trim().isEmpty || reason.length > 300) {
          throw ArgumentError('Enter a reason');
        }
        final found = await tx.query(
          'transfer_vouchers',
          where: "id=? AND status='posted'",
          whereArgs: [id],
        );
        if (found.isEmpty) throw StateError('Transfer already void or missing');
        final v = found.single;
        final source = v['branch_id'] as int,
            dest = v['destination_branch_id'] as int;
        final now = DateTime.now().toUtc().toIso8601String();
        for (final i in await items(tx, id)) {
          for (final a in (i['lots'] as List).cast<Map<String, Object?>>()) {
            if (v['received_at'] != null) {
              final target = a['destination_lot_id'];
              final lot = (await tx.query(
                'stock_lots',
                where: 'id=?',
                whereArgs: [target],
              )).single;
              final used = await tx.rawQuery(
                "SELECT 1 FROM sale_lot_allocations WHERE lot_id=? UNION ALL SELECT 1 FROM transfer_voucher_lots a JOIN transfer_voucher_items i ON i.id=a.item_id JOIN transfer_vouchers v ON v.id=i.voucher_id WHERE a.lot_id=? AND v.id<>? LIMIT 1",
                [target, target, id],
              );
              if (lot['branch_id'] != dest ||
                  lot['available'] != a['quantity'] ||
                  used.isNotEmpty) {
                throw StateError(
                  'Cannot void: tracked stock was sold or transferred. Reverse later transactions first.',
                );
              }
              await tx.update(
                'transfer_voucher_lots',
                {'destination_lot_id': null},
                where: 'item_id=? AND lot_id=?',
                whereArgs: [i['id'], a['lot_id']],
              );
              if (a['serial'] != null || a['imei'] != null) {
                await tx.update(
                  'stock_lots',
                  {'branch_id': source, 'available': 0},
                  where: 'id=?',
                  whereArgs: [target],
                );
              } else {
                await tx.delete(
                  'stock_lots',
                  where: 'id=?',
                  whereArgs: [target],
                );
              }
            }
            if (await tx.rawUpdate(
                  'UPDATE stock_lots SET available=available+? WHERE id=? AND branch_id=? AND available+?<=received_qty',
                  [a['quantity'], a['lot_id'], source, a['quantity']],
                ) !=
                1) {
              throw StateError('Source lot stock changed');
            }
          }
          if (v['received_at'] != null) {
            await stock(
              tx,
              dest,
              i['product_id'] as int,
              -(i['quantity'] as int),
              'Transfer voucher #$id void',
              now,
            );
          }
          await stock(
            tx,
            source,
            i['product_id'] as int,
            i['quantity'] as int,
            'Transfer voucher #$id void',
            now,
          );
        }
        await tx.update(
          'transfer_vouchers',
          {'status': 'void', 'void_reason': reason.trim()},
          where: 'id=?',
          whereArgs: [id],
        );
      });
}
