import 'desktop_ui.dart';

import 'dart:async';

import 'app_capabilities.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'app_currency.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'online_account_service.dart';
import 'simple_setup_service.dart';
import 'subscription_runtime.dart';

class DeviceSetupPage extends StatefulWidget {
  const DeviceSetupPage({super.key, this.setupFlow = false});
  final bool setupFlow;
  @override
  State<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends State<DeviceSetupPage> {
  Map<String, dynamic> license = {};
  bool editConnection = false;
  List<Map<String, dynamic>> businesses = [];
  List<Map<String, Object?>> local = [];
  String? business, branch, installation, error;
  int? localBranch;
  String currency = 'MMK';
  bool loading = true,
      busy = false,
      refreshing = false,
      newPos = false,
      currencyLoaded = false;
  final name = TextEditingController(text: AppCapabilities.defaultDeviceName);
  Timer? timer;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  Map<String, dynamic>? get selected =>
      businesses.where((b) => b['id'] == business).firstOrNull;
  List<Map<String, dynamic>> rows(Map<String, dynamic> b, String key) =>
      (b[key] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          !busy &&
          !loading &&
          (WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed ||
              WidgetsBinding.instance.lifecycleState == null)) {
        load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    name.dispose();
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (refreshing) return;
    refreshing = true;
    if (!silent) setState(() => loading = true);
    try {
      await OnlineAccounts.initialize();
      final all = (await OnlineAccounts.snapshot())
          .where((b) => b['active'] == true)
          .toList();
      final locals = await AppDatabase.instance.getBranches();
      final profile = await AppDatabase.instance.getBusinessProfile();
      final id = await OnlineAccounts.installation();
      final user = OnlineAccounts.client.auth.currentUser?.id;
      final draft = await SharedPreferencesAsync().getString(
        'simple_setup_draft:$user',
      );
      if (!currencyLoaded && draft != null) {
        try {
          final stored = jsonDecode(draft) as Map;
          currency = '${stored['currency'] ?? 'MMK'}';
        } catch (_) {}
      }
      if (!mounted) return;
      if (!currencyLoaded) {
        if (draft == null) currency = profile['currency_code'] as String;
        currencyLoaded = true;
      }
      final savedLicense = await SubscriptionRuntime.read();
      final boundShop = savedLicense['bound'] == true
          ? savedLicense['business_id']
          : null;
      final chosen = all.any((b) => b['id'] == business)
          ? business
          : all.any((b) => b['id'] == boundShop)
          ? boundShop as String
          : all.firstOrNull?['id'] as String?;
      final b = all.where((r) => r['id'] == chosen).firstOrNull;
      final available = b == null
          ? <Map<String, dynamic>>[]
          : rows(b, 'branches').where((r) => r['active'] != false).toList();
      String? retained;
      if (b != null && b['role'] == 'owner' && branch == null) {
        final home = await OnlineAccounts.client.rpc(
          'tp_billing_home',
          params: {'p_business': b['id']},
        );
        final policy = (home as Map)['policy'] as Map?;
        if (policy?['plan'] == 'standard') {
          retained = policy?['current_branch'] as String?;
        }
      }
      if (!mounted) return;
      var br = available.any((r) => r['id'] == branch)
          ? branch
          : available.any((r) => r['id'] == retained)
          ? retained
          : available.firstOrNull?['id'] as String?;
      // Reuse this installation's registration before choosing a new branch.
      final registered = b == null
          ? null
          : rows(
              b,
              'devices',
            ).where((r) => r['installation_id'] == id).firstOrNull;
      if (registered != null &&
          available.any((r) => r['id'] == registered['branch_id'])) {
        br = registered['branch_id'] as String;
        if (name.text == AppCapabilities.defaultDeviceName) {
          name.text = '${registered['name']}';
        }
      }
      if (!locals.any((r) => r['id'] == localBranch)) {
        final saved = savedLicense['business_id'] == chosen
            ? savedLicense['local_branch']
            : null;
        localBranch = locals.any((r) => r['id'] == saved)
            ? saved as int
            : locals.length == 1
            ? locals.single['id'] as int
            : null;
      }
      setState(() {
        license = savedLicense;
        businesses = all;
        business = chosen;
        branch = br;
        local = locals;
        installation = id;
        newPos = profile['configured'] != 1;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> request() async => run(() async {
    if (business == null || branch == null) {
      throw StateError(
        t('Choose shop and branch', 'ဆိုင်နှင့် ဆိုင်ခွဲရွေးပါ'),
      );
    }
    await OnlineAccounts.client.rpc(
      'tp_prepare_device_setup',
      params: {
        'p_business': business,
        'p_branch': branch,
        'p_installation': installation,
        'p_name': name.text.trim(),
      },
    );
    if (mounted) await load();
  });
  Future<void> connect() async => run(() async {
    final b = selected;
    if (b == null || branch == null) return;
    final br = rows(b, 'branches').firstWhere((r) => r['id'] == branch);
    await OnlineAccounts.client.rpc(
      'tp_prepare_device_setup',
      params: {
        'p_business': business,
        'p_branch': branch,
        'p_installation': installation,
        'p_name': name.text.trim(),
      },
    );
    await SimpleSetupService.connect(
      business: business!,
      onlineBranch: branch!,
      businessName: b['name'] as String,
      branchName: br['name'] as String,
      localBranch: localBranch,
      currency: currency,
    );
    if (mounted) Navigator.pop(context, true);
  });
  Future<void> approve(
    Map<String, dynamic> d, {
    bool allow = true,
  }) async => run(() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(
          allow
              ? t('Allow this device?', 'ဒီစက်ကို ခွင့်ပြုမလား?')
              : t('Revoke device access?', 'စက်ခွင့်ပြုချက် ပိတ်မလား?'),
        ),
        content: Text(
          '${d['name']}\n${t('Only allow a device you recognise.', 'သင်သိသော စက်ကိုသာ ခွင့်ပြုပါ။')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              allow ? t('Allow', 'ခွင့်ပြုမည်') : t('Revoke', 'ပိတ်မည်'),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await OnlineAccounts.client.rpc(
      'tp_decide_device',
      params: {'p_device': d['id'], 'p_approve': allow},
    );
    if (mounted) await load();
  });
  @override
  Widget build(BuildContext context) {
    final b = selected;
    final device = b == null
        ? null
        : rows(
            b,
            'devices',
          ).where((d) => d['installation_id'] == installation).firstOrNull;
    final connected =
        b != null &&
        device?['status'] == 'approved' &&
        license['bound'] == true &&
        license['paused'] != true &&
        license['business_id'] == business &&
        license['device_branch'] == branch &&
        license['installation_id'] == installation &&
        license['actor_id'] == OnlineAccounts.client.auth.currentUser?.id &&
        b['active'] == true &&
        rows(
          b,
          'branches',
        ).any((r) => r['id'] == branch && r['active'] != false) &&
        (!newPos) &&
        local.any((r) => r['id'] == license['local_branch']);
    final owners = businesses.any((shop) => shop['role'] == 'owner');
    final pending = [
      for (final shop in businesses.where((r) => r['role'] == 'owner'))
        for (final d in rows(
          shop,
          'devices',
        ).where((d) => d['status'] == 'pending'))
          {'shop': shop, ...d},
    ];
    return PopScope(
      canPop: !busy,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(
            t('Devices & approval', 'စက်ချိတ်ဆက်ခြင်းနှင့် ခွင့်ပြုခြင်း'),
          ),
          actions: [
            IconButton(
              onPressed: busy || loading ? null : () => load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: DesktopListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading || busy) const LinearProgressIndicator(),
            if (error != null)
              SelectableText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (businesses.isEmpty && !loading)
              Text(
                t(
                  'No active shop. Sign in or join with an Owner invitation from Online Accounts.',
                  'အသုံးပြုနိုင်သောဆိုင် မရှိပါ။ Online Accounts တွင် အကောင့်ဝင်ပါ သို့မဟုတ် Owner ဖိတ်ခေါ်ကုဒ်ဖြင့် ဝင်ပါ။',
                ),
              ),
            if (b != null)
              Card(
                child: DesktopListTile(
                  leading: Icon(
                    connected
                        ? Icons.check_circle_outline
                        : Icons.devices_outlined,
                  ),
                  title: Text('${b['name']}'),
                  subtitle: Text(
                    '${rows(b, 'branches').where((r) => r['id'] == branch).firstOrNull?['name'] ?? ''} · ${name.text}',
                  ),
                  trailing: connected
                      ? Chip(label: Text(t('Connected', 'ချိတ်ပြီး')))
                      : null,
                ),
              ),
            if (connected) ...[
              const SizedBox(height: 12),
              if (widget.setupFlow)
                FilledButton(
                  onPressed: busy || loading
                      ? null
                      : () => Navigator.pop(context, true),
                  child: Text(t('Continue to POS', 'POS သို့ ဆက်မည်')),
                ),
              TextButton(
                onPressed: busy || loading
                    ? null
                    : () => setState(() => editConnection = !editConnection),
                child: Text(
                  editConnection
                      ? t(
                          'Hide connection settings',
                          'ချိတ်ဆက်မှုဆက်တင် ပိတ်မည်',
                        )
                      : t('Connection settings', 'ချိတ်ဆက်မှုဆက်တင်'),
                ),
              ),
            ],
            if (b != null && (!connected || editConnection)) ...[
              if (businesses.length > 1)
                DropdownButtonFormField<String>(
                  key: ValueKey(business),
                  initialValue: business,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('Shop', 'ဆိုင်')),
                  items: [
                    for (final shop in businesses)
                      DropdownMenuItem(
                        value: shop['id'] as String,
                        child: Text('${shop['name']}'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() {
                            business = v;
                            branch = null;
                          });
                          load();
                        },
                ),
              const SizedBox(height: 12),
              if (rows(
                    b,
                    'branches',
                  ).where((r) => r['active'] != false).length >
                  1)
                DropdownButtonFormField<String>(
                  key: ValueKey('$business:$branch'),
                  initialValue: branch,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Branch', 'ဆိုင်ခွဲ'),
                  ),
                  items: [
                    for (final br in rows(
                      b,
                      'branches',
                    ).where((r) => r['active'] != false))
                      DropdownMenuItem(
                        value: br['id'] as String,
                        child: Text('${br['name']}'),
                      ),
                  ],
                  onChanged: busy || device != null
                      ? null
                      : (v) => setState(() => branch = v),
                ),
              if (local.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: localBranch,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t(
                      'Local POS branch to connect',
                      'ဒီ POS ထဲမှ ချိတ်မည့်ဆိုင်ခွဲ',
                    ),
                  ),
                  items: [
                    for (final br in local)
                      DropdownMenuItem(
                        value: br['id'] as int,
                        child: Text('${br['code']} · ${br['name']}'),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => localBranch = v),
                ),
              ],
              if (newPos) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: t(
                      'Currency · confirm before first use',
                      'ငွေကြေး · စမသုံးမီ စစ်ပါ',
                    ),
                  ),
                  items: [
                    for (final e in AppCurrency.names.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.key} · ${e.value}'),
                      ),
                  ],
                  onChanged: busy ? null : (v) => setState(() => currency = v!),
                ),
              ],
              if (device == null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  enabled: !busy,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: t('Device name', 'စက်အမည်'),
                    counterText: '',
                  ),
                ),
              ],
              if (device == null)
                FilledButton(
                  onPressed: busy || loading ? null : request,
                  child: Text(
                    t('Connect / request access', 'ချိတ်ဆက် / ခွင့်တောင်းမည်'),
                  ),
                ),
              if (device?['status'] == 'pending')
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      t(
                        'Waiting for Owner approval. Owner opens Account → Devices & approval → Allow. This page checks again automatically.',
                        'Owner ခွင့်ပြုချက် စောင့်နေပါသည်။ Owner က Account → စက်ချိတ်ဆက်ခြင်းနှင့် ခွင့်ပြုခြင်း → ခွင့်ပြုမည် ကိုနှိပ်ပါ။ ဤစာမျက်နှာက အလိုအလျောက် ပြန်စစ်ပါမည်။',
                      ),
                    ),
                  ),
                ),
              if (device?['status'] == 'approved')
                FilledButton.icon(
                  onPressed: busy || loading ? null : connect,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    connected
                        ? t('Save connection', 'ချိတ်ဆက်မှု သိမ်းမည်')
                        : t('Start using this POS', 'ဒီ POS စသုံးမည်'),
                  ),
                ),
              if (device?['status'] == 'revoked')
                Text(
                  t(
                    'Access revoked. Ask the Owner to review this device in Online Accounts.',
                    'ခွင့်ပြုချက် ပိတ်ထားပါသည်။ Owner က Online Accounts တွင် ဒီစက်ကို ပြန်စစ်ပေးရန်လိုပါသည်။',
                  ),
                ),
            ],
            if (owners) ...[
              const SizedBox(height: 20),
              Text(
                t('Device requests', 'စက်ခွင့်တောင်းမှုများ'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (pending.isEmpty)
                Text(
                  t(
                    'No pending requests',
                    'စောင့်ဆိုင်းနေသော ခွင့်တောင်းမှု မရှိပါ',
                  ),
                ),
            ],
            for (final d in pending)
              Card(
                child: DesktopListTile(
                  title: Text('${d['name']}'),
                  subtitle: Text(
                    '${(d['shop'] as Map)['name']} · ${rows(d['shop'] as Map<String, dynamic>, 'branches').where((br) => br['id'] == d['branch_id']).firstOrNull?['name'] ?? ''}\n${rows(d['shop'] as Map<String, dynamic>, 'members').where((m) => m['user_id'] == d['user_id']).firstOrNull?['contact'] ?? ''}\n${AppDateTime.format(d['requested_at'])}',
                  ),
                  trailing: TextButton(
                    onPressed: busy ? null : () => approve(d),
                    child: Text(t('Allow', 'ခွင့်ပြုမည်')),
                  ),
                ),
              ),
            if (b != null && b['role'] == 'owner')
              DesktopSection(
                title: Text(t('Manage devices', 'စက်များ စီမံရန်')),
                children: [
                  for (final d in rows(
                    b,
                    'devices',
                  ).where((d) => d['status'] != 'pending'))
                    DesktopListTile(
                      title: Text('${d['name']}'),
                      subtitle: Text(
                        '${d['status']} · ${rows(b, 'branches').where((br) => br['id'] == d['branch_id']).firstOrNull?['name'] ?? ''}',
                      ),
                      trailing: TextButton(
                        onPressed: busy || loading
                            ? null
                            : () =>
                                  approve(d, allow: d['status'] != 'approved'),
                        child: Text(
                          d['status'] == 'approved'
                              ? t('Revoke', 'ပိတ်မည်')
                              : t('Allow', 'ခွင့်ပြုမည်'),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
