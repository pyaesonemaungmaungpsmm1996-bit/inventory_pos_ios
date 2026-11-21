import 'package:sqflite/sqflite.dart';

/// Transactional dirty revision. TEMP triggers do not change portable backup
/// schemas; the revision itself is part of each consistent SQLite snapshot.
class BackupChangeTracker {
  static const key = 'backup_change_revision';
  static Future<int> revision(DatabaseExecutor db) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty
        ? 0
        : int.tryParse(rows.single['value'].toString()) ?? 0;
  }

  static Future<void> install(Database db) async {
    await db.rawInsert(
      "INSERT OR IGNORE INTO app_settings(key,value) VALUES (?, '0')",
      [key],
    );
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'android_metadata'",
    );
    for (final row in rows) {
      final table = row['name'] as String;
      if ([
            'activity_events',
            'activity_context',
            'category_changes',
          ].contains(table) ||
          table.startsWith('sync_')) {
        continue;
      }
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        final name = 'tp_backup_dirty_${table}_$event';
        final alias = event == 'DELETE' ? 'OLD' : 'NEW';
        final when = table == 'app_settings'
            ? " WHEN $alias.key<>'$key' AND $alias.key NOT LIKE 'backup_schema_%' AND $alias.key NOT GLOB 'live_sale_pending:*' AND $alias.key NOT GLOB 'live_purchase_pending:*'"
            : '';
        await db.execute('DROP TRIGGER IF EXISTS temp."$name"');
        await db.execute(
          '''CREATE TEMP TRIGGER "$name" AFTER $event ON main."$table"$when BEGIN UPDATE app_settings SET value=CAST(CAST(value AS INTEGER)+1 AS TEXT) WHERE key='$key'; END''',
        );
      }
    }
  }
}
