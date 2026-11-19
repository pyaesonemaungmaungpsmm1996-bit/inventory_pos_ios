import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_datetime.dart';

/// Read-only branch snapshots. Does not change the sale/default branch or license.
class DashboardRepository {
  static Future<Map<String, Object?>> overview(
    int branch, {
    required bool today,
  }) async {
    final db = await AppDatabase.instance.database;
    final range = today
        ? AppDateTime.currentDayUtcRange()
        : AppDateTime.currentMonthUtcRange();
    return read(db, branch, range.$1, range.$2);
  }

  static Future<Map<String, Object?>> read(
    Database db,
    int branch,
    DateTime from,
    DateTime to,
  ) => db.transaction((txn) async {
    if ((await txn.query(
      'branches',
      columns: ['id'],
      where: 'id=?',
      whereArgs: [branch],
    )).isEmpty) {
      throw StateError('Branch no longer exists. Refresh the list.');
    }
    final args = [
      branch,
      from.toUtc().toIso8601String(),
      to.toUtc().toIso8601String(),
    ];
    final sales = await txn.rawQuery(
      "SELECT COALESCE(SUM(total),0) amount FROM sale_invoices WHERE branch_id=? AND status='posted' AND confirmed_at>=? AND confirmed_at<?",
      args,
    );
    final expenses = await txn.rawQuery(
      "SELECT COALESCE(SUM(amount),0) amount FROM expenses WHERE branch_id=? AND status='posted' AND posted_at>=? AND posted_at<?",
      args,
    );
    final balance = await txn.rawQuery(
      'SELECT COALESCE(SUM(e.amount),0) amount FROM money_accounts a JOIN money_entries e ON e.account_id=a.id WHERE a.branch_id=?',
      [branch],
    );
    final latest = await recent(txn, branch);
    return {
      'sales': sales.single['amount'],
      'expenses': expenses.single['amount'],
      'balance': balance.single['amount'],
      'recent': latest,
      'loaded_at': DateTime.now().toUtc().toIso8601String(),
    };
  });

  /// Recent means latest recorded transactions in this branch, independent of KPI period.
  static Future<List<Map<String, Object?>>> recent(
    DatabaseExecutor db,
    int branch, {
    int limit = 5,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > 50 || offset < 0) {
      throw ArgumentError('Invalid history page');
    }
    return db.rawQuery(
      '''SELECT * FROM (
      SELECT 'sale' kind,id,total amount,confirmed_at recorded_at,status FROM sale_invoices WHERE branch_id=?
      UNION ALL SELECT 'purchase',id,total,confirmed_at,status FROM purchase_invoices WHERE branch_id=?
      UNION ALL SELECT 'receipt',id,total,created_at,status FROM customer_receipts WHERE branch_id=?
    ) ORDER BY recorded_at DESC,kind,id DESC LIMIT ? OFFSET ?''',
      [branch, branch, branch, limit, offset],
    );
  }
}
