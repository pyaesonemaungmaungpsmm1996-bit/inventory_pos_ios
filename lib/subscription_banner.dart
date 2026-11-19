import 'dart:async';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'subscription_billing_page.dart';
import 'subscription_runtime.dart';

class SubscriptionBanner extends StatefulWidget {
  const SubscriptionBanner({super.key});
  @override
  State<SubscriptionBanner> createState() => _SubscriptionBannerState();
}

class _SubscriptionBannerState extends State<SubscriptionBanner> {
  Map<String, dynamic> value = {};
  Timer? timer;
  @override
  void initState() {
    super.initState();
    SubscriptionRuntime.changed.addListener(reload);
    reload();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => reload());
  }

  @override
  void dispose() {
    SubscriptionRuntime.changed.removeListener(reload);
    timer?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final row = await SubscriptionRuntime.read();
      await AppDatabase.instance.refreshSubscriptionFence();
      if (mounted) {
        setState(() => value = row);
      }
    } catch (_) {
      /* Read-only access is retained. */
    }
  }

  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  Widget build(BuildContext context) {
    final state = SubscriptionRuntime.effective(value, DateTime.now());
    final days = state['days_left'] as int?;
    if (state['writable'] == true &&
        days != null &&
        days > 5 &&
        state['next_plan'] == null) {
      return const SizedBox.shrink();
    }
    final pending = state['payment_pending'] == true;
    final text = value['bound'] != true
        ? t(
            'Read-only until you connect this POS database to an online subscription. Your data is kept.',
            'Online Subscription နှင့် ဤ POS ဒေတာကို ချိတ်မထားသေးသဖြင့် ဖတ်ရှုရန်သာ ဖြစ်ပါသည်။ ဒေတာ ဆက်ရှိပါသည်။',
          )
        : value['provider_blocked'] == true ||
              value['actor_provider_blocked'] == true
        ? t(
            'Account or business access is paused by the provider. Contact support. Existing records remain available.',
            'Provider က အကောင့် သို့မဟုတ် လုပ်ငန်းအသုံးပြုခွင့်ကို ခေတ္တပိတ်ထားပါသည်။ Support ကို ဆက်သွယ်ပါ။ ဒေတာဟောင်းများ ဆက်ရှိပါသည်။',
          )
        : state['paused'] == true && state['pause_reason'] == 'device'
        ? t(
            'Device approval changed. Ask the Owner to approve and confirm this license again. Data is kept.',
            'Device ခွင့်ပြုချက် ပြောင်းသွားပါသည်။ Owner က အတည်ပြုပြီး License ပြန်ချိတ်ပါ။ ဒေတာ ဆက်ရှိပါသည်။',
          )
        : state['paused'] == true
        ? t(
            'License confirmation is required after restore. Viewing and Local Backup are available.',
            'Restore ပြီးနောက် License ပြန်အတည်ပြုရန် လိုပါသည်။ စာရင်းကြည့်ခြင်းနှင့် Local Backup ရပါသည်။',
          )
        : state['clock_warning'] == true
        ? t(
            'Device clock changed. Connect online to verify the subscription. Data is kept.',
            'ဖုန်းအချိန် ပြောင်းထားပါသည်။ Internet ချိတ်ပြီး သက်တမ်းစစ်ပါ။ ဒေတာ ဆက်ရှိပါသည်။',
          )
        : state['plan'] == 'standard' &&
              days != null &&
              days > 0 &&
              state['writable'] != true
        ? t(
            'Confirm the retained Standard branch and approved device. No extra payment is required for an active plan.',
            'Standard ဆက်သုံးမည့် ဆိုင်ခွဲနှင့် အတည်ပြု Device ကို စစ်ပါ။ သက်တမ်းရှိပြီးသားအတွက် ငွေထပ်ချေရန် မလိုပါ။',
          )
        : pending && state['writable'] != true
        ? t(
            'Payment review is pending. Read-only until approval; do not pay again. Data is kept.',
            'ငွေချေမှု စစ်ဆေးနေပါသည်။ အတည်မပြုမီ ဖတ်ရှုရန်သာ ဖြစ်ပြီး ငွေထပ်မချေပါနှင့်။ ဒေတာ ဆက်ရှိပါသည်။',
          )
        : pending
        ? t(
            'Payment review is pending. Do not pay again. Open Subscription to check status.',
            'ငွေချေမှု စစ်ဆေးနေပါသည်။ ငွေထပ်မချေဘဲ Subscription မှ အခြေအနေစစ်ပါ။',
          )
        : state['writable'] != true
        ? t(
            'Subscription is read-only. View/export existing records or create a Local Backup; renew to enter new records.',
            'စာရင်းကြည့်ရန်သာ ဖြစ်ပါသည်။ ဒေတာဟောင်းကြည့်/Export/Local Backup ထုတ်နိုင်ပြီး အသစ်ထည့်ရန် သက်တမ်းတိုးပါ။',
          )
        : state['next_plan'] != null
        ? t(
            'A switch to ${state['next_plan']} is scheduled. Check the retained branch before the change.',
            '${state['next_plan']} သို့ ပြောင်းရန် စီစဉ်ထားပါသည်။ ဆက်သုံးမည့်ဆိုင်ခွဲကို ကြိုစစ်ပါ။',
          )
        : state['plan'] == 'standard' && days != null && days > 5
        ? t(
            'Standard branch: ${state['local_branch_name'] ?? state['local_branch']}. Other branches are view-only.',
            'Standard ဆိုင်ခွဲ: ${state['local_branch_name'] ?? state['local_branch']}။ ကျန်ဆိုင်ခွဲများ ဖတ်ရှုရန်သာ ဖြစ်ပါသည်။',
          )
        : t(
            'Subscription expires in $days day(s).',
            'သက်တမ်းကုန်ရန် $days ရက် ကျန်ပါသည်။',
          );
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SubscriptionBillingPage(),
                ),
              ),
              child: Text(t('Subscription', 'သက်တမ်း')),
            ),
          ],
        ),
      ),
    );
  }
}
