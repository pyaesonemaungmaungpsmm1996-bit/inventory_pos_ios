import 'dart:typed_data';

import 'app_currency.dart';
import 'app_database.dart';
import 'report_models.dart';
import 'report_repository.dart';

/// Entries are ordered by business date, then immutable entry ID.
/// Reversals are entries in their own right; never drop entries for VOID vouchers.
ReportBook buildMoneyLedgerReport({
  required List<Map<String, Object?>> accounts,
  required List<Map<String, Object?>> entries,
  required String business,
  required String filters,
  String search = '',
}) {
  final running = <int, int>{},
      incoming = <int, int>{},
      outgoing = <int, int>{};
  var opening = 0, moneyIn = 0, moneyOut = 0;
  for (final account in accounts) {
    final id = account['id'] as int, before = account['opening_balance'] as int;
    running[id] = before;
    incoming[id] = 0;
    outgoing[id] = 0;
    opening += before;
  }
  var combined = opening;
  final detailRows = <List<Object?>>[];
  final query = search.trim().toLowerCase();
  for (final entry in entries) {
    final id = entry['account_id'] as int, amount = entry['amount'] as int;
    if (!running.containsKey(id)) {
      throw StateError('Entry account is outside report scope');
    }
    running[id] = running[id]! + amount;
    combined += amount;
    final credit = amount > 0 ? amount : 0, debit = amount < 0 ? -amount : 0;
    incoming[id] = incoming[id]! + credit;
    outgoing[id] = outgoing[id]! + debit;
    moneyIn += credit;
    moneyOut += debit;
    final reference = ledgerVoucherNumber(entry);
    final record = <Object?>[
      entry['id'],
      entry['entry_date'],
      entry['branch_name'],
      entry['account_name'],
      entry['account_type'],
      entry['kind'],
      reference,
      entry['voucher_status'] ?? '',
      entry['party'] ?? '',
      reportMoney(credit),
      reportMoney(debit),
      reportMoney(running[id]!),
      reportMoney(combined),
      entry['note'],
      entry['created_at'],
    ];
    if (query.isEmpty ||
        record.any((v) => '$v'.toLowerCase().contains(query))) {
      detailRows.add(record);
    }
  }
  if (combined != opening + moneyIn - moneyOut) {
    throw StateError('Ledger does not reconcile');
  }
  return ReportBook(
    title: 'Cash / Bank / Wallet Ledger',
    business: business,
    filters:
        '$filters | Currency: ${AppCurrency.code}. Business date then entry ID order. '
        'Opening = all entries before start; closing = balance at end date. '
        'In/out includes opening entries, corrections and VOID reversals. '
        'Search filters detail rows only; balances and totals retain all scoped entries. '
        'Recorded times are UTC. This is account movement, not a sales/profit report.',
    tables: [
      ReportTable(
        'Ledger Summary',
        ['Metric', 'Amount'],
        [
          ['Opening balance', reportMoney(opening)],
          ['Money in', reportMoney(moneyIn)],
          ['Money out', reportMoney(moneyOut)],
          ['Net movement', reportMoney(moneyIn - moneyOut)],
          ['Closing balance', reportMoney(combined)],
        ],
        moneyColumns: {1},
      ),
      ReportTable(
        'Account Balances',
        [
          'Branch',
          'Account',
          'Type',
          'Account number',
          'Opening',
          'Money in',
          'Money out',
          'Closing',
        ],
        [
          for (final a in accounts)
            [
              a['branch_name'],
              a['name'],
              a['type'],
              a['account_number'],
              reportMoney(a['opening_balance'] as int),
              reportMoney(incoming[a['id']]!),
              reportMoney(outgoing[a['id']]!),
              reportMoney(running[a['id']]!),
            ],
        ],
        moneyColumns: {4, 5, 6, 7},
      ),
      ReportTable(
        'Transaction Details',
        [
          'Entry ID',
          'Business date',
          'Branch',
          'Account',
          'Type',
          'Entry kind',
          'Voucher',
          'Voucher status now',
          'Customer / Supplier / Category',
          'Money in',
          'Money out',
          'Account running balance',
          'Combined running balance',
          'Note',
          'Recorded UTC',
        ],
        detailRows,
        moneyColumns: {9, 10, 11, 12},
      ),
    ],
  );
}

String ledgerVoucherNumber(Map<String, Object?> entry) {
  for (final reference in [
    ('balance_check_id', 'BLC'),
    ('other_money_id', 'MIO'),
    ('account_transfer_id', 'ACT'),
    ('sale_return_id', 'RET'),
    ('customer_receipt_id', 'RCPT'),
    ('supplier_settlement_id', 'SET'),
    ('sale_id', 'INV'),
    ('purchase_id', 'PUR'),
    ('expense_id', 'EXP'),
  ]) {
    if (entry[reference.$1] != null) {
      return voucherNo(reference.$2, entry[reference.$1]);
    }
  }
  return '${entry['kind']} #${entry['id']}';
}

class MoneyLedgerRepository {
  static Future<Map<String, List<Map<String, Object?>>>> options() async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) async => {
        'branches': await txn.query('branches', orderBy: 'name, id'),
        'accounts': await txn.rawQuery(
          '''SELECT a.*, b.name AS branch_name, b.code AS branch_code
        FROM money_accounts a JOIN branches b ON b.id = a.branch_id
        ORDER BY b.name, a.name, a.id''',
        ),
      },
    );
  }

  static Future<ReportBook> voucher(int entryId) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final entries = await txn.rawQuery(
        '''SELECT e.*, a.name AS account_name,
        a.type AS account_type, b.name AS branch_name
        FROM money_entries e JOIN money_accounts a ON a.id = e.account_id
        JOIN branches b ON b.id = a.branch_id WHERE e.id = ?''',
        [entryId],
      );
      if (entries.length != 1) throw StateError('Transaction no longer exists');
      final entry = entries.single;
      final tables = <ReportTable>[], photos = <ReportAttachment>[];
      const amounts = {
        'amount',
        'total',
        'subtotal',
        'discount_amount',
        'paid',
        'balance_due',
        'price',
        'sale_price',
        'purchase_price',
        'refund_amount',
        'previous_amount',
        'new_amount',
        'delta',
        'book_balance',
        'actual_balance',
        'difference',
      };
      void append(String name, List<Map<String, Object?>> records) {
        if (records.isEmpty) return;
        final columns = records.first.keys.toList();
        final monetary = <int>{};
        for (var j = 0; j < columns.length; j++) {
          if (amounts.contains(columns[j])) monetary.add(j);
        }
        final rows = <List<Object?>>[];
        for (var i = 0; i < records.length; i++) {
          rows.add([
            for (var j = 0; j < columns.length; j++)
              (() {
                final value = records[i][columns[j]];
                if (value is Uint8List) {
                  final ext =
                      value.length > 1 && value[0] == 137 && value[1] == 80
                      ? 'png'
                      : 'jpg';
                  final path =
                      'attachments/entry_${entryId}_${name.replaceAll(' ', '_')}_${i + 1}_$j.$ext';
                  photos.add(ReportAttachment(path, value));
                  return path;
                }
                return monetary.contains(j) && value is int
                    ? reportMoney(value)
                    : value;
              })(),
          ]);
        }
        tables.add(
          ReportTable(
            name,
            columns.map(reportHeading).toList(),
            rows,
            moneyColumns: monetary,
          ),
        );
      }

      append('Selected Money Entry', entries);
      String? parent;
      Object? parentId;
      List<(String, String)> children = [];
      for (final reference in [
        (
          'balance_check_id',
          'balance_checks',
          [
            ('money_entries', 'balance_check_id'),
            ('balance_check_revisions', 'check_id'),
          ],
        ),
        (
          'other_money_id',
          'other_money_vouchers',
          [
            ('money_entries', 'other_money_id'),
            ('other_money_revisions', 'voucher_id'),
          ],
        ),
        (
          'account_transfer_id',
          'account_transfers',
          [
            ('money_entries', 'account_transfer_id'),
            ('account_transfer_revisions', 'transfer_id'),
          ],
        ),
        (
          'sale_return_id',
          'sale_returns',
          [
            ('sale_return_items', 'return_id'),
            ('sale_return_refunds', 'return_id'),
          ],
        ),
        (
          'customer_receipt_id',
          'customer_receipts',
          [
            ('receipt_allocations', 'receipt_id'),
            ('receipt_payments', 'receipt_id'),
          ],
        ),
        (
          'supplier_settlement_id',
          'supplier_settlements',
          [('supplier_settlement_payments', 'settlement_id')],
        ),
        (
          'sale_id',
          'sale_invoices',
          [('sale_items', 'sale_id'), ('sale_payments', 'sale_id')],
        ),
        (
          'purchase_id',
          'purchase_invoices',
          [
            ('purchase_items', 'purchase_id'),
            ('purchase_payments', 'purchase_id'),
          ],
        ),
        (
          'expense_id',
          'expenses',
          [
            ('expense_payments', 'expense_id'),
            ('expense_receipts', 'expense_id'),
            ('expense_edits', 'expense_id'),
          ],
        ),
      ]) {
        if (entry[reference.$1] == null) continue;
        parent = reference.$2;
        parentId = entry[reference.$1];
        children = reference.$3;
        break;
      }
      if (parent != null) {
        append(
          reportHeading(parent),
          await txn.query(parent, where: 'id = ?', whereArgs: [parentId]),
        );
        for (final child in children) {
          append(
            reportHeading(child.$1),
            await txn.query(
              child.$1,
              where: '${child.$2} = ?',
              whereArgs: [parentId],
            ),
          );
        }
      } else {
        append(
          'Opening Balance Corrections',
          await txn.query(
            'opening_balance_corrections',
            where: 'money_entry_id = ?',
            whereArgs: [entryId],
          ),
        );
      }
      return ReportBook(
        title: ledgerVoucherNumber(entry),
        business: '${profile['name'] ?? ''}',
        filters:
            'Entry #$entryId. Current voucher details, including VOID status. '
            'Amounts are ${AppCurrency.code} currency units. This entry is one part of a voucher; '
            'full payment splits and item rows are shown separately. IDs link related records. Revision JSON keeps stored minor units.',
        tables: tables,
        attachments: photos,
      );
    });
  }

  static Future<ReportBook> load({
    required String from,
    required String to,
    int? branch,
    int? account,
    String? type,
    String search = '',
    required String labels,
  }) async {
    if (from.compareTo(to) > 0) throw ArgumentError('Invalid date range');
    if (type != null && !{'cash', 'bank', 'wallet'}.contains(type)) {
      throw ArgumentError('Invalid account type');
    }
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final where = <String>['1 = 1'];
      final args = <Object?>[];
      if (branch != null) {
        where.add('a.branch_id = ?');
        args.add(branch);
      }
      if (account != null) {
        where.add('a.id = ?');
        args.add(account);
      }
      if (type != null) {
        where.add('a.type = ?');
        args.add(type);
      }
      final accounts = await txn.rawQuery(
        '''SELECT a.*, b.name || ' (' || b.code || ')' AS branch_name,
        COALESCE((SELECT SUM(e.amount) FROM money_entries e
          WHERE e.account_id = a.id AND e.entry_date < ?), 0) AS opening_balance
        FROM money_accounts a JOIN branches b ON b.id = a.branch_id
        WHERE ${where.join(' AND ')} ORDER BY b.name, a.name, a.id''',
        [from, ...args],
      );
      final entries = await txn.rawQuery(
        '''SELECT e.*, a.name AS account_name, a.type AS account_type,
        b.name || ' (' || b.code || ')' AS branch_name,
        COALESCE(c.status, m.status, t.status, r.status, cr.status, ss.status, s.status, p.status, x.status, '') AS voucher_status,
        COALESCE('Balance check: ' || c.account_name, m.category || ': ' || m.description, t.from_account_name || ' → ' || t.to_account_name, r.customer_name, cr.customer_name, s.customer_name, p.supplier_name, sp.supplier_name, x.category, '') AS party
        FROM money_entries e JOIN money_accounts a ON a.id = e.account_id
        JOIN branches b ON b.id = a.branch_id
        LEFT JOIN balance_checks c ON c.id = e.balance_check_id
        LEFT JOIN other_money_vouchers m ON m.id = e.other_money_id
        LEFT JOIN account_transfers t ON t.id = e.account_transfer_id
        LEFT JOIN sale_invoices s ON s.id = e.sale_id
        LEFT JOIN purchase_invoices p ON p.id = e.purchase_id
        LEFT JOIN customer_receipts cr ON cr.id = e.customer_receipt_id
        LEFT JOIN supplier_settlements ss ON ss.id = e.supplier_settlement_id
        LEFT JOIN purchase_invoices sp ON sp.id = ss.purchase_id
        LEFT JOIN expenses x ON x.id = e.expense_id
        LEFT JOIN (SELECT r0.*, s0.customer_name FROM sale_returns r0
          JOIN sale_invoices s0 ON s0.id = r0.sale_id) r ON r.id = e.sale_return_id
        WHERE ${where.join(' AND ')} AND e.entry_date >= ? AND e.entry_date <= ?
        ORDER BY e.entry_date, e.id''',
        [...args, from, to],
      );
      return buildMoneyLedgerReport(
        accounts: accounts,
        entries: entries,
        business: '${profile['name'] ?? ''}',
        filters: labels,
        search: search,
      );
    });
  }
}
