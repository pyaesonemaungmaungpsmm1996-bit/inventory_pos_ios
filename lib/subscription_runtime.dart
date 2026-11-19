import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Device-local license cache, never included in POS backup/restore.
/// Server entitlement is authoritative; this is not a root/tamper-proof DRM system.
class SubscriptionRuntime {
  static final changed = ValueNotifier<int>(0);
  static Future<T> use<T>(Future<T> Function(Database) body) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'tp_subscription_runtime.db'),
      version: 1,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA busy_timeout=3000'),
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE settings (id INTEGER PRIMARY KEY CHECK(id=1), value TEXT NOT NULL)',
        );
        await db.insert('settings', {'id': 1, 'value': '{}'});
      },
    );
    try {
      return await body(db);
    } finally {
      await db.close();
    }
  }

  static Future<Map<String, dynamic>> read() => use(
    (db) async => Map<String, dynamic>.from(
      jsonDecode(
        (await db.query('settings', where: 'id=1')).single['value'] as String,
      ) as Map,
    ),
  );
  static Future<void> change(
    void Function(Map<String, dynamic>) edit, {
    bool notify = true,
  }) async {
    await use(
      (db) => db.transaction((tx) async {
        final value = Map<String, dynamic>.from(
          jsonDecode(
            (await tx.query('settings', where: 'id=1')).single['value']
                as String,
          ) as Map,
        );
        edit(value);
        await tx.update('settings', {
          'value': jsonEncode(value),
        }, where: 'id=1');
      }),
    );
    if (notify) {
      changed.value++;
    }
  }

  static Future<void> bind(
    Map<String, dynamic> policy,
    int? localBranch,
    int? nextLocalBranch,
  ) async {
    await change((v) {
      if (v['business_id'] != null &&
          v['business_id'] != policy['business_id']) {
        throw StateError(
          'This POS database is already licensed to another online business. Contact support before rebinding',
        );
      }
      v.addAll(policy);
      v['local_branch'] = localBranch;
      v['next_local_branch'] = nextLocalBranch;
      v['bound'] = true;
      v['paused'] = false;
      v['pause_reason'] = null;
      v['wall_seen'] = DateTime.now().toUtc().toIso8601String();
      v['offset_ms'] =
          DateTime.parse(policy['server_now'] as String)
              .millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
    });
  }

  static Future<void> update(Map<String, dynamic> policy) async => change((v) {
    if (v['bound'] == true &&
        v['business_id'] == policy['business_id'] &&
        v['owner_id'] == policy['owner_id']) {
      // Roll the explicitly chosen local branch at the same scheduled boundary.
      if (v['next_from'] != null &&
          policy['next_plan'] == null &&
          policy['plan'] == 'standard') {
        v['local_branch'] = v['next_local_branch'];
        v['local_branch_name'] = v['next_local_branch_name'];
        v['next_local_branch'] = null;
        v['next_local_branch_name'] = null;
      }
      if (v['next_branch'] != policy['next_branch']) {
        v['next_local_branch'] = null;
      }
      v.addAll(policy);
      v['wall_seen'] = DateTime.now().toUtc().toIso8601String();
      v['offset_ms'] =
          DateTime.parse(policy['server_now'] as String)
              .millisecondsSinceEpoch -
          DateTime.now().millisecondsSinceEpoch;
    }
  });
  static DateTime effectiveNow(Map<String, dynamic> v, DateTime wall) =>
      wall.toUtc().add(Duration(milliseconds: (v['offset_ms'] as int?) ?? 0));
  static Map<String, dynamic> effective(Map<String, dynamic> v, DateTime wall) {
    final result = Map<String, dynamic>.from(v);
    final now = effectiveNow(v, wall);
    final next = DateTime.tryParse('${v['next_from']}');
    if (v['next_plan'] != null && next != null && !now.isBefore(next)) {
      result['plan'] = v['next_plan'];
      result['ends_at'] = v['next_until'];
      result['current_branch'] = v['next_branch'];
      result['next_plan'] = null;
      result['next_from'] = null;
      result['local_branch'] = v['next_local_branch'];
      result['local_branch_name'] = v['next_local_branch_name'];
    }
    final end = DateTime.tryParse('${result['ends_at']}');
    final seen = DateTime.tryParse('${v['wall_seen']}');
    result['clock_warning'] =
        seen != null &&
        wall.toUtc().isBefore(seen.subtract(const Duration(minutes: 5)));
    result['writable'] =
        v['provider_blocked'] != true &&
        v['actor_provider_blocked'] != true &&
        ['trial', 'standard', 'premium'].contains(result['plan']) &&
        v['bound'] == true &&
        v['paused'] != true &&
        result['clock_warning'] != true &&
        end != null &&
        now.isBefore(end) &&
        (result['plan'] != 'standard' ||
            (result['local_branch'] is int &&
                (v['device_branch'] == null ||
                    result['current_branch'] == v['device_branch'])));
    result['days_left'] = end == null
        ? null
        : (end.difference(now).inMilliseconds / Duration.millisecondsPerDay)
              .ceil();
    return result;
  }

  static Future<void> pauseAfterRestore() => change((v) {
    if (v['bound'] == true) {
      v['paused'] = true;
      v['pause_reason'] = 'restore';
    }
  });

  /// TEMP triggers stay outside sqlite_master, preserving backup layout/version 39.
  static Future<void> install(Database db) async {
    await db.execute(
      'CREATE TEMP TABLE IF NOT EXISTS tp_license_runtime (id INTEGER PRIMARY KEY, writable INTEGER, deadline INTEGER, offset_ms INTEGER, branch_id INTEGER, standard INTEGER)',
    );
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'android_metadata'",
    );
    final exempt = {
      'business_profile',
      'activity_events',
      'activity_context',
      'category_changes',
      'app_settings',
    };
    final columns = <String, Set<String>>{};
    final foreign = <String, List<Map<String, Object?>>>{};
    for (final row in tables) {
      final name = row['name'] as String;
      columns[name] = (await db.rawQuery(
        'PRAGMA table_info("${name.replaceAll('"', '""')}")',
      )).map((r) => r['name'] as String).toSet();
      foreign[name] = await db.rawQuery(
        'PRAGMA foreign_key_list("${name.replaceAll('"', '""')}")',
      );
    }
    String q(String value) => '"${value.replaceAll('"', '""')}"';
    List<String> scope(
      String table,
      String alias,
      Set<String> visited,
      int depth,
    ) {
      if (depth > 4 || visited.contains(table)) {
        return [];
      }
      final result = <String>[];
      if (columns[table]?.contains('branch_id') == true) {
        result.add(
          '$alias.branch_id IS NOT NULL AND $alias.branch_id<>(SELECT branch_id FROM temp.tp_license_runtime WHERE id=1)',
        );
      }
      if (table == 'branches') {
        result.add(
          '$alias.id<>(SELECT branch_id FROM temp.tp_license_runtime WHERE id=1)',
        );
      }
      for (final fk in foreign[table] ?? <Map<String, Object?>>[]) {
        final parent = fk['table'] as String, from = fk['from'] as String;
        final to = (fk['to'] as String?) ?? 'id';
        if (!columns.containsKey(parent)) {
          continue;
        }
        final parentAlias = 'lp$depth';
        final checks = scope(parent, parentAlias, {
          ...visited,
          table,
        }, depth + 1);
        if (checks.isNotEmpty) {
          result.add(
            'EXISTS(SELECT 1 FROM main.${q(parent)} $parentAlias WHERE $parentAlias.${q(to)}=$alias.${q(from)} AND (${checks.map((c) => '($c)').join(' OR ')}))',
          );
        }
      }
      return result;
    }

    for (final row in tables) {
      final table = row['name'] as String;
      if (exempt.contains(table)) {
        continue;
      }
      for (final operation in ['INSERT', 'UPDATE', 'DELETE']) {
        final trigger = 'tp_license_${table}_$operation';
        await db.execute('DROP TRIGGER IF EXISTS temp.${q(trigger)}');
        final checks = <String>[];
        if (operation != 'DELETE') {
          checks.addAll(scope(table, 'NEW', {}, 0));
        }
        if (operation != 'INSERT') {
          checks.addAll(scope(table, 'OLD', {}, 0));
        }
        // An active bound Standard licence may seed its first mapped local branch.
        // Existing branches still cannot be expanded or deleted under Standard.
        if (table == 'branches' && operation == 'INSERT') {
          checks.add('EXISTS(SELECT 1 FROM main.branches)');
        }
        if (table == 'branches' && operation == 'DELETE') {
          checks.add('1=1');
        }
        final scoped = checks.isEmpty
            ? '0'
            : checks.map((x) => '($x)').join(' OR ');
        await db.execute(
          'CREATE TEMP TRIGGER ${q(trigger)} BEFORE $operation ON main.${q(table)} WHEN '
          'COALESCE((SELECT writable FROM temp.tp_license_runtime WHERE id=1),0)=0 OR '
          '(CAST(strftime(\'%s\',\'now\') AS INTEGER)*1000+(SELECT offset_ms FROM temp.tp_license_runtime WHERE id=1)) >= (SELECT deadline FROM temp.tp_license_runtime WHERE id=1) OR '
          '((SELECT standard FROM temp.tp_license_runtime WHERE id=1)=1 AND ($scoped)) '
          'BEGIN SELECT RAISE(ABORT,\'Subscription read-only: renew your plan or select the licensed branch. Existing data is kept.\'); END',
        );
      }
    }
    await apply(db);
  }

  static Future<void> apply(Database db) async {
    Map<String, dynamic> raw;
    try {
      raw = await read();
    } catch (_) {
      raw = {};
    }
    final wall = DateTime.now().toUtc();
    final seen = DateTime.tryParse('${raw['wall_seen']}');
    if (raw['bound'] == true && (seen == null || wall.isAfter(seen))) {
      await change((v) {
        final prior = DateTime.tryParse('${v['wall_seen']}');
        if (prior == null || wall.isAfter(prior)) {
          v['wall_seen'] = wall.toIso8601String();
        }
      }, notify: false);
    }
    final value = effective(raw, wall);
    await db.rawInsert(
      'INSERT OR REPLACE INTO temp.tp_license_runtime(id,writable,deadline,offset_ms,branch_id,standard) VALUES(1,?,?,?,?,?)',
      [
        value['writable'] == true ? 1 : 0,
        DateTime.tryParse('${value['ends_at']}')?.millisecondsSinceEpoch ?? 0,
        raw['offset_ms'] ?? 0,
        value['local_branch'],
        value['plan'] == 'standard' ? 1 : 0,
      ],
    );
  }
}
