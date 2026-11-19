import 'package:sqflite/sqflite.dart';

/// Global product identity is separate from per-branch stock. Existing duplicate
/// rows remain readable; only creation or identity changes are rejected.
class CatalogIdentity {
  static String normalize(Object? value) => (value?.toString() ?? '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
  static String sql(String field) {
    var value =
        "replace(replace(replace(COALESCE($field,''),char(9),' '),char(10),' '),char(13),' ')";
    for (var i = 0; i < 8; i++) {
      value = "replace($value,'  ',' ')";
    }
    return 'lower(trim($value))';
  }

  static Future<void> install(Database db) async {
    final name = sql('name'), color = sql('color'), size = sql('size');
    final nn = sql('NEW.name'), nc = sql('NEW.color'), ns = sql('NEW.size');
    final exists =
        'EXISTS(SELECT 1 FROM products WHERE $name=$nn AND $color=$nc AND $size=$ns';
    for (final event in ['INSERT', 'UPDATE']) {
      final trigger = 'tp_catalog_identity_$event';
      await db.execute('DROP TRIGGER IF EXISTS temp.$trigger');
      final changed = event == 'UPDATE'
          ? '($nn<>${sql('OLD.name')} OR $nc<>${sql('OLD.color')} OR $ns<>${sql('OLD.size')}) AND '
          : '';
      final excluded = event == 'UPDATE' ? ' AND id<>OLD.id' : '';
      await db.execute(
        '''CREATE TEMP TRIGGER $trigger BEFORE $event ON products WHEN $changed$exists$excluded) BEGIN SELECT RAISE(ABORT,'This item name and variant already exist. Select the existing item code for this branch.'); END''',
      );
    }
  }

  static Future<void> requireAvailable(
    DatabaseExecutor db, {
    required String name,
    String color = '',
    String size = '',
    int? excluding,
  }) async {
    final rows = await db.query(
      'products',
      columns: ['id', 'name', 'color', 'size'],
    );
    if (rows.any(
      (r) =>
          r['id'] != excluding &&
          normalize(r['name']) == normalize(name) &&
          normalize(r['color'] ?? '') == normalize(color) &&
          normalize(r['size'] ?? '') == normalize(size),
    )) {
      throw StateError(
        'This item name and variant already exist. Reuse its item code; stock remains separate for each branch.',
      );
    }
  }
}
