import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_database.dart';
import 'backup_service.dart';
import 'cloud_backup_record.dart';
import 'online_account_service.dart';
import 'sqlite_backup.dart';

class CloudBackupService {
  static void guard(String userId) {
    if (OnlineAccounts.client.auth.currentUser?.id != userId) {
      throw StateError(
        'Login changed. Refresh and sign in as the intended Owner',
      );
    }
  }

  static Future<List<CloudBackupRecord>> list(
    String business,
    String userId,
  ) async {
    guard(userId);
    final result = await OnlineAccounts.client.rpc(
      'tp_cloud_backup_list',
      params: {'p_business': business},
    );
    guard(userId);
    return (result as List)
        .map(
          (r) => CloudBackupRecord.fromJson(
            Map<String, dynamic>.from(r as Map),
            business,
          ),
        )
        .toList();
  }

  static Future<void> upload(String business, String userId) async {
    guard(userId);
    final local = await BackupService.create();
    if (local.bytes > CloudBackupRecord.maxBytes) {
      throw StateError(
        'Cloud pilot accepts up to 20 MB per backup. Your local backup has been kept',
      );
    }
    final hash = (await sha256.bind(File(local.path).openRead()).first)
        .toString();
    final schema = await SqliteBackup.schema(
      await AppDatabase.instance.database,
    );
    guard(userId);
    final reserved = Map<String, dynamic>.from(
      await OnlineAccounts.client.rpc(
        'tp_cloud_backup_start',
        params: {
          'p_business': business,
          'p_bytes': local.bytes,
          'p_sha256': hash,
          'p_schema_sha256': sha256.convert(utf8.encode(schema)).toString(),
          'p_db_version': local.version,
          'p_source_business': local.businessName,
          'p_counts': local.counts,
        },
      ) as Map,
    );
    final id = reserved['id'] as String,
        destination = reserved['object_name'] as String;
    if (destination != '$business/$id.tppos') {
      throw StateError('Unexpected cloud destination');
    }
    try {
      guard(userId);
      await OnlineAccounts.client.storage
          .from(CloudBackupRecord.bucket)
          .upload(
            destination,
            File(local.path),
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              cacheControl: '0',
              upsert: false,
            ),
          );
      guard(userId);
      await OnlineAccounts.client.rpc(
        'tp_cloud_backup_finish',
        params: {'p_backup': id},
      );
    } catch (e) {
      throw StateError(
        'Cloud upload status needs checking. Local backup is retained. Refresh; if Pending, try Finish upload or remove the incomplete entry. Details: $e',
      );
    }
  }

  static Future<void> finish(CloudBackupRecord record, String userId) async {
    guard(userId);
    final data = await OnlineAccounts.client.storage
        .from(CloudBackupRecord.bucket)
        .download(record.objectName);
    record.verify(data);
    guard(userId);
    await OnlineAccounts.client.rpc(
      'tp_cloud_backup_finish',
      params: {'p_backup': record.id},
    );
  }

  static Future<String> download(
    CloudBackupRecord record,
    String userId,
  ) async {
    if (record.state != 'ready') {
      throw StateError('Only a Ready cloud backup can be downloaded');
    }
    guard(userId);
    final data = await OnlineAccounts.client.storage
        .from(CloudBackupRecord.bucket)
        .download(record.objectName);
    record.verify(data);
    guard(userId);
    final path = p.join(
      (await BackupService.folder()).path,
      'cloud_${record.id}_${DateTime.now().microsecondsSinceEpoch}.tppos',
    );
    final partial = File('$path.partial');
    try {
      await partial.writeAsBytes(data, flush: true);
      await partial.rename(path);
      // Recovery downloads must remain available even if this audit notice fails.
      try {
        guard(userId);
        await OnlineAccounts.client.rpc(
          'tp_cloud_backup_download_notice',
          params: {'p_backup': record.id, 'p_business': record.businessId},
        );
      } catch (_) {
        /* Best-effort client-reported audit; the downloaded file is valid. */
      }
      return path;
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  static Future<void> delete(CloudBackupRecord record, String userId) async {
    guard(userId);
    final object = await OnlineAccounts.client.rpc(
      'tp_cloud_backup_delete_prepare',
      params: {'p_backup': record.id},
    );
    if (object != record.objectName) {
      throw StateError('Unexpected cloud deletion target');
    }
    guard(userId);
    await OnlineAccounts.client.storage.from(CloudBackupRecord.bucket).remove([
      record.objectName,
    ]);
    guard(userId);
    await OnlineAccounts.client.rpc(
      'tp_cloud_backup_delete_finish',
      params: {'p_backup': record.id, 'p_business': record.businessId},
    );
  }
}
