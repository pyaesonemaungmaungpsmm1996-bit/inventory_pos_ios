import 'auto_backup_policy.dart';

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Separate control database: never included in POS backup/restore.
class AutoBackupStore {
  static Future<T> use<T>(Future<T> Function(Database) body) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'tp_auto_backup_control.db'),
      version: 1,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA busy_timeout = 2000'),
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE control (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL)',
        );
        await db.insert('control', {'id': 1, 'value': '{}'});
      },
    );
    try {
      return await body(db);
    } finally {
      await db.close();
    }
  }

  static Future<Map<String, dynamic>> read() => use((db) async {
    final rows = await db.query('control', where: 'id=1');
    return Map<String, dynamic>.from(
      jsonDecode(rows.single['value'] as String) as Map,
    );
  });
  static Future<void> change(void Function(Map<String, dynamic>) edit) => use(
    (db) => db.transaction((txn) async {
      final rows = await txn.query('control', where: 'id=1');
      final value = Map<String, dynamic>.from(
        jsonDecode(rows.single['value'] as String) as Map,
      );
      edit(value);
      await txn.update('control', {'value': jsonEncode(value)}, where: 'id=1');
    }),
  );
  static Future<void> status(String worker, String message) => change((v) {
    if (v['worker'] == worker && v['enabled'] == true) {
      v['status'] = message;
    }
  });
  static Future<void> pause(String reason) => change((v) {
    v['enabled'] = false;
    v['status'] = reason;
  });
  static bool due(Map<String, dynamic> value, DateTime now) {
    if (value['enabled'] != true) {
      return false;
    }
    if (value['pending'] != null || value['force'] == true) {
      return true;
    }
    final captured = DateTime.tryParse('${value['capturedAt']}');
    final interval = value['minutes'];
    if (!AutoBackupPolicy.validMinutes(interval)) {
      return false;
    }
    return captured == null ||
        !now.toUtc().isBefore(
          captured.toUtc().add(Duration(minutes: interval as int)),
        );
  }
}
