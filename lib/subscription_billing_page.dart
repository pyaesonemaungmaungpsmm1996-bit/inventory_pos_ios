import 'desktop_ui.dart';
import 'simple_setup_page.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_forms.dart';
import 'app_database.dart';
import 'subscription_runtime.dart';
import 'subscription_reminders.dart';
import 'billing_admin_page.dart';
import 'online_account_service.dart';
import 'subscription_billing_service.dart';
import 'subscription_pricing.dart';

class SubscriptionBillingPage extends StatefulWidget {
  const SubscriptionBillingPage({super.key});
  @override
  State<SubscriptionBillingPage> createState() =>
      _SubscriptionBillingPageState();
}

class _SubscriptionBillingPageState extends State<SubscriptionBillingPage> {
  List<Map<String, dynamic>> businesses = [];
  Map<String, dynamic>? data;
  StreamSubscription<AuthState>? auth;
  String? selected, message, planBusiness;
  bool initialized = false, busy = false, loading = true, admin = false;
  String? keepBranch;
  List<Map<String, Object?>> localBranches = [];
  String plan = 'standard';
  int months = 1;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    generation++;
    auth?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      await OnlineAccounts.initialize();
      if (!mounted) {
        return;
      }
      initialized = true;
      auth = OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        unawaited(refresh());
      });
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          message = BillingService.friendly(e);
          loading = false;
        });
      }
    }
  }

  Future<void> refresh() async {
    if (!initialized || !mounted) {
      return;
    }
    final version = ++generation;
    setState(() {
      loading = true;
      data = null;
    });
    final owner = OnlineAccounts.client.auth.currentUser?.id;
    if (owner == null) {
      setState(() {
        businesses = [];
        selected = null;
        admin = false;
        loading = false;
      });
      return;
    }
    try {
      final rows = (await OnlineAccounts.snapshot())
          .where((r) => r['role'] == 'owner' && r['active'] == true)
          .toList();
      final chosen = rows.any((r) => r['id'] == selected)
          ? selected
          : rows.isEmpty
          ? null
          : rows.first['id'] as String;
      final localRows = await (await AppDatabase.instance.database).query(
        'branches',
        orderBy: 'id',
      );
      final isAdmin =
          await OnlineAccounts.client.rpc('tp_billing_is_admin') == true;
      final result = chosen == null
          ? null
          : await BillingService.call('tp_billing_home', {
              'p_business': chosen,
            }, owner);
      if (!mounted ||
          generation != version ||
          OnlineAccounts.client.auth.currentUser?.id != owner) {
        return;
      }
      if (result != null && result['policy'] is Map) {
        final policy = Map<String, dynamic>.from(result['policy'] as Map);
        final oldLicense = await SubscriptionRuntime.read();
        await SubscriptionRuntime.update(policy);
        if (oldLicense['business_id'] == policy['business_id'] &&
            (oldLicense['ends_at'] != policy['ends_at'] ||
                oldLicense['next_plan'] != policy['next_plan'] ||
                oldLicense['payment_pending'] != policy['payment_pending'])) {
          try {
            await SubscriptionReminders.cancelOldNotice();
          } catch (_) {
            /* Banner still reflects the current status. */
          }
        }
        await AppDatabase.instance.refreshSubscriptionFence();
      }
      final branches = chosen == null
          ? <dynamic>[]
          : (rows.firstWhere((b) => b['id'] == chosen)['branches'] as List);
      if (!branches.any((b) => b['id'] == keepBranch && b['active'] != false)) {
        keepBranch =
            ((result?['policy'] as Map?)?['next_branch'] ??
                    (result?['policy'] as Map?)?['current_branch'])
                as String?;
        keepBranch ??= branches.where((b) => b['active'] != false).isEmpty
            ? null
            : branches.firstWhere((b) => b['active'] != false)['id'] as String;
      }
      if (planBusiness != chosen) {
        final currentPlan = (result?['policy'] as Map?)?['plan'];
        plan = ['standard', 'premium'].contains(currentPlan)
            ? currentPlan as String
            : 'standard';
        months = 1;
        planBusiness = chosen;
      }
      setState(() {
        localBranches = localRows;
        businesses = rows;
        selected = chosen;
        data = result;
        admin = isAdmin;
        loading = false;
      });
    } catch (e) {
      if (mounted && version == generation) {
        setState(() {
          message = BillingService.friendly(e);
          loading = false;
        });
      }
    }
  }

  Future<void> run(Future<void> Function(String owner) operation) async {
    if (busy || loading) {
      return;
    }
    final owner = OnlineAccounts.client.auth.currentUser?.id;
    if (owner == null) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await operation(owner);
      if (mounted) {
        setState(
          () => message = bt(
            'Completed. Refreshing server status.',
            'ပြီးပါပြီ။ Server အခြေအနေ ပြန်ဖတ်နေပါသည်။',
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

  Future<void> login() async {
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const SimpleSetupPage()));
    if (mounted) {
      await refresh();
    }
  }

  Future<void> connectLicense() async {
    final raw = data?['policy'];
    if (raw is! Map) {
      return;
    }
    final policy = Map<String, dynamic>.from(raw);
    final branchOptions = {
      for (final b in localBranches)
        '${b['id']}': '${b['code']} · ${b['name']}',
    };
    final needsStandard = policy['plan'] == 'standard';
    final needsNext = policy['next_plan'] == 'standard';
    final fields = <BillingField>[
      if (needsStandard)
        BillingField(
          'local',
          bt(
            'Local branch to use on Standard',
            'Standard တွင် ဆက်သုံးမည့် ဖုန်းထဲကဆိုင်ခွဲ',
          ),
          options: branchOptions,
        ),
      if (needsNext)
        BillingField(
          'nextLocal',
          bt(
            'Local branch to keep when Standard starts',
            'Standard စသည့်နေ့တွင် ဆက်သုံးမည့် ဖုန်းထဲကဆိုင်ခွဲ',
          ),
          options: branchOptions,
        ),
    ];
    final form = await billingForm(
      context,
      bt(
        'Confirm POS license connection',
        'POS License ချိတ်ဆက်မှု အတည်ပြုရန်',
      ),
      fields,
      notice: bt(
        'Confirm that this entire local POS database belongs to the selected online business. Other local branches are retained for viewing when Standard starts. Local Backup and Restore do not replace the server subscription.',
        'ဖုန်းထဲက POS ဒေတာအားလုံးသည် ရွေးထားသော Online လုပ်ငန်းပိုင်ဖြစ်ကြောင်း အတည်ပြုပါ။ Standard စသည့်နေ့တွင် ကျန်ဆိုင်ခွဲများ ဖတ်ရှုရန်သာဖြစ်ပြီး ဒေတာမဖျက်ပါ။ Local Backup / Restore က Server သက်တမ်းကို မပြောင်းပါ။',
      ),
    );
    if (form == null || !mounted) {
      return;
    }
    final local = needsStandard ? int.tryParse('${form['local']}') : null;
    final next = needsNext ? int.tryParse('${form['nextLocal']}') : null;
    if ((needsStandard && local == null) || (needsNext && next == null)) {
      setState(
        () => message = bt(
          'Choose the local branch.',
          'ဖုန်းထဲက ဆိုင်ခွဲကို ရွေးပါ။',
        ),
      );
      return;
    }
    await run((owner) async {
      final installation = await OnlineAccounts.installation();
      final latest = await BillingService.call('tp_license_device_snapshot', {
        'p_business': selected,
        'p_installation': installation,
        'p_branch': policy['plan'] == 'standard'
            ? policy['current_branch']
            : keepBranch,
      }, owner);
      if (latest['plan'] != policy['plan'] ||
          latest['next_plan'] != policy['next_plan']) {
        throw StateError('Plan changed. Refresh and choose the branch again');
      }
      latest['local_branch_name'] = local == null
          ? null
          : localBranches.firstWhere((b) => b['id'] == local)['name'];
      latest['next_local_branch_name'] = next == null
          ? null
          : localBranches.firstWhere((b) => b['id'] == next)['name'];
      await SubscriptionRuntime.bind(latest, local, next);
      await AppDatabase.instance.refreshSubscriptionFence();
      await SubscriptionReminders.cancelOldNotice();
      await SubscriptionReminders.allowNotifications();
    });
  }

  Future<void> quote() async {
    if (!await billingConfirm(
          context,
          bt('Get a payment quote?', 'ငွေချေရန် ဈေးနှုန်းတောင်းမလား?'),
          bt(
            'The server will lock the current price and bank details for 24 hours. Check that quote before transferring. This does not activate a plan.',
            'Server မှ လက်ရှိဈေးနှင့် ဘဏ်အချက်အလက်ကို ၂၄ နာရီအတွက် သတ်မှတ်ပေးပါမည်။ ငွေမလွှဲမီ ဈေးနှုန်းကို စစ်ပါ။ Plan ကို ဖွင့်ပေးခြင်း မဟုတ်သေးပါ။',
          ),
        ) ||
        !mounted) {
      return;
    }
    await run((owner) async {
      await BillingService.call('tp_billing_quote_v2', {
        'p_business': selected,
        'p_plan': plan,
        'p_months': months,
        'p_keep_branch': plan == 'standard' ? keepBranch : null,
      }, owner);
    });
  }

  Future<void> pay(Map<String, dynamic> r) async {
    if (r['total_mmk'] == 0) {
      if (await billingConfirm(
            context,
            bt('Submit credit-only request?', 'Credit ဖြင့် တောင်းဆိုမလား?'),
            bt(
              'No bank transfer is required. The provider will review your subscription credit.',
              'ဘဏ်မှ ငွေလွှဲရန် မလိုပါ။ Provider က သက်တမ်း Credit ကို စစ်ဆေးပါမည်။',
            ),
          ) &&
          mounted) {
        await run((_) async {
          await OnlineAccounts.client.rpc(
            'tp_billing_credit_submit',
            params: {'p_request': r['id']},
          );
        });
      }
      return;
    }
    final banks = (r['banks'] as List)
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final form = await billingForm(
      context,
      bt('Submit bank transfer proof', 'ငွေလွှဲပြေစာတင်မည်'),
      [
        BillingField(
          'bank',
          bt('Bank paid to', 'ငွေလွှဲထားသော ဘဏ်'),
          initial: banks.first['id'] as String,
          options: {
            for (final b in banks)
              b['id'] as String: '${b['bank']} · ${b['number']}',
          },
        ),
        BillingField(
          'reference',
          bt('Transaction reference', 'ငွေလွှဲ Reference နံပါတ်'),
        ),
        BillingField(
          'amount',
          bt('Amount transferred (MMK)', 'လွှဲထားသောငွေ (ကျပ်)'),
          initial: '${r['total_mmk']}',
          number: true,
        ),
        BillingField(
          'paidAt',
          bt('Actual transfer date / time', 'တကယ်ငွေလွှဲခဲ့သော နေ့ / အချိန်'),
          initial: DateTime.now().toUtc().toIso8601String(),
          date: true,
        ),
      ],
      image: true,
      notice:
          '${r['plan']} · ${r['months']} ${bt('months', 'လ')} · ${subscriptionMmk(r['total_mmk'] as int)}\n'
          '${bt('Quote expires', 'ဈေးနှုန်း သက်တမ်းကုန်ချိန်')}: ${billingTime(r['expires_at'])}\n'
          '${bt('Upload before expiry. If already paid and the quote has expired, contact the provider before making another payment.', 'သက်တမ်းမကုန်မီ တင်ပါ။ ငွေလွှဲပြီးမှ သက်တမ်းကုန်လျှင် ထပ်မလွှဲဘဲ Provider ကို ဆက်သွယ်ပါ။')}',
    );
    if (form == null || !mounted) {
      return;
    }
    await run((owner) async {
      final amount = int.tryParse(form['amount'] as String);
      if (amount == null) {
        throw const FormatException('Enter a whole MMK amount');
      }
      if (DateTime.tryParse(form['paidAt'] as String) == null) {
        throw const FormatException('Choose the transfer date and time');
      }
      final doc = await BillingService.upload(
        r['business_id'] as String,
        'payment',
        form['image'] as BillingImage,
        owner,
      );
      BillingService.guard(owner);
      await OnlineAccounts.client.rpc(
        'tp_billing_payment_submit',
        params: {
          'p_request': r['id'],
          'p_document': doc,
          'p_bank': form['bank'],
          'p_reference': form['reference'],
          'p_claimed': amount,
          'p_paid_at': form['paidAt'],
        },
      );
    });
  }

  Future<void> copyAccount(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bt('Account number copied', 'အကောင့်နံပါတ် ကူးယူပြီးပါပြီ'),
        ),
      ),
    );
  }

  Widget paymentAccount(Map bank) {
    final colors = Theme.of(context).colorScheme;
    final number = '${bank['number'] ?? ''}';
    final instructions = '${bank['instructions'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${bank['bank'] ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            bt('Account holder', 'အကောင့်ပိုင်ရှင်'),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          SelectableText('${bank['holder'] ?? ''}'),
          const SizedBox(height: 12),
          Text(
            bt('Account number', 'အကောင့်နံပါတ်'),
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  number,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: bt('Copy account number', 'အကောင့်နံပါတ် ကူးယူရန်'),
                onPressed: () => copyAccount(number),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          if (instructions.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              instructions,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget request(Map<String, dynamic> r) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r['plan']} · ${r['months']} ${bt('months', 'လ')} · ${billingState(r['state'])}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bt('Amount to pay', 'ပေးချေရမည့်ငွေ')),
                const SizedBox(height: 6),
                Text(
                  subscriptionMmk(r['total_mmk'] as int),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          DesktopSection(
            tilePadding: EdgeInsets.zero,
            title: Text(
              bt(
                'Price & request details',
                'ဈေးနှုန်းနှင့် တောင်းဆိုမှုအသေးစိတ်',
              ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '${bt('Request', 'တောင်းဆိုမှု')}: ${r['id']}',
                    ),
                    Text(
                      '${bt('Original', 'မူရင်း')}: ${subscriptionMmk(r['base_mmk'] as int)}\n${bt('Discount', 'လျှော့ဈေး')}: ${subscriptionMmk(r['discount_mmk'] as int)}\n${bt('Total', 'စုစုပေါင်း')}: ${subscriptionMmk(r['total_mmk'] as int)}',
                    ),
                    Text(
                      '${bt('Unused Standard credit', 'မသုံးရသေးသော Standard တန်ဖိုး')}: ${subscriptionMmk((r['upgrade_credit'] as int?) ?? 0)} · ${bt('Credit left after approval', 'အတည်ပြုပြီး ကျန်မည့် Credit')}: ${subscriptionMmk(((r['wallet_before'] as int?) ?? 0) + ((r['upgrade_credit'] as int?) ?? 0) - ((r['credit_used'] as int?) ?? 0))}',
                    ),
                    Text(
                      '${bt('Change type', 'ပြောင်းလဲမှု')}: ${r['change_kind'] ?? 'purchase'} · ${bt('Credit applied', 'Credit နုတ်ငွေ')}: ${subscriptionMmk((r['credit_used'] as int?) ?? 0)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r['plan'] == 'standard' &&
              r['keep_branch'] == null &&
              ['draft', 'pending'].contains(r['state']))
            OutlinedButton(
              onPressed: busy || loading || keepBranch == null
                  ? null
                  : () => run((_) async {
                      await OnlineAccounts.client.rpc(
                        'tp_billing_assign_request_branch',
                        params: {'p_request': r['id'], 'p_branch': keepBranch},
                      );
                    }),
              child: Text(
                bt(
                  'Assign selected online branch to this request',
                  'ရွေးထားသော Online ဆိုင်ခွဲကို ဤတောင်းဆိုမှုတွင် သတ်မှတ်မည်',
                ),
              ),
            ),
          if (r['state'] == 'draft') ...[
            Text(
              '${bt('Pay and upload before', 'ငွေလွှဲပြီး ပြေစာတင်ရန် နောက်ဆုံးအချိန်')}: ${billingTime(r['expires_at'])}',
            ),
            if (r['total_mmk'] != 0) ...[
              const Divider(height: 32),
              Text(
                bt('Payment accounts', 'ငွေလက်ခံအကောင့်များ'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                bt(
                  'Transfer to ONE account below, then upload your receipt.',
                  'အောက်ပါအကောင့်တစ်ခုကိုသာ ငွေလွှဲပြီး ပြေစာတင်ပါ။',
                ),
              ),
              for (final b in r['banks'] as List) paymentAccount(b as Map),
              const SizedBox(height: 20),
            ],
            FilledButton(
              onPressed: busy || loading ? null : () => pay(r),
              child: Text(
                r['total_mmk'] == 0
                    ? bt('Submit using credit', 'Credit ဖြင့် တင်မည်')
                    : bt('Upload transfer proof', 'ငွေလွှဲပြေစာတင်မည်'),
              ),
            ),
            TextButton(
              onPressed: busy || loading
                  ? null
                  : () async {
                      if (await billingConfirm(
                            context,
                            bt(
                              'Cancel unpaid quote?',
                              'မချေရသေးသော ဈေးနှုန်းကို ပယ်ဖျက်မလား?',
                            ),
                            bt(
                              'Only cancel if no payment has been sent.',
                              'ငွေမလွှဲရသေးမှ ပယ်ဖျက်ပါ။',
                            ),
                          ) &&
                          mounted) {
                        await run((_) async {
                          await OnlineAccounts.client.rpc(
                            'tp_billing_cancel',
                            params: {'p_request': r['id']},
                          );
                        });
                      }
                    },
              child: Text(
                bt(
                  'Cancel unpaid quote',
                  'မချေရသေးသော တောင်းဆိုမှုကို ပယ်ဖျက်မည်',
                ),
              ),
            ),
          ],
          if (r['document_id'] != null)
            TextButton(
              onPressed: busy || loading
                  ? null
                  : () => run(
                      (owner) => billingView(
                        context,
                        r['document_id'] as String,
                        owner,
                      ),
                    ),
              child: Text(
                bt('View submitted proof', 'တင်ထားသော ပြေစာကြည့်မည်'),
              ),
            ),
          if (r['state'] == 'pending')
            Text(
              bt(
                'Waiting for administrator review. Do not send the payment again.',
                'Admin စစ်ဆေးရန် စောင့်နေပါသည်။ ငွေထပ်မလွှဲပါနှင့်။',
              ),
            ),
          if (r['state'] == 'rejected')
            Text(
              bt(
                'If money has already left your bank account, contact the provider before making another payment.',
                'ငွေလွှဲပြီးသားဖြစ်လျှင် ထပ်မလွှဲမီ Provider ကို ဆက်သွယ်ပြီး ဖြေရှင်းပါ။',
              ),
            ),
          if (r['state'] == 'approved')
            Text(
              '${bt('Approved expiry', 'အတည်ပြု သက်တမ်းကုန်ချိန်')}: ${billingTime(r['activated_until'])}',
            ),
          if ('${r['note']}'.isNotEmpty)
            Text('${bt('Review note', 'စစ်ဆေးမှတ်ချက်')}: ${r['note']}'),
        ],
      ),
    ),
  );
  Widget planOption(String id, String title, String description) {
    final chosen = plan == id;
    final colors = Theme.of(context).colorScheme;
    final price = (data!['catalog'] as Map)['${id}_mmk'] as int;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: chosen ? colors.primaryContainer : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: chosen ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: DesktopListTile(
          enabled: !busy && !loading,
          onTap: () => setState(() => plan = id),
          leading: Icon(
            chosen ? Icons.check_circle : Icons.circle_outlined,
            color: chosen ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            '$description\n${subscriptionMmk(price)} / ${bt('month', 'လ')}',
          ),
          isThreeLine: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = initialized
        ? OnlineAccounts.client.auth.currentUser?.id
        : null;
    final entitlement = data?['entitlement'] as Map?;
    final requests = (data?['requests'] as List?) ?? [];
    final current = requests
        .where((r) => r['state'] == 'draft' || r['state'] == 'pending')
        .toList();
    final history = requests
        .where((r) => r['state'] != 'draft' && r['state'] != 'pending')
        .toList();
    final active = entitlement?['active'] == true;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !busy,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(bt('Plan & Subscription', 'Plan နှင့် သက်တမ်း')),
          actions: [
            IconButton(
              tooltip: bt('Refresh', 'ပြန်စစ်မည်'),
              onPressed: busy
                  ? null
                  : initialized
                  ? refresh
                  : initialize,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: DesktopListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading || busy) const LinearProgressIndicator(),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(message!),
              ),
            if (!loading && owner == null) ...[
              Text(
                bt(
                  'Sign in as the shop Owner to view or renew a plan.',
                  'Plan ကြည့်ရန် သို့မဟုတ် သက်တမ်းတိုးရန် ဆိုင် Owner ဖြင့် ဝင်ပါ။',
                ),
              ),
              FilledButton(
                onPressed: busy ? null : login,
                child: Text(
                  bt('Login / Create Account', 'အကောင့်ဝင်ရန် / အသစ်ဖွင့်ရန်'),
                ),
              ),
            ],
            if (!loading && owner != null && businesses.isEmpty) ...[
              Text(
                bt(
                  'Only the shop Owner can buy or renew a plan. If you are setting up a new shop, continue setup.',
                  'ဆိုင် Owner သာ Plan ဝယ်/သက်တမ်းတိုးနိုင်ပါသည်။ ဆိုင်အသစ်ဖွင့်နေပါက Setup ဆက်လုပ်ပါ။',
                ),
              ),
              OutlinedButton(
                onPressed: busy ? null : login,
                child: Text(bt('Continue setup', 'Setup ဆက်လုပ်ရန်')),
              ),
            ],
            if (businesses.length > 1)
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: bt('Business', 'လုပ်ငန်း'),
                ),
                items: businesses
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'] as String,
                        child: Text(b['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: busy || loading
                    ? null
                    : (v) {
                        setState(() => selected = v);
                        refresh();
                      },
              ),
            if (data != null) ...[
              Card(
                color: colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        businesses.firstWhere(
                              (b) => b['id'] == selected,
                            )['name']
                            as String,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        entitlement?['plan'] == null
                            ? bt('No plan yet', 'Plan မစရသေးပါ')
                            : '${entitlement!['plan']}'.toUpperCase(),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? bt('Active', 'သက်တမ်းရှိ')
                            : bt('Inactive', 'သက်တမ်းမရှိ'),
                      ),
                      Text(
                        '${bt('Valid until', 'သက်တမ်းကုန်ချိန်')}: ${billingTime(entitlement?['ends_at'])}',
                      ),
                      if (entitlement?['next_plan'] != null)
                        Text(
                          '${bt('Next plan', 'နောက် Plan')}: ${entitlement!['next_plan']} · ${billingTime(entitlement['next_from'])}',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (current.isNotEmpty) ...[
                Text(
                  bt('Your payment progress', 'ငွေချေမှု အခြေအနေ'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ...current.map(
                  (r) => request(Map<String, dynamic>.from(r as Map)),
                ),
              ] else if (data!['catalog'] != null) ...[
                Text(
                  bt('1 · Choose your plan', '၁ · Plan ရွေးပါ'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                planOption(
                  'standard',
                  'Standard',
                  bt('1 branch · Local Backup', 'ဆိုင်ခွဲ ၁ ခု · Local Backup'),
                ),
                planOption(
                  'premium',
                  'Premium',
                  bt('Unlimited branches', 'ဆိုင်ခွဲအကန့်အသတ်မရှိ'),
                ),
                const SizedBox(height: 12),
                Text(
                  bt('2 · Choose duration', '၂ · သက်တမ်းရွေးပါ'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: months,
                  decoration: InputDecoration(
                    labelText: bt('Duration', 'သက်တမ်း'),
                  ),
                  items: SubscriptionCatalog.terms
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            m == 1
                                ? bt('1 month', '၁ လ')
                                : '${m ~/ 12} ${bt('year(s)', 'နှစ်')}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy || loading
                      ? null
                      : (v) {
                          if (v != null) setState(() => months = v);
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  '${bt('Discount', 'လျှော့ဈေး')}: ${(((data!['catalog'] as Map)['discounts'] as Map)['$months'] as num) / 100}%',
                ),
                if (plan == 'standard' &&
                    businesses.any((b) => b['id'] == selected))
                  DropdownButton<String>(
                    isExpanded: true,
                    value: keepBranch,
                    items:
                        ((businesses.firstWhere(
                                      (b) => b['id'] == selected,
                                    )['branches']
                                    as List)
                                .where((b) => b['active'] != false))
                            .map(
                              (b) => DropdownMenuItem(
                                value: b['id'] as String,
                                child: Text(
                                  '${bt('Keep online branch', 'ဆက်သုံးမည့် Online ဆိုင်ခွဲ')}: ${b['name']}',
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => keepBranch = v),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy || loading || data!['accepting'] != true
                      ? null
                      : quote,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    bt(
                      '3 · Review price & payment',
                      '၃ · ဈေးနှုန်းနှင့် ငွေချေနည်း ကြည့်မည်',
                    ),
                  ),
                ),
                Text(
                  bt(
                    'Review the confirmed price and payment account before transferring.',
                    'ငွေမလွှဲမီ အတည်ပြုဈေးနှုန်းနှင့် ငွေလက်ခံအကောင့်ကို စစ်ပါ။',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (data!['accepting'] != true)
                  Text(
                    bt(
                      'Payment collection is not enabled yet. Do not transfer money.',
                      'ငွေလက်ခံစနစ် မဖွင့်ရသေးပါ။ ငွေမလွှဲပါနှင့်။',
                    ),
                  ),
              ],
              if (history.isNotEmpty)
                Card(
                  child: DesktopSection(
                    title: Text(bt('Payment history', 'ငွေချေမှတ်တမ်း')),
                    subtitle: Text('${history.length} ${bt('requests', 'ခု')}'),
                    children: history
                        .map(
                          (r) => request(Map<String, dynamic>.from(r as Map)),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 12),
              DesktopSection(
                title: Text(
                  bt('Connection & more details', 'ချိတ်ဆက်မှုနှင့် အသေးစိတ်'),
                ),
                children: [
                  if (plan != 'standard' &&
                      businesses.any((b) => b['id'] == selected))
                    DropdownButton<String>(
                      isExpanded: true,
                      value: keepBranch,
                      items:
                          ((businesses.firstWhere(
                                        (b) => b['id'] == selected,
                                      )['branches']
                                      as List)
                                  .where((b) => b['active'] != false))
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b['id'] as String,
                                  child: Text(
                                    '${bt('Keep online branch', 'ဆက်သုံးမည့် Online ဆိုင်ခွဲ')}: ${b['name']}',
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => keepBranch = v),
                    ),
                  Text(
                    bt(
                      'Expired plans retain existing records, export and Local Backup access.',
                      'သက်တမ်းကုန်လည်း ဒေတာဟောင်း၊ Export နှင့် Local Backup ဆက်ရပါသည်။',
                    ),
                  ),
                  if (entitlement?['credit_mmk'] != null)
                    Text(
                      '${bt('Subscription credit', 'သက်တမ်း Credit')}: ${subscriptionMmk(entitlement!['credit_mmk'] as int)}',
                    ),
                  OutlinedButton(
                    onPressed: busy || loading ? null : connectLicense,
                    child: Text(
                      bt(
                        'Reconnect POS license & reminders',
                        'POS License နှင့် သတိပေးချက် ပြန်ချိတ်ရန်',
                      ),
                    ),
                  ),

                  if ((data!['entitlement'] as Map?)?['next_plan'] ==
                      'standard')
                    OutlinedButton(
                      onPressed: busy || loading || keepBranch == null
                          ? null
                          : () => run((_) async {
                              await OnlineAccounts.client.rpc(
                                'tp_billing_change_next_branch',
                                params: {
                                  'p_business': selected,
                                  'p_branch': keepBranch,
                                },
                              );
                            }),
                      child: Text(
                        bt(
                          'Change the scheduled Standard branch',
                          'စီစဉ်ထားသော Standard ဆိုင်ခွဲ ပြောင်းမည်',
                        ),
                      ),
                    ),
                  if ((data!['policy'] as Map?)?['plan'] == 'standard' &&
                      (data!['policy'] as Map?)?['current_branch'] == null)
                    OutlinedButton(
                      onPressed: busy || loading || keepBranch == null
                          ? null
                          : () => run((_) async {
                              await OnlineAccounts.client.rpc(
                                'tp_billing_set_standard_branch',
                                params: {
                                  'p_business': selected,
                                  'p_branch': keepBranch,
                                },
                              );
                            }),
                      child: Text(
                        bt(
                          'Confirm selected Standard online branch',
                          'ရွေးထားသော Standard Online ဆိုင်ခွဲကို အတည်ပြုမည်',
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (admin && owner != null)
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BillingAdminPage(owner: owner),
                          ),
                        );
                        if (mounted) {
                          await refresh();
                        }
                      },
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text(
                  bt(
                    'Provider Admin · Review payments',
                    'Provider Admin · ငွေချေမှုစစ်ဆေးရန်',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
