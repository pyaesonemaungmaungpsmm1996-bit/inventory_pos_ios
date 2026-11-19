import 'desktop_ui.dart';
import 'provider_users_page.dart';
import 'feedback_page.dart';

import 'package:flutter/material.dart';

import 'billing_forms.dart';
import 'online_account_service.dart';
import 'subscription_billing_service.dart';
import 'subscription_pricing.dart';

class BillingAdminPage extends StatefulWidget {
  const BillingAdminPage({super.key, required this.owner});
  final String owner;
  @override
  State<BillingAdminPage> createState() => _BillingAdminPageState();
}

class _BillingAdminPageState extends State<BillingAdminPage> {
  Map<String, dynamic>? data;
  String? message;
  bool busy = false, loading = true;
  final viewed = <String>{};
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await BillingService.call(
        'tp_billing_admin_data',
        {},
        widget.owner,
      );
      if (mounted) {
        setState(() {
          data = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = BillingService.friendly(e);
          loading = false;
          data = null;
        });
      }
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || loading) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      BillingService.guard(widget.owner);
      await operation();
      if (mounted) {
        setState(
          () => message = bt(
            'Completed. Server status refreshed.',
            'ပြီးပါပြီ။ Server အခြေအနေ ပြန်စစ်ပြီးပါပြီ။',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = BillingService.friendly(e));
      }
    } finally {
      if (mounted) {
        await refresh();
      }
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> view(String document) => run(() async {
    await billingView(context, document, widget.owner);
    viewed.add(document);
  });
  Future<void> reviewNotice(String text) async {
    if (!mounted) return;
    setState(() => message = text);
    await showDialog<void>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(bt('Before final approval', 'အတည်မပြုမီ စစ်ရန်')),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> reviewPayment(Map<String, dynamic> r, bool approve) async {
    final document = r['document_id'] as String?;
    if (approve && r['total_mmk'] != 0 && !viewed.contains(document)) {
      await reviewNotice(
        bt(
          'Open the transfer proof first and check the actual bank records.',
          'ပြေစာပုံကို အရင်ဖွင့်ပြီး တကယ့်ဘဏ်စာရင်းနှင့် တိုက်စစ်ပါ။',
        ),
      );
      return;
    }
    var note = bt(
      'Final review: payment or credit verified.',
      'နောက်ဆုံးစစ်ဆေးမှု — ငွေချေမှု သို့မဟုတ် Credit ကို စစ်ပြီးပါပြီ။',
    );
    if (!approve) {
      final form = await billingForm(
        context,
        bt('Reject request', 'တောင်းဆိုမှု ပယ်ချမည်'),
        [
          BillingField(
            'note',
            bt('Rejection reason', 'ပယ်ချရသည့်အကြောင်းရင်း'),
          ),
        ],
      );
      if (form == null || !mounted) {
        return;
      }
      note = form['note'] as String;
    }
    final confirm = await billingConfirm(
      context,
      approve
          ? bt('Approve subscription?', 'Plan ကို အတည်ပြုမလား?')
          : bt(
              'Reject this payment request?',
              'ဤငွေချေတောင်းဆိုမှုကို ပယ်ချမလား?',
            ),
      '${r['business_name']}\n${r['plan']} · ${r['months']} ${bt('months', 'လ')}\n${subscriptionMmk(r['total_mmk'] as int)}\n${r['reference']}\n\n'
      '${approve ? bt('I checked the actual bank transfer, or subscription credit for a zero-cash request. This decision activates or schedules the plan. Upgrade starts now; downgrade starts at Premium expiry.', 'တကယ့်ငွေလွှဲမှု သို့မဟုတ် Credit ကို စစ်ပြီးပါပြီ။ ဤအတည်ပြုမှုဖြင့် Plan ဖွင့် / စီစဉ်ပါမည်။ Upgrade က ယခုစပြီး Downgrade က Premium သက်တမ်းကုန်မှ စပါမည်။') : bt('The Owner will see your rejection reason. This does not issue a refund.', 'Owner က ပယ်ချရသည့်အကြောင်းရင်းကို မြင်ရပါမည်။ ဤလုပ်ဆောင်ချက်က ငွေပြန်အမ်းခြင်း မဟုတ်ပါ။')}',
    );
    if (!confirm || !mounted) {
      return;
    }
    await run(() async {
      await BillingService.call('tp_billing_final_review', {
        'p_request': r['id'],
        'p_identity': null,
        'p_approve': approve,
        'p_note': note,
      }, widget.owner);
    });
  }

  Future<void> bank([Map<String, dynamic>? b]) async {
    final form = await billingForm(
      context,
      bt('Receiving bank / wallet', 'ငွေလက်ခံ ဘဏ် / Wallet'),
      [
        BillingField(
          'bank',
          bt('Bank / wallet name', 'ဘဏ် / Wallet အမည်'),
          initial: '${b?['bank'] ?? ''}',
        ),
        BillingField(
          'holder',
          bt('Account holder', 'အကောင့်ပိုင်ရှင်အမည်'),
          initial: '${b?['holder'] ?? ''}',
        ),
        BillingField(
          'number',
          bt('Account number', 'အကောင့်နံပါတ်'),
          initial: '${b?['number'] ?? ''}',
        ),
        BillingField(
          'instructions',
          bt('Payment instructions', 'ငွေလွှဲရန် အညွှန်း'),
          initial: '${b?['instructions'] ?? ''}',
        ),
        BillingField(
          'active',
          bt('Available for new quotes', 'Quote အသစ်တွင် အသုံးပြုခွင့်'),
          initial: '${b?['active'] ?? true}',
          options: {
            'true': bt('Active', 'ဖွင့်ထားမည်'),
            'false': bt('Archived', 'ပိတ်ထားမည်'),
          },
        ),
      ],
      notice: bt(
        'Changes apply to new quotes. Existing quotes retain their bank details. Double-check the receiving account before enabling payment collection.',
        'ပြောင်းလဲမှုကို Quote အသစ်များတွင်သာ သက်ရောက်ပါမည်။ အဟောင်းများမှာ မူလဘဏ်အချက်အလက် ဆက်ရှိပါမည်။ ငွေလက်ခံစနစ် မဖွင့်မီ အကောင့်ကို တိုက်စစ်ပါ။',
      ),
    );
    if (form == null || !mounted) {
      return;
    }
    if (!await billingConfirm(
          context,
          bt('Publish bank details?', 'ဘဏ်အချက်အလက် သိမ်းမလား?'),
          '${form['bank']}\n${form['holder']}\n${form['number']}',
        ) ||
        !mounted) {
      return;
    }
    await run(() async {
      await OnlineAccounts.client.rpc(
        'tp_billing_bank_save',
        params: {
          'p_id': b?['id'],
          'p_bank': form['bank'],
          'p_holder': form['holder'],
          'p_number': form['number'],
          'p_instructions': form['instructions'],
          'p_active': form['active'] == 'true',
        },
      );
    });
  }

  Future<void> pricing() async {
    final catalog = Map<String, dynamic>.from(data!['catalog'] as Map);
    final discounts = Map<String, dynamic>.from(catalog['discounts'] as Map);
    final form = await billingForm(
      context,
      bt('Publish pricing', 'ဈေးနှုန်း ထုတ်ပြန်မည်'),
      [
        BillingField(
          'standard',
          bt('Standard monthly price (MMK)', 'Standard လစဉ်ဈေး (ကျပ်)'),
          initial: '${catalog['standard_mmk']}',
          number: true,
        ),
        BillingField(
          'premium',
          bt('Premium monthly price (MMK)', 'Premium လစဉ်ဈေး (ကျပ်)'),
          initial: '${catalog['premium_mmk']}',
          number: true,
        ),
        for (final m in SubscriptionCatalog.terms)
          BillingField(
            'd$m',
            '${m == 1 ? bt('1 month', '၁ လ') : '${m ~/ 12} ${bt('year(s)', 'နှစ်')}'} · ${bt('Discount %', 'လျှော့ဈေး %')}',
            initial: ((discounts['$m'] as num) / 100).toStringAsFixed(2),
            number: true,
          ),
        BillingField(
          'accepting',
          bt('Accept payment requests', 'ငွေချေတောင်းဆိုမှု လက်ခံခြင်း'),
          initial: '${data!['accepting']}',
          options: {
            'true': bt('Enabled', 'ဖွင့်မည်'),
            'false': bt('Disabled', 'ပိတ်မည်'),
          },
        ),
      ],
      notice: bt(
        'This publishes a new catalog version. Existing quotes and purchased subscriptions keep their agreed prices.',
        'ဈေးနှုန်းဗားရှင်းအသစ် ထုတ်ပြန်ပါမည်။ Quote အဟောင်းနှင့် ဝယ်ပြီးသားသက်တမ်းများ၏ သဘောတူဈေးကို မပြောင်းပါ။',
      ),
    );
    if (form == null || !mounted) {
      return;
    }
    if (!await billingConfirm(
          context,
          bt('Publish new prices?', 'ဈေးနှုန်းအသစ် ထုတ်ပြန်မလား?'),
          bt(
            'Check all prices, duration discounts and the payment collection switch.',
            'ဈေးနှုန်း၊ သက်တမ်းအလိုက် လျှော့ဈေးနှင့် ငွေလက်ခံခွင့်ကို စစ်ပါ။',
          ),
        ) ||
        !mounted) {
      return;
    }
    await run(() async {
      final standard = int.tryParse(form['standard'] as String),
          premium = int.tryParse(form['premium'] as String);
      if (standard == null || premium == null) {
        throw const FormatException('Enter whole MMK prices');
      }
      await OnlineAccounts.client.rpc(
        'tp_billing_catalog_publish',
        params: {
          'p_expected': catalog['id'],
          'p_standard': standard,
          'p_premium': premium,
          'p_discounts': {
            for (final m in SubscriptionCatalog.terms)
              '$m': BillingService.discountBps(form['d$m'] as String),
          },
          'p_accepting': form['accepting'] == 'true',
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final requests = (data?['requests'] as List?) ?? [];
    return PopScope(
      canPop: !busy,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(bt('Provider Billing Admin', 'Provider ငွေချေမှု Admin')),
        ),
        body: DesktopListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              bt(
                'Bank-transfer & subscription review',
                'ငွေလွှဲမှုနှင့် Subscription စစ်ဆေးခြင်း',
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (busy || loading) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(message!),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => loading = true);
                      await refresh();
                    },
              child: Text(bt('Refresh queue', 'စောင့်ဆိုင်းစာရင်း ပြန်စစ်မည်')),
            ),
            if (data != null) ...[
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProviderUsersPage(owner: widget.owner),
                        ),
                      ),
                icon: const Icon(Icons.groups_outlined),
                label: Text(
                  bt(
                    'Users, businesses & activity',
                    'User၊ လုပ်ငန်းနှင့် အသုံးပြုမှု',
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const FeedbackPage(admin: true),
                        ),
                      ),
                icon: const Icon(Icons.feedback_outlined),
                label: Text(bt('Feedback inbox', 'Feedback inbox')),
              ),

              Text(
                '${bt('Payment collection', 'ငွေချေလက်ခံခြင်း')}: ${data!['accepting'] == true ? bt('ON', 'ဖွင့်ထားသည်') : bt('OFF', 'ပိတ်ထားသည်')}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : pricing,
                    child: Text(
                      bt('Prices & discounts', 'ဈေးနှုန်းနှင့် လျှော့ဈေး'),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => bank(),
                    child: Text(
                      bt('Add bank / wallet', 'ဘဏ် / Wallet ထည့်မည်'),
                    ),
                  ),
                ],
              ),
              for (final raw in data!['banks'] as List)
                Card(
                  child: DesktopListTile(
                    title: Text(
                      '${raw['bank']} · ${raw['active'] == true ? bt('Active', 'ဖွင့်ထားသည်') : bt('Archived', 'ပိတ်ထားသည်')}',
                    ),
                    subtitle: Text('${raw['holder']}\n${raw['number']}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: busy
                        ? null
                        : () => bank(Map<String, dynamic>.from(raw as Map)),
                  ),
                ),
              const Divider(),
              Text(
                '${bt('Final subscription review', 'နောက်ဆုံး Subscription စစ်ဆေးရန်')} (${requests.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final raw in requests)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${raw['business_name']} · ${raw['plan']} · ${raw['months']} ${bt('months', 'လ')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${raw['owner_email']}'),
                        SelectableText(
                          '${bt('Request', 'တောင်းဆိုမှု')}: ${raw['id']}\n${bt('Reference', 'Reference')}: ${raw['reference']}',
                        ),
                        Text(
                          '${bt('Change', 'ပြောင်းလဲမှု')}: ${raw['change_kind'] ?? 'purchase'} · ${bt('Credit', 'Credit')}: ${subscriptionMmk((raw['credit_used'] as int?) ?? 0)}',
                        ),
                        Text(
                          '${bt('Expected', 'ကျသင့်ငွေ')}: ${subscriptionMmk(raw['total_mmk'] as int)}\n${bt('Claimed transfer', 'လွှဲထားသည်ဆိုသောငွေ')}: ${subscriptionMmk(raw['claimed_mmk'] as int)}\n${bt('Transfer time', 'လွှဲသည့်အချိန်')}: ${billingTime(raw['paid_at'])}',
                        ),
                        for (final bank in raw['banks'] as List)
                          if (bank['id'] == raw['bank_id'])
                            SelectableText(
                              '${bank['bank']}\n${bank['holder']}\n${bank['number']}',
                            ),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (raw['document_id'] != null)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => view(raw['document_id'] as String),
                                child: Text(
                                  bt(
                                    'View transfer proof',
                                    'ငွေလွှဲပြေစာကြည့်မည်',
                                  ),
                                ),
                              ),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => reviewPayment(
                                      Map<String, dynamic>.from(raw as Map),
                                      true,
                                    ),
                              child: Text(
                                bt('Final approve', 'နောက်ဆုံး အတည်ပြုမည်'),
                              ),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => reviewPayment(
                                      Map<String, dynamic>.from(raw as Map),
                                      false,
                                    ),
                              child: Text(bt('Reject', 'ပယ်ချမည်')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                bt(
                  'This queue replaces email attachments. Automated email notifications and refunds are not configured. Transfer proofs are kept in private cloud storage, outside POS backups.',
                  'ဤစာရင်းမှ စစ်ဆေးနိုင်ပြီး Email attachment ပို့ခြင်း မလိုပါ။ အလိုအလျောက် Email အသိပေးခြင်းနှင့် Refund မချိတ်ရသေးပါ။ ငွေလွှဲပြေစာများကို POS Backup ပြင်ပရှိ သီးသန့် Cloud တွင် သိမ်းပါသည်။',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
