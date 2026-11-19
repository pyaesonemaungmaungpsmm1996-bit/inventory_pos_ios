import 'app_currency.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'report_models.dart';
import 'report_repository.dart';

/// Positive balances are amounts owed to the supplier. Negative balances are credit.
ReportBook buildSupplierLedgerReport({
  required List<Map<String, Object?>> purchases,
  required List<Map<String, Object?>> payments,
  required List<Map<String, Object?>> items,
  required String from,
  required String to,
  required String business,
  required String filters,
  String search = '',
}) {
  final invoiceById = <int, Map<String, Object?>>{
    for (final p in purchases) p['id'] as int: p,
  };
  final events = <Map<String, Object?>>[];
  for (final p in purchases) {
    events.add({
      'date': p['invoice_date'],
      'recorded': p['confirmed_at'],
      'rank': 0,
      'id': p['id'],
      'purchase_id': p['id'],
      'type': 'Purchase',
      'delta': p['total'],
      'note': '',
      'account': '',
      'reference': voucherNo('PUR', p['id']),
      'status': p['status'],
      'entry_id': null,
    });
    if (p['status'] == 'void') {
      final day = p['void_date'] as String?;
      if (day == null || day.length != 10) {
        throw StateError('Missing purchase void business date');
      }
      events.add({
        'date': day,
        'recorded': p['voided_at'],
        'rank': 2,
        'id': p['id'],
        'purchase_id': p['id'],
        'type': 'Cancel purchase',
        'delta': -(p['total'] as int),
        'note': p['void_reason'] ?? '',
        'account': '',
        'reference': voucherNo('PUR', p['id']),
        'status': 'void',
        'entry_id': null,
      });
    }
  }
  for (final e in payments) {
    if (!invoiceById.containsKey(e['linked_purchase_id'])) {
      throw StateError('Payment outside supplier scope');
    }
    events.add({
      'date': e['entry_date'],
      'recorded': e['created_at'],
      'rank': 1,
      'id': e['id'],
      'purchase_id': e['linked_purchase_id'],
      'type': (e['amount'] as int) < 0
          ? 'Payment out'
          : 'Payment reversal / refund',
      'delta': e['amount'],
      'note': e['note'],
      'account': e['account_name'],
      'reference': e['supplier_settlement_id'] == null
          ? voucherNo('PUR', e['linked_purchase_id'])
          : voucherNo('SET', e['supplier_settlement_id']),
      'status': e['voucher_status'],
      'entry_id': e['id'],
    });
  }
  events.sort((a, b) {
    var result = (a['date'] as String).compareTo(b['date'] as String);
    if (result != 0) return result;
    result = '${a['recorded'] ?? ''}'.compareTo('${b['recorded'] ?? ''}');
    if (result != 0) return result;
    result = (a['rank'] as int).compareTo(b['rank'] as int);
    return result != 0 ? result : (a['id'] as int).compareTo(b['id'] as int);
  });
  String groupKey(Map<String, Object?> p) =>
      '${p['branch_id']}:${p['supplier_id']}';
  final groups = <String, List<int>>{};
  final groupInfo = <String, Map<String, Object?>>{};
  final invoiceBalances = <int, int>{};
  final periodInvoices = <int>{};
  final detail = <List<Object?>>[];
  final query = search.trim().toLowerCase();
  var combined = 0;
  for (final e in events) {
    final day = e['date'] as String;
    if (day.compareTo(to) > 0) continue;
    final id = e['purchase_id'] as int, amount = e['delta'] as int;
    final p = invoiceById[id]!;
    final key = groupKey(p);
    final group = groups.putIfAbsent(key, () => [0, 0, 0, 0, 0, 0]);
    groupInfo[key] = p;
    invoiceBalances[id] = (invoiceBalances[id] ?? 0) + amount;
    combined += amount;
    group[5] += amount;
    if (day.compareTo(from) < 0) {
      group[0] += amount;
      continue;
    }
    periodInvoices.add(id);
    if (e['type'] == 'Purchase') {
      group[1] += amount;
    } else if (e['type'] == 'Cancel purchase') {
      group[2] -= amount;
    } else if (amount < 0) {
      group[3] -= amount;
    } else {
      group[4] += amount;
    }
    final row = <Object?>[
      day,
      p['branch_name'],
      p['current_supplier_name'] ?? p['supplier_name'],
      e['type'],
      e['reference'],
      voucherNo('PUR', id),
      e['account'],
      reportMoney(amount > 0 ? amount : 0),
      reportMoney(amount < 0 ? -amount : 0),
      reportMoney(invoiceBalances[id]!),
      reportMoney(group[5]),
      reportMoney(combined),
      e['note'],
      e['status'],
      e['entry_id'],
      id,
      e['recorded'],
    ];
    if (query.isEmpty ||
        row.any((v) => '${v ?? ''}'.toLowerCase().contains(query))) {
      detail.add(row);
    }
  }
  final totals = List<int>.filled(6, 0);
  for (final g in groups.values) {
    for (var i = 0; i < 6; i++) {
      totals[i] += g[i];
    }
  }
  if (totals[0] + totals[1] - totals[2] - totals[3] + totals[4] != totals[5]) {
    throw StateError('Supplier ledger does not reconcile');
  }
  final relevant = <int>{
    ...periodInvoices,
    for (final e in invoiceBalances.entries)
      if (e.value != 0) e.key,
  };
  final invoiceRows =
      purchases.where((p) => relevant.contains(p['id'])).toList()..sort(
        (a, b) => '${a['invoice_date']}'.compareTo('${b['invoice_date']}'),
      );
  final supplierRows = groups.entries.toList()
    ..sort(
      (a, b) => '${groupInfo[a.key]!['current_supplier_name']}'.compareTo(
        '${groupInfo[b.key]!['current_supplier_name']}',
      ),
    );
  return ReportBook(
    title: 'Supplier Ledger',
    business: business,
    filters:
        '$filters | Currency: ${AppCurrency.code}. Positive balance = payable; negative = supplier credit. '
        'All balances are at end date. Payments and VOID reversals use stored money-entry business dates. '
        'Purchase cancellation uses saved reversal date, or configured business timezone for unpaid vouchers. '
        'Search affects transaction rows only. Invoice list includes period activity and outstanding balances at cutoff. '
        'Voucher status is current; it may differ from status on the selected date.',
    tables: [
      ReportTable(
        'Supplier Ledger Summary',
        ['Metric', 'Amount'],
        [
          ['Opening payable', reportMoney(totals[0])],
          ['Purchases', reportMoney(totals[1])],
          ['Cancelled purchases', reportMoney(totals[2])],
          ['Payments out', reportMoney(totals[3])],
          ['Reversals / refunds received', reportMoney(totals[4])],
          ['Closing payable', reportMoney(totals[5])],
        ],
        moneyColumns: {1},
      ),
      ReportTable(
        'Supplier Balances',
        [
          'Branch',
          'Supplier',
          'Phone',
          'Opening',
          'Purchases',
          'Cancelled purchases',
          'Paid out',
          'Reversals / refunds',
          'Closing payable',
        ],
        [
          for (final e in supplierRows)
            [
              groupInfo[e.key]!['branch_name'],
              groupInfo[e.key]!['current_supplier_name'] ??
                  groupInfo[e.key]!['supplier_name'],
              groupInfo[e.key]!['supplier_phone'],
              for (final amount in e.value) reportMoney(amount),
            ],
        ],
        moneyColumns: {3, 4, 5, 6, 7, 8},
      ),
      ReportTable(
        'Purchase Balances at Cutoff',
        [
          'Purchase ID',
          'Invoice',
          'Invoice date',
          'Branch',
          'Supplier at purchase',
          'Phone',
          'Address',
          'Original total',
          'Balance at end date',
          'Status now',
          'Effective paid now',
          'Effective due now',
          'Void reason',
          'Correction replacement ID',
        ],
        [
          for (final p in invoiceRows)
            [
              p['id'],
              voucherNo('PUR', p['id']),
              p['invoice_date'],
              p['branch_name'],
              p['supplier_name'],
              p['supplier_phone'],
              p['supplier_address'],
              reportMoney(p['total'] as int),
              reportMoney(invoiceBalances[p['id']] ?? 0),
              p['status'],
              reportMoney(p['status'] == 'posted' ? p['paid'] as int : 0),
              reportMoney(
                p['status'] == 'posted' ? p['balance_due'] as int : 0,
              ),
              p['void_reason'],
              p['replacement_id'],
            ],
        ],
        moneyColumns: {7, 8, 10, 11},
      ),
      ReportTable(
        'Supplier Transactions',
        [
          'Business date',
          'Branch',
          'Supplier',
          'Event',
          'Voucher',
          'Purchase',
          'Account',
          'Payable increase',
          'Payable decrease',
          'Invoice balance',
          'Supplier branch balance',
          'Combined balance',
          'Note / Reason',
          'Voucher status now',
          'Money entry ID',
          'Purchase ID',
          'Recorded UTC',
        ],
        detail,
        moneyColumns: {7, 8, 9, 10, 11},
      ),
      ReportTable(
        'Purchased Item Details',
        [
          'Purchase ID',
          'Invoice',
          'Item code',
          'Item name',
          'Category at purchase',
          'Quantity',
          'Purchase price',
          'Amount',
          'Sale price',
        ],
        [
          for (final i in items)
            if (relevant.contains(i['purchase_id']))
              [
                i['purchase_id'],
                voucherNo('PUR', i['purchase_id']),
                i['item_code'],
                i['item_name'],
                i['category_name'],
                i['qty'],
                reportMoney(i['purchase_price'] as int),
                reportMoney(i['amount'] as int),
                reportMoney(i['sale_price'] as int),
              ],
        ],
        moneyColumns: {6, 7, 8},
      ),
    ],
  );
}

class SupplierLedgerRepository {
  static Future<Map<String, List<Map<String, Object?>>>> options() async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) async => {
        'branches': await txn.query('branches', orderBy: 'name, id'),
        'suppliers': await txn.query(
          'contacts',
          where: "kind = 'supplier'",
          orderBy: 'name, id',
        ),
      },
    );
  }

  static Future<ReportBook> load({
    required String from,
    required String to,
    int? branch,
    int? supplier,
    String search = '',
    required String labels,
  }) async {
    if (from.compareTo(to) > 0) throw ArgumentError('Invalid date range');
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final conditions = <String>['1 = 1'];
      final args = <Object?>[];
      if (branch != null) {
        conditions.add('p.branch_id = ?');
        args.add(branch);
      }
      if (supplier != null) {
        conditions.add('p.supplier_id = ?');
        args.add(supplier);
      }
      final purchases = await txn.rawQuery(
        '''SELECT p.*, c.name AS current_supplier_name,
        b.name || ' (' || b.code || ')' AS branch_name,
        (SELECT MIN(e.entry_date) FROM money_entries e WHERE e.purchase_id = p.id
          AND e.created_at = p.voided_at AND e.amount > 0) AS reversal_date
        FROM purchase_invoices p JOIN branches b ON b.id = p.branch_id
        JOIN contacts c ON c.id = p.supplier_id
        WHERE ${conditions.join(' AND ')} ORDER BY p.invoice_date, p.id''',
        args,
      );
      final snapshots = <Map<String, Object?>>[];
      for (final p in purchases) {
        String? day = p['reversal_date'] as String?;
        if (p['status'] == 'void' && day == null) {
          final formatted = AppDateTime.format(p['voided_at']);
          if (formatted == '—') {
            throw StateError(
              'Cannot determine void date for purchase #${p['id']}',
            );
          }
          day = formatted.substring(0, 10);
        }
        snapshots.add({...p, 'void_date': day});
      }
      final payments = await txn.rawQuery(
        '''SELECT e.*, p.id AS linked_purchase_id,
        a.name AS account_name, COALESCE(ss.status, p.status) AS voucher_status
        FROM money_entries e
        LEFT JOIN supplier_settlements ss ON ss.id = e.supplier_settlement_id
        JOIN purchase_invoices p ON p.id = COALESCE(e.purchase_id, ss.purchase_id)
        JOIN money_accounts a ON a.id = e.account_id
        WHERE ${conditions.join(' AND ')} AND e.entry_date <= ?
        ORDER BY e.entry_date, e.id''',
        [...args, to],
      );
      final items = await txn.rawQuery(
        '''SELECT i.* FROM purchase_items i
        JOIN purchase_invoices p ON p.id = i.purchase_id
        WHERE ${conditions.join(' AND ')} ORDER BY p.invoice_date, i.id''',
        args,
      );
      return buildSupplierLedgerReport(
        purchases: snapshots,
        payments: payments,
        items: items,
        from: from,
        to: to,
        business: '${profile['name'] ?? ''}',
        filters: labels,
        search: search,
      );
    });
  }

  static Future<ReportBook> purchase(int id) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    final purchase = await AppDatabase.instance.getPurchase(id);
    final header = Map<String, Object?>.of(purchase);
    for (final key in [
      'items',
      'payments',
      'settlements',
      'settlement_payments',
    ]) {
      header.remove(key);
    }
    const money = {
      'total',
      'paid',
      'balance_due',
      'amount',
      'purchase_price',
      'sale_price',
    };
    ReportTable table(String title, List<Map<String, Object?>> rows) {
      final columns = rows.isEmpty
          ? <String>['No records']
          : rows.first.keys.toList();
      final amounts = <int>{
        for (var i = 0; i < columns.length; i++)
          if (money.contains(columns[i])) i,
      };
      return ReportTable(title, columns.map(reportHeading).toList(), [
        for (final row in rows)
          [
            for (var i = 0; i < columns.length; i++)
              amounts.contains(i) && row[columns[i]] is int
                  ? reportMoney(row[columns[i]] as int)
                  : row[columns[i]],
          ],
      ], moneyColumns: amounts);
    }

    return ReportBook(
      title: voucherNo('PUR', id),
      business: '${profile['name'] ?? ''}',
      filters:
          'Full purchase voucher at current status. Amounts in ${AppCurrency.code}. '
          'Initial payments and later settlements are separate tables; VOID rows are retained.',
      tables: [
        table('Purchase Invoice', [header]),
        for (final key in [
          'items',
          'payments',
          'settlements',
          'settlement_payments',
        ])
          table(reportHeading(key), [
            for (final row in purchase[key] as List)
              Map<String, Object?>.from(row as Map),
          ]),
      ],
    );
  }
}
