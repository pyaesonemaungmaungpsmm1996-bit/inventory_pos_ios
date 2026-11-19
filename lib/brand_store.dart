import 'package:sqflite/sqflite.dart';

/// Shared by Purchase and Account so both use the same category validation.
class BrandStore {
  static Future<List<Map<String, Object?>>> list(
    DatabaseExecutor db,
    int category, {
    bool includeArchived = false,
  }) => db.query(
    'product_brands',
    where: 'category_id = ?${includeArchived ? '' : ' AND active = 1'}',
    whereArgs: [category],
    orderBy: 'active DESC, name COLLATE NOCASE, id',
  );

  static Future<int> save(
    Database db,
    int category,
    String name, {
    int? id,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw ArgumentError('Enter a brand name with 1–100 characters.');
    }
    return db.transaction((txn) async {
      final parent = await txn.query(
        'product_categories',
        columns: ['id'],
        where: 'id = ? AND active = 1',
        whereArgs: [category],
      );
      if (parent.isEmpty) {
        throw StateError('Choose an active product category first.');
      }
      final existing = await txn.query(
        'product_brands',
        where: 'category_id = ? AND name = ? COLLATE NOCASE',
        whereArgs: [category, clean],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['active'] != 1) {
          throw StateError(
            'This brand is archived. Restore it in Account → Brands within categories.',
          );
        }
        if (id != null && row['id'] != id) {
          throw StateError(
            'Another brand already has this name in this category.',
          );
        }
        return row['id'] as int;
      }
      if (id == null) {
        return txn.insert('product_brands', {
          'category_id': category,
          'name': clean,
        });
      }
      final changed = await txn.update(
        'product_brands',
        {'name': clean},
        where: 'id = ? AND category_id = ?',
        whereArgs: [id, category],
      );
      if (changed != 1) {
        throw StateError('Brand no longer exists. Reload the list.');
      }
      return id;
    });
  }

  // SQLite errors often append SQL arguments. Do not display those payloads.
  static String errorText(Object error) {
    if (error is StateError) return error.message;
    if (error is ArgumentError) return '${error.message}';
    return error
        .toString()
        .split(RegExp(r'\s+sql\s*[:=]?\s*', caseSensitive: false))
        .first;
  }
}
