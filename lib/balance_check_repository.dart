import 'voucher_permissions.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'money_posting.dart';
import 'report_models.dart';
import 'report_repository.dart';

int balanceCheckDifference(int book, int actual) {
  if (actual < 0 || actual > 9000000000000) {
    throw ArgumentError('Enter a valid actual balance, including zero');
  }
  return actual - book;
}

List<MoneyPosting> balanceCheckPlan({
  Map<String, Object?>? before,
  Map<String, Object?>? after,
  required String today,
}) {
  final old = before ?? <String, Object?>{},
      next = after ?? <String, Object?>{};
  final oldApplied = old['status'] == 'adjusted',
      newApplied = next['status'] == 'adjusted';
  if (oldApplied &&
      newApplied &&
      [
        'account_id',
        'check_date',
        'difference',
      ].every((k) => old[k] == next[k])) {
    return [];
  }
  return [
    if (oldApplied && old['difference'] != 0)
      MoneyPosting(
        old['account_id'] as int,
        -(old['difference'] as int),
        after == null ? today : old['check_date'] as String,
        after == null
            ? 'Void balance adjustment'
            : 'Reverse previous adjustment',
      ),
    if (newApplied && next['difference'] != 0)
      MoneyPosting(
        next['account_id'] as int,
        next['difference'] as int,
        next['check_date'] as String,
        'Balance adjustment',
      ),
  ];
}

void requireBalanceSnapshot({
  required int storedBook,
  required int storedEntry,
  required int currentBook,
  required int currentEntry,
}) {
  if (storedBook != currentBook || storedEntry != currentEntry) {
    throw StateError(
      'Account entries changed. Refresh the book balance and verify the actual count again.',
    );
  }
}

class BalanceCheckRepository {
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
      },
    );
  }

  static void _date(String date) {
    final value = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        value == null ||
        value.toIso8601String().substring(0, 10) != date ||
        value.year < 2000 ||
        value.isAfter(AppDateTime.today())) {
      throw ArgumentError('Choose a valid check date, today or earlier');
    }
  }

  static Future<Map<String, Object?>> _snapshot(
    DatabaseExecutor txn,
    int account,
    String date,
    int? excluding,
  ) async {
    _date(date);
    final accounts = await txn.rawQuery(
      '''SELECT a.*, b.name || ' (' || b.code || ')' AS branch_name
      FROM money_accounts a JOIN branches b ON b.id = a.branch_id WHERE a.id = ?''',
      [account],
    );
    if (accounts.length != 1) {
      throw StateError('Account no longer exists');
    }
    if (date.compareTo(accounts.single['opening_date'] as String) < 0) {
      throw StateError('Check date precedes this account opening');
    }
    final rows = await txn.rawQuery(
      '''SELECT COALESCE(SUM(amount), 0) AS book_balance,
      COALESCE(MAX(id), 0) AS snapshot_entry_id FROM money_entries
      WHERE account_id = ? AND entry_date <= ? AND (balance_check_id IS NULL OR balance_check_id != ?)''',
      [account, date, excluding ?? 0],
    );
    return {
      ...rows.single,
      'account_name': accounts.single['name'],
      'branch_name': accounts.single['branch_name'],
    };
  }

  static Future<Map<String, Object?>> snapshot(
    int account,
    String date, {
    int? excluding,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) => _snapshot(txn, account, date, excluding));
  }

  static Future<List<Map<String, Object?>>> list({
    int? branch,
    int? account,
    String? status,
    required String from,
    required String to,
    String search = '',
  }) async {
    final db = await AppDatabase.instance.database;
    final where = <String>['c.check_date >= ?', 'c.check_date <= ?'];
    final args = <Object?>[from, to];
    if (branch != null) {
      where.add('a.branch_id = ?');
      args.add(branch);
    }
    if (account != null) {
      where.add('c.account_id = ?');
      args.add(account);
    }
    if (status != null) {
      where.add('c.status = ?');
      args.add(status);
    }
    final rows = await db.rawQuery('''SELECT c.* FROM balance_checks c
      JOIN money_accounts a ON a.id = c.account_id WHERE ${where.join(' AND ')}
      ORDER BY c.check_date DESC, c.id DESC''', args);
    final query = search.trim().toLowerCase();
    return rows
        .where(
          (r) =>
              query.isEmpty ||
              '${voucherNo('BLC', r['id'])} ${r['account_name']} ${r['branch_name']} ${r['note']} ${r['adjust_reason']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  static Future<void> _post(
    Transaction txn,
    int id,
    List<MoneyPosting> legs,
    String now,
    int revision,
  ) async {
    if (legs.any((leg) => leg.amount.abs() > 9000000000000)) {
      throw StateError('Adjustment exceeds posting limit');
    }
    await validateMoneyPostings(txn, legs);
    for (final leg in legs) {
      await txn.insert('money_entries', {
        'account_id': leg.accountId,
        'kind': 'adjustment',
        'amount': leg.amount,
        'entry_date': leg.date,
        'created_at': now,
        'balance_check_id': id,
        'note': '${voucherNo('BLC', id)} · revision $revision · ${leg.label}',
      });
    }
  }

  static Future<void> _revision(
    Transaction txn,
    int id,
    String action,
    Map<String, Object?>? before,
    String now,
  ) async {
    final after = (await txn.query(
      'balance_checks',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    await txn.insert('balance_check_revisions', {
      'check_id': id,
      'action': action,
      'before_json': jsonEncode(before ?? {}),
      'after_json': jsonEncode(after),
      'recorded_at': now,
    });
  }

  static Future<int> save({
    int? id,
    int? expectedRevision,
    String? requestKey,
    required int account,
    required String date,
    required int actual,
    required int expectedBook,
    required int expectedEntry,
    required String note,
    required String reason,
  }) async {
    if (id != null) await VoucherPermissions.requireEditable();
    _date(date);
    balanceCheckDifference(expectedBook, actual);
    final clean = note.trim(), explanation = reason.trim();
    if (clean.length > 500 || explanation.length > 300) {
      throw ArgumentError('Check note/reason lengths');
    }
    if (id == null &&
        (requestKey == null || requestKey.isEmpty || requestKey.length > 200)) {
      throw ArgumentError('Missing save request key');
    }
    if (id != null && expectedRevision == null) {
      throw ArgumentError('Missing expected revision');
    }
    final payload = jsonEncode([
      account,
      date,
      actual,
      expectedBook,
      expectedEntry,
      clean,
      explanation,
    ]);
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      Map<String, Object?>? before;
      if (id == null) {
        final previous = await txn.query(
          'balance_checks',
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
          'balance_checks',
          where: "id = ? AND status != 'void' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (rows.length != 1) {
          throw StateError('Check changed. Reload before editing');
        }
        before = rows.single;
      }
      final snap = await _snapshot(txn, account, date, id);
      requireBalanceSnapshot(
        storedBook: expectedBook,
        storedEntry: expectedEntry,
        currentBook: snap['book_balance'] as int,
        currentEntry: snap['snapshot_entry_id'] as int,
      );
      final difference = balanceCheckDifference(
        snap['book_balance'] as int,
        actual,
      );
      final applied = before?['status'] == 'adjusted';
      if (applied && difference != 0 && explanation.isEmpty) {
        throw ArgumentError('Explain the applied adjustment');
      }
      final now = DateTime.now().toUtc().toIso8601String(),
          revision = before == null ? 0 : (before['revision'] as int) + 1;
      final after = <String, Object?>{
        'account_id': account,
        'account_name': snap['account_name'],
        'branch_name': snap['branch_name'],
        'check_date': date,
        'actual_balance': actual,
        'book_balance': snap['book_balance'],
        'snapshot_entry_id': snap['snapshot_entry_id'],
        'difference': difference,
        'note': clean,
        'adjust_reason': explanation,
        'status': applied ? 'adjusted' : 'open',
        'updated_at': now,
        'revision': revision,
      };
      if (applied) {
        after['applied_at'] = now;
      }
      final int saved;
      if (id == null) {
        saved = await txn.insert('balance_checks', {
          ...after,
          'request_key': requestKey,
          'request_payload': payload,
          'created_at': now,
        });
      } else {
        saved = id;
        final count = await txn.update(
          'balance_checks',
          after,
          where: "id = ? AND status != 'void' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (count != 1) {
          throw StateError('Check changed. Reload');
        }
      }
      final legs = balanceCheckPlan(before: before, after: after, today: today);
      await _post(txn, saved, legs, now, revision);
      await _revision(
        txn,
        saved,
        before == null ? 'created' : 'edited',
        before,
        now,
      );
      return saved;
    });
  }

  static Future<void> apply({
    required int id,
    required int expectedRevision,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.length > 300) {
      throw ArgumentError('Reason is too long');
    }
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'balance_checks',
        where: "id = ? AND status = 'open' AND revision = ?",
        whereArgs: [id, expectedRevision],
      );
      if (rows.length != 1) {
        throw StateError('Check changed or was already applied. Reload');
      }
      final before = rows.single;
      final snap = await _snapshot(
        txn,
        before['account_id'] as int,
        before['check_date'] as String,
        id,
      );
      requireBalanceSnapshot(
        storedBook: before['book_balance'] as int,
        storedEntry: before['snapshot_entry_id'] as int,
        currentBook: snap['book_balance'] as int,
        currentEntry: snap['snapshot_entry_id'] as int,
      );
      if (before['difference'] != 0 && clean.isEmpty) {
        throw ArgumentError('Explain the adjustment');
      }
      final now = DateTime.now().toUtc().toIso8601String(),
          revision = expectedRevision + 1;
      final after = <String, Object?>{
        ...before,
        'status': 'adjusted',
        'adjust_reason': clean,
        'applied_at': now,
        'updated_at': now,
        'revision': revision,
      };
      await _post(
        txn,
        id,
        balanceCheckPlan(before: before, after: after, today: today),
        now,
        revision,
      );
      final count = await txn.update(
        'balance_checks',
        {
          'status': 'adjusted',
          'adjust_reason': clean,
          'applied_at': now,
          'updated_at': now,
          'revision': revision,
        },
        where: "id = ? AND status = 'open' AND revision = ?",
        whereArgs: [id, expectedRevision],
      );
      if (count != 1) {
        throw StateError('Check changed. Reload');
      }
      await _revision(txn, id, 'applied', before, now);
    });
  }

  static Future<void> voidCheck({
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
      'balance_checks',
      where: "id = ? AND status != 'void' AND revision = ?",
      whereArgs: [id, expectedRevision],
    );
    if (rows.length != 1) {
      throw StateError('Check changed. Reload');
    }
    final before = rows.single, now = DateTime.now().toUtc().toIso8601String();
    final revision = expectedRevision + 1;
    await _post(
      txn,
      id,
      balanceCheckPlan(before: before, today: today),
      now,
      revision,
    );
    final count = await txn.update(
      'balance_checks',
      {
        'status': 'void',
        'void_reason': clean,
        'voided_at': now,
        'updated_at': now,
        'revision': revision,
      },
      where: "id = ? AND status != 'void' AND revision = ?",
      whereArgs: [id, expectedRevision],
    );
    if (count != 1) {
      throw StateError('Check changed. Reload');
    }
    await _revision(txn, id, 'void', before, now);
  }

  static Future<Map<String, Object?>> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'balance_checks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw StateError('Check no longer exists');
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
            'SELECT * FROM balance_checks WHERE id IN ($placeholders) ORDER BY check_date, id',
            batch,
          ),
        );
        entries.addAll(
          await txn.rawQuery(
            '''SELECT e.*, a.name AS account_name FROM money_entries e
          JOIN money_accounts a ON a.id = e.account_id WHERE e.balance_check_id IN ($placeholders)
          ORDER BY e.entry_date, e.id''',
            batch,
          ),
        );
        revisions.addAll(
          await txn.rawQuery(
            'SELECT * FROM balance_check_revisions WHERE check_id IN ($placeholders) ORDER BY check_id, id',
            batch,
          ),
        );
      }
      ReportTable raw(String name, List<Map<String, Object?>> rows) {
        final columns = rows.isEmpty
            ? ['No records']
            : rows.first.keys.toList();
        const fields = {
          'amount',
          'book_balance',
          'actual_balance',
          'difference',
        };
        final money = <int>{
          for (var i = 0; i < columns.length; i++)
            if (fields.contains(columns[i])) i,
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

      return ReportBook(
        title: unique.length == 1
            ? voucherNo('BLC', unique.single)
            : 'Balance Checks',
        business: '${profile['name'] ?? ''}',
        filters:
            '$labels | Currency ${AppCurrency.code}. '
            'These are recorded count snapshots, not live account balances. Book excludes this check own adjustments. '
            'Open checks do not change money. Adjusted checks post actual minus book on the check date. '
            'Applied edits restate the old/new effective dates; VOID reverses on action date. '
            'Revision JSON/request payloads retain stored minor units.',
        tables: [
          ReportTable(
            'Balance Checks',
            [
              'Check',
              'Date',
              'Branch',
              'Account',
              'Book before adjustment',
              'Actual counted',
              'Difference',
              'Status',
              'Adjustment reason',
              'Note',
              'Recorded UTC',
            ],
            [
              for (final r in headers)
                [
                  voucherNo('BLC', r['id']),
                  r['check_date'],
                  r['branch_name'],
                  r['account_name'],
                  reportMoney(r['book_balance'] as int),
                  reportMoney(r['actual_balance'] as int),
                  reportMoney(r['difference'] as int),
                  r['status'],
                  r['adjust_reason'],
                  r['note'],
                  r['created_at'],
                ],
            ],
            moneyColumns: {4, 5, 6},
          ),
          raw('Full Check Metadata', headers),
          raw('Account Movements', entries),
          raw('Revision History', revisions),
        ],
      );
    });
  }
}
