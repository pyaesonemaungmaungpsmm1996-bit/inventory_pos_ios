import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/stock_sync.dart';
import 'package:inventory_pos/stock_sync_setup_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('isolated sync preview has its own sign-in form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StockSyncPreviewEntry()));
    expect(find.text('Stock sync test login'), findsOneWidget);
    expect(find.text('Sign in to test project'), findsOneWidget);
  });

  late Database db;
  const store = OfflineStockStore(shop: 'shop', device: 'device-a');

  Map<String, Object?> command(int quantity, {bool includeUnknown = false}) => {
    'kind': 'sale',
    'offline': true,
    'occurred_at': '2026-11-22T07:00:00Z',
    'counterparty': 'Test customer',
    'lines': [
      {'product_id': 'tea', 'quantity': quantity, 'unit_minor': 25},
      if (includeUnknown)
        {'product_id': 'coffee', 'quantity': 1, 'unit_minor': 30},
    ],
  };

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await OfflineStockStore.ensureTables(db);
    await store.applySnapshot(db, [
      {'id': 'tea', 'device_granted': 4, 'device_consumed': 0},
    ]);
  });

  tearDown(() => db.close());

  test('offline voucher and allowance roll back together', () async {
    await db.execute('create table local_vouchers(id text primary key)');
    await expectLater(
      db.transaction((txn) async {
        await txn.insert('local_vouchers', {'id': 'sale-1'});
        await store.stageSale(
          txn,
          operation: 'sale-1',
          command: command(2, includeUnknown: true),
        );
      }),
      throwsStateError,
    );
    expect(await db.query('local_vouchers'), isEmpty);
    expect(await store.remaining(db, 'tea'), 4);
    expect(await store.pending(db), isEmpty);
  });

  test(
    'repeated operation and stale snapshot do not change spent allowance',
    () async {
      Future<void> stage() => db.transaction(
        (txn) => store.stageSale(txn, operation: 'sale-1', command: command(2)),
      );
      await stage();
      await stage();
      expect(await store.remaining(db, 'tea'), 2);
      expect((await store.pending(db)).map((row) => row.operation), ['sale-1']);
      await store.applySnapshot(db, [
        {'id': 'tea', 'device_granted': 3, 'device_consumed': 0},
      ]);
      expect(await store.remaining(db, 'tea'), 2);
      await store.acknowledge(db, 'sale-1');
      await stage();
      expect(await store.pending(db), isEmpty);
      expect(await store.remaining(db, 'tea'), 2);
    },
  );

  test('another device cannot spend cached allowance', () async {
    const other = OfflineStockStore(shop: 'shop', device: 'device-b');
    expect(await other.remaining(db, 'tea'), 0);
    await expectLater(
      db.transaction(
        (txn) => other.stageSale(txn, operation: 'sale-2', command: command(1)),
      ),
      throwsStateError,
    );
    expect(await store.remaining(db, 'tea'), 4);
  });
}
