import 'dart:typed_data';

import 'app_currency.dart';
import 'app_database.dart';
import 'report_models.dart';

String reportHeading(String key) => key
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');
String voucherNo(String prefix, Object? id) =>
    '$prefix-${id.toString().padLeft(6, '0')}';
num reportMoney(int amount) => AppCurrency.digits == 0 ? amount : amount / 100;

class SalesReportFilter {
  const SalesReportFilter({
    required this.from,
    required this.to,
    this.branch,
    this.employee,
    this.product,
    this.category,
    this.customer,
    this.includeVoid = false,
  });
  final String from, to;
  final int? branch, employee, product, category, customer;
  final bool includeVoid;
}

class ReportRepository {
  static Future<Map<String, List<Map<String, Object?>>>> options() async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) async => {
        'branches': await txn.query('branches', orderBy: 'name, id'),
        'employees': await txn.query('employees', orderBy: 'name, id'),
        'products': await txn.query(
          'products',
          columns: ['id', 'name', 'item_code', 'category_id'],
          orderBy: 'name, id',
        ),
        'categories': await txn.query(
          'product_categories',
          orderBy: 'name, id',
        ),
        'customers': await txn.rawQuery(
          'SELECT DISTINCT customer_id AS id, customer_name AS name FROM sale_invoices WHERE customer_id IS NOT NULL ORDER BY customer_name, customer_id',
        ),
      },
    );
  }

  static Future<ReportBook> sales(
    SalesReportFilter filter,
    String labels,
  ) async {
    if (filter.from.compareTo(filter.to) > 0) {
      throw ArgumentError('Invalid date range');
    }
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final conditions = <String>['s.invoice_date >= ?', 's.invoice_date <= ?'];
      final args = <Object?>[filter.from, filter.to];
      void add(String sql, int? value) {
        if (value != null) {
          conditions.add(sql);
          args.add(value);
        }
      }

      add('s.branch_id = ?', filter.branch);
      add('s.employee_id = ?', filter.employee);
      add('s.customer_id = ?', filter.customer);
      // Filter full item rows below; do not restrict invoices before allocating discount.
      if (!filter.includeVoid) conditions.add("s.status = 'posted'");
      final saleRows = await txn.rawQuery(
        '''SELECT s.id AS invoice_id, s.invoice_date,
        s.customer_name, s.employee_id, s.employee_name, s.status, s.subtotal, s.total,
        s.confirmed_at, s.replacement_id, b.name AS branch, i.id AS item_id,
        i.product_id, i.item_code, i.item_name, i.qty, i.price, i.amount,i.item_discount,
        (s.subtotal-(SELECT COALESCE(SUM(di.item_discount),0) FROM sale_items di WHERE di.sale_id=s.id)) AS allocation_base,
        p.category_id, COALESCE(c.name, 'Uncategorized') AS category
        FROM sale_invoices s JOIN sale_items i ON i.sale_id = s.id
        JOIN branches b ON b.id = s.branch_id JOIN products p ON p.id = i.product_id
        LEFT JOIN product_categories c ON c.id = p.category_id
        WHERE ${conditions.join(' AND ')} ORDER BY s.id, i.id''',
        args,
      );
      final returnConditions = <String>[
        'r.return_date >= ?',
        'r.return_date <= ?',
      ];
      final returnArgs = <Object?>[filter.from, filter.to];
      void addReturn(String sql, int? value) {
        if (value != null) {
          returnConditions.add(sql);
          returnArgs.add(value);
        }
      }

      addReturn('r.branch_id = ?', filter.branch);
      // Salesperson means the original selling employee, consistently for sale and return.
      addReturn('s.employee_id = ?', filter.employee);
      addReturn('s.customer_id = ?', filter.customer);
      addReturn('i.product_id = ?', filter.product);
      addReturn('p.category_id = ?', filter.category);
      if (!filter.includeVoid) returnConditions.add("r.status = 'posted'");
      final returnRows = await txn.rawQuery(
        '''SELECT r.id AS return_id, r.sale_id,
        r.return_date, r.created_at, r.reason, r.employee_name AS processed_by,
        r.status, r.replacement_id, s.customer_name, s.employee_name,
        b.name AS branch, i.product_id, i.item_code, i.item_name, i.qty,
        i.refund_amount, si.price, COALESCE(c.name, 'Uncategorized') AS category
        FROM sale_returns r JOIN sale_invoices s ON s.id = r.sale_id
        JOIN sale_return_items i ON i.return_id = r.id
        JOIN sale_items si ON si.id = i.sale_item_id
        JOIN branches b ON b.id = r.branch_id JOIN products p ON p.id = i.product_id
        LEFT JOIN product_categories c ON c.id = p.category_id
        WHERE ${returnConditions.join(' AND ')} ORDER BY r.return_date, r.id, i.sale_item_id''',
        returnArgs,
      );
      final details = <List<Object?>>[], returned = <List<Object?>>[];
      final groups = <String, Map<String, Object?>>{};
      final periods = <String, List<int>>{};
      final saleIds = <int>{}, returnIds = <int>{};
      var gross = 0,
          discount = 0,
          sales = 0,
          refunds = 0,
          soldQty = 0,
          returnQty = 0;
      var previousInvoice = -1,
          cumulative = BigInt.zero,
          previousAllocated = BigInt.zero;
      Map<String, Object?> group(Map<String, Object?> row) =>
          groups.putIfAbsent(
            '${row['product_id']}',
            () => {
              'code': row['item_code'],
              'name': row['item_name'],
              'category': row['category'],
              'sold': 0,
              'returned': 0,
              'sales': 0,
              'refund': 0,
            },
          );
      for (final row in saleRows) {
        final invoiceId = row['invoice_id'] as int;
        if (previousInvoice != invoiceId) {
          previousInvoice = invoiceId;
          cumulative = BigInt.zero;
          previousAllocated = BigInt.zero;
        }
        cumulative += BigInt.from(
          (row['amount'] as int) - (row['item_discount'] as int),
        );
        final subtotal = row['allocation_base'] as int;
        final allocated = subtotal == 0
            ? BigInt.zero
            : cumulative *
                  BigInt.from(row['total'] as int) ~/
                  BigInt.from(subtotal);
        final net = (allocated - previousAllocated).toInt();
        previousAllocated = allocated;
        if (filter.product != null && row['product_id'] != filter.product) {
          continue;
        }
        if (filter.category != null && row['category_id'] != filter.category) {
          continue;
        }
        final amount = row['amount'] as int, qty = row['qty'] as int;
        details.add([
          voucherNo('INV', invoiceId),
          row['invoice_date'],
          row['branch'],
          row['employee_name'],
          row['customer_name'],
          row['category'],
          row['item_code'],
          row['item_name'],
          qty,
          reportMoney(row['price'] as int),
          reportMoney(amount),
          reportMoney(amount - net),
          reportMoney(net),
          row['status'],
          row['confirmed_at'],
          row['replacement_id'],
        ]);
        saleIds.add(invoiceId);
        if (row['status'] != 'posted') continue;
        gross += amount;
        discount += amount - net;
        sales += net;
        soldQty += qty;
        final g = group(row);
        g['sold'] = (g['sold'] as int) + qty;
        g['sales'] = (g['sales'] as int) + net;
        final period = periods.putIfAbsent(
          (row['invoice_date'] as String).substring(0, 7),
          () => [0, 0, 0, 0],
        );
        period[0] += net;
        period[2] += qty;
      }
      for (final row in returnRows) {
        final id = row['return_id'] as int,
            qty = row['qty'] as int,
            amount = row['refund_amount'] as int;
        returned.add([
          voucherNo('RET', id),
          voucherNo('INV', row['sale_id']),
          row['return_date'],
          row['branch'],
          row['employee_name'],
          row['processed_by'],
          row['customer_name'],
          row['category'],
          row['item_code'],
          row['item_name'],
          qty,
          reportMoney(row['price'] as int),
          reportMoney(amount),
          row['reason'],
          row['status'],
          row['created_at'],
          row['replacement_id'],
        ]);
        returnIds.add(id);
        if (row['status'] != 'posted') continue;
        refunds += amount;
        returnQty += qty;
        final g = group(row);
        g['returned'] = (g['returned'] as int) + qty;
        g['refund'] = (g['refund'] as int) + amount;
        final period = periods.putIfAbsent(
          (row['return_date'] as String).substring(0, 7),
          () => [0, 0, 0, 0],
        );
        period[1] += amount;
        period[3] += qty;
      }
      final payments = <List<Object?>>[];
      // Account splits are full-voucher amounts, never multiplied by item joins.
      // This is explicitly labelled so item-filtered totals cannot be confused with cash flow.
      for (final source in [
        ('sale_payments', 'sale_id', saleIds, 'Sale payment'),
        ('sale_return_refunds', 'return_id', returnIds, 'Return refund'),
      ]) {
        if (source.$3.isEmpty) continue;
        // Query in small batches to stay below SQLite's bind-variable limit.
        final ids = source.$3.toList();
        for (var offset = 0; offset < ids.length; offset += 400) {
          final batch = ids.skip(offset).take(400).toList();
          final rows = await txn.rawQuery(
            '''SELECT x.*, a.name AS account_name, v.status AS voucher_status
            FROM ${source.$1} x JOIN money_accounts a ON a.id = x.account_id
            JOIN ${source.$2 == 'sale_id' ? 'sale_invoices' : 'sale_returns'} v ON v.id = x.${source.$2}
            WHERE x.${source.$2} IN (${List.filled(batch.length, '?').join(',')})
            ORDER BY x.${source.$2}, x.account_id''',
            batch,
          );
          for (final row in rows) {
            payments.add([
              source.$4,
              voucherNo(source.$2 == 'sale_id' ? 'INV' : 'RET', row[source.$2]),
              row['account_name'],
              reportMoney(row['amount'] as int),
              row['voucher_status'],
              'Full voucher split; includes void records when selected',
            ]);
          }
        }
      }
      final receiptRows = await txn.rawQuery(
        '''SELECT ra.*, cr.payment_date, cr.status
        FROM receipt_allocations ra JOIN customer_receipts cr ON cr.id = ra.receipt_id''',
      );
      final allocations = <List<Object?>>[];
      final receiptIds = <int>{};
      for (final row in receiptRows) {
        if (!saleIds.contains(row['sale_id'])) continue;
        receiptIds.add(row['receipt_id'] as int);
        allocations.add([
          voucherNo('RCPT', row['receipt_id']),
          voucherNo('INV', row['sale_id']),
          row['payment_date'],
          reportMoney(row['amount'] as int),
          row['status'],
          'Full invoice allocation; receipt may be outside selected sale date range',
        ]);
      }
      final exchangeItems = <List<Object?>>[];
      final linkedSaleIds = <int>{
        ...saleIds,
        for (final row in returnRows) row['sale_id'] as int,
      };
      final linkedReturnIds = returnIds.toList();
      for (var offset = 0; offset < linkedReturnIds.length; offset += 400) {
        final batch = linkedReturnIds.skip(offset).take(400).toList();
        final rows = await txn.rawQuery(
          '''SELECT x.*, r.sale_id AS original_sale_id,
          r.status AS return_status, n.invoice_date, n.status AS replacement_status,
          n.customer_name, n.employee_name, b.name AS branch, i.item_code, i.item_name,
          i.qty, i.price, i.amount
          FROM sale_exchange_links x JOIN sale_returns r ON r.id = x.return_id
          JOIN sale_invoices n ON n.id = x.replacement_sale_id
          JOIN branches b ON b.id = n.branch_id JOIN sale_items i ON i.sale_id = n.id
          WHERE x.return_id IN (${List.filled(batch.length, '?').join(',')})
          ORDER BY x.return_id, i.id''',
          batch,
        );
        for (final row in rows) {
          linkedSaleIds.add(row['replacement_sale_id'] as int);
          exchangeItems.add([
            voucherNo('RET', row['return_id']),
            voucherNo('INV', row['original_sale_id']),
            voucherNo('INV', row['replacement_sale_id']),
            row['invoice_date'],
            row['branch'],
            row['customer_name'],
            row['employee_name'],
            row['item_code'],
            row['item_name'],
            row['qty'],
            reportMoney(row['price'] as int),
            reportMoney(row['amount'] as int),
            row['return_status'],
            row['replacement_status'],
            row['linked_at'],
            'Full replacement sale lines before discount; may be outside report period. Not added again to totals.',
          ]);
        }
      }
      final headerTables = <ReportTable>[];
      for (final source in [
        ('sale_invoices', linkedSaleIds, 'Invoice Headers'),
        ('sale_returns', returnIds, 'Return Headers'),
        ('customer_receipts', receiptIds, 'Linked Receipt Headers'),
      ]) {
        final rows = <Map<String, Object?>>[];
        final ids = source.$2.toList();
        for (var offset = 0; offset < ids.length; offset += 400) {
          final batch = ids.skip(offset).take(400).toList();
          rows.addAll(
            await txn.rawQuery(
              'SELECT * FROM ${source.$1} WHERE id IN (${List.filled(batch.length, '?').join(',')}) ORDER BY id',
              batch,
            ),
          );
        }
        final info = await txn.rawQuery('PRAGMA table_info("${source.$1}")');
        final columns = info.map((r) => r['name'] as String).toList();
        final money = <int>{};
        const moneyNames = {
          'subtotal',
          'discount_amount',
          'total',
          'paid',
          'balance_due',
        };
        for (var i = 0; i < columns.length; i++) {
          if (moneyNames.contains(columns[i])) money.add(i);
        }
        headerTables.add(
          ReportTable(source.$3, columns.map(reportHeading).toList(), [
            for (final row in rows)
              [
                for (var i = 0; i < columns.length; i++)
                  money.contains(i) && row[columns[i]] is int
                      ? reportMoney(row[columns[i]] as int)
                      : row[columns[i]],
              ],
          ], moneyColumns: money),
        );
      }
      final receiptAccounts = <List<Object?>>[];
      final allReceiptAccounts = await txn.rawQuery(
        'SELECT rp.*, a.name AS account_name FROM receipt_payments rp JOIN money_accounts a ON a.id = rp.account_id ORDER BY rp.receipt_id, rp.account_id',
      );
      for (final row in allReceiptAccounts) {
        if (!receiptIds.contains(row['receipt_id'])) continue;
        receiptAccounts.add([
          voucherNo('RCPT', row['receipt_id']),
          row['account_name'],
          reportMoney(row['amount'] as int),
          'Full receipt split; may pay other invoices too',
        ]);
      }
      final productRows = groups.values.toList()
        ..sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
      final categoryGroups = <String, List<int>>{};
      for (final g in productRows) {
        final bucket = categoryGroups.putIfAbsent(
          g['category'] as String,
          () => [0, 0, 0, 0],
        );
        bucket[0] += g['sold'] as int;
        bucket[1] += g['returned'] as int;
        bucket[2] += g['sales'] as int;
        bucket[3] += g['refund'] as int;
      }
      final months = periods.keys.toList()..sort();
      final years = <String, List<int>>{};
      for (final month in months) {
        final bucket = years.putIfAbsent(
          month.substring(0, 4),
          () => [0, 0, 0, 0],
        );
        for (var i = 0; i < 4; i++) {
          bucket[i] += periods[month]![i];
        }
      }
      return ReportBook(
        title: 'Sales, Items & Returns',
        business: '${profile['name'] ?? ''}',
        filters:
            '$labels | Currency: ${AppCurrency.code} | Business dates | '
            'Salesperson = original seller. Category = current product category. '
            'Totals exclude VOID. Linked invoice headers can be outside the selected period. Return dates are independent of original invoice dates. '
            'Line discount allocated proportionally; full invoice allocations reconcile exactly. '
            'Exchange links connect recorded returns to replacement sales; no additional financial posting.',
        tables: [
          ReportTable(
            'Summary',
            ['Metric', 'Value'],
            [
              ['Gross sales', reportMoney(gross)],
              ['Discounts', reportMoney(discount)],
              ['Sales after discount', reportMoney(sales)],
              ['Returned / refunded', reportMoney(refunds)],
              ['Net sales', reportMoney(sales - refunds)],
              ['Sold quantity', soldQty],
              ['Returned quantity', returnQty],
            ],
          ),
          ReportTable(
            'Monthly Summary',
            [
              'Month',
              'Sales',
              'Refunds',
              'Net sales',
              'Sold qty',
              'Returned qty',
            ],
            [
              for (final month in months)
                [
                  month,
                  reportMoney(periods[month]![0]),
                  reportMoney(periods[month]![1]),
                  reportMoney(periods[month]![0] - periods[month]![1]),
                  periods[month]![2],
                  periods[month]![3],
                ],
            ],
            moneyColumns: {1, 2, 3},
          ),
          ReportTable(
            'Yearly Summary',
            [
              'Year',
              'Sales',
              'Refunds',
              'Net sales',
              'Sold qty',
              'Returned qty',
            ],
            [
              for (final e in years.entries)
                [
                  e.key,
                  reportMoney(e.value[0]),
                  reportMoney(e.value[1]),
                  reportMoney(e.value[0] - e.value[1]),
                  e.value[2],
                  e.value[3],
                ],
            ],
            moneyColumns: {1, 2, 3},
          ),
          ReportTable(
            'Item Summary',
            [
              'Item code',
              'Item name',
              'Category',
              'Sold qty',
              'Returned qty',
              'Net qty',
              'Sales',
              'Refunds',
              'Net sales',
            ],
            [
              for (final g in productRows)
                [
                  g['code'],
                  g['name'],
                  g['category'],
                  g['sold'],
                  g['returned'],
                  (g['sold'] as int) - (g['returned'] as int),
                  reportMoney(g['sales'] as int),
                  reportMoney(g['refund'] as int),
                  reportMoney((g['sales'] as int) - (g['refund'] as int)),
                ],
            ],
            moneyColumns: {6, 7, 8},
          ),
          ReportTable(
            'Category Summary',
            [
              'Category',
              'Sold qty',
              'Returned qty',
              'Sales',
              'Refunds',
              'Net sales',
            ],
            [
              for (final e in categoryGroups.entries)
                [
                  e.key,
                  e.value[0],
                  e.value[1],
                  reportMoney(e.value[2]),
                  reportMoney(e.value[3]),
                  reportMoney(e.value[2] - e.value[3]),
                ],
            ],
            moneyColumns: {3, 4, 5},
          ),
          ReportTable(
            'Sale Item Details',
            [
              'Invoice',
              'Date',
              'Branch',
              'Salesperson',
              'Customer',
              'Category',
              'Item code',
              'Item name',
              'Qty',
              'Unit price',
              'Gross',
              'Discount allocated',
              'Net',
              'Status',
              'Recorded at UTC',
              'Correction replacement ID',
            ],
            details,
            moneyColumns: {9, 10, 11, 12},
          ),
          ReportTable(
            'Return Item Details',
            [
              'Return',
              'Original invoice',
              'Return date',
              'Branch',
              'Original seller',
              'Processed by',
              'Customer',
              'Category',
              'Item code',
              'Item name',
              'Returned qty',
              'Original unit price',
              'Refund',
              'Reason',
              'Status',
              'Recorded at UTC',
              'Correction replacement ID',
            ],
            returned,
            moneyColumns: {11, 12},
          ),
          ReportTable(
            'Voucher Account Splits',
            ['Type', 'Voucher', 'Account', 'Amount', 'Status', 'Scope'],
            payments,
            moneyColumns: {3},
          ),
          ReportTable(
            'Exchange Replacement Items',
            [
              'Return',
              'Original invoice',
              'Replacement invoice',
              'Replacement date',
              'Branch',
              'Customer',
              'Seller',
              'Item code',
              'Item name',
              'Qty',
              'Unit price',
              'Gross line amount',
              'Return status',
              'Replacement status',
              'Linked UTC',
              'Scope',
            ],
            exchangeItems,
            moneyColumns: {10, 11},
          ),
          ...headerTables,
          ReportTable(
            'Linked Receipt Accounts',
            ['Receipt', 'Account', 'Amount', 'Scope'],
            receiptAccounts,
            moneyColumns: {2},
          ),
          ReportTable(
            'Later Receipt Allocations',
            ['Receipt', 'Invoice', 'Receipt date', 'Amount', 'Status', 'Scope'],
            allocations,
            moneyColumns: {3},
          ),
        ],
      );
    });
  }

  static Future<List<Map<String, Object?>>> datasets() async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY name",
    );
  }

  static Future<ReportBook> allData(Set<String> selected) async {
    if (selected.isEmpty) throw ArgumentError('Select at least one dataset');
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final available = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY name",
      );
      final tables = <ReportTable>[], attachments = <ReportAttachment>[];
      final raw = <String, Object?>{};
      final nameCache = <String, Map<Object?, Object?>>{};
      for (final entry in available) {
        final name = entry['name'] as String;
        if (!selected.contains(name)) continue;
        if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(name)) {
          throw StateError('Unexpected dataset name');
        }
        final info = await txn.rawQuery('PRAGMA table_info("$name")');
        final columns = info.map((row) => row['name'] as String).toList();
        final keys = info.where((r) => (r['pk'] as int) > 0).toList()
          ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
        final order = keys.isEmpty
            ? ''
            : ' ORDER BY ${keys.map((r) => '"${r['name']}"').join(',')}';
        final records = await txn.rawQuery('SELECT * FROM "$name"$order');
        final foreignKeys = await txn.rawQuery(
          'PRAGMA foreign_key_list("$name")',
        );
        final displayLinks = <(String, String, Map<Object?, Object?>)>[];
        for (final fk in foreignKeys) {
          final target = fk['table'] as String,
              sourceColumn = fk['from'] as String;
          final targetColumn = fk['to'] as String? ?? 'id';
          if (![
            target,
            sourceColumn,
            targetColumn,
          ].every((n) => RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(n))) {
            continue;
          }
          final targetInfo = await txn.rawQuery('PRAGMA table_info("$target")');
          final targetColumns = targetInfo.map((r) => r['name']).toSet();
          String? labelColumn;
          for (final candidate in [
            'name',
            'customer_name',
            'item_name',
            'employee_name',
          ]) {
            if (targetColumns.contains(candidate)) {
              labelColumn = candidate;
              break;
            }
          }
          if (labelColumn == null) continue;
          final cacheKey = '$target.$targetColumn.$labelColumn';
          if (!nameCache.containsKey(cacheKey)) {
            final linked = await txn.rawQuery(
              'SELECT "$targetColumn", "$labelColumn" FROM "$target"',
            );
            nameCache[cacheKey] = {
              for (final r in linked) r[targetColumn]: r[labelColumn],
            };
          }
          displayLinks.add((
            sourceColumn,
            '${reportHeading(sourceColumn)} · ${reportHeading(labelColumn)}',
            nameCache[cacheKey]!,
          ));
        }
        final exportRows = <List<Object?>>[],
            jsonRows = <Map<String, Object?>>[];
        for (var i = 0; i < records.length; i++) {
          final values = <Object?>[], json = <String, Object?>{};
          for (final column in columns) {
            final value = records[i][column];
            if (value is Uint8List) {
              final ext = value.length > 3 && value[0] == 137 && value[1] == 80
                  ? 'png'
                  : value.length > 2 && value[0] == 255 && value[1] == 216
                  ? 'jpg'
                  : 'bin';
              final path = 'attachments/${name}_${i + 1}_$column.$ext';
              attachments.add(ReportAttachment(path, value));
              values.add(path);
              json[column] = {'attachment': path, 'bytes': value.length};
            } else {
              values.add(value);
              json[column] = value;
            }
          }
          for (final link in displayLinks) {
            values.add(link.$3[records[i][link.$1]]);
          }
          exportRows.add(values);
          jsonRows.add(json);
        }
        tables.add(
          ReportTable(reportHeading(name), [
            ...columns.map(reportHeading),
            ...displayLinks.map((link) => link.$2),
          ], exportRows),
        );
        raw[name] = {
          'columns': info,
          'records': jsonRows,
          'foreign_keys': foreignKeys,
        };
      }
      return ReportBook(
        title: 'Complete Data Export',
        business: '${profile['name'] ?? ''}',
        filters:
            'All records in selected datasets, including VOID and drafts. '
            'Database money fields are integer minor units; currency ${AppCurrency.code}, digits ${AppCurrency.digits}. '
            'Dates and IDs retain stored values. BLOB cells refer to attachment files in Complete ZIP. '
            'This export is for reporting; it is not an automatic restore file.',
        tables: tables,
        attachments: attachments,
        rawData: raw,
      );
    });
  }
}
