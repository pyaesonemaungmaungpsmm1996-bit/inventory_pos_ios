import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class CategoryUsage {
  const CategoryUsage({
    this.products = 0,
    this.documents = 0,
    this.history = 0,
    this.drafts = 0,
    this.uncertain = false,
  });
  final int products, documents, history, drafts;
  final bool uncertain;
  int get references => products + documents + history + drafts;
  bool get used => references > 0 || uncertain;
}

class CategoryStore {
  static const specs = <String, (String, int, bool)>{
    'product': ('product_categories', 100, false),
    'expense': ('expense_categories', 80, true),
    'other_money': ('other_money_categories', 80, false),
  };
  static (String, int, bool) spec(String kind) {
    final value = specs[kind];
    if (value == null) {
      throw ArgumentError('Unknown category type');
    }
    return value;
  }

  static String cleanName(String kind, String name) {
    final value = name.trim();
    if (value.isEmpty || value.length > spec(kind).$2) {
      throw ArgumentError('Enter a category name within the allowed length');
    }
    return value;
  }

  static bool isDefault(String kind, int id) => kind == 'product' && id == 1;
  static Future<void> _scope(Transaction txn, String kind, int? branch) async {
    if (spec(kind).$3) {
      if (branch == null ||
          (await txn.query(
            'branches',
            where: 'id = ?',
            whereArgs: [branch],
          )).isEmpty) {
        throw StateError('Choose an expense branch first');
      }
    }
  }

  static Future<Map<String, Object?>> row(
    Transaction txn,
    String kind,
    int id,
    int? branch,
  ) async {
    await _scope(txn, kind, branch);
    final scoped = spec(kind).$3;
    final rows = await txn.query(
      spec(kind).$1,
      where: 'id = ?${scoped ? ' AND branch_id = ?' : ''}',
      whereArgs: [id, if (scoped) branch],
    );
    if (rows.length != 1) {
      throw StateError('Category no longer exists. Reload');
    }
    return rows.single;
  }

  static void _expected(Map<String, Object?> row, String? name, int? active) {
    if ((name != null && row['name'] != name) ||
        (active != null && row['active'] != active)) {
      throw StateError('Category changed. Reload before saving');
    }
  }

  static Future<void> _log(
    Transaction txn,
    String kind,
    int id,
    int? branch,
    String action,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  ) async {
    await txn.insert('category_changes', {
      'category_kind': kind,
      'category_id': id,
      'branch_id': spec(kind).$3 ? branch : null,
      'action': action,
      'before_name': before?['name'] ?? '',
      'after_name': after?['name'] ?? '',
      'before_active': before?['active'],
      'after_active': after?['active'],
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<int> save(
    Transaction txn,
    String kind,
    String name, {
    int? id,
    int? branch,
    String? expectedName,
    int? expectedActive,
  }) async {
    final clean = cleanName(kind, name);
    await _scope(txn, kind, branch);
    final info = spec(kind);
    final before = id == null ? null : await row(txn, kind, id, branch);
    if (before != null) {
      _expected(before, expectedName, expectedActive);
    }
    final duplicates = await txn.query(
      info.$1,
      columns: ['id'],
      where:
          'name = ?${info.$3 ? ' AND branch_id = ?' : ''}${id == null ? '' : ' AND id != ?'}',
      whereArgs: [clean, if (info.$3) branch, ?id],
      limit: 1,
    );
    if (duplicates.isNotEmpty) {
      throw StateError(
        'Category already exists. Restore its archived entry if needed',
      );
    }
    if (before != null && before['name'] == clean) return before['id'] as int;
    final int saved;
    if (id == null) {
      saved = await txn.insert(info.$1, {
        'name': clean,
        if (info.$3) 'branch_id': branch,
      });
    } else {
      saved = id;
      final count = await txn.update(
        info.$1,
        {'name': clean},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) {
        throw StateError('Category changed. Reload');
      }
    }
    await _log(
      txn,
      kind,
      saved,
      branch,
      before == null ? 'created' : 'renamed',
      before,
      await row(txn, kind, saved, branch),
    );
    return saved;
  }

  static Future<String> ensureOtherMoneyName(
    Transaction txn,
    String name, {
    String? previousName,
  }) async {
    final clean = cleanName('other_money', name);
    // Editing a historical voucher may retain its old name after catalog rename.
    if (previousName == clean) return clean;
    final rows = await txn.query(
      'other_money_categories',
      where: 'name = ?',
      whereArgs: [clean],
    );
    if (rows.isNotEmpty) {
      if (rows.single['active'] != 1) {
        throw StateError(
          'Restore this archived category or choose an active one',
        );
      }
      return rows.single['name'] as String;
    }
    final id = await save(txn, 'other_money', clean);
    return (await row(txn, 'other_money', id, null))['name'] as String;
  }

  static Future<List<String>> aliases(
    Transaction txn,
    String kind,
    Map<String, Object?> category,
  ) async {
    final logs = await txn.query(
      'category_changes',
      columns: ['before_name', 'after_name'],
      where: 'category_kind = ? AND category_id = ?',
      whereArgs: [kind, category['id']],
    );
    final names = <String>{};
    void add(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        names.add(value);
      }
    }

    add(category['name']);
    for (final log in logs) {
      add(log['before_name']);
      add(log['after_name']);
    }
    return names.toList();
  }

  static Future<int> _names(
    Transaction txn,
    String source,
    String column,
    List<String> names, {
    String where = '1 = 1',
    List<Object?> args = const [],
  }) async {
    final ids = <int>{};
    for (var offset = 0; offset < names.length; offset += 400) {
      final batch = names.skip(offset).take(400).toList();
      final rows = await txn.rawQuery(
        'SELECT id FROM $source WHERE $where AND $column COLLATE NOCASE IN (${List.filled(batch.length, '?').join(',')})',
        [...args, ...batch],
      );
      ids.addAll(rows.map((r) => r['id'] as int));
    }
    return ids.length;
  }

  static Future<CategoryUsage> usage(
    Transaction txn,
    String kind,
    Map<String, Object?> category,
  ) async {
    final names = await aliases(txn, kind, category);
    final nameSet = names.map((n) => n.toLowerCase()).toSet();
    if (kind == 'product') {
      final products =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n FROM products WHERE category_id = ?',
                [category['id']],
              )).single['n']
              as int;
      final docs = await _names(txn, 'purchase_items', 'category_name', names);
      final brands =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n FROM product_brands WHERE category_id=?',
                [category['id']],
              )).single['n']
              as int;
      var drafts = 0;
      var uncertain = false;
      final work = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['purchase_recovery'],
      );
      if (work.isNotEmpty) {
        try {
          final decoded = jsonDecode(work.single['value'] as String);
          if (decoded is! Map ||
              (decoded['lines'] != null && decoded['lines'] is! List)) {
            uncertain = true;
          } else {
            for (final line in (decoded['lines'] as List? ?? [])) {
              if (line is! Map || line['category_id'] is! int) {
                uncertain = true;
              } else if (line['category_id'] == category['id']) {
                drafts++;
              }
            }
          }
        } catch (_) {
          uncertain = true;
        }
      }
      return CategoryUsage(
        products: products,
        documents: docs,
        drafts: drafts,
        history: brands,
        uncertain: uncertain,
      );
    }
    if (kind == 'expense') {
      final branch = category['branch_id'];
      final docs = await _names(
        txn,
        'expenses',
        'category',
        names,
        where: 'branch_id = ?',
        args: [branch],
      );
      final edits = await txn.rawQuery(
        '''SELECT e.id, e.previous_category, e.category FROM expense_edits e
        JOIN expenses x ON x.id = e.expense_id WHERE x.branch_id = ?''',
        [branch],
      );
      final history = edits
          .where(
            (e) =>
                nameSet.contains('${e['previous_category']}'.toLowerCase()) ||
                nameSet.contains('${e['category']}'.toLowerCase()),
          )
          .length;
      return CategoryUsage(documents: docs, history: history);
    }
    final docs = await _names(txn, 'other_money_vouchers', 'category', names);
    final logs = await txn.query(
      'other_money_revisions',
      columns: ['before_json', 'after_json'],
    );
    var history = 0;
    var uncertain = false;
    for (final log in logs) {
      try {
        final before = jsonDecode(log['before_json'] as String),
            after = jsonDecode(log['after_json'] as String);
        if (before is! Map || after is! Map) {
          uncertain = true;
        } else if (nameSet.contains('${before['category']}'.toLowerCase()) ||
            nameSet.contains('${after['category']}'.toLowerCase())) {
          history++;
        }
      } catch (_) {
        uncertain = true;
      }
    }
    return CategoryUsage(
      documents: docs,
      history: history,
      uncertain: uncertain,
    );
  }

  static Future<void> setActive(
    Transaction txn,
    String kind,
    int id,
    bool active, {
    int? branch,
    String? expectedName,
    int? expectedActive,
  }) async {
    final before = await row(txn, kind, id, branch);
    _expected(before, expectedName, expectedActive);
    if (!active && isDefault(kind, id)) {
      throw StateError('The default product category must remain available');
    }
    if (before['active'] == (active ? 1 : 0)) return;
    if (!active && kind == 'product') {
      final links = await usage(txn, kind, before);
      if (links.drafts > 0 || links.uncertain) {
        throw StateError(
          'Finish or change the unfinished purchase before archiving this category',
        );
      }
    }
    await txn.update(
      spec(kind).$1,
      {'active': active ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _log(
      txn,
      kind,
      id,
      branch,
      active ? 'restored' : 'archived',
      before,
      await row(txn, kind, id, branch),
    );
  }

  static Future<String> remove(
    Transaction txn,
    String kind,
    int id, {
    int? branch,
    String? expectedName,
    int? expectedActive,
  }) async {
    final before = await row(txn, kind, id, branch);
    _expected(before, expectedName, expectedActive);
    if (isDefault(kind, id)) {
      throw StateError('The default product category cannot be deleted');
    }
    final links = await usage(txn, kind, before);
    if (links.used) {
      await setActive(
        txn,
        kind,
        id,
        false,
        branch: branch,
        expectedName: expectedName,
        expectedActive: expectedActive,
      );
      return 'archived';
    }
    await _log(txn, kind, id, branch, 'deleted', before, null);
    await txn.delete(spec(kind).$1, where: 'id = ?', whereArgs: [id]);
    return 'deleted';
  }
}
