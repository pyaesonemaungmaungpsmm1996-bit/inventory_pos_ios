import 'desktop_ui.dart';
import 'phone_otp_input.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'online_account_service.dart';
import 'simple_setup_service.dart';
import 'device_setup_page.dart';
import 'user_guide_page.dart';

class SimpleSetupPage extends StatefulWidget {
  const SimpleSetupPage({super.key});
  @override
  State<SimpleSetupPage> createState() => _SimpleSetupPageState();
}

class _SimpleSetupPageState extends State<SimpleSetupPage> {
  final login = TextEditingController(),
      otp = TextEditingController(),
      ownerName = TextEditingController(),
      phone = TextEditingController(),
      shop = TextEditingController(),
      township = TextEditingController(),
      city = TextEditingController(),
      region = TextEditingController();
  bool verified(User? user) =>
      user != null &&
      !user.isAnonymous &&
      (user.emailConfirmedAt != null || user.phoneConfirmedAt != null);
  final form = GlobalKey<FormState>();
  final prefs = SharedPreferencesAsync();
  bool ready = false, busy = false, usePhone = false, existing = false;
  String? sentTo, error;
  bool sentPhone = false;
  String currency = 'MMK';
  int cooldown = 0;
  Timer? timer;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final c in [
      login,
      otp,
      ownerName,
      phone,
      shop,
      township,
      city,
      region,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      await OnlineAccounts.initialize();
      await loadAccount();
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> loadAccount() async {
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null || !verified(user)) return;
    final businesses = await OnlineAccounts.snapshot();
    final draft = await prefs.getString('simple_setup_draft:${user.id}');
    if (!mounted) return;
    setState(() => existing = businesses.isNotEmpty);
    if (draft != null) {
      try {
        final v = jsonDecode(draft) as Map;
        ownerName.text = '${v['owner'] ?? ''}';
        phone.text = '${v['phone'] ?? ''}';
        shop.text = '${v['shop'] ?? ''}';
        township.text = '${v['township'] ?? ''}';
        city.text = '${v['city'] ?? ''}';
        region.text = '${v['region'] ?? ''}';
        if (AppCurrency.precision.containsKey(v['currency'])) {
          currency = v['currency'] as String;
        }
      } catch (_) {}
    }
    if (phone.text.isEmpty) phone.text = user.phone ?? '';
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AuthException
              ? (otpErrorMessage(e.code, AppLanguage.current.value == 'my') ??
                    e.message)
              : e is FormatException
              ? e.message
              : '$e',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async => run(() async {
    if (cooldown > 0) return;
    final value = usePhone ? normalizeOtpPhone(login.text) : login.text.trim();
    if (usePhone
        ? !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)
        : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      throw StateError(
        t(
          'Enter a valid email or international phone (+959…).',
          'Email မှန် သို့မဟုတ် +959… ဖုန်းနံပါတ် ထည့်ပါ။',
        ),
      );
    }
    final mode = usePhone;
    await OnlineAccounts.client.auth.signInWithOtp(
      email: mode ? null : value,
      phone: mode ? value : null,
      shouldCreateUser: true,
    );
    if (!mounted) return;
    setState(() {
      sentTo = value;
      sentPhone = mode;
      cooldown = 60;
      otp.clear();
    });
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        timer?.cancel();
        return;
      }
      setState(() => cooldown--);
      if (cooldown <= 0) timer?.cancel();
    });
  });
  Future<void> verify() async => run(() async {
    if (sentTo == null || otp.text.trim().isEmpty) {
      throw StateError(t('Enter the OTP code.', 'OTP ကုဒ်ထည့်ပါ။'));
    }
    await OnlineAccounts.client.auth.verifyOTP(
      email: sentPhone ? null : sentTo,
      phone: sentPhone ? sentTo : null,
      token: sentPhone ? normalizeSmsCode(otp.text) : otp.text.trim(),
      type: sentPhone ? OtpType.sms : OtpType.email,
    );
    otp.clear();
    await loadAccount();
  });
  Future<void> joinShop() async {
    var token = '';
    final code = await showDialog<String>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(t('Join a shop', 'ရှိပြီးသားဆိုင်သို့ ဝင်ရန်')),
        content: TextField(
          autofocus: true,
          onChanged: (v) => token = v,
          decoration: InputDecoration(
            labelText: t('Owner invitation code', 'Owner ဖိတ်ခေါ်ကုဒ်'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, token.trim()),
            child: Text(t('Join', 'ဝင်မည်')),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    await run(() async {
      await OnlineAccounts.client.rpc('tp_join', params: {'p_token': code});
      await loadAccount();
    });
  }

  Future<void> finish() async {
    if (!form.currentState!.validate()) return;
    await run(() async {
      final actor = OnlineAccounts.client.auth.currentUser?.id;
      if (actor == null) throw StateError('Sign in first');
      await prefs.setString(
        'simple_setup_draft:$actor',
        jsonEncode({
          'owner': ownerName.text.trim(),
          'phone': phone.text.trim(),
          'shop': shop.text.trim(),
          'township': township.text.trim(),
          'city': city.text.trim(),
          'region': region.text.trim(),
          'currency': currency,
        }),
      );
      final result = await SimpleSetupService.finish(
        name: shop.text.trim(),
        township: township.text.trim(),
        city: city.text.trim(),
        region: region.text.trim(),
        ownerName: ownerName.text.trim(),
        phone: phone.text.trim(),
      );
      if (!mounted) return;
      final localBranches = await AppDatabase.instance.getBranches();
      if (!mounted) return;
      if (result['device_status'] != 'approved' || localBranches.length > 1) {
        final done = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => const DeviceSetupPage(setupFlow: true),
          ),
        );
        if (done == true && mounted) Navigator.pop(context, true);
        return;
      }
      final rows = await OnlineAccounts.snapshot();
      final business = rows.firstWhere((b) => b['id'] == result['business_id']);
      final branch = (business['branches'] as List).cast<Map>().firstWhere(
        (b) => b['id'] == result['branch_id'],
      );
      await SimpleSetupService.connect(
        business: result['business_id'] as String,
        onlineBranch: result['branch_id'] as String,
        businessName: business['name'] as String,
        branchName: branch['name'] as String,
        currency: currency,
        phone: phone.text.trim(),
      );
      await prefs.remove('simple_setup_draft:$actor');
      if (mounted) Navigator.pop(context, true);
    });
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool isRequired = true,
    bool contact = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      enabled: !busy,
      maxLength: contact ? 30 : 100,
      keyboardType: contact ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (v) {
        final value = (v ?? '').trim();
        if (isRequired && value.isEmpty) {
          return t('Required', 'ဖြည့်ရန်လိုပါသည်');
        }
        if (contact && !RegExp(r'^[+0-9 ()-]{7,30}$').hasMatch(value)) {
          return t('Check contact phone', 'ဖုန်းနံပါတ် စစ်ပါ');
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final current = ready ? OnlineAccounts.client.auth.currentUser : null;
    final user = verified(current) ? current : null;
    if (ready && user != null && existing) {
      return const DeviceSetupPage(setupFlow: true);
    }
    return PopScope(
      canPop: !busy,
      child: DesktopScaffold(
        appBar: AppBar(title: Text(t('Get started', 'စတင်အသုံးပြုရန်'))),
        body: DesktopListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user == null)
              Text(
                t('Sign in to your shop', 'ဆိုင်အကောင့်ဝင်ရန်'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 12),
            if (busy || !ready) const LinearProgressIndicator(),
            if (error != null) ...[
              SelectableText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (!ready)
                TextButton(
                  onPressed: initialize,
                  child: Text(t('Retry', 'ပြန်စမ်းရန်')),
                ),
            ],
            if (ready && user == null) ...[
              Text(
                t(
                  'Verify an email or phone to protect your account.',
                  'သင့်အကောင့်အတွက် Email သို့မဟုတ် ဖုန်းကို အတည်ပြုပါ။',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Email'),
                    selected: !usePhone,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => usePhone = false),
                  ),
                  ChoiceChip(
                    label: Text(t('Phone', 'ဖုန်း')),
                    selected: usePhone,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => usePhone = true),
                  ),
                ],
              ),
              TextField(
                controller: login,
                enabled: !busy,
                keyboardType: usePhone
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: usePhone
                      ? t('Phone (09… or +959…)', 'ဖုန်း (09… သို့မဟုတ် +959…)')
                      : 'Email',
                ),
              ),
              FilledButton(
                onPressed: busy || cooldown > 0 ? null : send,
                child: Text(
                  cooldown > 0
                      ? '${t('Resend in', 'ပြန်ပို့ရန်')} ${cooldown}s'
                      : t('Send code', 'ကုဒ်ပို့မည်'),
                ),
              ),
              if (sentTo != null) ...[
                Text('${t('Code sent to', 'ကုဒ်ပို့ထားသည်')}: $sentTo'),
                TextField(
                  controller: otp,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('OTP code', 'OTP ကုဒ်'),
                  ),
                ),
                FilledButton(
                  onPressed: busy ? null : verify,
                  child: Text(t('Verify & continue', 'အတည်ပြုပြီး ဆက်မည်')),
                ),
              ],
            ],
            if (user != null && !existing)
              OutlinedButton.icon(
                onPressed: busy ? null : joinShop,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(
                  t(
                    'Join an existing shop instead',
                    'ရှိပြီးသားဆိုင်တွင် ဝန်ထမ်းအဖြစ် ဝင်မည်',
                  ),
                ),
              ),
            if (user != null && !existing)
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${t('Signed in', 'ဝင်ထားသည့်အကောင့်')}: ${user.email ?? user.phone ?? ''}',
                    ),
                    const SizedBox(height: 12),
                    field(ownerName, t('Your name', 'သင့်အမည်')),
                    field(
                      phone,
                      t('Contact phone', 'ဆက်သွယ်ရန်ဖုန်း'),
                      contact: true,
                    ),
                    field(shop, t('Shop name', 'ဆိုင်အမည်')),
                    field(township, t('Township', 'မြို့နယ်')),
                    DesktopSection(
                      title: Text(
                        t(
                          'Optional address details',
                          'လိပ်စာ ထပ်ဖြည့်ရန် (မဖြစ်မနေမဟုတ်)',
                        ),
                      ),
                      children: [
                        field(city, t('City', 'မြို့'), isRequired: false),
                        field(
                          region,
                          t('Region / State', 'တိုင်း / ပြည်နယ်'),
                          isRequired: false,
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: currency,
                      decoration: InputDecoration(
                        labelText: t('Currency', 'ငွေကြေး'),
                      ),
                      items: [
                        for (final e in AppCurrency.names.entries)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text('${e.key} · ${e.value}'),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => currency = v!),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t(
                        '14-day trial starts automatically once setup is ready. No payment is needed. Your first branch uses the shop name. Cash starts at 0 and an Owner salesperson is added; edit them later in Settings. Country/time zone default to Myanmar; review Business Settings before entering transactions.',
                        'Setup အဆင်သင့်ဖြစ်တာနဲ့ ၁၄ ရက် Trial အလိုအလျောက်စပါမည်။ ငွေပေးရန် မလိုပါ။ ပထမဆိုင်ခွဲအမည်ကို ဆိုင်အမည်အတိုင်း သုံးမည်။ Cash လက်ကျန် 0 နှင့် Owner အရောင်းဝန်ထမ်းစာရင်း ထည့်ပေးမည်။ နောက်မှ Settings တွင် ပြင်နိုင်ပါသည်။ နိုင်ငံ/အချိန်ဇုန်သည် မြန်မာဖြစ်ပြီး စာရင်းမထည့်မီ Business Settings တွင် စစ်ပါ။',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy ? null : finish,
                      child: Text(t('Start using TP POS', 'TP POS စသုံးမည်')),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => const UserGuidePage()),
                    ),
              icon: const Icon(Icons.help_outline),
              label: Text(t('User Guide', 'အသုံးပြုနည်း')),
            ),
          ],
        ),
      ),
    );
  }
}
