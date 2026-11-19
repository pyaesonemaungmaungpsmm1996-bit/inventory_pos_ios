import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'category_store.dart';
import 'report_models.dart';

class CategoriesRepository {
  static Future<List<Map<String, Object?>>> branches() async =>
      AppDatabase.instance.getBranches();
  static Future<List<Map<String, Object?>>> _rows(
    Transaction txn,
    String kind,
    int? branch,
    String search,
    bool archived,
  ) async {
    final info = CategoryStore.spec(kind);
    if (info.$3 && branch == null) return <Map<String, Object?>>[];
    final rows = await txn.query(
      info.$1,
      where: info.$3 ? 'branch_id = ?' : null,
      whereArgs: info.$3 ? [branch] : null,
      orderBy: 'active DESC, name COLLATE NOCASE, id',
    );
    final results = <Map<String, Object?>>[];
    for (final row in rows) {
      if (!archived && row['active'] != 1) continue;
      if (!'${row['name']}'.toLowerCase().contains(
        search.trim().toLowerCase(),
      )) {
        continue;
      }
      final usage = await CategoryStore.usage(txn, kind, row);
      results.add({
        ...row,
        'product_refs': usage.products,
        'document_refs': usage.documents,
        'history_refs': usage.history,
        'draft_refs': usage.drafts,
        'uncertain': usage.uncertain,
        'used': usage.used,
        'is_default': CategoryStore.isDefault(kind, row['id'] as int),
      });
    }
    return results;
  }

  static Future<List<Map<String, Object?>>> list({
    required String kind,
    int? branch,
    String search = '',
    bool includeArchived = true,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) => _rows(txn, kind, branch, search, includeArchived),
    );
  }

  static Future<int> save({
    required String kind,
    required String name,
    int? branch,
    Map<String, Object?>? previous,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) => CategoryStore.save(
        txn,
        kind,
        name,
        branch: branch,
        id: previous?['id'] as int?,
        expectedName: previous?['name'] as String?,
        expectedActive: previous?['active'] as int?,
      ),
    );
  }

  static Future<void> setActive({
    required String kind,
    required Map<String, Object?> previous,
    int? branch,
    required bool active,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction(
      (txn) => CategoryStore.setActive(
        txn,
        kind,
        previous['id'] as int,
        active,
        branch: branch,
        expectedName: previous['name'] as String,
        expectedActive: previous['active'] as int,
      ),
    );
  }

  static Future<String> remove({
    required String kind,
    required Map<String, Object?> previous,
    int? branch,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction(
      (txn) => CategoryStore.remove(
        txn,
        kind,
        previous['id'] as int,
        branch: branch,
        expectedName: previous['name'] as String,
        expectedActive: previous['active'] as int,
      ),
    );
  }

  static Future<ReportBook> report({
    required String kind,
    int? branch,
    required String labels,
    String search = '',
    bool includeArchived = true,
  }) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final rows = await _rows(txn, kind, branch, search, includeArchived);
      final scoped = CategoryStore.spec(kind).$3;
      final history = await txn.query(
        'category_changes',
        where: 'category_kind = ?${scoped ? ' AND branch_id = ?' : ''}',
        whereArgs: [kind, if (scoped) branch],
        orderBy: 'id',
      );
      return ReportBook(
        title: 'Category Catalog & History',
        business: '${profile['name'] ?? ''}',
        filters:
            '$labels | Catalog uses selected search/status. History includes all category events in '
            'this type/branch, including deleted categories. Usage counts are references, not unique '
            'financial transactions. Old-name matching uses names recorded since v38; earlier untracked '
            'renames cannot be reconstructed. Posted voucher snapshots retain their original names.',
        tables: [
          ReportTable(
            'Categories',
            [
              'ID',
              'Name',
              'Status',
              'Default',
              'Assigned products',
              'Voucher references',
              'History references',
              'Draft references',
              'Uncertain references',
            ],
            [
              for (final r in rows)
                [
                  r['id'],
                  r['name'],
                  r['active'] == 1 ? 'Active' : 'Archived',
                  r['is_default'] == true ? 'Yes' : 'No',
                  r['product_refs'],
                  r['document_refs'],
                  r['history_refs'],
                  r['draft_refs'],
                  r['uncertain'] == true ? 'Yes' : 'No',
                ],
            ],
          ),
          ReportTable(
            'Category History',
            [
              'Event ID',
              'Type',
              'Category ID',
              'Branch ID',
              'Action',
              'Before name',
              'After name',
              'Before active',
              'After active',
              'Recorded UTC',
            ],
            [
              for (final h in history)
                [
                  h['id'],
                  h['category_kind'],
                  h['category_id'],
                  h['branch_id'],
                  h['action'],
                  h['before_name'],
                  h['after_name'],
                  h['before_active'],
                  h['after_active'],
                  h['recorded_at'],
                ],
            ],
          ),
        ],
      );
    });
  }
}
