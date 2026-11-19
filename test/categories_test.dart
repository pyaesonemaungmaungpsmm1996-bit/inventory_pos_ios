import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/category_store.dart';

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in [
      'CREATE TABLE branches(id INTEGER PRIMARY KEY, name TEXT)',
      'CREATE TABLE product_categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, active INTEGER NOT NULL DEFAULT 1)',
      'CREATE TABLE expense_categories(id INTEGER PRIMARY KEY AUTOINCREMENT, branch_id INTEGER, name TEXT NOT NULL COLLATE NOCASE, active INTEGER NOT NULL DEFAULT 1, UNIQUE(branch_id,name))',
      'CREATE TABLE other_money_categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, active INTEGER NOT NULL DEFAULT 1)',
      'CREATE TABLE category_changes(id INTEGER PRIMARY KEY AUTOINCREMENT, category_kind TEXT, category_id INTEGER, branch_id INTEGER, action TEXT, before_name TEXT, after_name TEXT, before_active INTEGER, after_active INTEGER, recorded_at TEXT)',
      'CREATE TABLE products(id INTEGER PRIMARY KEY, category_id INTEGER)',
      'CREATE TABLE product_brands(id INTEGER PRIMARY KEY, category_id INTEGER)',
      'CREATE TABLE purchase_items(id INTEGER PRIMARY KEY, category_name TEXT)',
      'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT)',
      'CREATE TABLE expenses(id INTEGER PRIMARY KEY, branch_id INTEGER, category TEXT, amount INTEGER)',
      'CREATE TABLE expense_edits(id INTEGER PRIMARY KEY, expense_id INTEGER, previous_category TEXT, category TEXT)',
      'CREATE TABLE other_money_vouchers(id INTEGER PRIMARY KEY, category TEXT, amount INTEGER)',
      'CREATE TABLE other_money_revisions(id INTEGER PRIMARY KEY, voucher_id INTEGER, before_json TEXT, after_json TEXT)',
      'CREATE TABLE money_entries(id INTEGER PRIMARY KEY, amount INTEGER)',
    ]) {
      await db.execute(sql);
    }
    await db.insert('branches', {'id': 1, 'name': 'A'});
    await db.insert('branches', {'id': 2, 'name': 'B'});
    await db.insert('product_categories', {'id': 1, 'name': 'Uncategorized'});
    await db.insert('money_entries', {'id': 1, 'amount': 1000});
  });
  tearDown(() async {
    await db.close();
  });

  test(
    'Unused category deletion keeps audit and never changes money',
    () async {
      final id = await db.transaction(
        (txn) => CategoryStore.save(txn, 'product', 'Accessories'),
      );
      final result = await db.transaction(
        (txn) => CategoryStore.remove(txn, 'product', id),
      );
      expect(result, 'deleted');
      expect(
        await db.query('product_categories', where: 'id = ?', whereArgs: [id]),
        isEmpty,
      );
      final log = await db.query(
        'category_changes',
        where: 'category_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      expect(log.map((r) => r['action']).toList(), ['created', 'deleted']);
      expect((await db.query('money_entries')).single['amount'], 1000);
    },
  );
  test('Used expense rename preserves old snapshots and still prevents hard deletion', () async {
    final id = await db.transaction(
      (txn) => CategoryStore.save(txn, 'expense', 'Rent', branch: 1),
    );
    await db.insert('expenses', {
      'id': 1,
      'branch_id': 1,
      'category': 'Rent',
      'amount': 39000,
    });
    await db.transaction(
      (txn) =>
          CategoryStore.save(txn, 'expense', 'Utilities', id: id, branch: 1),
    );
    final usage = await db.transaction(
      (txn) async => CategoryStore.usage(
        txn,
        'expense',
        await CategoryStore.row(txn, 'expense', id, 1),
      ),
    );
    expect(usage.documents, 1);
    expect(
      await db.transaction(
        (txn) => CategoryStore.remove(txn, 'expense', id, branch: 1),
      ),
      'archived',
    );
    expect((await db.query('expense_categories')).single['active'], 0);
    final expense = (await db.query('expenses')).single;
    expect(expense['category'], 'Rent');
    expect(expense['amount'], 39000);
    await db.transaction(
      (txn) => CategoryStore.setActive(txn, 'expense', id, true, branch: 1),
    );
    expect((await db.query('expense_categories')).single['active'], 1);
  });
  test('Expense names are unique per branch and stale edits fail', () async {
    final id = await db.transaction(
      (txn) => CategoryStore.save(txn, 'expense', 'Bill', branch: 1),
    );
    await db.transaction(
      (txn) => CategoryStore.save(txn, 'expense', 'Bill', branch: 2),
    );
    await expectLater(
      db.transaction(
        (txn) => CategoryStore.save(txn, 'expense', 'bill', branch: 1),
      ),
      throwsStateError,
    );
    await db.transaction(
      (txn) =>
          CategoryStore.save(txn, 'expense', 'Utilities', id: id, branch: 1),
    );
    await expectLater(
      db.transaction(
        (txn) => CategoryStore.save(
          txn,
          'expense',
          'Old form',
          id: id,
          branch: 1,
          expectedName: 'Bill',
          expectedActive: 1,
        ),
      ),
      throwsStateError,
    );
    expect(
      (await db.query(
        'expense_categories',
        where: 'id = ?',
        whereArgs: [id],
      )).single['name'],
      'Utilities',
    );
  });
  test('Default product category stays available but can be renamed', () async {
    await expectLater(
      db.transaction(
        (txn) => CategoryStore.setActive(txn, 'product', 1, false),
      ),
      throwsStateError,
    );
    await expectLater(
      db.transaction((txn) => CategoryStore.remove(txn, 'product', 1)),
      throwsStateError,
    );
    await db.transaction(
      (txn) => CategoryStore.save(txn, 'product', 'General', id: 1),
    );
    expect((await db.query('product_categories')).single['name'], 'General');
  });
  test(
    'Saved purchase draft and unreadable draft block archive/delete',
    () async {
      final id = await db.transaction(
        (txn) => CategoryStore.save(txn, 'product', 'Phones'),
      );
      await db.insert('app_settings', {
        'key': 'purchase_recovery',
        'value': jsonEncode({
          'lines': [
            {'category_id': id},
          ],
        }),
      });
      await expectLater(
        db.transaction(
          (txn) => CategoryStore.setActive(txn, 'product', id, false),
        ),
        throwsStateError,
      );
      await db.update('app_settings', {'value': '{bad json'});
      await expectLater(
        db.transaction((txn) => CategoryStore.remove(txn, 'product', id)),
        throwsStateError,
      );
      expect(
        (await db.query(
          'product_categories',
          where: 'id = ?',
          whereArgs: [id],
        )).single['active'],
        1,
      );
    },
  );
  test('Old Other Money snapshot is retained without resurrecting renamed category', () async {
    final id = await db.transaction(
      (txn) => CategoryStore.save(txn, 'other_money', 'Capital'),
    );
    await db.insert('other_money_vouchers', {
      'id': 1,
      'category': 'Capital',
      'amount': 1000,
    });
    await db.transaction(
      (txn) => CategoryStore.save(txn, 'other_money', 'Owner funds', id: id),
    );
    final retained = await db.transaction(
      (txn) => CategoryStore.ensureOtherMoneyName(
        txn,
        'Capital',
        previousName: 'Capital',
      ),
    );
    expect(retained, 'Capital');
    expect(
      (await db.query('other_money_categories')).single['name'],
      'Owner funds',
    );
    expect(
      await db.transaction(
        (txn) => CategoryStore.remove(txn, 'other_money', id),
      ),
      'archived',
    );
    expect(
      (await db.query('other_money_vouchers')).single['category'],
      'Capital',
    );
  });
}
