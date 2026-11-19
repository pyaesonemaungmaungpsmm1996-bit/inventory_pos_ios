import 'package:sqflite/sqflite.dart';

/// Called only during upgrade, with foreign keys disabled before the upgrade
/// transaction. Rebuild the parent without renaming it first, so child foreign
/// keys retain their original target. Existing invoices and indexes survive.
class PurchaseZeroCost {
  static Future<void> install(DatabaseExecutor db) async {
    final row = (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='purchase_invoices'",
    )).single;
    final sql = row['sql'] as String;
    final sequence = await db.rawQuery(
      "SELECT seq FROM sqlite_sequence WHERE name='purchase_invoices'",
    );
    final objects = await db.rawQuery(
      "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND ((tbl_name='purchase_invoices' AND type='index') OR type IN ('trigger','view')) ORDER BY CASE type WHEN 'view' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
    );
    final columns = (await db.rawQuery('PRAGMA table_info(purchase_invoices)'))
        .map((r) => '"${r['name']}"')
        .join(',');
    final updated = sql.replaceFirst(
      'total > 0 AND total <=',
      'total >= 0 AND total <=',
    );
    if (updated == sql) throw StateError('Unexpected purchase schema');
    // SQLite validates every trigger/view during ALTER TABLE. Temporarily remove
    // them while the parent name is absent, then restore their exact definitions.
    for (final object in objects.reversed) {
      if (object['type'] == 'index') continue;
      final name = (object['name'] as String).replaceAll('"', '""');
      await db.execute('DROP ${object['type']} "$name"');
    }
    await db.execute(
      updated.replaceFirst('purchase_invoices', 'purchase_invoices_new'),
    );
    await db.execute(
      'INSERT INTO purchase_invoices_new ($columns) SELECT $columns FROM purchase_invoices',
    );
    await db.execute('DROP TABLE purchase_invoices');
    await db.execute(
      'ALTER TABLE purchase_invoices_new RENAME TO purchase_invoices',
    );
    if (sequence.isNotEmpty) {
      await db.rawUpdate(
        "UPDATE sqlite_sequence SET seq=MAX(seq,?) WHERE name='purchase_invoices'",
        [sequence.single['seq']],
      );
    }
    for (final object in objects) {
      await db.execute(object['sql'] as String);
    }
    if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
      throw StateError('Purchase migration foreign key check failed');
    }
  }
}
