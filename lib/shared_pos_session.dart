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

  Map<String, String> get _identity => {
    'shop': connection.shop,
    'device': connection.device,
    'secret': connection.secret,
  };

  Future<Map<String, dynamic>> dashboard() async {
    final yangon = DateTime.now().toUtc().add(
      const Duration(hours: 6, minutes: 30),
    );
    final result = await connection.client.rpc(
      'tp_stock_sync_dashboard',
      params: {..._identity, 'day': yangon.toIso8601String().substring(0, 10)},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map>> openBalances(String kind) async {
    final result = await connection.client.rpc(
      'tp_stock_sync_open_balances',
      params: {..._identity, 'voucher_kind': kind},
    );
    return (result as List).cast<Map>();
  }

  Future<Map<String, dynamic>> load() async {
    final now = DateTime.now().toUtc();
    final results = await Future.wait([
      connection.client.rpc(
        'tp_stock_sync_branch_view',
        params: {
          ..._identity,
          'from_time': now.subtract(const Duration(days: 31)).toIso8601String(),
          'until_time': now.add(const Duration(minutes: 5)).toIso8601String(),
        },
      ),
      connection.client.rpc('tp_stock_sync_branch_serials', params: _identity),
    ]);
    return {
      ...Map<String, dynamic>.from(results[0] as Map),
      'serials': Map<String, dynamic>.from(results[1] as Map),
    };
  }

  Future<bool> hasPending() async =>
      await _storage.containsKey(key: _pendingKey);

  Future<String> post({
    required String kind,
    required List<SharedPosLine> lines,
    required Map<String, int> payments,
    int discount = 0,
    String? counterparty,
    String? salesperson,
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
    final total = subtotal - discount;
    final paid = payments.values.fold<int>(
      0,
      (total, amount) => total + amount,
    );
    final name = counterparty?.trim() ?? '';
    if (subtotal > 9999999999999 ||
        discount < 0 ||
        discount >= subtotal ||
        (kind == 'purchase' && discount != 0) ||
        paid > total ||
        (paid < total && name.isEmpty) || name.length > 150) {
      throw ArgumentError(
        'Check payment total and the name on the balance due.',
      );
    }
    final command = {
      'kind': kind,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'discount_minor': discount,
      if (name.isNotEmpty) 'counterparty': name,
      if (salesperson != null) 'salesperson': salesperson.trim(),
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
    return _stage(command);
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

  Future<void> transfer(String source, String destination, int amount) =>
      _exclusive(() async {
        if (await hasPending()) {
          throw StateError('Retry the pending transaction first.');
        }
        if (source == destination || amount <= 0 || amount > 9999999999999) {
          throw ArgumentError(
            'Choose two different accounts and enter a valid amount.',
          );
        }
        await _stage({
          'kind': 'transfer',
          'amount_minor': amount,
          'source_account': source,
          'target_account': destination,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
        });
      });

  Future<void> expense(String account, int amount, String note) =>
      postExpense({account: amount}, note);

  Future<void> postExpense(Map<String, int> payments, String note) =>
      _exclusive(() async {
        if (await hasPending()) {
          throw StateError('Retry the pending transaction first.');
        }
        final description = note.trim();
        final amount = payments.values.fold<int>(0, (sum, value) => sum + value);
        if (payments.length > 20 || payments.values.any((value) => value <= 0) ||
            amount <= 0 ||
            amount > 9999999999999 ||
            description.isEmpty ||
            description.length > 300) {
          throw ArgumentError('Enter an expense amount and description.');
        }
        await _stage({
          'kind': 'expense',
          'amount_minor': amount,
          'note': description,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'payments': [
                        for (final payment in payments.entries)
              {'account_id': payment.key, 'amount_minor': payment.value},
          ],
        });
      });

  Future<String> _stage(Map<String, Object?> command) async {
    final operation = newStockSyncId();
    await _storage.write(
      key: _pendingKey,
      value: jsonEncode({'operation': operation, 'command': command}),
    );
    await _sendPending();
    return operation;
  }

  Future<void> retry() => _exclusive(_sendPending);

  Future<void> returnSale({
    required String sale,
    required String product,
    required String account,
    required int units,
    required int refund,
    required List<String> serials,
  }) => _exclusive(() async {
    if (await hasPending()) {
      throw StateError('Retry the pending voucher first.');
    }
    await _stage({
      'kind': 'return',
      'sale': sale,
      'product': product,
      'account': account,
      'units': units,
      'refund': refund,
      'serial_numbers': serials,
    });
  });

  Future<void> correctVoucher(
    String voucher,
    Map<String, Object?> replacement,
    String reason,
  ) => _exclusive(() async {
    if (await hasPending()) {
      throw StateError('Retry the pending voucher first.');
    }
    await _stage({
      'kind': 'correction',
      'voucher': voucher,
      'replacement': replacement,
      'reason': reason.trim(),
    });
  });
  Future<void> voidVoucher(String voucher, String reason) =>
      _exclusive(() async {
        if (await hasPending()) {
          throw StateError('Retry the pending voucher first.');
        }
        final clean = reason.trim();
        if (clean.isEmpty || clean.length > 300) {
          throw ArgumentError('Enter a void reason.');
        }
        await _stage({'kind': 'void', 'voucher': voucher, 'reason': clean});
      });

  Future<void> settle(
    String voucher,
    String account,
    int amount, {
    bool archived = false,
  }) => _exclusive(() async {
    if (await hasPending()) {
      throw StateError('Retry the pending voucher first.');
    }
    if (amount <= 0 || amount > 9999999999999) {
      throw ArgumentError('Enter a valid payment amount.');
    }
    await _stage({
      'kind': archived ? 'archived_settlement' : 'settlement',
      'voucher': voucher,
      'account': account,
      'amount_minor': amount,
    });
  });

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_posting) throw StateError('A voucher is already being posted.');
    _posting = true;
    try {
      return await action();
    } finally {
      _posting = false;
    }
  }

  Future<void> _sendPending() async {
    final saved = await _storage.read(key: _pendingKey);
    if (saved == null) return;
    final pending = jsonDecode(saved) as Map;
    final command = Map<String, Object?>.from(pending['command'] as Map);
    try {
      if (command['kind'] == 'return') {
        await connection.client.rpc(
          'tp_stock_sync_return_sale',
          params: {
            'shop': connection.shop,
            'device': connection.device,
            'secret': connection.secret,
            'operation': pending['operation'],
            for (final key in [
              'sale',
              'product',
              'account',
              'units',
              'refund',
              'serial_numbers',
            ])
              key: command[key],
          },
        );
      } else if (command['kind'] == 'correction') {
        await connection.client.rpc(
          'tp_stock_sync_correct_voucher',
          params: {
            ..._identity,
            'operation': pending['operation'],
            'voucher': command['voucher'],
            'replacement': command['replacement'],
            'reason': command['reason'],
          },
        );
      } else if (command['kind'] == 'void') {
        await connection.client.rpc(
          'tp_stock_sync_void_voucher',
          params: {
            'shop': connection.shop,
            'device': connection.device,
            'secret': connection.secret,
            'operation': pending['operation'],
            'voucher': command['voucher'],
            'reason': command['reason'],
          },
        );
      } else if (command['kind'] == 'settlement' ||
          command['kind'] == 'archived_settlement') {
        final archived = command['kind'] == 'archived_settlement';
        await connection.client.rpc(
          archived
              ? 'tp_stock_sync_settle_archived'
              : 'tp_stock_sync_settle_voucher',
          params: {
            'shop': connection.shop,
            'device': connection.device,
            'secret': connection.secret,
            'operation': pending['operation'],
            (archived ? 'archive_key' : 'voucher'): command['voucher'],
            'account': command['account'],
            'amount_minor': command['amount_minor'],
          },
        );
      } else {
        await StockSyncApi(connection.client).post(
          shop: connection.shop,
          device: connection.device,
          secret: connection.secret,
          operation: pending['operation'] as String,
          command: command,
        );
      }
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
