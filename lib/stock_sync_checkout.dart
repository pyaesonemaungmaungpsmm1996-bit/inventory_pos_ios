import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product_tracking.dart';
import 'sale_invoice_details.dart';
import 'stock_sync.dart';
import 'voucher_code.dart';

/// Explicit binding for an approved device, its local branch and its catalog.
class StockSyncCheckout {
  final OfflineStockStore store;
  final int localBranchId;
  final Map<int, String> products;
  final Map<int, String> cashAccounts;
  final StockSyncApi? onlineApi;
  final String? onlineSecret;

  StockSyncCheckout({
    required this.store,
    required this.localBranchId,
    required Map<int, String> products,
    required Map<int, String> cashAccounts,
    this.onlineApi,
    this.onlineSecret,
  }) : products = Map.unmodifiable(products),
       cashAccounts = Map.unmodifiable(cashAccounts) {
    if ((onlineApi == null) != (onlineSecret == null)) {
      throw ArgumentError(
        'Online checkout requires an API and approved device credential.',
      );
    }
    if (products.values.toSet().length != products.length ||
        cashAccounts.values.toSet().length != cashAccounts.length) {
      throw ArgumentError('Stock sync mappings must be one-to-one.');
    }
  }

  bool get isOnline => onlineApi != null;

  static String _attemptKey(int draftId) => 'tp_sync_online_draft:$draftId';

  Future<void> prepareOnline(
    Database db, {
    required int draftId,
    required int revision,
    required List<Map<String, int>> payments,
  }) async {
    if (!isOnline) return;
    await db.transaction((txn) async {
      final posted = await txn.query(
        'sale_invoices',
        columns: ['id'],
        where: 'draft_id = ?',
        whereArgs: [draftId],
      );
      if (posted.isNotEmpty) return;
      final drafts = await txn.query(
        'sale_drafts',
        where: 'id = ? AND revision = ?',
        whereArgs: [draftId, revision],
      );
      if (drafts.isEmpty) {
        throw StateError('Draft changed. Reopen it before confirming.');
      }
      final draft = drafts.single;
      if (draft['correction_source_sale_id'] != null) {
        throw StateError('Online checkout requires a new voucher.');
      }
      final items = await txn.query(
        'sale_draft_items',
        where: 'draft_id = ?',
        whereArgs: [draftId],
        orderBy: 'id',
      );
      final previous = await _readAttempt(txn, draftId);
      final id = previous?['operation'] as String? ?? newStockSyncId();
      final time =
          previous?['time'] as String? ??
          DateTime.now().toUtc().toIso8601String();
      final command = await _saleCommand(
        txn,
        invoice: draft,
        items: items,
        payments: payments,
        offline: false,
        time: time,
        voucher: 'SYNC-$id',
      );
      final encoded = jsonEncode(command);
      if (previous != null) {
        _checkAttempt(previous, encoded);
        return;
      }
      await txn.insert('app_settings', {
        'key': _attemptKey(draftId),
        'value': jsonEncode({
          'shop': store.shop,
          'device': store.device,
          'operation': id,
          'time': time,
          'command': encoded,
        }),
      });
    });
  }

  static Future<Map<String, dynamic>?> _readAttempt(
    DatabaseExecutor db,
    int draftId,
  ) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_attemptKey(draftId)],
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(
      jsonDecode(rows.single['value'] as String) as Map,
    );
  }

  void _checkAttempt(Map<String, dynamic> attempt, String command) {
    if (attempt['shop'] != store.shop ||
        attempt['device'] != store.device ||
        attempt['command'] != command) {
      throw StateError(
        'Retry the original online checkout on its original device with the same items and payments.',
      );
    }
  }

  static Future<void> requireCheckoutMode(
    DatabaseExecutor db,
    int draft,
    StockSyncCheckout? checkout,
  ) async {
    if (checkout?.isOnline == true) return;
    if (await _readAttempt(db, draft) != null) {
      throw StateError(
        'This draft has an online checkout pending. Retry it from Online checkout.',
      );
    }
  }

  Future<bool> cancelOnline(Database db, int draftId) async {
    final attempt = await _readAttempt(db, draftId);
    if (attempt == null) return false;
    if (!isOnline ||
        attempt['shop'] != store.shop ||
        attempt['device'] != store.device) {
      throw StateError('Cancel this checkout from its original device.');
    }
    final key = attempt['operation'] as String;
    await onlineApi!
        .cancelSale(
          shop: store.shop,
          device: store.device,
          secret: onlineSecret!,
          operation: key,
        )
        .timeout(const Duration(seconds: 10));
    await db.transaction((txn) async {
      final current = await _readAttempt(txn, draftId);
      if (current?['operation'] == key) {
        await txn.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: [_attemptKey(draftId)],
        );
      }
    });
    return true;
  }

  Future<Map<String, Object?>> _saleCommand(
    Transaction txn, {
    required bool offline,
    required String time,
    required String voucher,
    required Map<String, Object?> invoice,
    required List<Map<String, Object?>> items,
    required List<Map<String, int>> payments,
  }) async {
    final snapshot = await store.cachedSnapshot(txn);
    if (invoice['branch_id'] != localBranchId ||
        snapshot == null ||
        invoice['currency_code'] != 'MMK' ||
        invoice['currency_digits'] != 0 ||
        snapshot['currency'] != 'MMK') {
      throw StateError(
        'The sale does not match the approved sync branch and currency.',
      );
    }

    final total = invoice['total'] as int;
    if (payments.fold<int>(0, (sum, payment) => sum + payment['amount']!) !=
        total) {
      throw StateError('The sync pilot requires full cash payment.');
    }
    final nets = SaleInvoiceDetails.lineNets(items, total);
    final lines = <String, Map<String, Object>>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (ProductTracking.decode(item['tracking_json']).isNotEmpty) {
        throw StateError(
          'Serial and lot items are outside the offline sync pilot.',
        );
      }
      final id = products[item['product_id']];
      if (id == null) {
        throw StateError('Sync mapping is missing for ${item['item_name']}.');
      }
      final quantity = item['qty'] as int;
      final price = item['price'] as int;
      final previous = lines[id];
      lines[id] = {
        'product_id': id,
        'quantity': quantity + (previous?['quantity'] as int? ?? 0),
        'unit_minor': max(price, previous?['unit_minor'] as int? ?? 0),
        'line_minor': nets[index] + (previous?['line_minor'] as int? ?? 0),
      };
    }
    if (lines.values.fold<int>(
          0,
          (sum, line) => sum + (line['line_minor'] as int),
        ) !=
        total) {
      throw StateError('Sync sale total does not match the printed voucher.');
    }

    final settlements = <Map<String, Object>>[];
    for (final payment in payments) {
      final account = cashAccounts[payment['account_id']];
      if (account == null) {
        throw StateError('Choose a mapped cash account for offline checkout.');
      }
      settlements.add({
        'account_id': account,
        'amount_minor': payment['amount']!,
      });
    }

    final sortedLines = lines.values.toList()
      ..sort(
        (a, b) =>
            (a['product_id'] as String).compareTo(b['product_id'] as String),
      );
    settlements.sort(
      (a, b) =>
          (a['account_id'] as String).compareTo(b['account_id'] as String),
    );
    return {
      'kind': 'sale',
      'offline': offline,
      'occurred_at': time,
      'counterparty': invoice['customer_name'],
      'voucher': voucher,
      'lines': sortedLines,
      'payments': settlements,
    };
  }

  Future<void> stage(
    Transaction txn, {
    required int saleId,
    required Map<String, Object?> invoice,
    required List<Map<String, Object?>> items,
    required List<Map<String, int>> payments,
  }) async {
    final draftId = invoice['draft_id'] as int;
    final attempt = isOnline ? await _readAttempt(txn, draftId) : null;
    if (isOnline && attempt == null) {
      throw StateError('Online checkout request was not saved.');
    }
    final operation = attempt?['operation'] as String? ?? newStockSyncId();
    final command = await _saleCommand(
      txn,
      invoice: invoice,
      items: items,
      payments: payments,
      offline: !isOnline,
      time: attempt?['time'] as String? ?? invoice['confirmed_at'] as String,
      voucher: isOnline
          ? 'SYNC-$operation'
          : VoucherCode.displayNumber({...invoice, 'id': saleId}),
    );
    if (attempt != null) {
      _checkAttempt(attempt, jsonEncode(command));
      // Only the isolated pilot uses this path. The stable intent is committed
      // separately, so a lost reply or a local rollback can retry the same ID.
      try {
        await onlineApi!
            .post(
              shop: store.shop,
              device: store.device,
              secret: onlineSecret!,
              operation: operation,
              command: command,
            )
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw StateError(
          'Online confirmation is uncertain. Reconnect and retry this same online checkout.',
        );
      } on PostgrestException catch (error) {
        throw StateError(error.message);
      }
      await txn.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [_attemptKey(draftId)],
      );
    } else {
      await store.stageSale(txn, operation: operation, command: command);
    }
    await txn.insert('app_settings', {
      'key': 'tp_sync_sale:$saleId',
      'value': operation,
    });
  }

  static Future<void> requireLocalVoucher(
    DatabaseExecutor db,
    int saleId,
  ) async {
    final marker = await db.query(
      'app_settings',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: ['tp_sync_sale:$saleId'],
      limit: 1,
    );
    if (marker.isNotEmpty) {
      throw StateError(
        'This synced test voucher can be viewed or printed. Reversals are not enabled.',
      );
    }
  }
}
