import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'online_account_service.dart';
import 'voucher_code.dart';

class LiveSaleSync {
  static const table = 'tp_live_sales';
  static Future<Database> Function()? _database;
  static bool _uploading = false;
  static StreamSubscription<List<Map<String, dynamic>>>? _updates;
  static final feed =
      ValueNotifier<
        ({String? account, List<Map<String, dynamic>> rows, bool unavailable})
      >((account: null, rows: const [], unavailable: false));
  static int _feedGeneration = 0;
  static bool _refreshing = false;
  static int _feedRevision = 0;
  static String? _installation;

  static String? get accountId {
    try {
      return OnlineAccounts.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static ({String account, String installation})? get origin {
    final account = accountId;
    final installation = _installation;
    if (account == null || installation == null) return null;
    return (account: account, installation: installation);
  }

  static const _identityPrefix = 'live_sale_identity:';
  static const _pendingPrefix = 'live_sale_pending:';

  static String? get localIdentityPrefix =>
      _installation == null ? null : '$_identityPrefix$_installation:';

  static Stream<List<Map<String, dynamic>>> watch(
    String account, {
    String? voucher,
    bool purchase = false,
  }) {
    final query = OnlineAccounts.client
        .from(purchase ? 'tp_live_purchases' : table)
        .stream(primaryKey: ['account_id', 'voucher_id'])
        .eq('account_id', account);
    return voucher == null
        ? query.order('updated_at', ascending: false).limit(100)
        : query.eq('voucher_id', voucher);
  }

  static Future<void> record(
    Transaction txn, {
    required ({String account, String installation})? origin,
    required int draftId,
    int? saleId,
    bool removed = false,
  }) async {
    if (origin == null) return;
    final (:account, :installation) = origin;
    final identityKey = '$_identityPrefix$installation:$draftId';
    final identities = await txn.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [identityKey],
    );
    final previous = identities.isEmpty
        ? null
        : jsonDecode(identities.single['value'] as String) as Map;
    if (previous != null && previous['account'] != account) return;
    if (removed && previous == null) return;
    final bool posted = saleId != null;
    final id = saleId ?? draftId;
    final row = (await txn.query(
      posted ? 'sale_invoices' : 'sale_drafts',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    if (!posted && row['correction_source_sale_id'] != null) return;
    final branch = (await txn.query(
      'branches',
      columns: ['name', 'code'],
      where: 'id = ?',
      whereArgs: [row['branch_id']],
    )).single;
    final items = await txn.query(
      posted ? 'sale_items' : 'sale_draft_items',
      columns: ['item_code', 'item_name', 'qty', 'price', 'amount'],
      where: posted ? 'sale_id = ?' : 'draft_id = ?',
      whereArgs: [id],
      orderBy: 'id',
    );
    final payload = jsonEncode({
      'number': posted
          ? VoucherCode.displayNumber(row)
          : 'DRAFT-${draftId.toString().padLeft(6, '0')}',
      'status': removed ? 'removed' : (posted ? row['status'] : 'draft'),
      'branch': posted ? row['branch_name_snapshot'] : branch['name'],
      'branch_code': posted ? row['branch_code_snapshot'] : branch['code'],
      'date': row['invoice_date'],
      'currency_code': row['currency_code'],
      'currency_digits': row['currency_digits'],
      'total': row['total'],
      'paid': row['paid'],
      'balance_due': row['balance_due'],
      'items': removed ? [] : items,
    });
    final voucher =
        previous?['voucher'] as String? ??
        (await txn.rawQuery('SELECT lower(hex(randomblob(16))) AS id'))
                .single['id']
            as String;
    final next = (previous?['revision'] as int? ?? 0) + 1;
    final now = DateTime.now().microsecondsSinceEpoch;
    final revision = now > next ? now : next;
    await txn.insert('app_settings', {
      'key': identityKey,
      'value': jsonEncode({
        'account': account,
        'voucher': voucher,
        'revision': revision,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert('app_settings', {
      'key': '$_pendingPrefix$installation:$account:$voucher',
      'value': jsonEncode({
        'revision': revision,
        'payload': jsonDecode(payload),
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static void start(Future<Database> Function() database) {
    if (_database != null) return;
    _database = database;
    unawaited(_initialize());
    Timer.periodic(const Duration(seconds: 15), (_) {
      wake();
      unawaited(refreshFeed());
    });
  }

  static Future<void> _initialize() async {
    try {
      _installation = await OnlineAccounts.installation();
      await OnlineAccounts.initialize();
      OnlineAccounts.client.auth.onAuthStateChange.listen(
        (_) => _connectFeed(),
      );
      _connectFeed();
      wake();
    } catch (_) {
      // Account settings can retry initialization independently.
    }
  }

  static void _connectFeed() {
    final account = accountId;
    if (account == feed.value.account) return;
    final generation = ++_feedGeneration;
    unawaited(_updates?.cancel());
    feed.value = (account: account, rows: const [], unavailable: false);
    if (account == null) return;
    _updates = watch(account).listen((rows) {
      if (generation != _feedGeneration) return;
      _feedRevision++;
      feed.value = (account: account, rows: rows, unavailable: false);
    }, onError: (Object _) => unawaited(refreshFeed()));
  }

  static Future<void> refreshFeed() async {
    _connectFeed();
    final account = feed.value.account;
    if (account == null || _refreshing) return;
    final generation = _feedGeneration;
    final revision = _feedRevision;
    _refreshing = true;
    try {
      final rows = await OnlineAccounts.client
          .from(table)
          .select()
          .eq('account_id', account)
          .order('updated_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 10));
      if (generation == _feedGeneration && revision == _feedRevision) {
        feed.value = (account: account, rows: rows, unavailable: false);
      }
    } catch (_) {
      if (generation == _feedGeneration && revision == _feedRevision) {
        feed.value = (
          account: account,
          rows: feed.value.rows,
          unavailable: true,
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  static void wake() => unawaited(_flush());

  static Future<void> _flush() async {
    final account = accountId;
    final database = _database;
    final installation = _installation;
    if (account == null ||
        database == null ||
        installation == null ||
        _uploading) {
      return;
    }
    final prefix = '$_pendingPrefix$installation:$account:';
    _uploading = true;
    try {
      final db = await database();
      while (accountId == account) {
        final rows = await db.query(
          'app_settings',
          where: 'key GLOB ?',
          whereArgs: ['$prefix*'],
          orderBy: 'key',
          limit: 50,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          if (accountId != account) return;
          final key = row['key'] as String;
          final value = row['value'] as String;
          final update = jsonDecode(value) as Map;
          await OnlineAccounts.client
              .rpc(
                'tp_publish_live_sale',
                params: {
                  'p_account': account,
                  'p_voucher': key.substring(prefix.length),
                  'p_revision': update['revision'],
                  'p_payload': update['payload'],
                },
              )
              .timeout(const Duration(seconds: 10));
          await db.delete(
            'app_settings',
            where: 'key = ? AND value = ?',
            whereArgs: [key, value],
          );
        }
      }
    } catch (_) {
      // A failed upload remains pending and is retried without reposting a sale.
    } finally {
      _uploading = false;
    }
  }
}
