import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'package:inventory_pos/app_database.dart';
import 'package:inventory_pos/backup_files.dart';
import 'package:inventory_pos/sqlite_backup.dart';
import 'package:inventory_pos/subscription_runtime.dart';

void main() {
  late Directory root;
  setUpAll(() async {
    ffi.sqfliteFfiInit(); sq.databaseFactory = ffi.databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('tp-backup-tests-');
    await Directory(p.join(root.path,'databases')).create(recursive:true);
    await sq.databaseFactory.setDatabasesPath(p.join(root.path, 'databases'));
    await SubscriptionRuntime.bind({'business_id':'backup-fixture','owner_id':'fixture-owner','plan':'premium','server_now':DateTime.now().toUtc().toIso8601String(),'ends_at':DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String()},null,null);
  });
  tearDownAll(() async {
    if (await root.exists()) { await root.delete(recursive: true); }
  });

  test('Real database snapshot restores stock, photos and profile and retains pre-restore copy', () async {
    final app = AppDatabase.instance;
    await app.saveBusinessProfile(name: 'Backup fixture', countryCode: 'MM', currencyCode: 'MMK');
    await app.saveBranch(code: 'TEST', name: 'Branch A', phone: '', address: '');
    final branch = (await app.getBranches()).single['id'] as int;
    final photo = Uint8List.fromList([255, 216, 255, 217]);
    final product = await app.addProduct(name: 'Coffee', price: 100, stock: 2, branchId: branch, imageBytes: photo);
    final db = await app.database;
    final schema = await SqliteBackup.schema(db);
    final version = await db.getVersion();
    final snapshot = p.join(root.path, 'full.tppos');
    await SqliteBackup.create(db, snapshot);
    final info = await SqliteBackup.inspect(snapshot, expectedSchema: schema, expectedVersion: version);
    expect(info.businessName, 'Backup fixture'); expect(info.counts['products'], 1);
    await db.update('products', {'name': 'Changed later'}, where: 'id = ?', whereArgs: [product]);
    await db.update('branch_stocks', {'stock': 9}, where: 'product_id = ?', whereArgs: [product]);
    final safety = await app.restoreLocalBackup(snapshot);
    final restored = await app.database;
    expect((await restored.query('products')).single['name'], 'Coffee');
    expect((await restored.query('branch_stocks')).single['stock'], 2);
    expect(await app.getProductImage(product), orderedEquals(photo));
    expect(await File(safety).exists(), true);
    expect(await BackupFiles.marker(restored.path).exists(), false);
    final old = await sq.openDatabase(safety, readOnly: true, singleInstance: false);
    try { expect((await old.query('products')).single['name'], 'Changed later'); }
    finally { await old.close(); }
    expect((await restored.query('activity_events', where: "action='restore'")).length, 1);

    final bad = p.join(root.path, 'not-a-backup.tppos');
    await File(bad).writeAsString('not a database');
    await expectLater(app.restoreLocalBackup(bad), throwsA(isA<FormatException>()));
    expect((await (await app.database).query('products')).single['name'], 'Coffee');
    await restored.close();
  });

  test('Interrupted replacement rolls back at each rename boundary', () async {
    for (final phase in [0, 1, 2]) {
      final dir = await Directory(p.join(root.path, 'phase$phase')).create();
      final live = p.join(dir.path, 'inventory_pos.db');
      final stage = '$live.stage.1', rollback = '$live.before_restore.1.tppos';
      await File(live).writeAsString('original'); await File(stage).writeAsString('new');
      await BackupFiles.begin(live, stage, rollback);
      if (phase >= 1) { await File(live).rename(rollback); }
      if (phase >= 2) { await File(stage).rename(live); }
      expect(await BackupFiles.recover(live), true);
      expect(await File(live).readAsString(), 'original');
      expect(await BackupFiles.marker(live).exists(), false);
      expect(await File(stage).exists(), false);
    }
  });
  test('Committed replacement keeps restored data and separate recovery copy', () async {
    final dir = await Directory(p.join(root.path, 'committed')).create();
    final live = p.join(dir.path, 'inventory_pos.db');
    final stage = '$live.stage.1', rollback = '$live.before_restore.1.tppos';
    await File(live).writeAsString('original'); await File(stage).writeAsString('new');
    await BackupFiles.begin(live, stage, rollback);
    await File(live).rename(rollback); await File(stage).rename(live);
    await BackupFiles.commit(live);
    expect(await BackupFiles.recover(live), false);
    expect(await File(live).readAsString(), 'new');
    expect(await File(rollback).readAsString(), 'original');
  });
  test('Journal rejects paths outside the database directory', () async {
    final live = p.join(root.path, 'inventory_pos.db');
    await File(live).writeAsString('original');
    await BackupFiles.marker(live).writeAsString('{"stage":"../elsewhere","rollback":"../other"}');
    await expectLater(BackupFiles.recover(live), throwsStateError);
    expect(await File(live).readAsString(), 'original');
    await BackupFiles.marker(live).delete();
  });
}
