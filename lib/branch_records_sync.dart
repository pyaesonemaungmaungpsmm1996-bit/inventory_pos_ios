import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_database.dart';
import 'voucher_code.dart';

/// One Windows source per branch. Publishes a read-only copy of the normal
/// POS records from a single committed SQLite snapshot.
class BranchRecordsSync {
  BranchRecordsSync({
    required this.client,
    required this.shop,
    required this.branchCode,
    required this.device,
    required this.secret,
  });

  static BranchRecordsSync? publisher;
  final SupabaseClient client;
  final String shop, branchCode, device, secret;
  Timer? _timer;
  Future<void>? _upload;
  String? _lastDocument;
  Object? error;

  Map<String, dynamic> get _params => {
    'shop': shop,
    'device': device,
    'secret': secret,
  };

  Future<void> start() async {
    await publish();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        await publish();
        error = null;
      } catch (e) {
        error = e;
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    try {
      await _upload;
    } catch (_) {
      // Stopping must work even if the last upload failed.
    }
  }

  Future<void> publish() async {
    final previous = _upload;
    if (previous != null) return previous;
    final next = _publish();
    _upload = next;
    try {
      await next;
    } finally {
      _upload = null;
    }
  }

  Future<void> _publish() async {
    final db = await AppDatabase.instance.database;
    final document = await db.transaction((txn) async {
      final branches = await txn.query(
        'branches',
        columns: ['id'],
        where: 'code = ?',
        whereArgs: [branchCode],
      );
      if (branches.length != 1) {
        throw StateError(
          'The Windows POS branch code must match the sync branch.',
        );
      }
      final id = branches.single['id'];
      Future<List<Map<String, Object?>>> vouchers(
        String table,
        String prefix,
      ) async {
        final rows = await txn.query(
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
            'currency_digits',
            if (prefix == 'INV') 'branch_code_snapshot',
          ],
          where: 'branch_id = ?',
          whereArgs: [id],
          orderBy: 'id DESC',
        );
        return [
          for (final row in rows)
            {
              ...row,
              'number': VoucherCode.displayNumber({
                ...row,
                'document_prefix': prefix,
              }),
            },
        ];
      }

      return <String, Object?>{
        'branch_code': branchCode,
        'stock': await txn.rawQuery(
          '''
          SELECT p.item_code, p.name, p.price, s.stock
          FROM branch_stocks s JOIN products p ON p.id = s.product_id
          WHERE s.branch_id = ? ORDER BY p.id
        ''',
          [id],
        ),
        'sales': await vouchers('sale_invoices', 'INV'),
        'purchases': await vouchers('purchase_invoices', 'PUR'),
      };
    });
    final encoded = jsonEncode(document);
    if (_lastDocument == encoded) return;
    if (utf8.encode(encoded).length > 1900000) {
      throw StateError('Branch records exceed the current sync size limit.');
    }
    await client.rpc(
      'tp_stock_sync_publish_records',
      params: {..._params, 'document': document},
    );
    _lastDocument = encoded;
  }

  Future<Map<String, dynamic>?> read() async {
    final result = await client.rpc(
      'tp_stock_sync_read_records',
      params: _params,
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }
}
