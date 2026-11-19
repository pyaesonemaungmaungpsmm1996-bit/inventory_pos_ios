import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// One unfinished transfer per source branch, inside the matching POS database.
class TransferWorkStore {
  static String key(int source) => 'transfer_work_v1:$source';
  static Future<Map<String, dynamic>?> read(
    DatabaseExecutor db,
    int source,
  ) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key=?',
      whereArgs: [key(source)],
    );
    if (rows.isEmpty) return null;
    final text = rows.single['value'] as String;
    if (text.length > 1000000) {
      throw const FormatException('Transfer draft is too large');
    }
    final value = jsonDecode(text) as Map<String, dynamic>;
    if (value['source'] != source ||
        value['version'] != 1 ||
        value['lines'] is! List ||
        (value['lines'] as List).length > 200 ||
        !RegExp(r'^[0-9a-f]{48}$').hasMatch('${value['request_key']}')) {
      throw const FormatException('Invalid saved transfer draft');
    }
    final posted = await db.query(
      'transfer_vouchers',
      columns: ['id'],
      where: 'request_key=?',
      whereArgs: [value['request_key']],
      limit: 1,
    );
    if (posted.isNotEmpty) {
      await clear(db, source);
      return null;
    }
    return value;
  }

  static Future<void> save(
    DatabaseExecutor db,
    int source,
    Map<String, Object?> value,
  ) async {
    final text = jsonEncode({...value, 'version': 1, 'source': source});
    if (text.length > 1000000) {
      throw const FormatException('Transfer draft is too large');
    }
    await db.insert('app_settings', {
      'key': key(source),
      'value': text,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> clear(DatabaseExecutor db, int source) => db
      .delete('app_settings', where: 'key=?', whereArgs: [key(source)])
      .then((_) {});
}
