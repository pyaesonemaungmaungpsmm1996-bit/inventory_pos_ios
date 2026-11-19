import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_datetime.dart';
import 'category_store.dart';

/// Reuses definitions, never another branch's cash or opening balance.
class BranchReuse {
  static Future<List<Map<String, Object?>>> accounts(int target) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      '''SELECT a.*,b.name branch_name,COALESCE((SELECT value FROM app_settings WHERE key='money_account_holder:'||a.id),'') account_holder FROM money_accounts a JOIN branches b ON b.id=a.branch_id WHERE a.branch_id<>? ORDER BY a.name COLLATE NOCASE,b.name''',
      [target],
    );
  }

  static Future<int> account(int source, int target) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final sourceRows = await txn.rawQuery(
        '''SELECT a.*,COALESCE((SELECT value FROM app_settings WHERE key='money_account_holder:'||a.id),'') account_holder FROM money_accounts a WHERE a.id=?''',
        [source],
      );
      if (sourceRows.isEmpty) {
        throw StateError('Source account no longer exists');
      }
      final s = sourceRows.single;
      final found = await txn.query(
        'money_accounts',
        where: 'branch_id=? AND name=? COLLATE NOCASE',
        whereArgs: [target, s['name']],
      );
      if (found.isNotEmpty) {
        final existing = found.single;
        if (existing['type'] != s['type'] ||
            existing['account_number'] != s['account_number']) {
          throw StateError(
            'An account with this name already has different details in the target branch',
          );
        }
        return existing['id'] as int;
      }
      final today = AppDateTime.today().toIso8601String().substring(0, 10),
          now = DateTime.now().toUtc().toIso8601String();
      final id = await txn.insert('money_accounts', {
        'branch_id': target,
        'name': s['name'],
        'type': s['type'],
        'account_number': s['account_number'],
        'remark': s['remark'],
        'opening_date': today,
        'created_at': now,
      });
      await txn.insert('app_settings', {
        'key': 'money_account_holder:$id',
        'value': s['account_holder'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('money_entries', {
        'account_id': id,
        'kind': 'opening',
        'amount': 0,
        'entry_date': today,
        'note': 'Opening balance · reused account details',
        'created_at': now,
      });
      return id;
    });
  }

  static Future<List<Map<String, Object?>>> expenseCategories(
    int target,
  ) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery(
      'SELECT c.*,b.name branch_name FROM expense_categories c JOIN branches b ON b.id=c.branch_id WHERE c.branch_id<>? AND c.active=1 ORDER BY c.name COLLATE NOCASE,b.name',
      [target],
    );
  }

  static Future<int> expenseCategory(int source, int target) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'expense_categories',
        where: 'id=? AND active=1',
        whereArgs: [source],
      );
      if (rows.isEmpty) throw StateError('Source category no longer available');
      final s = rows.single;
      final existing = await txn.query(
        'expense_categories',
        where: 'branch_id=? AND name=? COLLATE NOCASE',
        whereArgs: [target, s['name']],
      );
      if (existing.isNotEmpty) {
        final e = existing.single;
        if (e['active'] != 1) {
          await CategoryStore.setActive(
            txn,
            'expense',
            e['id'] as int,
            true,
            branch: target,
          );
        }
        return e['id'] as int;
      }
      return CategoryStore.save(
        txn,
        'expense',
        s['name'] as String,
        branch: target,
      );
    });
  }
}
