import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'live_sale_sync.dart';
import 'online_account_service.dart';

class LivePurchaseSync {
  static const table = 'tp_live_purchases';
  static const requestPrefix = 'tp-live-purchase:';
  static final applied = ValueNotifier<int>(0);

  static bool isAppliedRequest(Object? key) =>
      key is String && key.startsWith(requestPrefix);

  static Future<void> markApplied(
    Transaction txn,
    int localId,
    ({String account, String installation, String voucher, int revision})
    remote,
  ) async {
    await txn.insert('app_settings', {
      'key': '$_identity${remote.installation}:$localId',
      'value': jsonEncode({
        'account': remote.account,
        'voucher': remote.voucher,
        'revision': remote.revision,
        'received': true,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static const _identity = 'live_purchase_identity:';
  static const _pending = 'live_purchase_pending:';
  static final rows = ValueNotifier<List<Map<String, dynamic>>>([]);
  static Future<Database> Function()? _database;
  static bool _busy = false;
  static String? _watchedAccount;
  static int _feedRevision = 0;
  static StreamSubscription<List<Map<String, dynamic>>>? _updates;

  static void _watchAccount() {
    final account = LiveSaleSync.accountId;
    if (account == _watchedAccount) return;
    _watchedAccount = account;
    _feedRevision++;
    unawaited(_updates?.cancel());
    rows.value = [];
    if (account == null) return;
    _updates = OnlineAccounts.client
        .from(table)
        .stream(primaryKey: ['account_id', 'voucher_id'])
        .eq('account_id', account)
        .order('updated_at', ascending: false)
        .limit(100)
        .listen((remote) {
          if (_watchedAccount != account || LiveSaleSync.accountId != account) {
            return;
          }
          _feedRevision++;
          rows.value = remote;
        }, onError: (Object _) => wake());
  }

  static String? get identityPrefix {
    final installation = LiveSaleSync.origin?.installation;
    return installation == null ? null : '$_identity$installation:';
  }

  static void start(Future<Database> Function() database) {
    if (_database != null) return;
    _database = database;
    unawaited(_listen());
    Timer.periodic(const Duration(seconds: 15), (_) => wake());
  }

  static Future<void> _listen() async {
    try {
      await OnlineAccounts.initialize();
      OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        _watchAccount();
        wake();
      });
      _watchAccount();
      wake();
    } catch (_) {
      // The periodic refresh retries after sign-in becomes available.
    }
  }

  static Future<bool> record(
    Transaction txn,
    int id, {
    required ({String account, String installation})? origin,
    bool removed = false,
  }) async {
    if (origin == null || _database == null) return false;
    final key = '$_identity${origin.installation}:$id';
    final identities = await txn.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    final previous = identities.isEmpty
        ? null
        : jsonDecode(identities.single['value'] as String) as Map;
    if (previous != null && previous['account'] != origin.account) return false;
    if (removed && previous == null) return false;

    final row = (await txn.query(
      'purchase_invoices',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    final branch = (await txn.query(
      'branches',
      columns: ['name', 'code'],
      where: 'id = ?',
      whereArgs: [row['branch_id']],
    )).single;
    final items = <Map<String, Object?>>[];
    if (!removed) {
      final lines = await txn.rawQuery(
        '''SELECT i.product_id,i.item_code,i.item_name,i.qty,i.amount,
          i.purchase_price,p.tracking
          FROM purchase_items i JOIN products p ON p.id=i.product_id
          WHERE i.purchase_id = ? ORDER BY i.id''',
        [id],
      );
      for (final item in lines) {
        final lots = await txn.rawQuery(
          '''SELECT serial,imei,expires_on,received_qty qty FROM stock_lots
             WHERE purchase_id=? AND product_id=? ORDER BY id''',
          [id, item['product_id']],
        );
        items.add({
          for (final field in [
            'item_code',
            'item_name',
            'qty',
            'amount',
            'purchase_price',
            'tracking',
          ])
            field: item[field],
          'lots': lots,
        });
      }
    }
    final payments = removed
        ? const []
        : await txn.rawQuery(
            '''SELECT p.account_name,a.type,p.amount
         FROM purchase_payments p JOIN money_accounts a ON a.id = p.account_id
         WHERE p.purchase_id = ? ORDER BY p.account_id''',
            [id],
          );
    final voucher =
        previous?['voucher'] as String? ??
        (await txn.rawQuery('SELECT lower(hex(randomblob(16))) AS id'))
                .single['id']
            as String;
    final next = (previous?['revision'] as int? ?? 0) + 1;
    final now = DateTime.now().microsecondsSinceEpoch;
    final revision = now > next ? now : next;
    await txn.insert('app_settings', {
      'key': key,
      'value': jsonEncode({
        'account': origin.account,
        'voucher': voucher,
        'revision': revision,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('app_settings', {
      'key': '$_pending${origin.installation}:${origin.account}:$voucher',
      'value': jsonEncode({
        'revision': revision,
        'payload': {
          'number': 'PUR-${id.toString().padLeft(6, '0')}',
          'status': removed ? 'removed' : row['status'],
          'branch': branch['name'],
          'branch_code': branch['code'],
          'date': row['invoice_date'],
          'recorded_at': row['confirmed_at'],
          'supplier_name': row['supplier_name'],
          'currency_code': row['currency_code'],
          'currency_digits': row['currency_digits'],
          'total': row['total'],
          'paid': row['paid'],
          'balance_due': row['balance_due'],
          'items': items,
          'posting_payload_version': 1,
          'payments': payments,
        },
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  static void wake() => unawaited(_sync());

  static Future<void> _sync() async {
    final account = LiveSaleSync.accountId;
    final database = _database;
    if (account == null || database == null || _busy) return;
    _busy = true;
    try {
      final installation = await OnlineAccounts.installation();
      final db = await database();
      final prefix = '$_pending$installation:$account:';
      final pending = await db.query(
        'app_settings',
        where: 'key GLOB ?',
        whereArgs: ['$prefix*'],
        limit: 50,
      );
      for (final row in pending) {
        if (LiveSaleSync.accountId != account) return;
        final key = row['key'] as String;
        final original = row['value'] as String;
        final data = jsonDecode(original) as Map;
        await OnlineAccounts.client
            .rpc(
              'tp_publish_live_purchase',
              params: {
                'p_account': account,
                'p_voucher': key.substring(prefix.length),
                'p_revision': data['revision'],
                'p_payload': data['payload'],
              },
            )
            .timeout(const Duration(seconds: 10));
        await db.delete(
          'app_settings',
          where: 'key = ? AND value = ?',
          whereArgs: [key, original],
        );
      }
      if (LiveSaleSync.accountId != account) return;
      final revision = _feedRevision;
      final remote = await OnlineAccounts.client
          .from(table)
          .select()
          .eq('account_id', account)
          .order('updated_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 10));
      if (LiveSaleSync.accountId == account && revision == _feedRevision) {
        rows.value = remote;
      }
    } catch (_) {
      // Retry without posting again or changing local stock.
    } finally {
      _busy = false;
    }
  }

  static List<Map<String, Object?>> forBranch(
    Iterable<Map<String, Object?>> localIdentities,
    Map<String, Object?> branch,
  ) {
    final account = LiveSaleSync.accountId;
    if (account == null) return [];
    final local = <String>{};
    for (final row in localIdentities) {
      try {
        final value = jsonDecode(row['live_identity'].toString());
        if (value is Map &&
            value['account'] == account &&
            value['voucher'] is String) {
          local.add(value['voucher'] as String);
        }
      } on FormatException {
        /* Old rows can have no sync identity. */
      }
    }
    String normalize(Object? value) =>
        value?.toString().trim().toLowerCase() ?? '';
    return [
      for (final row in rows.value)
        if (row['account_id'] == account && !local.contains(row['voucher_id']))
          if (row['payload'] case final Map payload)
            if (payload['status'] != 'removed' &&
                normalize(payload['branch_code']).isNotEmpty &&
                normalize(payload['branch_code']) ==
                    normalize(branch['code']) &&
                payload['total'] is int &&
                payload['balance_due'] is int &&
                payload['number'] is String &&
                payload['recorded_at'] is String)
              {
                ...Map<String, Object?>.from(payload),
                'live_voucher': row['voucher_id'],
                'live_number': payload['number'],
                'live_account': account,
                'kind': 'purchase',
                'branch_id': branch['id'],
                'invoice_date': payload['date'],
                'confirmed_at': payload['recorded_at'],
                'amount': payload['total'],
              },
    ];
  }

  static Future<List<Map<String, Object?>>> localIdentities(
    DatabaseExecutor db,
    int branch,
  ) async {
    final prefix = identityPrefix;
    if (prefix == null) return [];
    return db.rawQuery(
      'SELECT v.value live_identity FROM purchase_invoices p '
      'JOIN app_settings v ON v.key = ? || p.id WHERE p.branch_id = ?',
      [prefix, branch],
    );
  }
}
