import 'voucher_permissions.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_currency.dart';
import 'category_store.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'money_posting.dart';
import 'report_models.dart';
import 'report_repository.dart';

int otherMoneySigned(Map<String, Object?> row) =>
    row['direction'] == 'in' ? row['amount'] as int : -(row['amount'] as int);

List<MoneyPosting> otherMoneyPlan({
  Map<String, Object?>? before,
  Map<String, Object?>? after,
  required String today,
}) {
  if (before != null &&
      after != null &&
      [
        'account_id',
        'direction',
        'amount',
        'entry_date',
      ].every((k) => before[k] == after[k])) {
    return [];
  }
  String label(Map<String, Object?> row, String action) =>
      '$action · ${row['category'] ?? ''}: ${row['description'] ?? ''}';
  return [
    if (before != null)
      MoneyPosting(
        before['account_id'] as int,
        -otherMoneySigned(before),
        after == null ? today : before['entry_date'] as String,
        label(before, after == null ? 'Void reversal' : 'Edit reversal'),
      ),
    if (after != null)
      MoneyPosting(
        after['account_id'] as int,
        otherMoneySigned(after),
        after['entry_date'] as String,
        label(after, before == null ? 'Original entry' : 'Edited entry'),
      ),
  ];
}

class OtherMoneyRepository {
  static String get today =>
      AppDateTime.today().toIso8601String().substring(0, 10);
  static Future<Map<String, List<Map<String, Object?>>>> options() async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) async => {
        'branches': await txn.query('branches', orderBy: 'name, id'),
        'accounts': await txn.rawQuery(
          '''SELECT a.*, b.name || ' (' || b.code || ')' AS branch_name,
        COALESCE((SELECT SUM(e.amount) FROM money_entries e WHERE e.account_id = a.id), 0) AS balance
        FROM money_accounts a JOIN branches b ON b.id = a.branch_id ORDER BY b.name, a.name, a.id''',
        ),
        'categories': await txn.query(
          'other_money_categories',
          orderBy: 'name COLLATE NOCASE',
        ),
        'category_filters': await txn.rawQuery(
          'SELECT name FROM other_money_categories UNION SELECT category AS name FROM other_money_vouchers ORDER BY name COLLATE NOCASE',
        ),
      },
    );
  }

  static Future<List<Map<String, Object?>>> list({
    int? branch,
    int? account,
    String? direction,
    String? category,
    required String from,
    required String to,
    String search = '',
    bool includeVoid = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final where = <String>['v.entry_date >= ?', 'v.entry_date <= ?'];
    final args = <Object?>[from, to];
    if (branch != null) {
      where.add('a.branch_id = ?');
      args.add(branch);
    }
    if (account != null) {
      where.add('v.account_id = ?');
      args.add(account);
    }
    if (direction != null) {
      where.add('v.direction = ?');
      args.add(direction);
    }
    if (category != null) {
      where.add('v.category COLLATE NOCASE = ?');
      args.add(category);
    }
    if (!includeVoid) {
      where.add("v.status = 'posted'");
    }
    final rows = await db.rawQuery('''SELECT v.* FROM other_money_vouchers v
      JOIN money_accounts a ON a.id = v.account_id WHERE ${where.join(' AND ')}
      ORDER BY v.entry_date DESC, v.id DESC''', args);
    final query = search.trim().toLowerCase();
    return rows
        .where(
          (r) =>
              query.isEmpty ||
              '${voucherNo('MIO', r['id'])} ${r['account_name']} ${r['branch_name']} ${r['category']} ${r['description']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  static void _validate(
    int account,
    String direction,
    int amount,
    String date,
    String category,
    String description,
  ) {
    if (account <= 0 || !{'in', 'out'}.contains(direction)) {
      throw ArgumentError('Choose an account and money direction');
    }
    if (amount < 1 || amount > 9000000000000) {
      throw ArgumentError('Enter a valid amount');
    }
    if (category.isEmpty || category.length > 80 || description.length > 500) {
      throw ArgumentError('Check category and description lengths');
    }
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        parsed.year < 2000 ||
        parsed.isAfter(AppDateTime.today())) {
      throw ArgumentError('Choose a valid date, today or earlier');
    }
  }

  static Future<void> _post(
    Transaction txn,
    int id,
    List<MoneyPosting> legs,
    String now,
    int revision,
  ) async {
    for (final leg in legs) {
      await txn.insert('money_entries', {
        'account_id': leg.accountId,
        'kind': leg.amount > 0 ? 'receipt' : 'payment',
        'amount': leg.amount,
        'entry_date': leg.date,
        'created_at': now,
        'other_money_id': id,
        'note': '${voucherNo('MIO', id)} · revision $revision · ${leg.label}',
      });
    }
  }

  static Future<int> save({
    int? id,
    int? expectedRevision,
    String? requestKey,
    required int account,
    required String direction,
    required int amount,
    required String date,
    required String category,
    required String description,
  }) async {
    if (id != null) await VoucherPermissions.requireEditable();
    final cleanCategory = category.trim(),
        cleanDescription = description.trim();
    _validate(
      account,
      direction,
      amount,
      date,
      cleanCategory,
      cleanDescription,
    );
    if (id == null &&
        (requestKey == null || requestKey.isEmpty || requestKey.length > 200)) {
      throw ArgumentError('Missing save request key');
    }
    if (id != null && expectedRevision == null) {
      throw ArgumentError('Missing expected revision');
    }
    final payload = jsonEncode([
      account,
      direction,
      amount,
      date,
      cleanCategory,
      cleanDescription,
    ]);
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      Map<String, Object?>? before;
      if (id == null) {
        final previous = await txn.query(
          'other_money_vouchers',
          where: 'request_key = ?',
          whereArgs: [requestKey],
        );
        if (previous.isNotEmpty) {
          if (previous.single['request_payload'] != payload) {
            throw StateError('Save request was reused with different data');
          }
          return previous.single['id'] as int;
        }
      } else {
        final rows = await txn.query(
          'other_money_vouchers',
          where: "id = ? AND status = 'posted' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (rows.length != 1) {
          throw StateError('Voucher changed. Reload before editing');
        }
        before = rows.single;
      }
      final accounts = await txn.rawQuery(
        '''SELECT a.*, b.name || ' (' || b.code || ')' AS branch_name
        FROM money_accounts a JOIN branches b ON b.id = a.branch_id WHERE a.id = ?''',
        [account],
      );
      if (accounts.length != 1) {
        throw StateError('Account no longer exists');
      }
      if (date.compareTo(accounts.single['opening_date'] as String) < 0) {
        throw StateError('Date precedes this account opening');
      }
      final canonical = await CategoryStore.ensureOtherMoneyName(
        txn,
        cleanCategory,
        previousName: before?['category'] as String?,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final revision = before == null ? 0 : (before['revision'] as int) + 1;
      final after = <String, Object?>{
        'account_id': account,
        'direction': direction,
        'amount': amount,
        'entry_date': date,
        'category': canonical,
        'description': cleanDescription,
        'account_name': accounts.single['name'],
        'branch_name': accounts.single['branch_name'],
        'revision': revision,
        'updated_at': now,
      };
      final legs = otherMoneyPlan(before: before, after: after, today: today);
      await validateMoneyPostings(txn, legs);
      final int saved;
      if (id == null) {
        saved = await txn.insert('other_money_vouchers', {
          ...after,
          'request_key': requestKey,
          'request_payload': payload,
          'created_at': now,
        });
      } else {
        saved = id;
        final count = await txn.update(
          'other_money_vouchers',
          after,
          where: "id = ? AND status = 'posted' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (count != 1) {
          throw StateError('Voucher changed. Reload');
        }
      }
      await _post(txn, saved, legs, now, revision);
      final header = (await txn.query(
        'other_money_vouchers',
        where: 'id = ?',
        whereArgs: [saved],
      )).single;
      await txn.insert('other_money_revisions', {
        'voucher_id': saved,
        'action': before == null ? 'created' : 'edited',
        'before_json': jsonEncode(before ?? {}),
        'after_json': jsonEncode(header),
        'recorded_at': now,
      });
      return saved;
    });
  }

  static Future<void> voidVoucher({
    required int id,
    required int expectedRevision,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Enter a reason for void');
    }
    final db = await AppDatabase.instance.database;
    await db.transaction(
      (txn) => voidForDelete(txn, id, expectedRevision, clean),
    );
  }

  static Future<void> voidForDelete(
    Transaction txn,
    int id,
    int expectedRevision,
    String clean,
  ) async {
    final rows = await txn.query(
      'other_money_vouchers',
      where: "id = ? AND status = 'posted' AND revision = ?",
      whereArgs: [id, expectedRevision],
    );
    if (rows.length != 1) {
      throw StateError('Voucher changed. Reload');
    }
    final before = rows.single, now = DateTime.now().toUtc().toIso8601String();
    final revision = expectedRevision + 1;
    final legs = otherMoneyPlan(before: before, today: today);
    await validateMoneyPostings(txn, legs);
    await _post(txn, id, legs, now, revision);
    final count = await txn.update(
      'other_money_vouchers',
      {
        'status': 'void',
        'void_reason': clean,
        'voided_at': now,
        'updated_at': now,
        'revision': revision,
      },
      where: "id = ? AND status = 'posted' AND revision = ?",
      whereArgs: [id, expectedRevision],
    );
    if (count != 1) {
      throw StateError('Voucher changed. Reload');
    }
    final header = (await txn.query(
      'other_money_vouchers',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    await txn.insert('other_money_revisions', {
      'voucher_id': id,
      'action': 'void',
      'before_json': jsonEncode(before),
      'after_json': jsonEncode(header),
      'recorded_at': now,
    });
  }

  static Future<Map<String, Object?>> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'other_money_vouchers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw StateError('Voucher no longer exists');
    }
    return rows.single;
  }

  static Future<ReportBook> report(List<int> ids, String labels) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final headers = <Map<String, Object?>>[],
          entries = <Map<String, Object?>>[],
          revisions = <Map<String, Object?>>[];
      final unique = ids.toSet().toList();
      for (var offset = 0; offset < unique.length; offset += 400) {
        final batch = unique.skip(offset).take(400).toList();
        final placeholders = List.filled(batch.length, '?').join(',');
        headers.addAll(
          await txn.rawQuery(
            'SELECT * FROM other_money_vouchers WHERE id IN ($placeholders) ORDER BY entry_date, id',
            batch,
          ),
        );
        entries.addAll(
          await txn.rawQuery(
            '''SELECT e.*, a.name AS account_name FROM money_entries e
          JOIN money_accounts a ON a.id = e.account_id WHERE e.other_money_id IN ($placeholders)
          ORDER BY e.entry_date, e.id''',
            batch,
          ),
        );
        revisions.addAll(
          await txn.rawQuery(
            'SELECT * FROM other_money_revisions WHERE voucher_id IN ($placeholders) ORDER BY voucher_id, id',
            batch,
          ),
        );
      }
      ReportTable raw(String name, List<Map<String, Object?>> rows) {
        final columns = rows.isEmpty
            ? ['No records']
            : rows.first.keys.toList();
        final money = <int>{
          for (var i = 0; i < columns.length; i++)
            if (columns[i] == 'amount') i,
        };
        return ReportTable(name, columns.map(reportHeading).toList(), [
          for (final row in rows)
            [
              for (var i = 0; i < columns.length; i++)
                money.contains(i)
                    ? reportMoney(row[columns[i]] as int)
                    : row[columns[i]],
            ],
        ], moneyColumns: money);
      }

      var income = 0, out = 0;
      for (final row in headers.where((r) => r['status'] == 'posted')) {
        if (row['direction'] == 'in') {
          income += row['amount'] as int;
        } else {
          out += row['amount'] as int;
        }
      }
      return ReportBook(
        title: unique.length == 1
            ? voucherNo('MIO', unique.single)
            : 'Other Money In / Out',
        business: '${profile['name'] ?? ''}',
        filters:
            '$labels | Currency ${AppCurrency.code}. '
            'Summary uses current POSTED voucher amounts by voucher date; it is not a historical account statement. '
            'Cash/Bank/Wallet Ledger shows historical balances and all reversals. '
            'These entries affect accounts only, not Sales/Expense summary totals or stock. '
            'Revision JSON/request payloads retain database minor units.',
        tables: [
          ReportTable(
            'Current Posted Voucher Summary',
            ['Metric', 'Amount'],
            [
              ['Money in', reportMoney(income)],
              ['Money out', reportMoney(out)],
              ['Net movement', reportMoney(income - out)],
            ],
            moneyColumns: {1},
          ),
          ReportTable(
            'Money Vouchers',
            [
              'Voucher',
              'Date',
              'Branch',
              'Account',
              'Direction',
              'Category',
              'Description',
              'Amount',
              'Status',
            ],
            [
              for (final r in headers)
                [
                  voucherNo('MIO', r['id']),
                  r['entry_date'],
                  r['branch_name'],
                  r['account_name'],
                  r['direction'],
                  r['category'],
                  r['description'],
                  reportMoney(r['amount'] as int),
                  r['status'],
                ],
            ],
            moneyColumns: {7},
          ),
          raw('Full Voucher Metadata', headers),
          raw('Account Movements', entries),
          raw('Revision History', revisions),
        ],
      );
    });
  }
}
