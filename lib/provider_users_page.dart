import 'desktop_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'billing_forms.dart';
import 'subscription_billing_service.dart';
import 'online_account_service.dart';

class ProviderUsersPage extends StatefulWidget {
  const ProviderUsersPage({super.key, required this.owner});
  final String owner;
  @override
  State<ProviderUsersPage> createState() => _ProviderUsersPageState();
}

class _ProviderUsersPageState extends State<ProviderUsersPage> {
  Map<String, dynamic>? data;
  String search = '', status = 'all', plan = 'all';
  int page = 0, request = 0;
  bool loading = false;
  String? error;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ModalRoute.of(context)?.isCurrent == true && !loading) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    request++;
    super.dispose();
  }

  Future<void> load() async {
    final version = ++request;
    setState(() => loading = true);
    try {
      final result = await BillingService.call('tp_provider_users', {
        'p_search': search,
        'p_state': status,
        'p_plan': plan,
        'p_page': page,
      }, widget.owner);
      if (mounted && version == request) {
        setState(() {
          data = result;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && version == request) {
        setState(() {
          data = null;
          error = BillingService.friendly(e);
          loading = false;
        });
      }
    }
  }

  Widget filter(
    String label,
    String value,
    List<String> items,
    void Function(String) change,
  ) => Expanded(
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final x in items)
          DropdownMenuItem(value: x, child: Text(x.toUpperCase())),
      ],
      onChanged: loading
          ? null
          : (v) {
              change(v!);
              page = 0;
              load();
            },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final summary = data?['summary'] as Map?;
    final rows = (data?['rows'] as List?) ?? [];
    final total = (data?['total'] as int?) ?? 0;
    final counts = summary?['plan_users'] as Map?;
    return DesktopScaffold(
      appBar: AppBar(
        title: Text(bt('Users & Businesses', 'User နှင့် လုပ်ငန်းများ')),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (summary != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bt('Registered users', 'မှတ်ပုံတင် User စုစုပေါင်း')}: ${summary['registered_users']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${bt('Seen in the last 5 minutes', 'နောက်ဆုံး ၅ မိနစ်အတွင်း Online ချိတ်ထားသူ')}: ${summary['recent_users']}',
                    ),
                    Text(
                      '${bt('Businesses', 'လုပ်ငန်းစုစုပေါင်း')}: ${summary['businesses']}',
                    ),
                    const Divider(),
                    for (final p in ['trial', 'standard', 'premium'])
                      Text(
                        '${p.toUpperCase()} · ${counts?[p] ?? 0} ${bt('users', 'ဦး')} · ${summary[p]} ${bt('businesses', 'လုပ်ငန်း')}',
                      ),
                    const SizedBox(height: 8),
                    Text(
                      bt(
                        'Plan counts show active subscriptions. Recent use means a foreground heartbeat within 5 minutes, not proof of continuous activity. Offline use is not live. A person in multiple businesses can appear under more than one plan.',
                        'Plan အရေအတွက်သည် သက်တမ်းရှိသူများ ဖြစ်ပါသည်။ ၅ မိနစ်အတွင်း App မှ Online အချက်ပြရရှိသူကို Recent ဟုတွက်ပါသည်။ Offline သုံးခြင်းကို Live မမြင်ရပါ။ လုပ်ငန်းများစွာတွင် ပါသူကို Plan တစ်မျိုးထက်ပို၍ တွက်နိုင်ပါသည်။',
                      ),
                    ),
                    Text(
                      '${bt('Server time', 'Server အချိန်')}: ${billingTime(data?['server_now'])}',
                    ),
                  ],
                ),
              ),
            ),
          TextField(
            onChanged: (v) => search = v,
            onSubmitted: (_) {
              page = 0;
              load();
            },
            decoration: InputDecoration(
              labelText: bt(
                'Search email / phone / shop / township',
                'Email / ဖုန်း / ဆိုင် / မြို့နယ် ရှာရန်',
              ),
              suffixIcon: IconButton(
                onPressed: () {
                  page = 0;
                  load();
                },
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          Row(
            children: [
              filter(bt('Status', 'အခြေအနေ'), status, [
                'all',
                'active',
                'suspended',
                'archived',
              ], (v) => status = v),
              const SizedBox(width: 12),
              filter('Plan', plan, [
                'all',
                'trial',
                'standard',
                'premium',
                'expired',
                'none',
              ], (v) => plan = v),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          DesktopInlineTable(
            columns: const [
              "Name",
              "Email / Phone",
              "Status",
              "Last seen",
              "Businesses",
            ],
            rows: [
              for (final raw in rows)
                Card(
                  child: DesktopListTile(
                    title: Text(
                      '${raw['display_name'] ?? ''}\n${raw['email'] ?? raw['phone'] ?? raw['id']}',
                    ),
                    subtitle: Text(
                      '${raw['status']} · ${bt('Last seen', 'နောက်ဆုံးတွေ့ချိန်')}: ${billingTime(raw['seen_at'])}\n${(raw['businesses'] as List).map((b) => '${b['name']} · ${b['township'] ?? bt('Location not supplied', 'မြို့နယ်မဖြည့်ရသေး')} · ${b['role']}').join('\n')}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProviderUserDetailPage(
                            owner: widget.owner,
                            userId: raw['id'] as String,
                          ),
                        ),
                      );
                      if (mounted) load();
                    },
                  ),
                ),
            ],
            cells: [
              for (final raw in rows)
                [
                  desktopCellText(raw['display_name']),
                  desktopCellText(raw['email'] ?? raw['phone'] ?? raw['id']),
                  desktopCellText(raw['status']),
                  desktopCellText(billingTime(raw['seen_at'])),
                  desktopCellText(
                    (raw['businesses'] as List)
                        .map((b) => b['name'])
                        .join(', '),
                  ),
                ],
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: page > 0 && !loading
                    ? () {
                        page--;
                        load();
                      }
                    : null,
                child: Text(bt('Previous', 'ရှေ့စာမျက်နှာ')),
              ),
              Text('${page + 1} · $total'),
              TextButton(
                onPressed: (page + 1) * 30 < total && !loading
                    ? () {
                        page++;
                        load();
                      }
                    : null,
                child: Text(bt('Next', 'နောက်စာမျက်နှာ')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProviderUserDetailPage extends StatefulWidget {
  const ProviderUserDetailPage({
    super.key,
    required this.owner,
    required this.userId,
  });
  final String owner, userId;
  @override
  State<ProviderUserDetailPage> createState() => _ProviderUserDetailPageState();
}

class _ProviderUserDetailPageState extends State<ProviderUserDetailPage> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  int page = 0;
  Future<void> load() async {
    try {
      final r = await BillingService.call('tp_provider_user_detail', {
        'p_user': widget.userId,
        'p_page': page,
      }, widget.owner);
      if (mounted) setState(() => data = r);
    } catch (e) {
      if (mounted) {
        setState(() {
          data = null;
          error = BillingService.friendly(e);
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      BillingService.guard(widget.owner);
      await operation();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = BillingService.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editUser(Map u) async {
    final f = await billingForm(
      context,
      bt('Edit / archive account', 'User ပြင် / ပိတ်ထားရန်'),
      [
        BillingField(
          'name',
          bt('Display name', 'ဖော်ပြမည့်အမည်'),
          initial: '${u['display_name']}',
        ),
        BillingField(
          'status',
          'Status',
          initial: '${u['status']}',
          options: const {
            'active': 'Active',
            'suspended': 'Suspended',
            'archived': 'Archived / Remove from active list',
          },
        ),
        BillingField(
          'note',
          bt('Private support note', 'သီးသန့် Support မှတ်ချက်'),
          initial: '${u['note']}',
        ),
        BillingField(
          'reason',
          bt('Reason · required', 'အကြောင်းရင်း · မဖြစ်မနေ'),
        ),
      ],
      notice: bt(
        'Archive/suspend keeps payment and local POS records. Email/phone changes require the user OTP flow. Provider admin accounts cannot be changed here.',
        'ပိတ်ထားခြင်းသည် ငွေချေမှုနှင့် Local POS ဒေတာ မဖျက်ပါ။ Email/ဖုန်းပြောင်းရန် User OTP လိုပါသည်။ Provider Admin အကောင့်ကို ဤနေရာမှ မပြင်နိုင်ပါ။',
      ),
    );
    if (f == null || !mounted) return;
    if (!await billingConfirm(
      context,
      bt('Save account change?', 'User ပြောင်းလဲမှု သိမ်းမလား?'),
      bt(
        'A status change takes effect when connected devices refresh online. Offline caches are not remotely erased.',
        'Device က Online ပြန်စစ်ချိန် အသုံးပြုခွင့် ပြောင်းပါမည်။ Offline ဒေတာကို အဝေးမှ မဖျက်ပါ။',
      ),
    )) {
      return;
    }
    await action(() async {
      await OnlineAccounts.client.rpc(
        'tp_provider_user_edit',
        params: {
          'p_user': widget.userId,
          'p_name': f['name'],
          'p_status': f['status'],
          'p_note': f['note'],
          'p_revision': u['revision'],
          'p_reason': f['reason'],
        },
      );
    });
  }

  Future<void> editBusiness(Map b) async {
    final profile = b['profile'] as Map;
    final f = await billingForm(
      context,
      bt('Edit business', 'လုပ်ငန်းပြင်ရန်'),
      [
        BillingField(
          'name',
          bt('Business name', 'လုပ်ငန်းအမည်'),
          initial: '${b['name']}',
        ),
        BillingField(
          'township',
          bt('Township', 'မြို့နယ်'),
          initial: '${profile['township'] ?? ''}',
        ),
        BillingField(
          'city',
          bt('City', 'မြို့'),
          initial: '${profile['city'] ?? ''}',
        ),
        BillingField(
          'region',
          bt('Region / State', 'တိုင်း / ပြည်နယ်'),
          initial: '${profile['region'] ?? ''}',
        ),
        BillingField(
          'status',
          'Status',
          initial: '${profile['status']}',
          options: const {
            'active': 'Active',
            'suspended': 'Suspended',
            'archived': 'Archived',
          },
        ),
        BillingField(
          'reason',
          bt('Reason · required', 'အကြောင်းရင်း · မဖြစ်မနေ'),
        ),
      ],
    );
    if (f == null || !mounted) return;
    if (!await billingConfirm(
      context,
      bt('Save business change?', 'လုပ်ငန်းပြင်ဆင်မှု သိမ်းမလား?'),
      '${f['name']} · ${f['status']}',
    )) {
      return;
    }
    await action(() async {
      await OnlineAccounts.client.rpc(
        'tp_provider_business_edit',
        params: {
          'p_business': b['id'],
          'p_name': f['name'],
          'p_township': f['township'],
          'p_city': f['city'],
          'p_region': f['region'],
          'p_status': f['status'],
          'p_revision': profile['revision'],
          'p_reason': f['reason'],
        },
      );
    });
  }

  Future<void> expiry(Map b) async {
    final e = b['entitlement'] as Map?;
    if (e == null) return;
    final f = await billingForm(
      context,
      bt('Correct approved expiry', 'အတည်ပြုသက်တမ်းရက် ပြင်ရန်'),
      [
        BillingField(
          'until',
          bt(
            'New expiry · ISO date/time with timezone',
            'သက်တမ်းအသစ် · Timezone ပါသော ISO ရက်အချိန်',
          ),
          initial: '${e['ends_at']}',
        ),
        BillingField(
          'reason',
          bt('Correction reason', 'ပြင်ရသည့်အကြောင်းရင်း'),
        ),
      ],
      notice: bt(
        'Support correction only. Standard/Premium changes and renewals still use the normal quote/payment approval flow. No new payment is created.',
        'Support ပြင်ဆင်မှုအတွက်သာ ဖြစ်ပါသည်။ Plan ပြောင်းခြင်းနှင့် သက်တမ်းတိုးခြင်းသည် မူရင်းငွေချေတောင်းဆိုမှုအတိုင်း လုပ်ရပါမည်။ ငွေချေမှုအသစ် မဖန်တီးပါ။',
      ),
    );
    if (f == null || !mounted) return;
    final parsed = DateTime.tryParse('${f['until']}');
    if (parsed == null ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch('${f['until']}')) {
      setState(
        () => error = bt(
          'Enter a timezone, for example 2026-12-11T23:59:00+06:30',
          'Timezone ပါအောင် ထည့်ပါ။ ဥပမာ 2026-12-11T23:59:00+06:30',
        ),
      );
      return;
    }
    if (!await billingConfirm(
      context,
      bt('Correct expiry?', 'သက်တမ်းကုန်ရက် ပြင်မလား?'),
      '${billingTime(e['ends_at'])} → ${billingTime(f['until'])}\n${f['reason']}',
    )) {
      return;
    }
    await action(() async {
      await OnlineAccounts.client.rpc(
        'tp_provider_expiry_correct',
        params: {
          'p_business': b['id'],
          'p_expected': e['ends_at'],
          'p_until': parsed.toUtc().toIso8601String(),
          'p_reason': f['reason'],
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = data?['user'] as Map?;
    return DesktopScaffold(
      appBar: AppBar(
        title: Text(
          bt('User details & history', 'User အသေးစိတ်နှင့် မှတ်တမ်း'),
        ),
      ),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy || data == null) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (u != null) ...[
            SelectableText(
              '${u['display_name']}\n${u['email'] ?? ''}\n${u['phone'] ?? ''}\n${u['id']}\n${u['status']}\n${bt('Registered', 'စာရင်းသွင်းရက်')}: ${billingTime(u['created_at'])}\n${bt('Last login', 'နောက်ဆုံး Login')}: ${billingTime(u['last_sign_in_at'])}\n${u['note']}',
            ),
            FilledButton(
              onPressed: busy ? null : () => editUser(u),
              child: Text(bt('Edit / archive user', 'User ပြင် / ပိတ်ထားရန်')),
            ),
            for (final raw in data!['businesses'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${raw['name']} · ${raw['role']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${raw['profile']['township'] ?? ''} · ${raw['profile']['city'] ?? ''} · ${raw['profile']['region'] ?? ''}\n${raw['policy']['plan'] ?? '—'} · ${raw['policy']['active'] == true ? 'ACTIVE' : 'INACTIVE'}\n${bt('Expiry', 'သက်တမ်းကုန်')}: ${billingTime(raw['policy']['ends_at'])}',
                      ),
                      for (final br in raw['branches'] as List)
                        Text(
                          '• ${br['name']} · ${br['active'] == true ? 'Active' : 'Archived'}',
                        ),
                      for (final dv in raw['devices'] as List)
                        Text('Device: ${dv['name']} · ${dv['status']}'),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => editBusiness(raw as Map),
                            child: Text(bt('Edit business', 'လုပ်ငန်းပြင်ရန်')),
                          ),
                          OutlinedButton(
                            onPressed: busy ? null : () => expiry(raw as Map),
                            child: Text(
                              bt('Correct expiry', 'သက်တမ်းရက်ပြင်ရန်'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(),
            Text(
              bt(
                'Payment request history · 30 per page',
                'ငွေချေတောင်းဆိုမှုမှတ်တမ်း · တစ်မျက်နှာ ၃၀',
              ),
            ),
            for (final r in data!['requests'] as List)
              Card(
                child: DesktopListTile(
                  title: Text('${r['plan']} · ${r['months']} · ${r['state']}'),
                  subtitle: SelectableText(
                    '${r['id']}\n${r['total_mmk']} MMK\n${billingTime(r['created_at'])}\n${r['note']}',
                  ),
                  onTap: r['document_id'] == null
                      ? null
                      : () => action(
                          () => billingView(
                            context,
                            r['document_id'] as String,
                            widget.owner,
                          ),
                        ),
                ),
              ),
            const Divider(),
            Text(
              bt(
                'Admin / account audit · 30 per page',
                'Admin / အကောင့်ပြင်ဆင်မှတ်တမ်း · တစ်မျက်နှာ ၃၀',
              ),
            ),
            for (final a in data!['audit'] as List)
              DesktopListTile(
                title: Text('${a['action']}'),
                subtitle: SelectableText(
                  '${billingTime(a['recorded_at'])}\n${a['details']}',
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: page > 0 && !busy
                      ? () {
                          page--;
                          load();
                        }
                      : null,
                  child: Text(bt('Previous', 'ရှေ့စာမျက်နှာ')),
                ),
                Text('${page + 1}'),
                TextButton(
                  onPressed:
                      !busy &&
                          ((data!['requests'] as List).length == 30 ||
                              (data!['audit'] as List).length == 30)
                      ? () {
                          page++;
                          load();
                        }
                      : null,
                  child: Text(bt('More history', 'မှတ်တမ်းထပ်ကြည့်ရန်')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
