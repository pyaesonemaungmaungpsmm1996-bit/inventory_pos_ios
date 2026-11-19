import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_datetime.dart';

class ActivitySpec {
  const ActivitySpec(
    this.table,
    this.module,
    this.prefix, {
    this.technical = false,
    this.attachment = false,
  });
  final String table, module, prefix;
  final bool technical, attachment;
}

class ActivityStore {
  static const specs = [
    ActivitySpec('sale_invoices', 'sales', 'INV'),
    ActivitySpec('sale_returns', 'sales', 'RET'),
    ActivitySpec('customer_receipts', 'sales', 'RCPT'),
    ActivitySpec('sale_exchange_links', 'sales', 'RET'),
    ActivitySpec('purchase_invoices', 'purchases', 'PUR'),
    ActivitySpec('supplier_settlements', 'purchases', 'SET'),
    ActivitySpec('expenses', 'expenses', 'EXP'),
    ActivitySpec('stock_transfers', 'inventory', 'TRF'),
    ActivitySpec('stock_adjustments', 'inventory', 'ADJ'),
    ActivitySpec('products', 'inventory', 'ITEM'),
    ActivitySpec('money_accounts', 'money', 'ACC'),
    ActivitySpec('account_transfers', 'money', 'ACT'),
    ActivitySpec('other_money_vouchers', 'money', 'MIO'),
    ActivitySpec('balance_checks', 'money', 'BLC'),
    ActivitySpec('product_categories', 'categories', 'PCAT'),
    ActivitySpec('expense_categories', 'categories', 'ECAT'),
    ActivitySpec('other_money_categories', 'categories', 'MCAT'),
    ActivitySpec('contacts', 'contacts', 'CONTACT'),
    ActivitySpec('employees', 'users', 'EMP'),
    ActivitySpec('branches', 'settings', 'BR'),
    ActivitySpec('business_profile', 'settings', 'BUSINESS'),
    ActivitySpec('app_settings', 'settings', 'SETTING'),
    ActivitySpec('product_images', 'inventory', 'IMAGE', attachment: true),
    ActivitySpec('expense_receipts', 'expenses', 'EXP-PHOTO', attachment: true),
    ActivitySpec(
      'stock_transfer_photos',
      'inventory',
      'TRF-PHOTO',
      attachment: true,
    ),
    ActivitySpec('money_entries', 'money', 'ENTRY', technical: true),
    ActivitySpec('stock_movements', 'inventory', 'MOVE', technical: true),
    ActivitySpec('branch_stocks', 'inventory', 'STOCK', technical: true),
    ActivitySpec('sale_items', 'sales', 'INV-LINE', technical: true),
    ActivitySpec('sale_payments', 'sales', 'INV-PAY', technical: true),
    ActivitySpec('sale_return_items', 'sales', 'RET-LINE', technical: true),
    ActivitySpec('sale_return_refunds', 'sales', 'RET-PAY', technical: true),
    ActivitySpec('purchase_items', 'purchases', 'PUR-LINE', technical: true),
    ActivitySpec('purchase_payments', 'purchases', 'PUR-PAY', technical: true),
    ActivitySpec('receipt_allocations', 'sales', 'RCPT-ALLOC', technical: true),
    ActivitySpec('receipt_payments', 'sales', 'RCPT-PAY', technical: true),
    ActivitySpec(
      'supplier_settlement_payments',
      'purchases',
      'SET-PAY',
      technical: true,
    ),
    ActivitySpec('expense_payments', 'expenses', 'EXP-PAY', technical: true),
  ];
  static const captured = {
    'id',
    'name',
    'item_code',
    'item_name',
    'account_name',
    'branch_name',
    'from_account_name',
    'to_account_name',
    'from_branch_name',
    'to_branch_name',
    'type',
    'kind',
    'category',
    'category_name',
    'active',
    'status',
    'revision',
    'branch_id',
    'source_branch_id',
    'destination_branch_id',
    'account_id',
    'from_account_id',
    'to_account_id',
    'product_id',
    'customer_id',
    'supplier_id',
    'employee_id',
    'employee_name',
    'sale_id',
    'purchase_id',
    'return_id',
    'receipt_id',
    'settlement_id',
    'expense_id',
    'sale_return_id',
    'transfer_id',
    'account_transfer_id',
    'other_money_id',
    'balance_check_id',
    'customer_receipt_id',
    'supplier_settlement_id',
    'replacement_sale_id',
    'replacement_id',
    'invoice_date',
    'payment_date',
    'expense_date',
    'transfer_date',
    'check_date',
    'return_date',
    'entry_date',
    'opening_date',
    'amount',
    'total',
    'subtotal',
    'discount_amount',
    'paid',
    'balance_due',
    'price',
    'purchase_price',
    'sale_price',
    'quantity',
    'qty',
    'stock',
    'difference',
    'book_balance',
    'actual_balance',
    'snapshot_entry_id',
    'receive_required',
    'received_at',
    'applied_at',
    'voided_at',
    'void_reason',
    'adjust_reason',
    'country_code',
    'currency_code',
    'currency_digits',
    'key',
    'value',
  };
  static const ignored = {
    'request_key',
    'request_payload',
    'updated_at',
    'revision',
    'created_at',
    'confirmed_at',
    'posted_at',
  };
  static bool _private(String name) => RegExp(
    r'password|secret|token|credential|pin_hash|pin_salt',
    caseSensitive: false,
  ).hasMatch(name);
  static String q(String value) => "'${value.replaceAll("'", "''")}'";
  static String _field(String row, String col) => '$row."$col"';
  static String _id(String row, List<String> pk) =>
      pk.map((c) => 'CAST(${_field(row, c)} AS TEXT)').join(" || ':' || ");
  static String _branch(
    String table,
    String row,
    Set<String> columns,
    Set<String> tables, {
    bool peer = false,
  }) {
    if (table == 'account_transfers' && tables.contains('money_accounts')) {
      final col = peer ? 'to_account_id' : 'from_account_id';
      return '(SELECT branch_id FROM money_accounts WHERE id = ${_field(row, col)})';
    }
    if (table == 'stock_transfers') {
      return _field(row, peer ? 'destination_branch_id' : 'source_branch_id');
    }
    if (table == 'stock_transfer_photos' &&
        tables.contains('stock_transfers')) {
      return '(SELECT ${peer ? 'destination_branch_id' : 'source_branch_id'} FROM stock_transfers WHERE id = ${_field(row, 'transfer_id')})';
    }
    if (peer) return 'NULL';
    if (table == 'branches') return _field(row, 'id');
    if (columns.contains('branch_id')) return _field(row, 'branch_id');
    if (columns.contains('account_id') && tables.contains('money_accounts')) {
      return '(SELECT branch_id FROM money_accounts WHERE id = ${_field(row, 'account_id')})';
    }
    const parents = {
      'sale_items': ('sale_invoices', 'sale_id'),
      'sale_payments': ('sale_invoices', 'sale_id'),
      'purchase_items': ('purchase_invoices', 'purchase_id'),
      'purchase_payments': ('purchase_invoices', 'purchase_id'),
      'sale_return_items': ('sale_returns', 'return_id'),
      'sale_return_refunds': ('sale_returns', 'return_id'),
      'sale_exchange_links': ('sale_returns', 'return_id'),
      'receipt_allocations': ('customer_receipts', 'receipt_id'),
      'receipt_payments': ('customer_receipts', 'receipt_id'),
      'supplier_settlement_payments': ('supplier_settlements', 'settlement_id'),
      'expense_payments': ('expenses', 'expense_id'),
      'expense_receipts': ('expenses', 'expense_id'),
    };
    final parent = parents[table];
    if (parent != null && tables.contains(parent.$1)) {
      return '(SELECT branch_id FROM ${parent.$1} WHERE id = ${_field(row, parent.$2)})';
    }
    return 'NULL';
  }

  static String? _amount(ActivitySpec spec, Set<String> cols) {
    if (!{
      'sales',
      'purchases',
      'expenses',
      'money',
      'inventory',
    }.contains(spec.module)) {
      return null;
    }
    if (spec.module == 'inventory' && spec.table != 'products') return null;
    for (final col in ['total', 'amount', 'price', 'difference']) {
      if (cols.contains(col)) return col;
    }
    return null;
  }

  static String _summary(
    String row,
    Set<String> cols, {
    bool settings = false,
  }) {
    final parts = <String>[];
    for (final col in cols.where((c) => captured.contains(c) && !_private(c))) {
      if (col == 'value' && !settings) continue;
      parts.add(
        '${q('$col=')} || COALESCE(CAST(${_field(row, col)} AS TEXT), ${q('<null>')}) || char(10)',
      );
    }
    for (final col in ['photo', 'image']) {
      if (cols.contains(col)) {
        parts.add(
          '${q('${col}_bytes=')} || COALESCE(length(${_field(row, col)}), 0) || char(10)',
        );
      }
    }
    return parts.isEmpty ? q('No scalar summary') : parts.join(' || ');
  }

  static List<String> triggers(
    ActivitySpec spec,
    List<Map<String, Object?>> info,
    Set<String> tables,
  ) {
    final cols = info.map((r) => r['name'] as String).toSet();
    final keys = info.where((r) => (r['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    final pk = keys.map((r) => r['name'] as String).toList();
    if (pk.isEmpty) return [];
    if (![
      spec.table,
      ...cols,
    ].every((s) => RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(s))) {
      throw StateError('Unexpected audit identifier');
    }
    final mutable = cols
        .where((c) => !ignored.contains(c) && !_private(c))
        .toList();
    final changed = mutable
        .map((c) => '${_field('OLD', c)} IS NOT ${_field('NEW', c)}')
        .join(' OR ');
    final changeFields = mutable
        .map(
          (c) =>
              'CASE WHEN ${_field('OLD', c)} IS NOT ${_field('NEW', c)} THEN ${q('$c, ')} ELSE ${q('')} END',
        )
        .join(' || ');
    final amount = _amount(spec, cols);
    final commands = <String>[];
    for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = operation == 'DELETE' ? 'OLD' : 'NEW';
      String action = q(
        operation == 'INSERT'
            ? 'create'
            : operation == 'DELETE'
            ? 'delete'
            : 'update',
      );
      if (spec.attachment) {
        action = q(
          operation == 'INSERT'
              ? 'attach'
              : operation == 'DELETE'
              ? 'remove_attachment'
              : 'replace_attachment',
        );
      }
      if (spec.table == 'sale_exchange_links') {
        action = q(operation == 'DELETE' ? 'unlink' : 'link');
      }
      if (operation == 'UPDATE' && !spec.attachment) {
        final cases = <String>[];
        if (cols.contains('status')) {
          cases.add(
            "WHEN OLD.status IS NOT NEW.status AND NEW.status = 'void' THEN 'void'",
          );
          cases.add(
            "WHEN OLD.status IS NOT NEW.status AND NEW.status = 'adjusted' THEN 'apply'",
          );
        }
        if (cols.contains('received_at')) {
          cases.add(
            "WHEN OLD.received_at IS NULL AND NEW.received_at IS NOT NULL THEN 'receive'",
          );
        }
        if (cols.contains('active')) {
          cases.add("WHEN OLD.active = 1 AND NEW.active = 0 THEN 'archive'");
          cases.add("WHEN OLD.active = 0 AND NEW.active = 1 THEN 'restore'");
        }
        if (spec.module == 'categories' && cols.contains('name')) {
          cases.add("WHEN OLD.name IS NOT NEW.name THEN 'rename'");
        }
        if (cols.contains('replacement_id')) {
          cases.add(
            "WHEN OLD.replacement_id IS NOT NEW.replacement_id AND NEW.replacement_id IS NOT NULL THEN 'correct'",
          );
        }
        if (cases.isNotEmpty) {
          action = 'CASE ${cases.join(' ')} ELSE $action END';
        }
      }
      final filters = <String>[];
      if (operation == 'UPDATE') {
        filters.add(changed.isEmpty ? '0' : '($changed)');
      }
      if (spec.table == 'app_settings') {
        filters.add("$row.key IN ('default_branch', 'business_timezone')");
      }
      final condition = filters.isEmpty ? '' : 'WHEN ${filters.join(' AND ')}';
      final before = operation == 'INSERT'
          ? q('')
          : _summary('OLD', cols, settings: spec.table == 'app_settings');
      final after = operation == 'DELETE'
          ? q('')
          : _summary('NEW', cols, settings: spec.table == 'app_settings');
      final integerKey =
          pk.length == 1 &&
          info.any(
            (r) =>
                r['name'] == pk.single &&
                '${r['type']}'.toUpperCase().contains('INT'),
          );
      final keyText = integerKey
          ? "printf('%06d', ${_field(row, pk.single)})"
          : _id(row, pk);
      var reference = spec.table == 'products' && cols.contains('item_code')
          ? "COALESCE(NULLIF(${_field(row, 'item_code')}, ''), ${q('${spec.prefix}-')} || $keyText)"
          : '${q('${spec.prefix}-')} || $keyText';
      if (spec.technical || spec.attachment) {
        final cases = <String>[];
        for (final link in [
          ('balance_check_id', 'BLC'),
          ('other_money_id', 'MIO'),
          ('account_transfer_id', 'ACT'),
          ('customer_receipt_id', 'RCPT'),
          ('supplier_settlement_id', 'SET'),
          ('expense_id', 'EXP'),
          ('sale_return_id', 'RET'),
          ('return_id', 'RET'),
          ('receipt_id', 'RCPT'),
          ('settlement_id', 'SET'),
          ('sale_id', 'INV'),
          ('purchase_id', 'PUR'),
          ('transfer_id', 'TRF'),
          ('product_id', 'ITEM'),
        ]) {
          if (cols.contains(link.$1)) {
            cases.add(
              "WHEN ${_field(row, link.$1)} IS NOT NULL THEN ${q('${link.$2}-')} || printf('%06d', ${_field(row, link.$1)}) || ' / ' || $reference",
            );
          }
        }
        if (cases.isNotEmpty) {
          reference = 'CASE ${cases.join(' ')} ELSE $reference END';
        }
      }
      final beforeAmount = operation == 'INSERT' || amount == null
          ? 'NULL'
          : _field('OLD', amount);
      final afterAmount = operation == 'DELETE' || amount == null
          ? 'NULL'
          : _field('NEW', amount);
      final currency = amount != null && tables.contains('business_profile')
          ? '(SELECT currency_code FROM business_profile WHERE id = 1)'
          : 'NULL';
      commands.add(
        '''CREATE TRIGGER activity_${spec.table}_${operation.toLowerCase()}
        AFTER $operation ON "${spec.table}" $condition BEGIN
        INSERT INTO activity_events(event_key, source_table, record_id, reference, module, action,
          branch_id, peer_branch_id, actor_id, actor_name, event_at, event_ms, origin, technical,
          changed_fields, before_summary, after_summary, amount_field, amount_before, amount_after, currency_code)
        VALUES(lower(hex(randomblob(16))), ${q(spec.table)}, ${_id(row, pk)}, $reference,
          ${q(spec.module)}, $action, ${_branch(spec.table, row, cols, tables)},
          ${_branch(spec.table, row, cols, tables, peer: true)},
          (SELECT actor_id FROM activity_context WHERE id = 1),
          COALESCE((SELECT actor_name FROM activity_context WHERE id = 1), 'Not recorded'),
          strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
          CAST(strftime('%s', 'now') AS INTEGER) * 1000 + CAST(substr(strftime('%f', 'now'), 4, 3) AS INTEGER),
          'tracked', ${spec.technical ? 1 : 0},
          ${operation == 'UPDATE' && changeFields.isNotEmpty ? "rtrim($changeFields, ', ')" : q(operation.toLowerCase())},
          $before, $after, ${amount == null ? 'NULL' : q(amount)}, $beforeAmount, $afterAmount, $currency);
        END''',
      );
    }
    return commands;
  }

  static Future<void> install(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE activity_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, event_key TEXT NOT NULL UNIQUE,
      source_table TEXT NOT NULL, record_id TEXT NOT NULL, reference TEXT NOT NULL,
      module TEXT NOT NULL, action TEXT NOT NULL, branch_id INTEGER, peer_branch_id INTEGER,
      actor_id INTEGER, actor_name TEXT NOT NULL DEFAULT 'Not recorded',
      event_at TEXT NOT NULL, event_ms INTEGER NOT NULL, origin TEXT NOT NULL,
      technical INTEGER NOT NULL DEFAULT 0 CHECK(technical IN (0,1)),
      changed_fields TEXT NOT NULL DEFAULT '', before_summary TEXT NOT NULL DEFAULT '',
      after_summary TEXT NOT NULL DEFAULT '', amount_field TEXT, amount_before INTEGER,
      amount_after INTEGER, currency_code TEXT
    )''');
    await db.execute(
      'CREATE INDEX activity_time ON activity_events(event_ms DESC, id DESC)',
    );
    await db.execute(
      'CREATE INDEX activity_module_time ON activity_events(module, event_ms DESC)',
    );
    await db.execute('''CREATE TABLE activity_context (
      id INTEGER PRIMARY KEY CHECK(id = 1), actor_id INTEGER,
      actor_name TEXT NOT NULL DEFAULT 'Not recorded'
    )''');
    await db.insert('activity_context', {
      'id': 1,
      'actor_name': 'Not recorded',
    });
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = tableRows.map((r) => r['name'] as String).toSet();
    for (final spec in specs.where((s) => tables.contains(s.table))) {
      final info = await db.rawQuery('PRAGMA table_info("${spec.table}")');
      for (final sql in triggers(spec, info, tables)) {
        await db.execute(sql);
      }
    }
    await append(
      db,
      key: 'system:tracking_started',
      source: 'activity_events',
      record: 'start',
      reference: 'Tracking started',
      module: 'system',
      action: 'tracking_started',
      origin: 'system',
      after: 'Database activity tracking starts here. Older rows are imported only from saved history or creation/void time metadata. Actor identity was not previously recorded.',
    );
    await _import(db, tables);
  }

  static Future<void> append(
    DatabaseExecutor db, {
    required String key,
    required String source,
    required String record,
    required String reference,
    required String module,
    required String action,
    required String origin,
    String before = '',
    String after = '',
    String fields = '',
    DateTime? at,
    int? branch,
    int? peer,
    String actor = 'Not recorded',
    int? actorId,
    String? amountField,
    int? amountBefore,
    int? amountAfter,
    String? currency,
  }) async {
    final time = at ?? DateTime.now().toUtc();
    await db.insert('activity_events', {
      'event_key': key,
      'source_table': source,
      'record_id': record,
      'reference': reference,
      'module': module,
      'action': action,
      'origin': origin,
      'event_at': time.toUtc().toIso8601String(),
      'event_ms': time.millisecondsSinceEpoch,
      'branch_id': branch,
      'peer_branch_id': peer,
      'actor_id': actorId,
      'actor_name': actor,
      'changed_fields': fields,
      'before_summary': before,
      'after_summary': after,
      'amount_field': amountField,
      'amount_before': amountBefore,
      'amount_after': amountAfter,
      'currency_code': currency,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static String _plain(Map<String, Object?> row) => row.entries
      .where((e) => captured.contains(e.key) && !_private(e.key))
      .map((e) => '${e.key}=${e.value ?? '<null>'}')
      .join('\n');
  static int? _integer(Object? value) => value is int ? value : null;
  static DateTime? _time(Object? value) => AppDateTime.parse(value);
  static Map<String, Object?> _json(Object? value) {
    try {
      final row = jsonDecode(value as String);
      return row is Map ? Map<String, Object?>.from(row) : {};
    } catch (_) {
      return {};
    }
  }

  static String _action(String value) => switch (value) {
    'created' => 'create',
    'edited' => 'update',
    'applied' => 'apply',
    'renamed' => 'rename',
    'archived' => 'archive',
    'restored' => 'restore',
    'deleted' => 'delete',
    _ => value,
  };
  static Future<void> _import(DatabaseExecutor db, Set<String> tables) async {
    var skipped = 0;
    final covered = <String>{};
    final history = [
      (
        'account_transfer_revisions',
        'transfer_id',
        'recorded_at',
        'money',
        'ACT',
      ),
      ('other_money_revisions', 'voucher_id', 'recorded_at', 'money', 'MIO'),
      ('balance_check_revisions', 'check_id', 'recorded_at', 'money', 'BLC'),
      (
        'stock_transfer_revisions',
        'transfer_id',
        'changed_at',
        'inventory',
        'TRF',
      ),
      ('expense_edits', 'expense_id', 'changed_at', 'expenses', 'EXP'),
      (
        'opening_balance_corrections',
        'account_id',
        'created_at',
        'money',
        'ACC',
      ),
      ('category_changes', 'category_id', 'recorded_at', 'categories', 'CAT'),
    ];
    for (final spec in history.where((s) => tables.contains(s.$1))) {
      final rows = await db.query(spec.$1, orderBy: 'id');
      for (final row in rows) {
        final time = _time(row[spec.$3]);
        if (time == null) {
          skipped++;
          continue;
        }
        Map<String, Object?> before = {}, after = {};
        String action = _action(row['action'] as String? ?? 'update');
        if (row.containsKey('before_json')) {
          before = _json(row['before_json']);
          after = _json(row['after_json']);
        } else if (spec.$1 == 'stock_transfer_revisions') {
          before = _json(row['previous_data']);
        } else if (spec.$1 == 'expense_edits') {
          before = {
            'category': row['previous_category'],
            'account_id': row['previous_account_id'],
            'amount': row['previous_amount'],
            'expense_date': row['previous_expense_date'],
          };
          after = {
            'category': row['category'],
            'account_id': row['account_id'],
            'amount': row['amount'],
            'expense_date': row['expense_date'],
          };
          if (row['receipt_action'] != 'unchanged') action = 'attachment';
        } else if (spec.$1 == 'category_changes') {
          before = {'name': row['before_name'], 'active': row['before_active']};
          after = {'name': row['after_name'], 'active': row['after_active']};
        } else if (spec.$1 == 'opening_balance_corrections') {
          before = {'amount': row['previous_amount']};
          after = {'amount': row['new_amount']};
          action = 'adjust';
        }
        int? branch =
            _integer(row['branch_id']) ??
            _integer(after['branch_id']) ??
            _integer(before['branch_id']);
        int? peer;
        if (spec.$1 == 'stock_transfer_revisions') {
          branch = _integer(before['source_branch_id']);
          peer = _integer(before['destination_branch_id']);
        }
        final record = '${row[spec.$2]}';
        if (branch == null) {
          if (spec.$1 == 'expense_edits' && tables.contains('expenses')) {
            final parents = await db.query(
              'expenses',
              columns: ['branch_id'],
              where: 'id = ?',
              whereArgs: [row['expense_id']],
            );
            if (parents.isNotEmpty) {
              branch = parents.single['branch_id'] as int?;
            }
          }
        }
        final prefix = spec.$1 == 'category_changes'
            ? switch (row['category_kind']) {
                'product' => 'PCAT',
                'expense' => 'ECAT',
                _ => 'MCAT',
              }
            : spec.$5;
        await append(
          db,
          key: 'legacy:${spec.$1}:${row['id']}',
          source: spec.$1,
          record: record,
          reference: '$prefix-${record.padLeft(6, '0')}',
          module: spec.$4,
          action: action,
          origin: 'saved_history',
          at: time,
          branch: branch,
          peer: peer,
          before: _plain(before),
          after: after.isEmpty
              ? 'After values not captured in this original log.'
              : _plain(after),
          fields:
              'Imported saved revision; original actor identity unavailable.',
        );
        final parent = switch (spec.$1) {
          'account_transfer_revisions' => 'account_transfers',
          'other_money_revisions' => 'other_money_vouchers',
          'balance_check_revisions' => 'balance_checks',
          _ => null,
        };
        if (parent != null && (action == 'create' || action == 'void')) {
          covered.add(
            '$parent:$record:${action == 'create' ? 'record_created' : action}',
          );
        }
      }
    }
    // Existing creation/VOID timestamps are evidence of time only, not an original field snapshot.
    for (final spec in specs.where(
      (s) => !s.technical && !s.attachment && tables.contains(s.table),
    )) {
      final info = await db.rawQuery('PRAGMA table_info("${spec.table}")');
      final cols = info.map((r) => r['name'] as String).toSet();
      if (!cols.contains('id')) continue;
      String? created;
      for (final col in ['created_at', 'confirmed_at', 'posted_at']) {
        if (cols.contains(col)) {
          created = col;
          break;
        }
      }
      if (created == null &&
          !cols.contains('voided_at') &&
          !cols.contains('received_at')) {
        continue;
      }
      final rows = await db.rawQuery(
        '''SELECT r.*, ${_branch(spec.table, 'r', cols, tables)} AS audit_branch,
        ${_branch(spec.table, 'r', cols, tables, peer: true)} AS audit_peer FROM "${spec.table}" r''',
      );
      for (final row in rows) {
        for (final item in [
          (created, 'record_created'),
          (cols.contains('voided_at') ? 'voided_at' : null, 'void'),
          (cols.contains('received_at') ? 'received_at' : null, 'receive'),
        ]) {
          if (item.$1 == null ||
              row[item.$1] == null ||
              covered.contains('${spec.table}:${row['id']}:${item.$2}')) {
            continue;
          }
          final time = _time(row[item.$1]);
          if (time == null) {
            skipped++;
            continue;
          }
          await append(
            db,
            key: 'metadata:${spec.table}:${row['id']}:${item.$2}',
            source: spec.table,
            record: '${row['id']}',
            reference: '${spec.prefix}-${row['id'].toString().padLeft(6, '0')}',
            module: spec.module,
            action: item.$2,
            origin: 'timestamp_only',
            at: time,
            branch: row['audit_branch'] as int?,
            peer: row['audit_peer'] as int?,
            after:
                'Existing ${item.$1} timestamp. Original field values and actor were not captured; current values may differ. Branch linkage reflects the current record.',
          );
        }
      }
    }
    if (skipped > 0) {
      await append(
        db,
        key: 'system:unreadable_legacy_times',
        source: 'activity_events',
        record: 'import',
        reference: 'Legacy import note',
        module: 'system',
        action: 'import_note',
        origin: 'system',
        after:
            '$skipped older records lacked a valid timezone-qualified timestamp. They were not assigned invented dates. Original datasets remain available in Data Export.',
      );
    }
  }
}
