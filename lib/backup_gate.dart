import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite owns these locks across engines/processes; no expiring leases or
/// process-scoped File.lock (which cannot serialize Android Dart isolates).
class BackupGate {
  static final Object _zoneKey = Object();
  static Future<T> run<T>(String name, Future<T> Function() body) async {
    final held = (Zone.current[_zoneKey] as Set<String>?) ?? <String>{};
    if (held.contains(name)) {
      return body();
    }
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'tp_$name.lock.db'),
      singleInstance: false,
    );
    try {
      await db.rawQuery('PRAGMA busy_timeout = 0');
      return await db.transaction(
        (_) => runZoned(
          body,
          zoneValues: {
            _zoneKey: {...held, name},
          },
        ),
        exclusive: true,
      );
    } finally {
      await db.close();
    }
  }
}
