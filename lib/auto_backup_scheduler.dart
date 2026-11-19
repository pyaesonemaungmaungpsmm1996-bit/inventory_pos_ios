import 'app_database.dart';
import 'desktop_runtime.dart';
import 'backup_change_tracker.dart';
import 'auto_backup_policy.dart';
import 'cloud_proxy_client.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'auto_backup_runner.dart';
import 'subscription_reminders.dart';
import 'auto_backup_store.dart';
import 'backup_gate.dart';
import 'online_account_service.dart';

@pragma('vm:entry-point')
void toePwarBackupDispatcher() {
  var stopped = false;
  Workmanager().executeTask(
    (task, input) async {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      if (task == SubscriptionReminders.task) {
        return SubscriptionReminders.check();
      }
      if (task != AutoBackupScheduler.task) {
        return true;
      }
      try {
        return await AutoBackupRunner.run(isStopped: () => stopped);
      } catch (_) {
        return false;
      }
    },
    onTaskStopped: (_, _) async {
      stopped = true;
    },
  );
}

class AutoBackupScheduler with WidgetsBindingObserver {
  static const task = 'toe_pwar_auto_cloud_backup';
  static const periodic = 'toe_pwar_backup_periodic',
      immediate = 'toe_pwar_backup_due';
  static final instance = AutoBackupScheduler();
  static Future<void>? _initialized;
  static Future<void> initialize() => _initialized ??= _initialize();
  static Future<void> _initialize() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await Workmanager().initialize(toePwarBackupDispatcher);
    } catch (_) {
      _initialized = null;
      rethrow;
    }
  }

  static bool _started = false, _ticking = false, _foregroundRunning = false;
  static bool? _wasOnline;
  static Timer? _foregroundTimer;
  static void _ensureForegroundLoop() {
    _foregroundTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(foregroundTick()),
    );
  }

  static Future<void> start() async {
    if (_started || !(Platform.isAndroid || Platform.isWindows)) return;
    try {
      await DesktopRuntime.initialize();
      await initialize();
      await OnlineAccounts.initialize();
      if (Platform.isAndroid) await SubscriptionReminders.start();
      WidgetsBinding.instance.addObserver(instance);
      OnlineAccounts.client.auth.onAuthStateChange.listen(
        (_) => unawaited(checkOwner()),
      );
      _started = true;
      _ensureForegroundLoop();
      await checkOwner();
      await foregroundTick();
    } catch (_) {
      /* Offline POS remains available; settings can retry setup. */
    }
  }

  static Future<bool> _online() async {
    Socket? socket;
    try {
      final host = Uri.parse(
        CloudProxyClient.enabled ? CloudProxyClient.proxy : OnlineAccounts.url,
      ).host;
      socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(seconds: 3),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<void> foregroundTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      final value = await AutoBackupStore.read();
      if (value['enabled'] != true) return;
      if (value['owner'] != OnlineAccounts.client.auth.currentUser?.id) {
        await checkOwner();
        return;
      }
      final revision = await BackupChangeTracker.revision(
        await AppDatabase.instance.database,
      );
      final dirty = AutoBackupPolicy.dirty(revision, value['uploadedRevision']);
      final online = await _online();
      final reconnect = AutoBackupPolicy.catchUp(
        online: online,
        previouslyOnline: _wasOnline,
        dirty: dirty,
      );
      _wasOnline = online;
      if (reconnect || (!online && dirty && Platform.isAndroid)) {
        await AutoBackupStore.change((v) {
          if (v['worker'] == value['worker'] && v['enabled'] == true) {
            v['force'] = true;
            v['status'] = 'Queued — waiting for network';
          }
        });
      }
      if (!online) {
        if (dirty && Platform.isAndroid) await enqueue(foreground: false);
        return;
      }
      if (AutoBackupStore.due(await AutoBackupStore.read(), DateTime.now())) {
        await enqueue();
      }
    } catch (_) {
      /* Retry next foreground tick; never block offline sales. */
    } finally {
      _ticking = false;
    }
  }

  static Future<void> _runForeground() async {
    if (_foregroundRunning) return;
    _foregroundRunning = true;
    try {
      await AutoBackupRunner.run();
    } catch (_) {
      /* Runner preserves pending work. */
    } finally {
      _foregroundRunning = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(checkOwner());
      unawaited(foregroundTick());
    } else if (state == AppLifecycleState.paused && Platform.isAndroid) {
      unawaited(queueBackgroundCatchUp());
    }
  }

  static Future<void> queueBackgroundCatchUp() async {
    try {
      final control = await AutoBackupStore.read();
      if (control['enabled'] != true ||
          control['owner'] != OnlineAccounts.client.auth.currentUser?.id) {
        return;
      }
      final revision = await BackupChangeTracker.revision(
        await AppDatabase.instance.database,
      );
      if (!AutoBackupPolicy.dirty(revision, control['uploadedRevision'])) {
        return;
      }
      await AutoBackupStore.change((v) {
        if (v['enabled'] == true && v['worker'] == control['worker']) {
          v['force'] = true;
          v['status'] = 'Queued — waiting for network';
        }
      });
      await enqueue(foreground: false);
    } catch (_) {
      /* Periodic work and next resume remain available. */
    }
  }

  static Future<void> checkOwner() async {
    try {
      var value = await AutoBackupStore.read();
      if (value['enabled'] == true &&
          value['owner'] != OnlineAccounts.client.auth.currentUser?.id) {
        await disable(
          'Paused because the signed-in account changed. Enable again as Owner.',
        );
      }
      await flushRevocations();
      value = await AutoBackupStore.read();
      if (value['enabled'] == true) {
        await schedule(value['minutes'] as int);
        if (AutoBackupStore.due(value, DateTime.now())) {
          await enqueue();
        }
      }
    } catch (_) {
      /* Status stays available; next resume/settings visit retries. */
    }
  }

  static Future<void> schedule(int minutes) async {
    if (!AutoBackupPolicy.validMinutes(minutes)) {
      throw StateError('Choose 15 to 43200 minutes');
    }
    _ensureForegroundLoop();
    if (Platform.isWindows) return;
    await initialize();
    await Workmanager().registerPeriodicTask(
      periodic,
      task,
      frequency: Duration(minutes: minutes),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  static Future<void> enqueue({bool foreground = true}) async {
    if (Platform.isAndroid) {
      await initialize();
      await Workmanager().registerOneOffTask(
        immediate,
        task,
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
    }
    if (foreground && (Platform.isAndroid || Platform.isWindows)) {
      unawaited(_runForeground());
    }
  }

  static Future<void> changeInterval(int minutes) async {
    if (!AutoBackupPolicy.validMinutes(minutes)) {
      throw StateError('Choose 15 to 43200 minutes');
    }
    final owner = OnlineAccounts.client.auth.currentUser?.id;
    await AutoBackupStore.change((v) {
      if (v['enabled'] != true || v['owner'] != owner) {
        throw StateError('Owner login changed');
      }
      v['minutes'] = minutes;
    });
    await schedule(minutes);
    if (AutoBackupStore.due(await AutoBackupStore.read(), DateTime.now())) {
      await enqueue();
    }
  }

  static Future<void> backupNow() async {
    await AutoBackupStore.change((v) {
      if (v['enabled'] == true) {
        v['force'] = true;
        v['status'] = 'Queued — waiting for network';
      }
    });
    await enqueue();
  }

  static Future<void> disable(String reason) async {
    String? oldWorker;
    await AutoBackupStore.change((v) {
      oldWorker = v['worker'] as String?;
      if (v['worker'] != null && v['business'] != null) {
        final queue = List<dynamic>.from((v['revocations'] as List?) ?? []);
        queue.add({
          'owner': v['owner'],
          'business': v['business'],
          'installation': v['installation'],
        });
        v['revocations'] = queue;
      }
      v['enabled'] = false;
      v['status'] = reason;
    });
    if (Platform.isAndroid) {
      try {
        await Workmanager().cancelByUniqueName(periodic);
        await Workmanager().cancelByUniqueName(immediate);
      } catch (_) {
        /* Disabled control row blocks all future jobs. */
      }
    }
    try {
      await BackupGate.run('auto_backup_run', () async {
        if (oldWorker != null) {
          await AutoBackupRunner.secrets.delete(
            key: AutoBackupRunner.secretKey(oldWorker!),
          );
        }
      });
    } catch (_) {
      /* A running worker checks disabled state and removes its own token. */
    }
    await flushRevocations();
  }

  static Future<void> flushRevocations() async {
    final owner = OnlineAccounts.client.auth.currentUser?.id;
    if (owner == null) {
      return;
    }
    final value = await AutoBackupStore.read();
    for (final item in List<dynamic>.from(
      (value['revocations'] as List?) ?? [],
    )) {
      final row = Map<String, dynamic>.from(item as Map);
      if (row['owner'] != owner) {
        continue;
      }
      try {
        await OnlineAccounts.client.rpc(
          'tp_auto_revoke',
          params: {
            'p_business': row['business'],
            'p_installation': row['installation'],
          },
        );
        await AutoBackupStore.change((v) {
          v['revocations'] = ((v['revocations'] as List?) ?? [])
              .where(
                (e) =>
                    e['owner'] != row['owner'] ||
                    e['business'] != row['business'] ||
                    e['installation'] != row['installation'],
              )
              .toList();
        });
      } catch (_) {
        return;
      } // Offline revocation is retried on next Owner resume.
    }
  }

  static Future<void> enable(
    String business,
    String name,
    String owner,
    int minutes,
  ) => BackupGate.run('auto_backup_run', () async {
    if (!(Platform.isAndroid || Platform.isWindows)) {
      throw StateError('Auto Backup is supported on Android and Windows');
    }
    if (!AutoBackupPolicy.validMinutes(minutes)) {
      throw StateError('Choose a supported interval');
    }
    if (OnlineAccounts.client.auth.currentUser?.id != owner) {
      throw StateError('Owner login changed');
    }
    await initialize();
    final old = await AutoBackupStore.read();
    if (old['enabled'] == true) {
      throw StateError(
        'Turn off the existing schedule before enabling another',
      );
    }
    // Flush pending revocations before pairing so an old offline disable cannot
    // revoke a newly paired identity on the same installation.
    await flushRevocations();
    final remaining = (await AutoBackupStore.read())['revocations'] as List?;
    if ((remaining ?? []).any((r) => r['owner'] == owner)) {
      throw StateError(
        'Connect online to finish the previous disable, then retry',
      );
    }
    final installation = await OnlineAccounts.installation();
    final workerClient = AutoBackupRunner.isolatedClient();
    String? worker;
    try {
      final response = await workerClient.auth.signInAnonymously();
      final session = response.session;
      if (session == null || session.refreshToken == null) {
        throw StateError(
          'Enable Anonymous sign-ins in Supabase first (after SQL 009)',
        );
      }
      worker = session.user.id;
      final ticket = await workerClient.rpc(
        'tp_auto_pair_ticket',
        params: {'p_installation': installation},
      );
      if (OnlineAccounts.client.auth.currentUser?.id != owner) {
        throw StateError('Owner login changed');
      }
      final paired = await OnlineAccounts.client.rpc(
        'tp_auto_pair',
        params: {
          'p_ticket': ticket,
          'p_business': business,
          'p_minutes': [60, 180, 1440].contains(minutes) ? minutes : 60,
        },
      );
      if (paired != worker) {
        throw StateError('Pairing did not match background identity');
      }
      await AutoBackupRunner.secrets.write(
        key: AutoBackupRunner.secretKey(worker),
        value: session.refreshToken!,
      );
      if (OnlineAccounts.client.auth.currentUser?.id != owner) {
        throw StateError('Owner login changed');
      }
      await AutoBackupStore.change((v) {
        v.addAll({
          'enabled': true,
          'owner': owner,
          'business': business,
          'businessName': name,
          'worker': worker,
          'installation': installation,
          'minutes': minutes,
          'pending': null,
          'capturedAt': null,
          'uploadedAt': null,
          'force': true,
          'status': 'Queued — waiting for network',
        });
      });
      if (OnlineAccounts.client.auth.currentUser?.id != owner) {
        throw StateError('Owner login changed');
      }
      await schedule(minutes);
      await enqueue();
      if (OnlineAccounts.client.auth.currentUser?.id != owner) {
        throw StateError('Owner login changed');
      }
      if (old['worker'] != null && old['worker'] != worker) {
        await AutoBackupRunner.secrets.delete(
          key: AutoBackupRunner.secretKey(old['worker'] as String),
        );
      }
    } catch (_) {
      // Do not leave an enabled control row after a failed scheduler/credential setup.
      await AutoBackupStore.pause(
        'Setup incomplete. Connect online and enable Auto Backup again.',
      );
      if (worker != null) {
        await AutoBackupRunner.secrets.delete(
          key: AutoBackupRunner.secretKey(worker),
        );
      }
      rethrow;
    } finally {
      await workerClient.dispose();
    }
  });
}
