import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'models.dart';

class SyncProofLocalStore {
  SyncProofLocalStore(this.db);

  final Database db;

  static Future<void> install(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_proof_products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        version INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_proof_outbox (
        operation_id TEXT PRIMARY KEY,
        business_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        expected_version INTEGER,
        status TEXT NOT NULL DEFAULT 'pending',
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_proof_state (
        business_id TEXT PRIMARY KEY,
        last_event_id INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> saveLocalProductAndQueue(
    SyncProofOperation operation,
  ) async {
    await db.transaction((txn) async {
      await txn.insert(
        'sync_proof_products',
        {
          'id': operation.productId,
          'name': operation.name,
          'price': operation.price,
          'version': operation.expectedVersion ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'sync_proof_outbox',
        {
          'operation_id': operation.operationId,
          'business_id': operation.businessId,
          'device_id': operation.deviceId,
          'product_id': operation.productId,
          'name': operation.name,
          'price': operation.price,
          'expected_version': operation.expectedVersion,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  Future<List<SyncProofOperation>> pendingOperations({int limit = 50}) async {
    final rows = await db.query(
      'sync_proof_outbox',
      where: "status IN ('pending', 'failed')",
      orderBy: 'created_at, operation_id',
      limit: limit,
    );
    return rows.map((row) {
      final status = switch (row['status']) {
        'conflict' => SyncOperationStatus.conflict,
        'failed' => SyncOperationStatus.failed,
        _ => SyncOperationStatus.pending,
      };
      return SyncProofOperation(
        operationId: row['operation_id'] as String,
        businessId: row['business_id'] as String,
        deviceId: row['device_id'] as String,
        productId: row['product_id'] as String,
        name: row['name'] as String,
        price: row['price'] as int,
        expectedVersion: row['expected_version'] as int?,
        status: status,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  Future<void> markApplied(String operationId, SyncProofProduct product) async {
    await db.transaction((txn) async {
      await txn.update(
        'sync_proof_products',
        product.toJson(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await txn.update(
        'sync_proof_outbox',
        {'status': 'applied', 'last_error': null},
        where: 'operation_id = ?',
        whereArgs: [operationId],
      );
    });
  }

  Future<void> markConflict(String operationId, String error) => db.update(
    'sync_proof_outbox',
    {'status': 'conflict', 'last_error': 'CONFLICT: $error'},
    where: 'operation_id = ?',
    whereArgs: [operationId],
  );

  Future<List<Map<String, Object?>>> outbox() => db.query(
        'sync_proof_outbox',
        orderBy: 'created_at DESC, operation_id DESC',
      );

  Future<int> cursor(String businessId) async {
    final rows = await db.query(
      'sync_proof_state',
      columns: ['last_event_id'],
      where: 'business_id = ?',
      whereArgs: [businessId],
    );
    return rows.isEmpty ? 0 : rows.single['last_event_id'] as int;
  }

  Future<void> applyEvents(
    String businessId,
    List<SyncProofEvent> events,
  ) async {
    if (events.isEmpty) return;
    await db.transaction((txn) async {
      for (final event in events) {
        await txn.insert(
          'sync_proof_products',
          event.payload,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'sync_proof_state',
          {'business_id': businessId, 'last_event_id': event.eventId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> products() => db.query(
        'sync_proof_products',
        orderBy: 'name, id',
      );

  static String encodePayload(Map<String, dynamic> value) => jsonEncode(value);
}
