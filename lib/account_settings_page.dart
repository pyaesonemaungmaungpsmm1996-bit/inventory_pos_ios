import 'desktop_ui.dart';
import 'business_logo_page.dart';
import 'business_logo_avatar.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'online_account_service.dart';
import 'online_accounts_page.dart';
import 'simple_setup_page.dart';
import 'device_setup_page.dart';
import 'subscription_billing_page.dart';
import 'subscription_runtime.dart';
import 'business_profile_page.dart';
import 'business_location_page.dart';
import 'branches_page.dart';
import 'auto_backup_scheduler.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

/// Local identity loads without waiting for an online policy request.
class AccountEntryCard extends StatefulWidget {
  const AccountEntryCard({super.key});
  @override
  State<AccountEntryCard> createState() => _AccountEntryCardState();
}

class _AccountEntryCardState extends State<AccountEntryCard> {
  String name = 'TP POS';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await AppDatabase.instance.getBusinessProfile();
      final value = '${p['name'] ?? ''}'.trim();
      if (mounted) setState(() => name = value.isEmpty ? 'TP POS' : value);
    } catch (_) {
      /* Keep a neutral app identity. */
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Card(
      child: DesktopListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const BusinessLogoAvatar(),
        title: Text(name, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(_t('My Account', 'ကျွန်ုပ်အကောင့်')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
          );
          if (mounted) await load();
        },
      ),
    ),
  );
}

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});
  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool busy = true, configured = false;
  String name = 'TP POS';
  User? user;
  String? error;
  Map<String, dynamic> license = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => busy = true);
    try {
      final profile = await AppDatabase.instance.getBusinessProfile();
      if (!mounted) return;
      setState(() {
        final value = '${profile['name'] ?? ''}'.trim();
        name = value.isEmpty ? 'TP POS' : value;
        configured = profile['configured'] == 1;
      });
      await OnlineAccounts.initialize();
      final current = OnlineAccounts.client.auth.currentUser;
      final saved = await SubscriptionRuntime.read();
      if (mounted) {
        setState(() {
          user = current?.isAnonymous == true ? null : current;
          license = saved;
          busy = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = _t(
            'Could not load account. Tap to retry.',
            'အကောင့်မဖွင့်နိုင်သေးပါ။ ပြန်စမ်းပါ။',
          );
        });
      }
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await load();
  }

  Widget row(
    String en,
    String my,
    IconData icon,
    Widget page, {
    String? subtitle,
  }) => DesktopListTile(
    leading: Icon(icon),
    title: Text(_t(en, my)),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: busy ? null : () => open(page),
  );
  @override
  Widget build(BuildContext context) {
    final mine =
        user != null &&
        (license['actor_id'] == user!.id || license['owner_id'] == user!.id);
    final policy = mine
        ? SubscriptionRuntime.effective(license, DateTime.now())
        : <String, dynamic>{};
    final plan = '${policy['plan'] ?? ''}';
    final known = ['trial', 'standard', 'premium'].contains(plan);
    final end = DateTime.tryParse('${policy['ends_at']}');
    final active =
        end != null &&
        SubscriptionRuntime.effectiveNow(
          license,
          DateTime.now(),
        ).isBefore(end) &&
        policy['provider_blocked'] != true &&
        policy['actor_provider_blocked'] != true;
    return DesktopScaffold(
      appBar: AppBar(title: Text(_t('My Account', 'ကျွန်ုပ်အကောင့်'))),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          DesktopListTile(
            contentPadding: EdgeInsets.zero,
            leading: const BusinessLogoAvatar(size: 48),
            title: Text(name, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            DesktopListTile(
              title: Text(error!),
              trailing: const Icon(Icons.refresh),
              onTap: load,
            ),
          if (!busy && error == null && user == null)
            FilledButton.icon(
              onPressed: () => open(const SimpleSetupPage()),
              icon: const Icon(Icons.login),
              label: Text(
                _t('Login / Create Account', 'အကောင့်ဝင်ရန် / အသစ်ဖွင့်ရန်'),
              ),
            ),
          if (!busy && user != null && !configured)
            OutlinedButton.icon(
              onPressed: () => open(const SimpleSetupPage()),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: Text(_t('Continue setup', 'Setup ဆက်လုပ်ရန်')),
            ),
          if (user != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t('Account Information', 'အကောင့်အချက်အလက်'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => open(const ChangeContactPage()),
                          child: Text(_t('Edit', 'ပြင်ရန်')),
                        ),
                      ],
                    ),
                    if (user?.email?.isNotEmpty == true)
                      DesktopListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.mail_outline),
                        title: const Text('Email'),
                        subtitle: Text(user!.email!),
                      ),
                    if (user?.phone?.isNotEmpty == true)
                      DesktopListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(_t('Phone', 'ဖုန်း')),
                        subtitle: Text(user!.phone!),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                row(
                  'Business Info',
                  'လုပ်ငန်းအချက်အလက်',
                  Icons.business_outlined,
                  const BusinessInfoPage(),
                ),
                const Divider(height: 1),
                row(
                  'Plan & Subscription',
                  'Plan နှင့် သက်တမ်း',
                  Icons.workspace_premium_outlined,
                  const SubscriptionBillingPage(),
                  subtitle: known
                      ? '${plan[0].toUpperCase()}${plan.substring(1)} · ${active ? _t('Active', 'သက်တမ်းရှိ') : _t('Expired / paused', 'သက်တမ်းကုန် / ခေတ္တပိတ်')}'
                      : null,
                ),
                if (user != null) ...[
                  const Divider(height: 1),
                  row(
                    'Devices & Approval',
                    'စက်ချိတ်ဆက်ခြင်းနှင့် ခွင့်ပြုခြင်း',
                    Icons.devices_outlined,
                    const DeviceSetupPage(),
                  ),
                  const Divider(height: 1),
                  row(
                    'Members & Roles',
                    'အဖွဲ့ဝင်နှင့် ခွင့်ပြုချက်များ',
                    Icons.group_outlined,
                    DesktopScaffold(
                      appBar: AppBar(
                        title: Text(
                          _t(
                            'Members & Roles',
                            'အဖွဲ့ဝင်နှင့် ခွင့်ပြုချက်များ',
                          ),
                        ),
                      ),
                      body: const OnlineAccountsPage(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      await logoutFromAccount(context);
                      if (mounted) await load();
                    },
              icon: const Icon(Icons.logout),
              label: Text(_t('Log out', 'အကောင့်ထွက်မည်')),
            ),
          ],
        ],
      ),
    );
  }
}

class BusinessInfoPage extends StatelessWidget {
  const BusinessInfoPage({super.key});
  @override
  Widget build(BuildContext context) {
    Widget tile(
      String en,
      String my,
      IconData icon,
      Widget page, {
      bool wrap = true,
    }) => DesktopListTile(
      leading: Icon(icon),
      title: Text(_t(en, my)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => wrap
              ? DesktopScaffold(
                  appBar: AppBar(title: Text(_t(en, my))),
                  body: page,
                )
              : page,
        ),
      ),
    );
    return DesktopScaffold(
      appBar: AppBar(title: Text(_t('Business Info', 'လုပ်ငန်းအချက်အလက်'))),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                tile(
                  'Business Logo / Photo',
                  'လုပ်ငန်း Logo / ပုံ',
                  Icons.add_photo_alternate_outlined,
                  const BusinessLogoPage(),
                  wrap: false,
                ),
                tile(
                  'Business profile',
                  'လုပ်ငန်းအချက်အလက်',
                  Icons.business_outlined,
                  const BusinessProfilePage(),
                ),
                const Divider(height: 1),
                tile(
                  'Township / city',
                  'မြို့နယ် / မြို့',
                  Icons.location_on_outlined,
                  const BusinessLocationPage(),
                  wrap: false,
                ),
                const Divider(height: 1),
                tile(
                  'Branches, phone & address',
                  'ဆိုင်ခွဲ၊ ဖုန်းနှင့် လိပ်စာ',
                  Icons.store_outlined,
                  const BranchesPage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChangeContactPage extends StatefulWidget {
  const ChangeContactPage({super.key});
  @override
  State<ChangeContactPage> createState() => _ChangeContactPageState();
}

class _ChangeContactPageState extends State<ChangeContactPage> {
  final contact = TextEditingController(), otp = TextEditingController();
  bool phone = false, busy = false;
  String? target, error, info;
  DateTime? sent;
  @override
  void dispose() {
    contact.dispose();
    otp.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (sent != null && DateTime.now().difference(sent!).inSeconds < 60) {
      setState(
        () => error = _t(
          'Wait 60 seconds before requesting another code.',
          'နောက် OTP တောင်းရန် စက္ကန့် ၆၀ စောင့်ပါ။',
        ),
      );
      return;
    }
    final value = contact.text.trim();
    if (phone
        ? !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)
        : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      setState(
        () => error = _t(
          'Enter a valid email or +959… phone number.',
          'Email သို့မဟုတ် +959… ဖုန်းနံပါတ် မှန်ကန်စွာထည့်ပါ။',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await OnlineAccounts.client.auth.updateUser(
        phone ? UserAttributes(phone: value) : UserAttributes(email: value),
      );
      if (mounted) {
        setState(() {
          target = value;
          sent = DateTime.now();
          info = _t(
            'Enter the OTP sent to your new contact. Secure email change may require codes from BOTH old and new email inboxes; confirm each code here.',
            'အချက်အလက်အသစ်သို့ ပို့ထားသော OTP ထည့်ပါ။ Secure Email Change ဖွင့်ထားလျှင် Email အဟောင်းနှင့် အသစ်နှစ်ခုလုံးမှ OTP ကို တစ်ခုစီ အတည်ပြုပါ။',
          );
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (target == null || otp.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final expected = target!;
      await OnlineAccounts.client.auth.verifyOTP(
        email: phone ? null : expected,
        phone: phone ? expected : null,
        token: otp.text.trim(),
        type: phone ? OtpType.phoneChange : OtpType.emailChange,
      );
      final result = await OnlineAccounts.client.auth.getUser();
      final actual = phone ? result.user?.phone : result.user?.email;
      final done = actual?.toLowerCase() == expected.toLowerCase();
      if (mounted) {
        setState(() {
          otp.clear();
          info = done
              ? _t(
                  'Contact updated and verified.',
                  'အချက်အလက်ပြောင်းလဲပြီး အတည်ပြုပြီးပါပြီ။',
                )
              : _t(
                  'First confirmation received. Enter the code from the other email inbox.',
                  'ပထမအတည်ပြုချက် ရရှိပါပြီ။ ကျန် Email မှ OTP ကို ဆက်ထည့်ပါ။',
                );
          if (done) target = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(_t('Change email / phone', 'Email / ဖုန်းပြောင်းရန်')),
    ),
    body: DesktopListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _t(
            'This updates your existing login account. Your business and subscription stay linked to the same user ID.',
            'လက်ရှိ Login အကောင့်ကို ပြင်ဆင်ခြင်းဖြစ်ပြီး လုပ်ငန်းနှင့် သက်တမ်းမှာ မူရင်း User ID နှင့် ဆက်ရှိပါမည်။',
          ),
        ),
        SwitchListTile(
          title: Text(_t('Change phone number', 'ဖုန်းနံပါတ်ပြောင်းမည်')),
          value: phone,
          onChanged: busy || target != null
              ? null
              : (v) => setState(() {
                  phone = v;
                  contact.clear();
                }),
        ),
        TextField(
          controller: contact,
          enabled: !busy && target == null,
          keyboardType: phone
              ? TextInputType.phone
              : TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: phone ? '+959…' : _t('New email', 'Email အသစ်'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(_t('Send confirmation OTP', 'အတည်ပြု OTP ပို့မည်')),
        ),
        if (target != null) ...[
          TextField(
            controller: otp,
            enabled: !busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'OTP'),
          ),
          FilledButton(
            onPressed: busy ? null : verify,
            child: Text(_t('Confirm OTP', 'OTP အတည်ပြုမည်')),
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (info != null) Text(info!),
        const SizedBox(height: 16),
        Text(
          _t(
            'Phone OTP requires an enabled SMS provider. Email Change must use an OTP email template.',
            'Phone OTP အတွက် SMS Provider ဖွင့်ထားရန်နှင့် Email Change အတွက် OTP ပါသော Email Template လိုအပ်ပါသည်။',
          ),
        ),
      ],
    ),
  );
}

Future<void> logoutFromAccount(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => DesktopDialog(
      title: Text(_t('Log out?', 'အကောင့်ထွက်မလား?')),
      content: Text(
        _t(
          'Local records remain. Auto Cloud Backup pauses.',
          'ဒေတာများ ဆက်ရှိပြီး Auto Cloud Backup ခေတ္တရပ်ပါမည်။',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(_t('Cancel', 'မလုပ်တော့')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(_t('Log out', 'အကောင့်ထွက်မည်')),
        ),
      ],
    ),
  );
  if (yes != true) return;
  try {
    await OnlineAccounts.initialize();
    await AutoBackupScheduler.disable(
      'Paused after sign out. Enable again as Owner.',
    );
    await OnlineAccounts.client.auth.signOut(scope: SignOutScope.local);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Signed out.', 'အကောင့်ထွက်ပြီးပါပြီ။'))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
