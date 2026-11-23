import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String newStockSyncId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String newStockSyncSecret() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

class StockSyncApi {
  final SupabaseClient client;

  StockSyncApi(this.client);

  Future<List<Map<String, dynamic>>> catalog() async {
    final data = await client.rpc('tp_stock_sync_catalog') as List;
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Future<Map<String, dynamic>> createShop({
    required String name,
    required String currency,
    required String branchCode,
    required String branchName,
  }) async {
    final data = await client.rpc(
      'tp_stock_sync_create_shop',
      params: {
        'name': name,
        'currency': currency,
        'branch_code': branchCode,
        'branch_name': branchName,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<String> admin({
    required String shop,
    required String operation,
    required Map<String, Object?> command,
  }) async {
    final data = await client.rpc(
      'tp_stock_sync_admin',
      params: {'shop': shop, 'operation': operation, 'command': command},
    );
    return data as String;
  }

  Future<bool> enroll({
    required String shop,
    required String branch,
    required String device,
    required String label,
    required String secret,
  }) async {
    final data = await client.rpc(
      'tp_stock_sync_enroll',
      params: {
        'shop': shop,
        'branch': branch,
        'device': device,
        'label': label,
        'secret': secret,
      },
    );
    return data as bool;
  }

  Future<Map<String, dynamic>> snapshot({
    required String shop,
    required String device,
    required String secret,
  }) async {
    final data = await client.rpc(
      'tp_stock_sync_snapshot',
      params: {'shop': shop, 'device': device, 'secret': secret},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> post({
    required String shop,
    required String device,
    required String secret,
    required String operation,
    required Map<String, Object?> command,
  }) async {
    await client.rpc(
      'tp_stock_sync_post',
      params: {
        'shop': shop,
        'device': device,
        'secret': secret,
        'operation': operation,
        'command': command,
      },
    );
  }

  Future<void> cancelSale({
    required String shop,
    required String device,
    required String secret,
    required String operation,
  }) async {
    await client.rpc(
      'tp_stock_sync_cancel_sale',
      params: {
        'shop': shop,
        'device': device,
        'secret': secret,
        'operation': operation,
      },
    );
  }

  Future<Map<String, dynamic>> ownerReport({
    required String shop,
    required DateTime from,
    required DateTime until,
  }) async {
    final data = await client.rpc(
      'tp_stock_sync_owner_report',
      params: {
        'shop': shop,
        'from_time': from.toUtc().toIso8601String(),
        'until_time': until.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Stream<int> revisions(String shop) => client
      .from('tp_stock_sync_changes')
      .stream(primaryKey: ['shop_id'])
      .eq('shop_id', shop)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => rows.single['revision'] as int)
      .distinct();
}

class PendingStockSale {
  final String operation;
  final Map<String, Object?> command;

  const PendingStockSale({required this.operation, required this.command});
}

class OfflineStockStore {
  final String shop;
  final String device;

  const OfflineStockStore({required this.shop, required this.device});

  static Future<void> ensureTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tp_sync_offline_allowance (
        shop TEXT NOT NULL,
        device TEXT NOT NULL,
        product TEXT NOT NULL,
        granted INTEGER NOT NULL CHECK (granted >= 0),
        spent INTEGER NOT NULL CHECK (spent BETWEEN 0 AND granted),
        PRIMARY KEY (shop, device, product)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tp_sync_offline_snapshot (
        shop TEXT NOT NULL,
        device TEXT NOT NULL,
        payload TEXT NOT NULL,
        PRIMARY KEY (shop, device)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tp_sync_outbox (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        shop TEXT NOT NULL,
        device TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT,
        payload_hash TEXT NOT NULL,
        UNIQUE (shop, device, operation)
      )
    ''');
  }

  Future<void> applySnapshot(
    Database db,
    List<Map<String, dynamic>> products, {
    Map<String, dynamic>? snapshot,
  }) {
    return db.transaction((txn) async {
      if (snapshot != null) {
        await txn.insert('tp_sync_offline_snapshot', {
          'shop': shop,
          'device': device,
          'payload': jsonEncode(snapshot),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final row in products) {
        await txn.rawInsert(
          '''
          INSERT INTO tp_sync_offline_allowance(shop, device, product, granted, spent)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(shop, device, product) DO UPDATE SET
            granted = MAX(granted, excluded.granted),
            spent = MAX(spent, excluded.spent)
          ''',
          [
            shop,
            device,
            row['id'],
            row['device_granted'],
            row['device_consumed'],
          ],
        );
      }
    });
  }

  Future<Map<String, dynamic>?> cachedSnapshot(DatabaseExecutor db) async {
    final rows = await db.query(
      'tp_sync_offline_snapshot',
      columns: ['payload'],
      where: 'shop=? AND device=?',
      whereArgs: [shop, device],
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(
      jsonDecode(rows.single['payload'] as String) as Map,
    );
  }

  Future<int> remaining(DatabaseExecutor db, String product) async {
    final rows = await db.rawQuery(
      '''
      SELECT granted - spent AS remaining FROM tp_sync_offline_allowance
      WHERE shop=? AND device=? AND product=?
      ''',
      [shop, device, product],
    );
    return rows.isEmpty ? 0 : rows.single['remaining'] as int;
  }

  // The caller uses its voucher transaction so insufficient allowance rolls
  // back printing eligibility and all local accounting changes together.
  Future<void> stageSale(
    Transaction txn, {
    required String operation,
    required Map<String, Object?> command,
  }) async {
    if (command['kind'] != 'sale' || command['offline'] != true) {
      throw ArgumentError('An offline sale command is required.');
    }
    final lines = command['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 100) {
      throw ArgumentError('Offline sales require product lines.');
    }
    final payload = jsonEncode(command);
    final payloadHash = sha256.convert(utf8.encode(payload)).toString();
    final existing = await txn.query(
      'tp_sync_outbox',
      columns: ['payload_hash'],
      where: 'shop=? AND device=? AND operation=?',
      whereArgs: [shop, device, operation],
    );
    if (existing.isNotEmpty) {
      if (existing.single['payload_hash'] != payloadHash) {
        throw StateError('This offline sale ID was already used.');
      }
      return;
    }

    final checked = <String, int>{};
    var lineTotal = 0;
    for (final line in lines) {
      if (line is! Map ||
          line['product_id'] is! String ||
          line['quantity'] is! int) {
        throw ArgumentError('Invalid offline sale line.');
      }
      final product = line['product_id'] as String;
      final quantity = line['quantity'] as int;
      final unit = line['unit_minor'];
      if (quantity < 1 ||
          quantity > 999999999 ||
          checked.containsKey(product) ||
          unit is! int ||
          unit < 0 ||
          unit > 9999999999999) {
        throw ArgumentError('Invalid or repeated offline sale line.');
      }
      // Use BigInt for the intermediate product to avoid overflowing Dart int.
      final maximum = BigInt.from(quantity) * BigInt.from(unit);
      final amount =
          line['line_minor'] ??
          (maximum > BigInt.from(9999999999999) ? null : maximum.toInt());
      if (amount is! int ||
          amount < 0 ||
          BigInt.from(amount) > maximum ||
          amount > 9999999999999 ||
          lineTotal > 9999999999999 - amount) {
        throw ArgumentError('Invalid offline line amount.');
      }
      lineTotal += amount;
      checked[product] = quantity;
    }
    await _validatePayments(txn, command, lineTotal);
    for (final entry in checked.entries) {
      final count = await txn.rawUpdate(
        '''
        UPDATE tp_sync_offline_allowance
        SET spent=spent+?
        WHERE shop=? AND device=? AND product=? AND granted-spent>=?
        ''',
        [entry.value, shop, device, entry.key, entry.value],
      );
      if (count != 1) {
        throw StateError(
          'Offline allocation is insufficient for ${entry.key}.',
        );
      }
    }
    await txn.insert('tp_sync_outbox', {
      'shop': shop,
      'device': device,
      'operation': operation,
      'payload': payload,
      'payload_hash': payloadHash,
    });
  }

  Future<void> _validatePayments(
    Transaction txn,
    Map<String, Object?> command,
    int lineTotal,
  ) async {
    const maxMoney = 9999999999999;
    final discount = command['discount_minor'] ?? 0;
    if (discount is! int ||
        discount < 0 ||
        discount > lineTotal ||
        lineTotal - discount > maxMoney) {
      throw ArgumentError('Invalid offline sale discount or total.');
    }
    final date = command['occurred_at'];
    if (date is! String || DateTime.tryParse(date) == null) {
      throw ArgumentError(
        'An offline sale requires its original transaction time.',
      );
    }
    final total = lineTotal - discount;
    final payments = command['payments'] ?? const [];
    if (payments is! List || payments.length > 20) {
      throw ArgumentError('Invalid offline payments.');
    }
    final snapshot = await cachedSnapshot(txn);
    final cash = (snapshot?['accounts'] as List? ?? [])
        .whereType<Map>()
        .where((account) => account['kind'] == 'cash')
        .map((account) => account['id'])
        .toSet();
    var paid = 0;
    for (final payment in payments) {
      if (payment is! Map ||
          !cash.contains(payment['account_id']) ||
          payment['amount_minor'] is! int) {
        throw ArgumentError(
          'Only this branch’s cached cash accounts work offline.',
        );
      }
      final amount = payment['amount_minor'] as int;
      if (amount <= 0 || amount > total - paid) {
        throw ArgumentError('Invalid offline payment amount.');
      }
      paid += amount;
    }
    final party = command['counterparty'];
    if (paid < total && (party is! String || party.trim().isEmpty)) {
      throw ArgumentError('A customer is required for outstanding balances.');
    }
  }

  Future<int> pendingCount(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM tp_sync_outbox WHERE shop=? AND device=? AND payload IS NOT NULL',
      [shop, device],
    );
    return rows.single['total'] as int;
  }

  Future<List<PendingStockSale>> pending(Database db) async {
    final rows = await db.query(
      'tp_sync_outbox',
      columns: ['operation', 'payload'],
      where: 'shop=? AND device=? AND payload IS NOT NULL',
      whereArgs: [shop, device],
      orderBy: 'sequence',
      limit: 50,
    );
    return [
      for (final row in rows)
        PendingStockSale(
          operation: row['operation'] as String,
          command: Map<String, Object?>.from(
            jsonDecode(row['payload'] as String) as Map,
          ),
        ),
    ];
  }

  Future<void> acknowledge(Database db, String operation) async {
    await db.update(
      'tp_sync_outbox',
      {'payload': null},
      where: 'shop=? AND device=? AND operation=?',
      whereArgs: [shop, device, operation],
    );
  }
}

class OfflineStockUploader {
  final OfflineStockStore store;
  final StockSyncApi api;
  final String secret;
  Future<void>? _running;

  OfflineStockUploader({
    required this.store,
    required this.api,
    required this.secret,
  });

  Future<void> flush(Database db) async {
    final active = _running;
    if (active != null) return active;
    final request = _flush(db);
    _running = request;
    try {
      await request;
    } finally {
      _running = null;
    }
  }

  Future<void> _flush(Database db) async {
    while (true) {
      final rows = await store.pending(db);
      if (rows.isEmpty) return;
      for (final row in rows) {
        await api.post(
          shop: store.shop,
          device: store.device,
          secret: secret,
          operation: row.operation,
          command: row.command,
        );
        await store.acknowledge(db, row.operation);
      }
    }
  }
}
