import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'branch_records_sync.dart';
import 'stock_sync.dart';

typedef SharedPosLine = ({
  String product,
  String label,
  int quantity,
  int unitPrice,
  List<String>? serials,
});

class SharedPosSession {
  SharedPosSession(this.connection);
  static SharedPosSession? current;
  final BranchRecordsSync connection;
  static const _storage = FlutterSecureStorage();
  bool _posting = false;

  String get _pendingKey =>
      'shared-pos:${connection.shop}:${connection.device}:pending';

  Future<Map<String, dynamic>> load() async {
    final now = DateTime.now().toUtc();
    final identity = {
      'shop': connection.shop,
      'device': connection.device,
      'secret': connection.secret,
    };
    final results = await Future.wait([
      connection.client.rpc(
        'tp_stock_sync_branch_view',
        params: {
          ...identity,
          'from_time': now.subtract(const Duration(days: 31)).toIso8601String(),
          'until_time': now.add(const Duration(minutes: 5)).toIso8601String(),
        },
      ),
      connection.client.rpc('tp_stock_sync_branch_serials', params: identity),
    ]);
    return {
      ...Map<String, dynamic>.from(results[0] as Map),
      'serials': Map<String, dynamic>.from(results[1] as Map),
    };
  }

  Future<bool> hasPending() async =>
      await _storage.containsKey(key: _pendingKey);

  Future<void> post({
    required String kind,
    required List<SharedPosLine> lines,
    required Map<String, int> payments,
    int discount = 0,
  }) => _exclusive(() async {
    if (await hasPending()) {
      throw StateError('Retry the pending voucher first.');
    }
    if (!const ['sale', 'purchase'].contains(kind) ||
        lines.isEmpty ||
        lines.length > 100 ||
        lines.map((line) => line.product).toSet().length != lines.length ||
        lines.any(
          (line) =>
              line.quantity <= 0 ||
              line.quantity > 999999999 ||
              line.unitPrice <= 0 ||
              line.unitPrice > 9999999999999 ~/ line.quantity,
        ) ||
        payments.length > 20 ||
        payments.values.any((amount) => amount <= 0)) {
      throw ArgumentError('Check voucher items and payment amounts.');
    }
    final subtotal = lines.fold<int>(
      0,
      (total, line) => total + line.quantity * line.unitPrice,
    );
    if (subtotal > 9999999999999 ||
        discount < 0 ||
        discount >= subtotal ||
        (kind == 'purchase' && discount != 0) ||
        payments.values.fold<int>(0, (total, amount) => total + amount) !=
            subtotal - discount) {
      throw ArgumentError('Payment total must match the voucher total.');
    }
    final command = {
      'kind': kind,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'discount_minor': discount,
      'lines': [
        for (final line in lines)
          {
            'product_id': line.product,
            'quantity': line.quantity,
            'unit_minor': line.unitPrice,
            'serials': ?line.serials,
          },
      ],
      'payments': [
        for (final payment in payments.entries)
          {'account_id': payment.key, 'amount_minor': payment.value},
      ],
    };
    await _stage(command);
  });

  Future<void> deposit(String account, int amount) => _exclusive(() async {
    if (await hasPending()) {
      throw StateError('Retry the pending voucher first.');
    }
    if (amount <= 0 || amount > 9999999999999) {
      throw ArgumentError('Enter a valid cash amount.');
    }
    await _stage({
      'kind': 'deposit',
      'amount_minor': amount,
      'target_account': account,
    });
  });

  Future<void> _stage(Map<String, Object?> command) async {
    await _storage.write(
      key: _pendingKey,
      value: jsonEncode({'operation': newStockSyncId(), 'command': command}),
    );
    await _sendPending();
  }

  Future<void> retry() => _exclusive(_sendPending);

  Future<void> _exclusive(Future<void> Function() action) async {
    if (_posting) throw StateError('A voucher is already being posted.');
    _posting = true;
    try {
      await action();
    } finally {
      _posting = false;
    }
  }

  Future<void> _sendPending() async {
    final saved = await _storage.read(key: _pendingKey);
    if (saved == null) return;
    final pending = jsonDecode(saved) as Map;
    try {
      await StockSyncApi(connection.client).post(
        shop: connection.shop,
        device: connection.device,
        secret: connection.secret,
        operation: pending['operation'] as String,
        command: Map<String, Object?>.from(pending['command'] as Map),
      );
    } on PostgrestException catch (error) {
      if (const ['P0001', '23514', '22003'].contains(error.code)) {
        // PostgreSQL rolled this request back. Timeouts retain the original ID.
        await _storage.delete(key: _pendingKey);
      }
      rethrow;
    }
    await _storage.delete(key: _pendingKey);
  }
}
