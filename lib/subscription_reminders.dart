import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_language.dart';
import 'backup_gate.dart';
import 'online_account_service.dart';
import 'subscription_runtime.dart';

class SubscriptionReminders with WidgetsBindingObserver {
  static final instance = SubscriptionReminders();
  static final plugin = FlutterLocalNotificationsPlugin();
  static const task = 'toe_pwar_subscription_reminder',
      unique = 'toe_pwar_subscription_reminder_periodic',
      notificationId = 9021;
  static bool _initialized = false, _refreshing = false, _started = false;
  static Timer? _timer;
  static DateTime? _lastNetwork;
  static Future<void> init() async {
    if (_initialized || !Platform.isAndroid) {
      return;
    }
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('tp_subscription_notification'),
      ),
    );
    _initialized = true;
  }

  static Future<void> allowNotifications() async {
    if (!Platform.isAndroid) {
      return;
    }
    await init();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await SubscriptionRuntime.change((v) {
      v['reminders'] = true;
      v['language'] = AppLanguage.current.value;
    });
    await schedule();
    await check();
  }

  static Future<void> schedule() async {
    if (!Platform.isAndroid) {
      return;
    }
    await Workmanager().registerPeriodicTask(
      unique,
      task,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> start() async {
    if (!Platform.isAndroid || _started) {
      return;
    }
    _started = true;
    AppLanguage.current.addListener(instance.languageChanged);
    WidgetsBinding.instance.addObserver(instance);
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(refresh());
    });
    try {
      await OnlineAccounts.initialize();
      await refresh();
    } catch (_) {
      /* Cached expiry remains available offline. */
    }
  }

  void languageChanged() {
    unawaited(
      SubscriptionRuntime.change((v) {
        v['language'] = AppLanguage.current.value;
      }).catchError((Object _) {
        /* Banner follows the app setting even if the local reminder cache is temporarily unavailable. */
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh(force: true));
    }
  }

  static Future<void> refresh({bool force = false}) async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final v = await SubscriptionRuntime.read();
      if (v['bound'] == true &&
          OnlineAccounts.client.auth.currentUser != null &&
          (force ||
              _lastNetwork == null ||
              DateTime.now().difference(_lastNetwork!) >
                  const Duration(minutes: 15))) {
        _lastNetwork = DateTime.now();
        try {
          final result = Map<String, dynamic>.from(
            await OnlineAccounts.client.rpc(
              'tp_license_device_snapshot',
              params: {
                'p_business': v['business_id'],
                'p_installation': v['installation_id'],
                'p_branch': v['device_branch'],
              },
            ) as Map,
          );
          if (result['actor_id'] ==
              OnlineAccounts.client.auth.currentUser?.id) {
            await SubscriptionRuntime.update(result);
            if (v['ends_at'] != result['ends_at'] ||
                v['plan'] != result['plan'] ||
                v['next_plan'] != result['next_plan'] ||
                v['payment_pending'] != result['payment_pending']) {
              await cancelOldNotice();
            }
          }
        } on PostgrestException catch (e) {
          if (e.message.startsWith('Approved device access required')) {
            await SubscriptionRuntime.change((r) {
              r['paused'] = true;
              r['pause_reason'] = 'device';
            });
          }
        } catch (_) {
          /* Do not erase entitlement/data on temporary network errors. */
        }
      }
      await SubscriptionRuntime.change((current) {
        current['language'] = AppLanguage.current.value;
      });
      if (v['reminders'] == true) {
        await schedule();
        await check();
      }
    } catch (_) {
      /* Main POS must remain readable even when notification setup fails. */
    } finally {
      _refreshing = false;
    }
  }

  static int? daysLeft(Map<String, dynamic> v, DateTime now) =>
      SubscriptionRuntime.effective(v, now)['days_left'] as int?;
  static bool due(Map<String, dynamic> v, DateTime now) {
    if (v['bound'] != true || v['reminders'] != true) {
      return false;
    }
    final days = daysLeft(v, now);
    if (days == null || days > 5) {
      return false;
    }
    final today = now.toLocal().toIso8601String().substring(0, 10);
    final signature =
        '${SubscriptionRuntime.effective(v, now)['ends_at']}|$today';
    return v['last_reminder'] != signature;
  }

  static Future<bool> check() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await BackupGate.run('subscription_reminder', () async {
        final v = await SubscriptionRuntime.read();
        final now = DateTime.now();
        if (!due(v, now)) {
          final left = daysLeft(v, now);
          if (left == null || left > 5) {
            await cancelOldNotice();
          }
          return true;
        }
        await init();
        final android = plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (await android?.areNotificationsEnabled() != true) {
          return true;
        }
        final days = daysLeft(v, now)!;
        final my = v['language'] == 'my';
        final pending = v['payment_pending'] == true;
        final body = pending
            ? (my
                  ? 'ငွေချေမှု စစ်ဆေးနေပါသည်။ ငွေထပ်မချေပါနှင့်။ App မှ အခြေအနေပြန်စစ်ပါ။'
                  : 'Payment review is pending. Do not pay again; open the app to check status.')
            : v['next_plan'] != null && days > 0
            ? (my
                  ? '${v['next_plan']} သို့ $days ရက်အတွင်း ပြောင်းပါမည်။ ဆက်သုံးမည့်ဆိုင်ခွဲကို စစ်ပါ။ ငွေထပ်ချေရန် မလိုပါ။'
                  : 'Your paid switch to ${v['next_plan']} starts in $days day(s). Check the retained branch; no additional payment is required.')
            : days <= 0
            ? (my
                  ? 'သက်တမ်းကုန်ပါပြီ။ ဒေတာမဖျက်ပါ။ စာရင်းဟောင်းကြည့်ပြီး Local Backup ထုတ်နိုင်ပါသည်။'
                  : 'Your subscription has expired. Data is kept; viewing and Local Backup remain available.')
            : (my
                  ? 'သက်တမ်းကုန်ရန် $days ရက် ကျန်ပါသည်။ သက်တမ်းတိုးရန် App ကို ဖွင့်ပါ။'
                  : 'Your subscription expires in $days day(s). Open the app to renew.');
        await plugin.show(
          id: notificationId,
          title: my
              ? 'Toe Pwar POS သက်တမ်းအသိပေးချက်'
              : 'Toe Pwar POS subscription reminder',
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'subscription_expiry',
              'Subscription expiry',
              channelDescription: 'Daily subscription expiry reminders',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          payload: 'subscription',
        );
        final current = SubscriptionRuntime.effective(v, now);
        await SubscriptionRuntime.change((r) {
          if (r['business_id'] == v['business_id']) {
            r['last_reminder'] =
                '${current['ends_at']}|${now.toLocal().toIso8601String().substring(0, 10)}';
          }
        });
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  static Future<void> testNotification() async {
    await allowNotifications();
    await plugin.show(
      id: 9022,
      title: 'Toe Pwar POS · Test reminder',
      body: AppLanguage.current.value == 'my'
          ? 'အသိပေးချက် စမ်းသပ်မှု အောင်မြင်ပါသည်။ Plan သက်တမ်း မပြောင်းပါ။'
          : 'Notification test. Your subscription dates have not changed.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'subscription_expiry',
          'Subscription expiry',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }

  static Future<void> cancelOldNotice() async {
    if (Platform.isAndroid) {
      await init();
      await plugin.cancel(id: notificationId);
    }
  }
}
