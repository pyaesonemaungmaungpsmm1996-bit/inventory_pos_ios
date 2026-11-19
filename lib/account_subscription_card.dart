import 'desktop_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'online_account_service.dart';
import 'subscription_runtime.dart';
import 'subscription_billing_page.dart';

class AccountSubscriptionCard extends StatefulWidget {
  const AccountSubscriptionCard({super.key});
  @override
  State<AccountSubscriptionCard> createState() =>
      _AccountSubscriptionCardState();
}

class _AccountSubscriptionCardState extends State<AccountSubscriptionCard> {
  Map<String, dynamic> policy = {};
  bool loading = true, offline = false;
  int generation = 0;
  Timer? timer;
  StreamSubscription<dynamic>? auth;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    SubscriptionRuntime.changed.addListener(reload);
    reload();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => reload());
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    auth?.cancel();
    SubscriptionRuntime.changed.removeListener(reload);
    super.dispose();
  }

  Future<void> reload() async {
    final version = ++generation;
    Map<String, dynamic> next = {};
    bool cached = false;
    try {
      final local = await SubscriptionRuntime.read();
      if (local['bound'] == true) {
        next = local;
      }
      await OnlineAccounts.initialize();
      if (!mounted || version != generation) return;
      auth ??= OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        if (mounted) {
          setState(() {
            policy = {};
            loading = true;
          });
          reload();
        }
      });
      final owner = OnlineAccounts.client.auth.currentUser?.id;
      if (owner != null) {
        final rows = (await OnlineAccounts.snapshot())
            .where((r) => r['role'] == 'owner' && r['active'] == true)
            .toList();
        final matches = rows
            .where((r) => r['id'] == local['business_id'])
            .toList();
        final chosen = matches.isNotEmpty
            ? matches.first
            : rows.length == 1
            ? rows.single
            : null;
        if (chosen != null) {
          final result = await OnlineAccounts.client.rpc(
            'tp_billing_home',
            params: {'p_business': chosen['id']},
          );
          next = Map<String, dynamic>.from((result as Map)['policy'] as Map);
          next['offset_ms'] =
              DateTime.parse(next['server_now'] as String)
                  .millisecondsSinceEpoch -
              DateTime.now().millisecondsSinceEpoch;
        } else if (local['owner_id'] != owner) {
          next = {};
        }
      } else {
        next = {};
      }
      if (OnlineAccounts.client.auth.currentUser?.id != owner) return;
    } catch (_) {
      cached = true;
    }
    if (!mounted || version != generation) return;
    setState(() {
      policy = next;
      offline = cached;
      loading = false;
    });
  }

  Future<void> open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SubscriptionBillingPage()),
    );
    if (mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final value = SubscriptionRuntime.effective(policy, DateTime.now());
    final plan = '${value['plan'] ?? ''}';
    final known = ['trial', 'standard', 'premium'].contains(plan);
    final end = DateTime.tryParse('${value['ends_at']}');
    final now = SubscriptionRuntime.effectiveNow(policy, DateTime.now());
    final blocked =
        value['provider_blocked'] == true ||
        value['actor_provider_blocked'] == true;
    final active = known && end != null && now.isBefore(end) && !blocked;
    final days = value['days_left'] as int?;
    final urgent = known && (!active || (days != null && days <= 5));
    final label = plan == 'premium'
        ? 'Premium'
        : plan == 'standard'
        ? 'Standard'
        : plan == 'trial'
        ? t('Trial', 'အစမ်းသုံး')
        : t('Subscription', 'သက်တမ်း');
    final status = loading
        ? t('Loading…', 'စစ်ဆေးနေသည်…')
        : !known
        ? t('View plans', 'Plan များကြည့်ရန်')
        : blocked
        ? t('PAUSED', 'ခေတ္တပိတ်ထားသည်')
        : active
        ? t('ACTIVE', 'သက်တမ်းရှိ')
        : t('EXPIRED', 'သက်တမ်းကုန်ပြီ');
    final background = urgent ? colors.errorContainer : colors.primaryContainer;
    final foreground = urgent
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: background,
        child: DesktopListTile(
          onTap: open,
          leading: Icon(
            Icons.workspace_premium_outlined,
            color: foreground,
            size: 22,
          ),
          title: Text(
            '$label · $status',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: foreground),
          ),
          subtitle: Text(
            '${active && days != null ? t('$days days left', 'သက်တမ်း $days ရက် ကျန်သည်') : t('Tap for details', 'အသေးစိတ်ကြည့်ရန် နှိပ်ပါ')}${offline ? ' · Offline' : ''}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground),
          ),
          trailing: Icon(Icons.chevron_right, color: foreground),
        ),
      ),
    );
  }
}
