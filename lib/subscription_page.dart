import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'subscription_pricing.dart';
import 'subscription_billing_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});
  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final catalog = SubscriptionCatalog.preview;
  String selected = 'standard';
  int months = 1;

  String term(int value) => value == 1
      ? _t('1 month', '၁ လ')
      : '${value ~/ 12} ${_t('year(s)', 'နှစ်')}';
  String planName(String id) => id == 'standard' ? 'Standard' : 'Premium';

  @override
  Widget build(BuildContext context) {
    final quote = catalog.quote(selected, months);
    final style = Theme.of(context).textTheme;
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Text(
          _t('Plans & pricing', 'Plan နှင့် ဈေးနှုန်းများ'),
          style: style.headlineSmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    'Pricing preview — use Online Subscription for payment',
                    'ဈေးနှုန်း အစမ်းကြည့်ရန် — ငွေချေရန် Online Subscription သို့ ဝင်ပါ',
                  ),
                  style: style.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _t(
                    'These are estimated prices. No trial or paid plan has been activated by this screen. Your existing app data remains available.',
                    'ဤဈေးများသည် ခန့်မှန်းတွက်ချက်မှုဖြစ်ပါသည်။ ဤစာမျက်နှာမှ Trial သို့မဟုတ် Paid Plan ကို ဖွင့်ပေးခြင်း မရှိသေးပါ။ လက်ရှိ app ဒေတာများကို ဆက်သုံးနိုင်ပါသည်။',
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: DesktopListTile(
            leading: const Icon(Icons.hourglass_top),
            title: const Text('Trial · 14 days'),
            subtitle: Text(
              _t(
                'Free trial. Online registration will be required to start it.',
                '၁၄ ရက် အခမဲ့စမ်းသုံးခွင့်။ စတင်ရန် Online Register ချိတ်ဆက်မှု လိုပါမည်။',
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(_t('Choose a plan', 'Plan ရွေးရန်'), style: style.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: catalog.plans
              .map(
                (plan) => ChoiceChip(
                  label: Text(planName(plan.id)),
                  selected: selected == plan.id,
                  onSelected: (_) => setState(() => selected = plan.id),
                ),
              )
              .toList(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '${subscriptionMmk(quote.plan.monthlyMmk)} / ${_t('month', 'လ')}\n'
            '${quote.plan.branchLimit == null ? _t('Unlimited branches', 'ဆိုင်ခွဲအရေအတွက် အကန့်အသတ်မရှိ') : '${_t('Branches in total', 'ဆိုင်ခွဲစုစုပေါင်း')}: ${quote.plan.branchLimit}'}\n'
            '${_t('Up to 3 approved devices per branch', 'ဆိုင်ခွဲတစ်ခုလျှင် အတည်ပြုထားသော Device ၃ လုံးအထိ')}',
          ),
        ),
        Text(
          selected == 'standard'
              ? _t(
                  'For one shop. Local Backup & Restore included; Cloud Backup is not included.',
                  'ဆိုင်တစ်ဆိုင်အတွက်။ Local Backup & Restore ပါဝင်ပြီး Cloud Backup မပါဝင်ပါ။',
                )
              : _t(
                  'For multiple branches or cloud protection. Unlimited branches and all Premium features, with staff roles still controlled by the Owner.',
                  'ဆိုင်ခွဲများ သို့မဟုတ် Cloud Backup လိုသူများအတွက်။ ဆိုင်ခွဲအကန့်အသတ်မရှိ၊ Premium လုပ်ဆောင်ချက်အားလုံး ပါဝင်ပြီး ဝန်ထမ်းခွင့်များကို Owner က ထိန်းချုပ်နိုင်ပါသည်။',
                ),
        ),
        Text(
          _t('Choose a duration', 'သက်တမ်းရွေးရန်'),
          style: style.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: SubscriptionCatalog.terms
              .map(
                (value) => ChoiceChip(
                  label: Text(term(value)),
                  selected: months == value,
                  onSelected: (_) => setState(() => months = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _line(
                  _t('Plan / duration', 'Plan / သက်တမ်း'),
                  '${planName(selected)} · ${term(months)}',
                ),
                _line(
                  _t('Original price', 'မူရင်းဈေး'),
                  subscriptionMmk(quote.baseMmk),
                ),
                _line(
                  '${_t('Discount', 'လျှော့ဈေး')} ${(quote.discountBps / 100).toStringAsFixed(quote.discountBps % 100 == 0 ? 0 : 2)}%',
                  subscriptionMmk(quote.discountMmk),
                ),
                const Divider(),
                _line(
                  _t('Estimated total', 'ခန့်မှန်းကျသင့်ငွေ'),
                  subscriptionMmk(quote.totalMmk),
                  strong: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t(
            'Annual discounts: 1 year 10%, 2 years 15%, and 3–5 years 20%. Future pricing changes will apply to new server quotes; purchased terms will retain their agreed price.',
            'လျှော့ဈေး — ၁ နှစ် 10%၊ ၂ နှစ် 15%၊ ၃ မှ ၅ နှစ် 20%။ နောက်ပိုင်းဈေးပြောင်းလဲမှုကို Server Quote အသစ်များတွင် သက်ရောက်စေပြီး ဝယ်ပြီးသားသက်တမ်း၏ သဘောတူဈေးကို ထိန်းသိမ်းပါမည်။',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SubscriptionBillingPage(),
            ),
          ),
          child: Text(
            _t(
              'Online Subscription & Payments',
              'Online Subscription နှင့် ငွေချေမှု',
            ),
          ),
        ),
        Text(
          _t(
            'Open Online Subscription for server prices, identity verification, payment requests and provider review. This preview does not change your plan.',
            'Server ဈေးနှုန်း၊ အထောက်အထား၊ ငွေချေတောင်းဆိုမှုနှင့် Admin စစ်ဆေးမှုအတွက် Online Subscription ကို ဝင်ပါ။ ဤအစမ်းကြည့်စာမျက်နှာမှ Plan မပြောင်းပါ။',
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: strong
                ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                : null,
          ),
        ),
      ],
    ),
  );
}
