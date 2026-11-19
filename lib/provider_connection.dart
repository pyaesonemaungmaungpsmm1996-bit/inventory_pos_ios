import 'subscription_reminders.dart';

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'online_account_service.dart';
import 'subscription_runtime.dart';

class ProviderConnection with WidgetsBindingObserver {
  static final instance = ProviderConnection();
  Timer? timer;
  StreamSubscription<dynamic>? auth;
  bool foreground = true, running = false, started = false;
  static void start() => instance._start();
  void _start() {
    if (started) return;
    started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await OnlineAccounts.initialize();
      auth = OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        unawaited(ping());
      });
      timer = Timer.periodic(const Duration(minutes: 2), (_) {
        unawaited(ping());
      });
      await ping();
    } catch (_) {
      /* Offline POS remains available. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) unawaited(ping());
  }

  Future<void> ping() async {
    if (!foreground || running) return;
    running = true;
    try {
      final id = OnlineAccounts.client.auth.currentUser?.id;
      if (id == null) return;
      await OnlineAccounts.client.rpc(
        'tp_app_heartbeat',
        params: {'p_version': 'TP-UPDATE-02-v40'},
      );
      final status = await OnlineAccounts.client.rpc('tp_provider_my_status');
      if (OnlineAccounts.client.auth.currentUser?.id == id) {
        await SubscriptionRuntime.change((v) {
          v['actor_provider_blocked'] = (status as Map)['blocked'] == true;
        });
      }
      await SubscriptionReminders.refresh(force: true);
    } catch (_) {
      /* Missing deployment or network trouble must not erase licences/data. */
    } finally {
      running = false;
    }
  }
}
