import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

class BackupInfo {
  const BackupInfo({
    required this.path,
    required this.bytes,
    required this.version,
    required this.businessName,
    required this.currency,
    required this.counts,
  });
  final String path, businessName, currency;
  final int bytes, version;
  final Map<String, int> counts;
}

class SqliteBackup {
  static const maxBytes = 512 * 1024 * 1024;
  static Future<String> schema(DatabaseExecutor db) async => jsonEncode(
    await db.rawQuery(
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' AND name <> 'android_metadata' ORDER BY type,name",
    ),
  );

  /// v40 only appends these columns and adds these tables/indexes. Project the
  /// trusted current schema back to v39 so a fresh install can validate v39 too.
  static String legacy42Schema(String current) {
    final rows = (jsonDecode(current) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    for (final row in rows) {
      if (row['type'] == 'table' && row['name'] == 'purchase_invoices') {
        row['sql'] = (row['sql'] as String)
            .replaceFirst('"purchase_invoices"', 'purchase_invoices')
            .replaceFirst('total >= 0 AND total <=', 'total > 0 AND total <=');
      }
    }
    return jsonEncode(rows);
  }

  static String legacy41Schema(String current) {
    current = legacy42Schema(current);
    final rows = (jsonDecode(current) as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    for (final row in rows) {
      final column = switch (row['name']) {
        'sale_drafts' => 'remark',
        'sale_invoices' => 'remark',
        'sale_draft_items' => 'item_discount',
        'sale_items' => 'item_discount',
        _ => null,
      };
      if (row['type'] == 'table' && column != null) {
        var sql = row['sql'] as String;
        for (final name in [
          'remark',
          'voucher_discount_amount',
          'desktop_payment_json',
          'item_discount',
          'color_snapshot',
          'size_snapshot',
        ]) {
          final marker = RegExp(',\\s*$name\\b').firstMatch(sql);
          if (marker == null) continue;
          var depth = 1;
          var quoted = false;
          var end = marker.end;
          for (; end < sql.length; end++) {
            final c = sql[end];
            if (c == "'") {
              if (quoted && end + 1 < sql.length && sql[end + 1] == "'") {
                end++;
                continue;
              }
              quoted = !quoted;
            }
            if (quoted) continue;
            if (c == '(') depth++;
            if (c == ')') depth--;
            if (depth == 0 || (c == ',' && depth == 1)) break;
          }
          sql = sql.substring(0, marker.start) + sql.substring(end);
        }
        row['sql'] = sql;
      }
    }
    return jsonEncode(rows);
  }

  static String legacy40Schema(String current) {
    current = legacy41Schema(current);
    final rows = (jsonDecode(current) as List)
        .where(
          (r) => ![
            'transfer_vouchers',
            'transfer_voucher_items',
            'transfer_voucher_lots',
          ].contains(r['tbl_name']),
        )
        .toList();
    return jsonEncode(rows);
  }

  static String legacy39Schema(String current) {
    current = legacy40Schema(current);
    final rows = (jsonDecode(current) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    const added = {
      'product_brands',
      'stock_lots',
      'sale_lot_allocations',
      'return_lot_allocations',
    };
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (added.contains(row['tbl_name'])) continue;
      final first = switch (row['name']) {
        'products' => 'brand_id',
        'sale_draft_items' => 'tracking_json',
        'sale_items' => 'tracking_json',
        'purchase_items' => 'tracking_json',
        _ => null,
      };
      if (row['type'] == 'table' && first != null) {
        final sql = row['sql'] as String;
        final marker = RegExp(',\\s*$first\\b').firstMatch(sql);
        if (marker == null) {
          throw StateError('Cannot project legacy backup schema');
        }
        row['sql'] =
            '${sql.substring(0, marker.start)}${sql.substring(sql.lastIndexOf(')'))}';
      }
      result.add(row);
    }
    return jsonEncode(result);
  }

  static Future<void> create(Database db, String destination) async {
    if (await File(destination).exists()) {
      throw StateError('Backup destination already exists');
    }
    try {
      // VACUUM INTO gives a consistent snapshot, including committed WAL data.
      await db.execute("VACUUM INTO '${destination.replaceAll("'", "''")}'");
      final handle = await File(destination).open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
    } catch (_) {
      if (await File(destination).exists()) {
        await File(destination).delete();
      }
      rethrow;
    }
  }

  static Future<BackupInfo> inspect(
    String path, {
    required String expectedSchema,
    required int expectedVersion,
    String? legacySchema,
  }) async {
    final file = File(path);
    final size = await file.length();
    if (size < 100 || size > maxBytes) {
      throw const FormatException(
        'Backup must be between 100 bytes and 512 MB',
      );
    }
    final input = await file.open();
    try {
      final header = await input.read(16);
      if (ascii.decode(header, allowInvalid: true) != 'SQLite format 3\u0000') {
        throw const FormatException(
          'Choose a Toe Pwar POS database backup, not an Excel/PDF/ZIP report',
        );
      }
    } finally {
      await input.close();
    }
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      await db.execute('PRAGMA trusted_schema = OFF');
      final version = await db.getVersion();
      final actualSchema = await schema(db);
      final legacy =
          (version == 39 &&
              [40, 41, 42, 43].contains(expectedVersion) &&
              actualSchema ==
                  (legacySchema ?? legacy39Schema(expectedSchema))) ||
          (version == 40 &&
              [41, 42, 43].contains(expectedVersion) &&
              actualSchema == legacy40Schema(expectedSchema)) ||
          (version == 41 &&
              [42, 43].contains(expectedVersion) &&
              actualSchema == legacy41Schema(expectedSchema)) ||
          (version == 42 &&
              expectedVersion == 43 &&
              actualSchema == legacy42Schema(expectedSchema));
      if (!legacy &&
          (version != expectedVersion || actualSchema != expectedSchema)) {
        throw const FormatException(
          'Backup database layout differs from this installation. Restore using a matching app/database version',
        );
      }
      final check = await db.rawQuery('PRAGMA integrity_check(20)');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw const FormatException('Backup integrity check failed');
      }
      if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const FormatException('Backup has broken linked records');
      }
      final profile = await db.query('business_profile', where: 'id = 1');
      if (profile.length != 1) {
        throw const FormatException('Business profile is missing');
      }
      final counts = <String, int>{};
      for (final table in [
        'products',
        'branches',
        'sale_invoices',
        'purchase_invoices',
        'expenses',
        'sale_returns',
        'money_accounts',
        'activity_events',
      ]) {
        final exists = await db.rawQuery(
          'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
          ['table', table],
        );
        if (exists.isNotEmpty) {
          counts[table] =
              Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM "$table"'),
              ) ??
              0;
        }
      }
      return BackupInfo(
        path: path,
        bytes: size,
        version: version,
        businessName: '${profile.single['name']}',
        currency: '${profile.single['currency_code']}',
        counts: counts,
      );
    } finally {
      await db.close();
    }
  }
}
