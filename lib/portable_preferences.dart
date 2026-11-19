import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Document layouts live with the shop database, so SQLite backups carry them
/// between Android and Windows. Native printer handles remain device-local.
class PortablePreferences {
  static const prefix = 'portable.';
  static Future<String?> read(String key) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: [prefix + key],
    );
    if (rows.isNotEmpty) return rows.single['value'] as String;
    final legacy = await SharedPreferencesAsync().getString(key);
    if (legacy != null) await write(key, legacy);
    return legacy;
  }

  static Future<void> write(String key, String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert('app_settings', {
      'key': prefix + key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // The database is authoritative; migration never depends on this mirror.
    try {
      await SharedPreferencesAsync().remove(key);
    } catch (_) {
      /* Native mirror cleanup does not undo a durable database write. */
    }
  }

  static Future<void> remove(String key) async {
    final db = await AppDatabase.instance.database;
    await db.delete('app_settings', where: 'key=?', whereArgs: [prefix + key]);
    await SharedPreferencesAsync().remove(key);
  }
}
