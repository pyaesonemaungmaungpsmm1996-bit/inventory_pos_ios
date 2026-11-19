import 'dart:math';

import 'package:timezone/timezone.dart' as tz;

import 'app_currency.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'activity_store.dart';
import 'report_models.dart';

class ActivityFilter {
  const ActivityFilter({
    required this.from,
    required this.to,
    this.module,
    this.action,
    this.branch,
    this.origin,
    this.technical = false,
    this.includeGlobal = true,
    this.search = '',
  });
  final String from, to, search;
  final String? module, action, origin;
  final int? branch;
  final bool technical, includeGlobal;
}

(int, int) activityDateBounds(String from, String to) {
  DateTime valid(String text) {
    final parsed = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != text) {
      throw ArgumentError('Invalid activity date');
    }
    return parsed;
  }

  final first = valid(from), last = valid(to);
  if (first.isAfter(last)) {
    throw ArgumentError('Invalid activity date range');
  }
  AppDateTime.initialize();
  final location = tz.getLocation(AppDateTime.current.value);
  return (
    tz.TZDateTime(
      location,
      first.year,
      first.month,
      first.day,
    ).millisecondsSinceEpoch,
    tz.TZDateTime(
      location,
      last.year,
      last.month,
      last.day + 1,
    ).millisecondsSinceEpoch,
  );
}

String activityLocalTime(Object? value) {
  final instant = AppDateTime.parse(value);
  if (instant == null) return '—';
  AppDateTime.initialize();
  final local = tz.TZDateTime.from(
    instant,
    tz.getLocation(AppDateTime.current.value),
  );
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class ActivityPageData {
  const ActivityPageData(this.rows, this.total);
  final List<Map<String, Object?>> rows;
  final int total;
}

class ActivityRepository {
  static (String, List<Object?>) filterSql(ActivityFilter filter) {
    final bounds = activityDateBounds(filter.from, filter.to);
    final clauses = <String>['event_ms >= ?', 'event_ms < ?'];
    final args = <Object?>[bounds.$1, bounds.$2];
    if (!filter.technical) clauses.add('technical = 0');
    if (filter.module != null) {
      clauses.add('module = ?');
      args.add(filter.module);
    }
    if (filter.action != null) {
      clauses.add('action = ?');
      args.add(filter.action);
    }
    if (filter.origin != null) {
      clauses.add('origin = ?');
      args.add(filter.origin);
    }
    if (filter.branch != null) {
      clauses.add(
        '(branch_id = ? OR peer_branch_id = ?${filter.includeGlobal ? ' OR (branch_id IS NULL AND peer_branch_id IS NULL)' : ''})',
      );
      args.addAll([filter.branch, filter.branch]);
    }
    if (filter.search.trim().isNotEmpty) {
      final text = filter.search
          .trim()
          .replaceAll('!', '!!')
          .replaceAll('%', '!%')
          .replaceAll('_', '!_');
      const columns = [
        'reference',
        'source_table',
        'record_id',
        'actor_name',
        'changed_fields',
        'before_summary',
        'after_summary',
      ];
      clauses.add(
        '(${columns.map((c) => "$c LIKE ? ESCAPE '!' ").join(' OR ')})',
      );
      args.addAll(List.filled(columns.length, '%$text%'));
    }
    return (clauses.join(' AND '), args);
  }

  static Future<Map<String, List<Map<String, Object?>>>> options() async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final branches = List<Map<String, Object?>>.of(
        await txn.query('branches', orderBy: 'name, id'),
      );
      final seen = branches.map((r) => r['id']).toSet();
      final recorded = await txn.rawQuery(
        'SELECT branch_id AS id FROM activity_events WHERE branch_id IS NOT NULL UNION SELECT peer_branch_id AS id FROM activity_events WHERE peer_branch_id IS NOT NULL',
      );
      for (final r in recorded) {
        if (seen.add(r['id'])) {
          branches.add({
            'id': r['id'],
            'name': 'Earlier branch #${r['id']}',
            'code': 'history',
          });
        }
      }
      return {
        'branches': branches,
        'modules': await txn.rawQuery(
          'SELECT DISTINCT module AS value FROM activity_events ORDER BY module',
        ),
        'actions': await txn.rawQuery(
          'SELECT DISTINCT action AS value FROM activity_events ORDER BY action',
        ),
      };
    });
  }

  static Future<ActivityPageData> page(
    ActivityFilter filter, {
    int? beforeTime,
    int? beforeId,
  }) async {
    final where = filterSql(filter);
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final count =
          (await txn.rawQuery(
                'SELECT COUNT(*) AS n FROM activity_events WHERE ${where.$1}',
                where.$2,
              )).single['n']
              as int;
      final cursor = beforeTime == null || beforeId == null
          ? ''
          : ' AND (event_ms < ? OR (event_ms = ? AND id < ?))';
      final rows = await txn.rawQuery(
        'SELECT * FROM activity_events WHERE ${where.$1}$cursor ORDER BY event_ms DESC, id DESC LIMIT 80',
        [
          ...where.$2,
          if (cursor.isNotEmpty) ...[beforeTime, beforeTime, beforeId],
        ],
      );
      return ActivityPageData(rows, count);
    });
  }

  static Future<Map<String, Object?>> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'activity_events',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) {
      throw StateError('Activity record no longer exists');
    }
    return rows.single;
  }

  static Future<void> _appendUi(
    String source,
    String record,
    String module,
    String action,
    String before,
    String after,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final actor = await txn.query('activity_context', where: 'id = 1');
      await ActivityStore.append(
        txn,
        key:
            'ui:${DateTime.now().toUtc().microsecondsSinceEpoch}:${Random.secure().nextInt(1 << 32)}',
        source: source,
        record: record,
        reference: record,
        module: module,
        action: action,
        origin: 'tracked',
        before: before,
        after: after,
        actor: actor.isEmpty
            ? 'Not recorded'
            : actor.single['actor_name'] as String,
        actorId: actor.isEmpty ? null : actor.single['actor_id'] as int?,
      );
    });
  }

  static Future<void> preference(
    String key,
    String before,
    String after,
  ) async {
    if (before == after) return;
    await _appendUi(
      'preferences',
      key,
      'settings',
      'preference_update',
      before,
      after,
    );
  }

  static Future<void> exportPrepared(ReportBook book, String format) async {
    await _appendUi(
      'report_export',
      book.title,
      'reports',
      'export_prepared',
      '',
      'format=$format\nreport=${book.title}\ntables=${book.tables.length}\nrows=${book.tables.fold<int>(0, (n, t) => n + t.rows.length)}\n'
          'Report bytes were prepared. This does not confirm a completed print, save, delivery or share.',
    );
  }

  static Object? _money(Map<String, Object?> row, String key) {
    final amount = row[key];
    if (amount is! int) return null;
    final digits = AppCurrency.precision[row['currency_code']];
    return digits == 2 ? amount / 100 : amount;
  }

  static ReportBook _book(
    List<Map<String, Object?>> rows,
    String business,
    String labels,
  ) {
    final groups = <String, int>{};
    for (final r in rows) {
      final key = '${r['module']} / ${r['action']}';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    return ReportBook(
      title: 'Activity History',
      business: business,
      filters:
          '$labels | Display timezone ${AppDateTime.current.value}. Activities are database events, '
          'not unique financial transactions; amounts must not be summed. Tracked = captured after v39. '
          'Saved history = original saved revisions; timestamp only = time evidence without original field values. '
          'Actor Not recorded means no authenticated identity was captured. Branch labels can use current names. '
          'Before/after text keeps stored database units; numeric amount columns use recorded currency units. '
          'Summaries remain after voucher deletion; original voucher/photo rows are still deleted. '
          'Export-prepared events do not prove files were delivered or saved.',
      tables: [
        ReportTable(
          'Event Counts',
          ['Module / Action', 'Count'],
          [
            for (final e in groups.entries) [e.key, e.value],
          ],
        ),
        ReportTable(
          'Activity Log',
          [
            'Activity ID',
            'Local time',
            'Recorded UTC',
            'Module',
            'Action',
            'Reference',
            'Source table',
            'Record ID',
            'Branch ID',
            'Other branch ID',
            'Actor ID',
            'Actor',
            'Evidence origin',
            'Technical',
            'Changed fields',
            'Amount field',
            'Amount before',
            'Amount after',
            'Currency',
            'Before summary',
            'After summary',
          ],
          [
            for (final r in rows)
              [
                r['id'],
                activityLocalTime(r['event_at']),
                r['event_at'],
                r['module'],
                r['action'],
                r['reference'],
                r['source_table'],
                r['record_id'],
                r['branch_id'],
                r['peer_branch_id'],
                r['actor_id'],
                r['actor_name'],
                r['origin'],
                r['technical'] == 1 ? 'Yes' : 'No',
                r['changed_fields'],
                r['amount_field'],
                _money(r, 'amount_before'),
                _money(r, 'amount_after'),
                r['currency_code'],
                r['before_summary'],
                r['after_summary'],
              ],
          ],
          moneyColumns: {16, 17},
        ),
      ],
    );
  }

  static Future<ReportBook> report(ActivityFilter filter, String labels) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    final db = await AppDatabase.instance.database;
    final where = filterSql(filter);
    final rows = await db.rawQuery(
      'SELECT * FROM activity_events WHERE ${where.$1} ORDER BY event_ms DESC, id DESC',
      where.$2,
    );
    return _book(rows, '${profile['name'] ?? ''}', labels);
  }

  static Future<ReportBook> reportOne(int id) async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    return _book([await get(id)], '${profile['name'] ?? ''}', 'Activity #$id');
  }
}
