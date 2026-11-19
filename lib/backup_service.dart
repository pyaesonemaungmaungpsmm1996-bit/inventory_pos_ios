import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'backup_gate.dart';
import 'sqlite_backup.dart';

class BackupService {
  static Future<Directory> folder() async =>
      Directory(p.join(await getDatabasesPath(), 'toe_pwar_backups'))
          .create(recursive: true);
  static Future<BackupInfo> inspect(String path) async {
    final db = await AppDatabase.instance.database;
    final legacy = await db.query(
      'app_settings',
      where: 'key=?',
      whereArgs: ['backup_schema_v39'],
    );
    return SqliteBackup.inspect(
      path,
      legacySchema: legacy.isEmpty ? null : legacy.single['value'] as String,
      expectedSchema: await SqliteBackup.schema(db),
      expectedVersion: await db.getVersion(),
    );
  }

  static Future<BackupInfo> create() =>
      BackupGate.run('backup_maintenance', _create);
  static Future<BackupInfo> _create() async {
    final db = await AppDatabase.instance.database;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final destination = p.join(
      (await folder()).path,
      'toe_pwar_pos_$stamp.tppos',
    );
    final partial = '$destination.partial';
    try {
      await SqliteBackup.create(db, partial);
      await inspect(partial);
      await File(partial).rename(destination);
      return await inspect(destination);
    } catch (_) {
      if (await File(partial).exists()) {
        await File(partial).delete();
      }
      rethrow;
    }
  }

  static Future<List<File>> files() async {
    final db = await AppDatabase.instance.database;
    final result = <File>[];
    final backups = await folder();
    for (final directory in [backups, Directory(p.dirname(db.path))]) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.tppos')) &&
            (p.dirname(entity.path) == backups.path ||
                p
                    .basename(entity.path)
                    .startsWith('${p.basename(db.path)}.before_restore.'))) {
          result.add(entity);
        }
      }
    }
    result.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return result;
  }

  static Future<String?> importFile() async {
    final chosen = await FilePicker.pickFile(
      dialogTitle: 'Choose Toe Pwar POS backup',
      type: FileType.any,
    );
    if (chosen == null) {
      return null;
    }
    final length = await chosen.length();
    if (length != null && length > SqliteBackup.maxBytes) {
      throw StateError('Choose a backup smaller than 512 MB');
    }
    final destination = File(
      p.join(
        (await folder()).path,
        'import_${DateTime.now().microsecondsSinceEpoch}.partial',
      ),
    );
    final output = destination.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in chosen.readAsByteStream()) {
        bytes += chunk.length;
        if (bytes > SqliteBackup.maxBytes) {
          throw StateError('Backup exceeds 512 MB');
        }
        output.add(chunk);
      }
      await output.flush();
      await output.close();
      await inspect(destination.path);
      return destination.path;
    } catch (_) {
      await output.close();
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }
}
