import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:inventory_pos/backup_gate.dart';
void main() {
  late Directory folder;
  setUp(() async {
    ffi.sqfliteFfiInit(); databaseFactory = ffi.databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('tp_backup_gate_');
    await databaseFactory.setDatabasesPath(folder.path);
  });
  tearDown(() async { await folder.delete(recursive: true); });
  test('Separate connections cannot capture and restore at the same time', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final capture = BackupGate.run('backup_maintenance', () async {
      entered.complete(); await release.future;
    });
    await entered.future;
    try {
      await expectLater(BackupGate.run('backup_maintenance', () async => fail('Overlapping restore entered')), throwsA(isA<DatabaseException>()));
    } finally { release.complete(); await capture; }
    expect(await BackupGate.run('backup_maintenance', () async => 'restored'), 'restored');
  });
  test('Nested opening in a restore is reentrant; exceptions release the gate', () async {
    expect(await BackupGate.run('backup_maintenance', () => BackupGate.run('backup_maintenance', () async => 42)), 42);
    await expectLater(BackupGate.run('backup_maintenance', () async => throw StateError('interrupted')), throwsStateError);
    expect(await BackupGate.run('backup_maintenance', () async => true), isTrue);
  });
  test('Network job lock does not block a maintenance snapshot', () async {
    expect(await BackupGate.run('auto_backup_run', () => BackupGate.run('backup_maintenance', () async => true)), isTrue);
  });
}
