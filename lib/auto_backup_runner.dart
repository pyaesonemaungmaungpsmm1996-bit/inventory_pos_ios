import 'auto_backup_policy.dart';
import 'backup_change_tracker.dart';
import 'cloud_proxy_client.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auto_backup_store.dart';
import 'backup_files.dart';
import 'backup_gate.dart';
import 'cloud_backup_record.dart';
import 'online_account_service.dart';
import 'sqlite_backup.dart';

class AutoBackupRunner {
  static const secrets = FlutterSecureStorage();
  static String secretKey(String worker) => 'tp_auto_worker_$worker';
  static SupabaseClient isolatedClient() => SupabaseClient(
    OnlineAccounts.url,
    OnlineAccounts.key,
    httpClient: CloudProxyClient.forBuild(),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  static String uuid() {
    final r = Random.secure(), b = List.generate(16, (_) => 0);
    for (var i = 0; i < b.length; i++) {
      b[i] = r.nextInt(256);
    }
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<void> check(String worker, bool Function() stopped) async {
    final v = await AutoBackupStore.read();
    if (stopped() || v['enabled'] != true || v['worker'] != worker) {
      throw StateError('Auto Backup stopped');
    }
  }

  static Future<Map<String, dynamic>> capture(
    String worker,
    bool Function() stopped,
  ) => BackupGate.run('backup_maintenance', () async {
    await check(worker, stopped);
    final root = await getDatabasesPath(),
        live = p.join(await getDatabasesPath(), 'inventory_pos.db');
    if (!await File(live).exists() || await BackupFiles.marker(live).exists()) {
      throw StateError(
        'Open the app to finish database recovery before Auto Backup',
      );
    }
    final folder = await Directory(p.join(root, 'toe_pwar_auto_pending'))
        .create(recursive: true);
    final id = uuid(), captured = DateTime.now().toUtc().toIso8601String();
    final file = p.join(folder.path, '$id.tppos');
    // Never opens AppDatabase or closes the foreground application's connection.
    final db = await openDatabase(live, readOnly: true, singleInstance: false);
    try {
      final schema = await SqliteBackup.schema(db),
          version = await db.getVersion();
      await SqliteBackup.create(db, file);
      final info = await SqliteBackup.inspect(
        file,
        expectedSchema: schema,
        expectedVersion: version,
      );
      if (info.bytes > CloudBackupRecord.maxBytes) {
        throw StateError(
          'Backup exceeds 20 MB cloud limit. Use Local Backup & Restore',
        );
      }
      final digest = (await sha256.bind(File(file).openRead()).first)
          .toString();
      await check(worker, stopped);
      final snapshot = await openDatabase(
        file,
        readOnly: true,
        singleInstance: false,
      );
      late int revision;
      try {
        revision = await BackupChangeTracker.revision(snapshot);
      } finally {
        await snapshot.close();
      }
      final job = <String, dynamic>{
        'id': id,
        'revision': revision,
        'path': file,
        'captured': captured,
        'bytes': info.bytes,
        'sha256': digest,
        'schema_sha256': sha256.convert(utf8.encode(schema)).toString(),
        'version': version,
        'businessName': info.businessName,
        'counts': info.counts,
      };
      var saved = false;
      await AutoBackupStore.change((v) {
        if (v['worker'] == worker && v['enabled'] == true) {
          v['pending'] = job;
          saved = true;
        }
      });
      if (!saved) {
        throw StateError('Auto Backup stopped');
      }
      return job;
    } catch (_) {
      if (await File(file).exists()) {
        await File(file).delete();
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
  static Future<void> archiveOrphans(Map<String, dynamic> config) async {
    final root = await getDatabasesPath();
    final staging = Directory(p.join(root, 'toe_pwar_auto_pending'));
    if (!await staging.exists()) {
      return;
    }
    final pending = config['pending'];
    final keep = pending is Map ? pending['path'] : null;
    final recovery = await Directory(p.join(root, 'toe_pwar_backups'))
        .create(recursive: true);
    await for (final item in staging.list(followLinks: false)) {
      if (item is File && item.path != keep && item.path.endsWith('.tppos')) {
        // Preserve interrupted snapshots for inspection in Local Backup & Restore.
        // An incomplete file will fail that page's normal integrity validation.
        await item.rename(
          p.join(
            recovery.path,
            'interrupted_auto_${DateTime.now().microsecondsSinceEpoch}_${p.basename(item.path)}',
          ),
        );
      }
    }
  }

  /// false asks Android for a backoff retry; errors are visible in settings.
  static Future<bool> run({bool Function()? isStopped}) async {
    final stopped = isStopped ?? () => false;
    try {
      return await BackupGate.run('auto_backup_run', () async {
        final config = await AutoBackupStore.read();
        if (!AutoBackupStore.due(config, DateTime.now())) {
          return true;
        }
        final worker = config['worker'] as String;
        final client = isolatedClient();
        try {
          await archiveOrphans(config);
          await check(worker, stopped);
          await AutoBackupStore.status(
            worker,
            'Connecting / waiting for network',
          );
          final token = await secrets.read(key: secretKey(worker));
          if (token == null) {
            throw StateError(
              'Background login unavailable. Enable Auto Backup again as Owner',
            );
          }
          final auth = await client.auth.setSession(token);
          final session = auth.session;
          if (session == null ||
              session.user.id != worker ||
              session.refreshToken == null) {
            throw StateError('Background identity changed. Enable again');
          }
          // Immediately persist token rotation under the cross-isolate run lock.
          await secrets.write(
            key: secretKey(worker),
            value: session.refreshToken!,
          );
          await check(worker, stopped);
          // An old offline pending upload is completed first. At most one fresh
          // snapshot follows if that capture is already older than the interval.
          for (var pass = 0; pass < 2; pass++) {
            final current = await AutoBackupStore.read();
            if (!AutoBackupStore.due(current, DateTime.now())) {
              break;
            }
            await check(worker, stopped);
            await AutoBackupStore.status(
              worker,
              'Creating / checking snapshot',
            );
            final pending = current['pending'];
            final job = pending == null
                ? await capture(worker, stopped)
                : Map<String, dynamic>.from(pending as Map);
            final file = File(job['path'] as String);
            if (!await file.exists()) {
              throw StateError(
                'Pending local snapshot missing. Disable and enable Auto Backup again; review Pending cloud entries',
              );
            }
            if (await file.length() != job['bytes'] ||
                (await sha256.bind(file.openRead()).first).toString() !=
                    job['sha256']) {
              throw StateError(
                'Pending snapshot changed. Disable and enable again; review Pending cloud entries',
              );
            }
            await check(worker, stopped);
            await AutoBackupStore.status(
              worker,
              'Uploading / retrying pending backup',
            );
            final row = Map<String, dynamic>.from(
              await client.rpc(
                'tp_auto_reserve',
                params: {
                  'p_job': job['id'],
                  'p_bytes': job['bytes'],
                  'p_sha256': job['sha256'],
                  'p_schema_sha256': job['schema_sha256'],
                  'p_db_version': job['version'],
                  'p_source_business': job['businessName'],
                  'p_counts': job['counts'],
                },
              ) as Map,
            );
            final record = CloudBackupRecord.fromJson(
              row,
              config['business'] as String,
            );
            if (record.id != job['id'] || record.sha256Hex != job['sha256']) {
              throw StateError('Unexpected reservation');
            }
            await check(worker, stopped);
            if (record.state != 'ready') {
              // Immutable uploads: a lost successful response may make the retry
              // return duplicate-object. Verify the existing bytes before finishing.
              try {
                await client.storage
                    .from(CloudBackupRecord.bucket)
                    .upload(
                      record.objectName,
                      file,
                      fileOptions: const FileOptions(
                        contentType: 'application/octet-stream',
                        cacheControl: '0',
                        upsert: false,
                      ),
                    );
              } catch (_) {
                await check(worker, stopped);
                final existing = await client.storage
                    .from(CloudBackupRecord.bucket)
                    .download(record.objectName);
                record.verify(existing);
              }
              await check(worker, stopped);
              final uploaded = await client.storage
                  .from(CloudBackupRecord.bucket)
                  .download(record.objectName);
              record.verify(uploaded);
              await check(worker, stopped);
              await client.rpc('tp_auto_finish', params: {'p_job': job['id']});
            }
            final liveRevision=await BackupGate.run<int?>('backup_maintenance',()async{
              final livePath=p.join(await getDatabasesPath(),'inventory_pos.db');
              if(await BackupFiles.marker(livePath).exists())return null;
              Database? current;
              try{
                current=await openDatabase(livePath,readOnly:true,singleInstance:false);
                return await BackupChangeTracker.revision(current);
              }catch(_){return null;}finally{await current?.close();}
            });
            await AutoBackupStore.change((v) {
              if (v['worker'] == worker && v['enabled'] == true) {
                v['pending'] = null;
                v['force'] =
                    liveRevision != null &&
                    AutoBackupPolicy.dirty(liveRevision, job['revision']);
                v['capturedAt'] = job['captured'];
                v['uploadedRevision'] = job['revision'];
                v['uploadedAt'] = DateTime.now().toUtc().toIso8601String();
                v['status'] = 'Ready — cloud copy verified';
              }
            });
            // Only delete our private temporary snapshot after server confirms Ready.
            if (await file.exists()) {
              await file.delete();
            }
          }
          return true;
        } catch (e) {
          // Never log tokens or store raw authentication/network URLs in status.
          final message = e is AuthException
              ? 'Background sign-in failed. Check network or enable Auto Backup again.'
              : e is PostgrestException
              ? e.message
              : e is StorageException
              ? 'Cloud upload incomplete. Will retry; check network and cloud entries.'
              : e is StateError
              ? e.message
              : 'Backup interrupted. Will retry; check network and reopen the app.';
          await AutoBackupStore.status(worker, message);
          if (e is PostgrestException &&
              e.message.startsWith('Cloud Backup requires')) {
            await AutoBackupStore.pause(
              'Paused by subscription. Enable again after Premium or Trial is active.',
            );
          }
          return false;
        } finally {
          await client.dispose();
          final v = await AutoBackupStore.read();
          if (v['enabled'] != true || v['worker'] != worker) {
            await secrets.delete(key: secretKey(worker));
          }
        }
      });
    } on DatabaseException {
      return false;
    }
  }
}
