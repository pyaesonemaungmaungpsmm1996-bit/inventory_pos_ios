import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A journal for replacing one closed SQLite file. Recovery always prefers the
/// original if the replacement was not explicitly committed.
class BackupFiles {
  static File marker(String live) => File('$live.restore_pending.json');
  static Future<void> removeSidecars(String live) async {
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final file = File('$live$suffix');
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static Future<void> begin(String live, String stage, String rollback) async {
    if (await marker(live).exists()) {
      throw StateError('An unfinished restore needs recovery first');
    }
    final directory = p.dirname(live);
    if (p.dirname(stage) != directory ||
        p.dirname(rollback) != directory ||
        !p.basename(stage).startsWith('${p.basename(live)}.stage.') ||
        !p
            .basename(rollback)
            .startsWith('${p.basename(live)}.before_restore.')) {
      throw StateError('Invalid restore paths');
    }
    if (!await File(live).exists() ||
        !await File(stage).exists() ||
        await File(rollback).exists()) {
      throw StateError('Restore files are not ready');
    }
    final writing = File('${marker(live).path}.writing');
    await writing.writeAsString(
      jsonEncode({
        'stage': p.basename(stage),
        'rollback': p.basename(rollback),
      }),
      flush: true,
    );
    await writing.rename(marker(live).path);
  }

  static Future<bool> recover(String live) async {
    final journal = marker(live);
    if (!await journal.exists()) {
      return false;
    }
    final record = Map<String, dynamic>.from(
      jsonDecode(await journal.readAsString()) as Map,
    );
    final stageName = record['stage'], rollbackName = record['rollback'];
    bool valid(Object? name, String prefix) =>
        name is String &&
        p.basename(name) == name &&
        !name.contains('/') &&
        !name.contains('\\') &&
        name.startsWith(prefix);
    if (!valid(stageName, '${p.basename(live)}.stage.') ||
        !valid(rollbackName, '${p.basename(live)}.before_restore.')) {
      throw StateError(
        'Restore journal is invalid. Keep all database files for recovery.',
      );
    }
    final stage = File(p.join(p.dirname(live), stageName as String));
    final rollback = File(p.join(p.dirname(live), rollbackName as String));
    if (await rollback.exists()) {
      await removeSidecars(live);
      if (await File(live).exists()) {
        await File(live).delete();
      }
      await rollback.rename(live);
    } else if (!await File(live).exists()) {
      throw StateError('Original database is missing. Keep the restore files.');
    }
    if (await stage.exists()) {
      await stage.delete();
    }
    await journal.delete();
    return true;
  }

  static Future<void> commit(String live) async {
    await marker(live).delete();
  }
}
