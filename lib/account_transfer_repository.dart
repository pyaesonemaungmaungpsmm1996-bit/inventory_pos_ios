import 'voucher_permissions.dart';

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'report_models.dart';
import 'report_repository.dart';

class AccountTransferLeg {
  const AccountTransferLeg(this.accountId, this.amount, this.date, this.label);
  final int accountId, amount;
  final String date, label;
}

List<AccountTransferLeg> accountTransferPlan({
  Map<String, Object?>? before,
  Map<String, Object?>? after,
  required String today,
}) {
  if (before != null &&
      after != null &&
      [
        'from_account_id',
        'to_account_id',
        'amount',
        'transfer_date',
      ].every((k) => before[k] == after[k])) {
    return [];
  }
  final legs = <AccountTransferLeg>[];
  if (before != null) {
    final date = after == null ? today : before['transfer_date'] as String;
    final amount = before['amount'] as int;
    legs.add(
      AccountTransferLeg(
        before['from_account_id'] as int,
        amount,
        date,
        after == null ? 'Void reversal' : 'Edit reversal',
      ),
    );
    legs.add(
      AccountTransferLeg(
        before['to_account_id'] as int,
        -amount,
        date,
        after == null ? 'Void reversal' : 'Edit reversal',
      ),
    );
  }
  if (after != null) {
    final amount = after['amount'] as int,
        date = after['transfer_date'] as String;
    legs.add(
      AccountTransferLeg(
        after['from_account_id'] as int,
        -amount,
        date,
        before == null ? 'Transfer out' : 'Edited transfer out',
      ),
    );
    legs.add(
      AccountTransferLeg(
        after['to_account_id'] as int,
        amount,
        date,
        before == null ? 'Transfer in' : 'Edited transfer in',
      ),
    );
  }
  return legs;
}

Map<int, int> accountTransferNet(List<AccountTransferLeg> legs) {
  final net = <int, int>{};
  for (final leg in legs) {
    net[leg.accountId] = (net[leg.accountId] ?? 0) + leg.amount;
  }
  if (net.values.fold<int>(0, (sum, amount) => sum + amount) != 0) {
    throw StateError('Transfer must balance');
  }
  return net;
}

class AccountTransferRepository {
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

  static Future<List<Map<String, Object?>>> list({
    int? branch,
    required String from,
    required String to,
    String search = '',
    bool includeVoid = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      '''SELECT t.* FROM account_transfers t
      JOIN money_accounts f ON f.id = t.from_account_id JOIN money_accounts a ON a.id = t.to_account_id
      WHERE t.transfer_date >= ? AND t.transfer_date <= ?
        AND (? IS NULL OR f.branch_id = ? OR a.branch_id = ?)
        AND (? = 1 OR t.status = 'posted') ORDER BY t.transfer_date DESC, t.id DESC''',
      [from, to, branch, branch, branch, includeVoid ? 1 : 0],
    );
    final query = search.trim().toLowerCase();
    return rows
        .where(
          (r) =>
              query.isEmpty ||
              '${voucherNo('ACT', r['id'])} ${r['from_account_name']} ${r['to_account_name']} ${r['from_branch_name']} ${r['to_branch_name']} ${r['note']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  static void _validate(
    int from,
    int to,
    int amount,
    String date,
    String note,
  ) {
    final parsed = DateTime.tryParse(date);
    if (from <= 0 || to <= 0 || from == to) {
      throw ArgumentError('Choose two different accounts');
    }
    if (amount < 1 || amount > 9000000000000) {
      throw ArgumentError('Enter a valid transfer amount');
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        parsed.year < 2000 ||
        parsed.isAfter(AppDateTime.today())) {
      throw ArgumentError('Choose a valid transfer date, today or earlier');
    }
    if (note.length > 500) throw ArgumentError('Note is too long');
  }

  static Future<Map<String, Object?>> _account(Transaction txn, int id) async {
    final rows = await txn.rawQuery(
      '''SELECT a.*, b.name || ' (' || b.code || ')' AS branch_name
      FROM money_accounts a JOIN branches b ON b.id = a.branch_id WHERE a.id = ?''',
      [id],
    );
    if (rows.length != 1) throw StateError('Account no longer exists');
    return rows.single;
  }

  static Future<void> _checkBalances(
    Transaction txn,
    List<AccountTransferLeg> legs,
  ) async {
    for (final pair in accountTransferNet(legs).entries) {
      final account = await _account(txn, pair.key);
      final rows = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS balance FROM money_entries WHERE account_id = ?',
        [pair.key],
      );
      final after = (rows.single['balance'] as int) + pair.value;
      if (after < 0) {
        throw StateError(
          'Insufficient balance in ${account['name']}. Funds already used may need to be restored before editing or voiding.',
        );
      }
      if (after > 9000000000000) {
        throw StateError('Account balance limit exceeded');
      }
      final changes = <String, int>{};
      for (final leg in legs.where((leg) => leg.accountId == pair.key)) {
        changes[leg.date] = (changes[leg.date] ?? 0) + leg.amount;
      }
      changes.removeWhere((_, amount) => amount == 0);
      if (changes.isEmpty) continue;
      final earliest = (changes.keys.toList()..sort()).first;
      final history = await txn.rawQuery(
        'SELECT entry_date, SUM(amount) AS amount FROM money_entries WHERE account_id = ? GROUP BY entry_date ORDER BY entry_date',
        [pair.key],
      );
      var running = 0;
      for (final row in history) {
        final day = row['entry_date'] as String;
        if (day.compareTo(earliest) < 0) {
          running += row['amount'] as int;
        } else {
          changes[day] = (changes[day] ?? 0) + (row['amount'] as int);
        }
      }
      final days = changes.keys.toList()..sort();
      for (final day in days) {
        running += changes[day]!;
        if (running < 0 || running > 9000000000000) {
          throw StateError(
            'Transfer would make ${account['name']} balance invalid on $day. Check the date and available funds.',
          );
        }
      }
    }
  }

  static Future<void> _post(
    Transaction txn,
    int id,
    List<AccountTransferLeg> legs,
    String now,
    int revision,
  ) async {
    for (final leg in legs) {
      await txn.insert('money_entries', {
        'account_id': leg.accountId,
        'kind': 'transfer',
        'amount': leg.amount,
        'entry_date': leg.date,
        'created_at': now,
        'account_transfer_id': id,
        'note': '${voucherNo('ACT', id)} · revision $revision · ${leg.label}',
      });
    }
  }

  static Future<int> save({
    int? id,
    int? expectedRevision,
    String? requestKey,
    required int fromAccount,
    required int toAccount,
    required int amount,
    required String date,
    required String note,
  }) async {
    if (id != null) await VoucherPermissions.requireEditable();
    final clean = note.trim();
    _validate(fromAccount, toAccount, amount, date, clean);
    if (id == null &&
        (requestKey == null || requestKey.isEmpty || requestKey.length > 200)) {
      throw ArgumentError('Missing save request key');
    }
    if (id != null && expectedRevision == null) {
      throw ArgumentError('Missing expected revision');
    }
    final payload = jsonEncode([fromAccount, toAccount, amount, date, clean]);
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      Map<String, Object?>? before;
      if (id == null) {
        final previous = await txn.query(
          'account_transfers',
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
          'account_transfers',
          where: "id = ? AND status = 'posted' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (rows.length != 1) {
          throw StateError('Transfer changed. Reload before editing');
        }
        before = rows.single;
      }
      final source = await _account(txn, fromAccount),
          target = await _account(txn, toAccount);
      if (date.compareTo(source['opening_date'] as String) < 0 ||
          date.compareTo(target['opening_date'] as String) < 0) {
        throw StateError(
          'Transfer date cannot precede either account opening date',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final revision = before == null ? 0 : (before['revision'] as int) + 1;
      final after = <String, Object?>{
        'from_account_id': fromAccount,
        'to_account_id': toAccount,
        'amount': amount,
        'transfer_date': date,
        'note': clean,
        'from_account_name': source['name'],
        'to_account_name': target['name'],
        'from_branch_name': source['branch_name'],
        'to_branch_name': target['branch_name'],
        'revision': revision,
        'updated_at': now,
      };
      final legs = accountTransferPlan(
        before: before,
        after: after,
        today: today,
      );
      await _checkBalances(txn, legs);
      final int saved;
      if (id == null) {
        saved = await txn.insert('account_transfers', {
          ...after,
          'request_key': requestKey,
          'request_payload': payload,
          'created_at': now,
        });
      } else {
        saved = id;
        final count = await txn.update(
          'account_transfers',
          after,
          where: "id = ? AND status = 'posted' AND revision = ?",
          whereArgs: [id, expectedRevision],
        );
        if (count != 1) throw StateError('Transfer changed. Reload');
      }
      await _post(txn, saved, legs, now, revision);
      final header = (await txn.query(
        'account_transfers',
        where: 'id = ?',
        whereArgs: [saved],
      )).single;
      await txn.insert('account_transfer_revisions', {
        'transfer_id': saved,
        'action': before == null ? 'created' : 'edited',
        'before_json': jsonEncode(before ?? {}),
        'after_json': jsonEncode(header),
        'recorded_at': now,
      });
      return saved;
    });
  }

  static Future<void> voidTransfer({
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
      'account_transfers',
      where: "id = ? AND status = 'posted' AND revision = ?",
      whereArgs: [id, expectedRevision],
    );
    if (rows.length != 1) throw StateError('Transfer changed. Reload');
    final before = rows.single, now = DateTime.now().toUtc().toIso8601String();
    final revision = expectedRevision + 1;
    final legs = accountTransferPlan(before: before, today: today);
    await _checkBalances(txn, legs);
    await _post(txn, id, legs, now, revision);
    final count = await txn.update(
      'account_transfers',
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
    if (count != 1) throw StateError('Transfer changed. Reload');
    final header = (await txn.query(
      'account_transfers',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    await txn.insert('account_transfer_revisions', {
      'transfer_id': id,
      'action': 'void',
      'before_json': jsonEncode(before),
      'after_json': jsonEncode(header),
      'recorded_at': now,
    });
  }

  static Future<Map<String, Object?>> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'account_transfers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('Transfer no longer exists');
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
            'SELECT * FROM account_transfers WHERE id IN ($placeholders) ORDER BY transfer_date, id',
            batch,
          ),
        );
        entries.addAll(
          await txn.rawQuery(
            '''SELECT e.*, a.name AS account_name FROM money_entries e
          JOIN money_accounts a ON a.id = e.account_id WHERE e.account_transfer_id IN ($placeholders)
          ORDER BY e.entry_date, e.id''',
            batch,
          ),
        );
        revisions.addAll(
          await txn.rawQuery(
            'SELECT * FROM account_transfer_revisions WHERE transfer_id IN ($placeholders) ORDER BY transfer_id, id',
            batch,
          ),
        );
      }
      ReportTable table(
        String name,
        List<Map<String, Object?>> rows,
        List<String> empty,
      ) {
        final columns = rows.isEmpty ? empty : rows.first.keys.toList();
        final amountColumns = <int>{
          for (var j = 0; j < columns.length; j++)
            if (columns[j] == 'amount') j,
        };
        return ReportTable(name, columns.map(reportHeading).toList(), [
          for (final row in rows)
            [
              for (var j = 0; j < columns.length; j++)
                amountColumns.contains(j)
                    ? reportMoney(row[columns[j]] as int)
                    : row[columns[j]],
            ],
        ], moneyColumns: amountColumns);
      }

      return ReportBook(
        title: unique.length == 1
            ? voucherNo('ACT', unique.single)
            : 'Account Transfers',
        business: '${profile['name'] ?? ''}',
        filters:
            '$labels | ${AppCurrency.code}. Transfers move money between accounts, '
            'not revenue or expense. Current headers plus all original/edit/VOID entries and revisions are included. '
            'Edits restate transfer legs on original/new transfer dates; VOID reverses on its action date. '
            'Revision JSON retains stored minor units.',
        tables: [
          ReportTable(
            'Transfers',
            [
              'Voucher',
              'Date',
              'From branch',
              'From account',
              'To branch',
              'To account',
              'Amount',
              'Status',
              'Note',
            ],
            [
              for (final h in headers)
                [
                  voucherNo('ACT', h['id']),
                  h['transfer_date'],
                  h['from_branch_name'],
                  h['from_account_name'],
                  h['to_branch_name'],
                  h['to_account_name'],
                  reportMoney(h['amount'] as int),
                  h['status'],
                  h['note'],
                ],
            ],
            moneyColumns: {6},
          ),
          table('Transfer Vouchers', headers, ['No records']),
          table('Account Movements', entries, ['No entries']),
          table('Revision History', revisions, ['No revisions']),
        ],
      );
    });
  }
}
