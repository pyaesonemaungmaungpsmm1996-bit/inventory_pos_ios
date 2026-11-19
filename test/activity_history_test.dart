import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/activity_store.dart';
import 'package:inventory_pos/activity_repository.dart';
import 'package:inventory_pos/app_datetime.dart';

void main() {
  late Database db;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final sql in [
      'CREATE TABLE branches(id INTEGER PRIMARY KEY, name TEXT, code TEXT)',
      'CREATE TABLE business_profile(id INTEGER PRIMARY KEY, name TEXT, currency_code TEXT)',
      'CREATE TABLE expenses(id INTEGER PRIMARY KEY, branch_id INTEGER, amount INTEGER, category TEXT, note TEXT, status TEXT, revision INTEGER DEFAULT 0, posted_at TEXT, voided_at TEXT)',
      'CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT, item_code TEXT, price INTEGER, category_id INTEGER)',
      'CREATE TABLE product_categories(id INTEGER PRIMARY KEY, name TEXT, active INTEGER)',
      'CREATE TABLE money_accounts(id INTEGER PRIMARY KEY, branch_id INTEGER, name TEXT)',
      'CREATE TABLE money_entries(id INTEGER PRIMARY KEY, account_id INTEGER, amount INTEGER, entry_date TEXT)',
      'CREATE TABLE stock_transfers(id INTEGER PRIMARY KEY, source_branch_id INTEGER, destination_branch_id INTEGER, quantity INTEGER, status TEXT, received_at TEXT)',
      'CREATE TABLE expense_receipts(expense_id INTEGER PRIMARY KEY, photo BLOB)',
      'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT)',
    ]) { await db.execute(sql); }
    await db.insert('branches', {'id': 1, 'name': 'A', 'code': 'A'});
    await db.insert('branches', {'id': 2, 'name': 'B', 'code': 'B'});
    await db.insert('business_profile', {'id': 1, 'name': 'Shop', 'currency_code': 'MMK'});
    await db.insert('money_accounts', {'id': 1, 'branch_id': 1, 'name': 'Cash'});
    await db.transaction((txn) => ActivityStore.install(txn));
  });
  tearDown(() async { await db.close(); });

  test('Create/update/VOID/delete history remains after original deletion', () async {
    await db.insert('expenses', {'id': 1, 'branch_id': 1, 'amount': 100, 'category': 'Food', 'status': 'posted', 'posted_at': '2026-10-30T00:00:00Z'});
    await db.update('expenses', {'amount': 120}, where: 'id=1');
    await db.update('expenses', {'status': 'void', 'voided_at': '2026-10-30T01:00:00Z'}, where: 'id=1');
    await db.delete('expenses', where: 'id=1');
    final rows = await db.query('activity_events', where: "source_table='expenses' AND origin='tracked'", orderBy: 'id');
    expect(rows.map((r) => r['action']).toList(), ['create', 'update', 'void', 'delete']);
    expect(rows.first['reference'], 'EXP-000001');
    expect(rows[1]['amount_before'], 100); expect(rows[1]['amount_after'], 120);
    expect(rows.last['before_summary'], contains('amount=120'));
    expect(rows.first['actor_name'], 'Not recorded');
    expect(rows.first['branch_id'], 1);
  });
  test('A failed business transaction leaves no phantom activity rows', () async {
    await expectLater(db.transaction((txn) async {
      await txn.insert('expenses', {'id': 1, 'branch_id': 1, 'amount': 100, 'status': 'posted'});
      throw StateError('Forced rollback');
    }), throwsStateError);
    expect(await db.query('expenses'), isEmpty);
    expect(await db.query('activity_events', where: "source_table='expenses'"), isEmpty);
  });
  test('Receive/archive/restore actions and cross-branch scope are captured', () async {
    await db.insert('stock_transfers', {'id': 1, 'source_branch_id': 1, 'destination_branch_id': 2, 'quantity': 2, 'status': 'posted'});
    await db.update('stock_transfers', {'received_at': '2026-10-30T00:00:00Z'}, where: 'id=1');
    final receive = (await db.query('activity_events', where: "source_table='stock_transfers' AND action='receive'")).single;
    expect(receive['branch_id'], 1); expect(receive['peer_branch_id'], 2);
    await db.insert('product_categories', {'id': 1, 'name': 'Food', 'active': 1});
    await db.update('product_categories', {'active': 0}, where: 'id=1');
    await db.update('product_categories', {'active': 1}, where: 'id=1');
    expect((await db.query('activity_events', where: "source_table='product_categories'", orderBy: 'id')).map((r) => r['action']).toList(), ['create', 'archive', 'restore']);
  });
  test('Photos keep byte counts only; draft autosave settings are ignored', () async {
    await db.insert('expense_receipts', {'expense_id': 1, 'photo': Uint8List.fromList([1, 2, 3, 4])});
    final photo = (await db.query('activity_events', where: "source_table='expense_receipts'")).single;
    expect(photo['after_summary'], contains('photo_bytes=4'));
    expect(photo['after_summary'], isNot(contains('1, 2, 3, 4')));
    await db.insert('app_settings', {'key': 'purchase_recovery', 'value': 'draft'});
    expect(await db.query('activity_events', where: "source_table='app_settings'"), isEmpty);
    await db.insert('app_settings', {'key': 'default_branch', 'value': '1'});
    expect((await db.query('activity_events', where: "source_table='app_settings'")).length, 1);
  });
  test('Unchanged writes do not create update events; unknown actors are not invented', () async {
    await db.insert('products', {'id': 1, 'name': 'Coffee', 'item_code': 'COF-1', 'price': 100});
    await db.update('products', {'price': 100}, where: 'id=1');
    final rows = await db.query('activity_events', where: "source_table='products'");
    expect(rows.length, 1); expect(rows.single['reference'], 'COF-1'); expect(rows.single['actor_id'], isNull);
  });
  test('Saved revisions import on upgrade without inventing actors or exposing secrets', () async {
    // Simulate a pre-v39 database: setup already installed the audit schema.
    final triggers = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'activity_%'");
    for (final trigger in triggers) {
      final name = (trigger['name'] as String).replaceAll('"', '""');
      await db.execute('DROP TRIGGER "$name"');
    }
    await db.execute('DROP TABLE activity_events');
    await db.execute('DROP TABLE activity_context');
    await db.execute('CREATE TABLE account_transfer_revisions(id INTEGER PRIMARY KEY, transfer_id INTEGER, recorded_at TEXT, action TEXT, before_json TEXT, after_json TEXT)');
    await db.insert('account_transfer_revisions', {'id': 1, 'transfer_id': 7, 'recorded_at': '2026-10-29T01:00:00Z', 'action': 'edited',
      'before_json': '{"amount":100,"password":"private"}', 'after_json': '{"amount":120,"token":"private"}'});
    await db.transaction((txn) => ActivityStore.install(txn));
    final rows = await db.query('activity_events', where: "source_table='account_transfer_revisions'");
    expect(rows.length, 1);
    expect(rows.single['origin'], 'saved_history');
    expect(rows.single['actor_name'], 'Not recorded');
    expect(rows.single['before_summary'], contains('100'));
    expect(rows.single['after_summary'], isNot(contains('private')));
  });
  test('Literal search and technical filters select only matching activity', () async {
    AppDateTime.configure('Etc/UTC');
    final at = DateTime.utc(2026, 10, 30, 12);
    await ActivityStore.append(db, key: 'literal', source: 'test', record: '1', reference: 'REF-%_!', module: 'money', action: 'create', origin: 'tracked', at: at, branch: 1);
    await ActivityStore.append(db, key: 'other', source: 'test', record: '2', reference: 'REF-abc', module: 'money', action: 'create', origin: 'tracked', at: at, branch: 2);
    final query = ActivityRepository.filterSql(const ActivityFilter(from: '2026-10-30', to: '2026-10-30', search: '%_!', branch: 1, includeGlobal: false));
    final rows = await db.query('activity_events', where: query.$1, whereArgs: query.$2);
    expect(rows.length, 1);
    expect(rows.single['reference'], 'REF-%_!');
    await db.update('activity_events', {'technical': 1}, where: "event_key='literal'");
    expect(await db.query('activity_events', where: query.$1, whereArgs: query.$2), isEmpty);
  });
  test('Activity date bounds respect business timezone rather than UTC calendar dates', () {
    AppDateTime.configure('Asia/Yangon');
    final bounds = activityDateBounds('2026-10-30', '2026-10-30');
    expect(DateTime.fromMillisecondsSinceEpoch(bounds.$1, isUtc: true), DateTime.utc(2026, 10, 29, 17, 30));
    expect(DateTime.fromMillisecondsSinceEpoch(bounds.$2, isUtc: true), DateTime.utc(2026, 10, 30, 17, 30));
    expect(activityLocalTime('2026-10-29T18:00:00Z'), '2026-10-30 00:30:00');
    AppDateTime.configure('Etc/UTC');
  });
}
