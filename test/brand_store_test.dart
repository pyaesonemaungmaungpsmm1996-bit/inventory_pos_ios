import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/brand_store.dart';

void main() {
  late Database db;
  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('PRAGMA foreign_keys=ON');
    await db.execute('CREATE TABLE product_categories(id INTEGER PRIMARY KEY, name TEXT, active INTEGER NOT NULL DEFAULT 1)');
    await db.execute('CREATE TABLE product_brands(id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL REFERENCES product_categories(id), name TEXT NOT NULL COLLATE NOCASE, active INTEGER NOT NULL DEFAULT 1, UNIQUE(category_id,name))');
    await db.insert('product_categories', {'id': 1, 'name': 'Phones'});
    await db.insert('product_categories', {'id': 2, 'name': 'Shoes'});
  });
  tearDown(() async => db.close());
  test('saving a brand makes it immediately selectable in its category', () async {
    final id = await BrandStore.save(db, 1, ' Ness ');
    expect((await BrandStore.list(db, 1)).single['id'], id);
    expect((await BrandStore.list(db, 1)).single['name'], 'Ness');
    expect(await BrandStore.list(db, 2), isEmpty);
    expect(await BrandStore.save(db, 1, 'ness'), id);
    expect((await BrandStore.list(db, 1)).length, 1);
    expect(await BrandStore.save(db, 2, 'Ness'), isNot(id));
  });
  test('archived brands require explicit restoration', () async {
    final id = await BrandStore.save(db, 1, 'Ness');
    await db.update('product_brands', {'active': 0}, where: 'id=?', whereArgs: [id]);
    expect(await BrandStore.list(db, 1), isEmpty);
    expect((await BrandStore.list(db, 1, includeArchived: true)).length, 1);
    await expectLater(BrandStore.save(db, 1, 'ness'), throwsStateError);
    await db.update('product_brands', {'active': 1}, where: 'id=?', whereArgs: [id]);
    expect(await BrandStore.save(db, 1, 'Ness'), id);
  });
  test('invalid category and conflicting rename leave brands unchanged', () async {
    await expectLater(BrandStore.save(db, 999, 'Bad'), throwsStateError);
    final first = await BrandStore.save(db, 1, 'First');
    await BrandStore.save(db, 1, 'Second');
    await expectLater(BrandStore.save(db, 1, 'Second', id: first), throwsStateError);
    await db.update('product_categories', {'active': 0}, where: 'id=1');
    await expectLater(BrandStore.save(db, 1, 'Other'), throwsStateError);
    expect((await BrandStore.list(db, 1)).length, 2);
  });
  test('database diagnostics omit SQL arguments', () {
    expect(BrandStore.errorText(StateError('Choose category')), 'Choose category');
    expect(BrandStore.errorText(Exception('UNIQUE failed sql INSERT args [private]')), isNot(contains('private')));
  });
}
