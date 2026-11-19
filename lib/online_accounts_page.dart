import 'desktop_ui.dart';
import 'simple_setup_page.dart';
import 'billing_forms.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'online_account_service.dart';
import 'online_permissions_page.dart';

/// Online account-management pilot. Deliberately separate from legacy POS data.
class OnlineAccountsPage extends StatefulWidget {
  const OnlineAccountsPage({super.key});
  @override
  State<OnlineAccountsPage> createState() => _OnlineAccountsPageState();
}

class _OnlineAccountsPageState extends State<OnlineAccountsPage> {
  final contact = TextEditingController();
  final code = TextEditingController();
  List<Map<String, dynamic>> businesses = [];
  StreamSubscription<AuthState>? auth;
  Timer? cooldownTimer;
  String? error, selected, otpContact;
  bool ready = false, busy = false, phone = false, otpPhone = false;
  int cooldown = 0;
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
    cooldownTimer?.cancel();
    contact.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      await OnlineAccounts.initialize();
      if (!mounted) {
        return;
      }
      auth = OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        refresh();
      });
      setState(() => ready = true);
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> refresh() async {
    final request = ++generation;
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          businesses = [];
          selected = null;
        });
      }
      return;
    }
    try {
      final rows = await OnlineAccounts.snapshot();
      for (final business in rows.where((b) => b['role'] == 'owner')) {
        business['invitations'] = await OnlineAccounts.client.rpc(
          'tp_pending_invitations',
          params: {'p_business': business['id']},
        );
      }
      if (!mounted || request != generation) {
        return;
      }
      setState(() {
        businesses = rows;
        error = null;
        if (!rows.any((r) => r['id'] == selected)) {
          selected = rows.isEmpty ? null : rows.first['id'] as String;
        }
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() => error = '$e');
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> sendOtp() => run(() async {
    if (cooldown > 0) {
      return;
    }
    final value = contact.text.trim();
    if (phone
        ? !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(value)
        : !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      throw const FormatException(
        'Enter an email or an international phone number such as +959…',
      );
    }
    final usePhone = phone;
    await OnlineAccounts.client.auth.signInWithOtp(
      email: usePhone ? null : value,
      phone: usePhone ? value : null,
      shouldCreateUser: true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      otpContact = value;
      otpPhone = usePhone;
      cooldown = 60;
      code.clear();
    });
    cooldownTimer?.cancel();
    cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        cooldown--;
        if (cooldown <= 0) {
          timer.cancel();
        }
      });
    });
  });
  Future<void> verify() => run(() async {
    final target = otpContact;
    if (target == null || code.text.trim().isEmpty) {
      throw StateError('Request and enter an OTP first');
    }
    await OnlineAccounts.client.auth.verifyOTP(
      email: otpPhone ? null : target,
      phone: otpPhone ? target : null,
      token: code.text.trim(),
      type: otpPhone ? OtpType.sms : OtpType.email,
    );
    code.clear();
    await refresh();
  });
  Future<String?> ask(String title, String label, {String initial = ''}) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => value = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (value.trim().isNotEmpty) {
                Navigator.pop(ctx, value.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> createBusiness() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SimpleSetupPage()),
    );
    if (mounted) await refresh();
  }

  Future<void> join() async {
    final token = await ask('Join an invited business', 'Invitation code');
    if (token == null || !mounted) {
      return;
    }
    await run(() async {
      await OnlineAccounts.client.rpc('tp_join', params: {'p_token': token});
      await refresh();
    });
  }

  List<Map<String, dynamic>> rows(Map<String, dynamic> b, String key) =>
      (b[key] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  Future<Map<String, String>?> chooseAssignment(
    Map<String, dynamic> b, {
    Map<String, dynamic>? member,
  }) async {
    final branches = rows(
      b,
      'branches',
    ).where((r) => r['active'] != false).toList();
    if (branches.isEmpty) {
      return null;
    }
    var branch = (member?['branch_id'] ?? branches.first['id']) as String;
    if (!branches.any((r) => r['id'] == branch)) {
      branch = branches.first['id'] as String;
    }
    var role = member?['role'] as String? ?? 'cashier';
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => DesktopDialog(
          title: const Text('Role & branch'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                isExpanded: true,
                value: role,
                items: OnlineAccounts.roles
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    update(() => role = v);
                  }
                },
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: branch,
                items: branches
                    .map(
                      (r) => DropdownMenuItem(
                        value: r['id'] as String,
                        child: Text(r['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    update(() => branch = v);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, {'role': role, 'branch': branch}),
              child: const Text('Choose'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> invite(Map<String, dynamic> b) async {
    final value = await ask('Invite staff', 'Their login email or +phone');
    if (value == null || !mounted) {
      return;
    }
    final assignment = await chooseAssignment(b);
    if (assignment == null || !mounted) {
      return;
    }
    await run(() async {
      final token = await OnlineAccounts.client.rpc(
        'tp_invite',
        params: {
          'p_business': b['id'],
          'p_branch': assignment['branch'],
          'p_contact': value,
          'p_role': assignment['role'],
        },
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => DesktopDialog(
          title: const Text('Invitation code · 7 days'),
          content: SelectableText(
            '$token\n\nGive this to the invited person. They must sign in with the invited email or phone.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '$token'));
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await refresh();
    });
  }

  Future<void> editMember(
    Map<String, dynamic> b,
    Map<String, dynamic> member, {
    bool? active,
  }) async {
    final assignment = active == null
        ? await chooseAssignment(b, member: member)
        : {
            'role': member['role'] as String,
            'branch': member['branch_id'] as String,
          };
    if (assignment == null || !mounted) {
      return;
    }
    await run(() async {
      await OnlineAccounts.client.rpc(
        'tp_member_update',
        params: {
          'p_business': b['id'],
          'p_user': member['user_id'],
          'p_role': assignment['role'],
          'p_branch': assignment['branch'],
          'p_active': active ?? member['active'],
        },
      );
      await refresh();
    });
  }

  String branchName(Map<String, dynamic> b, Object? id) {
    if (id == null) {
      return 'All branches';
    }
    final found = rows(b, 'branches').where((r) => r['id'] == id);
    return found.isEmpty
        ? 'Earlier branch'
        : '${found.first['name']}${found.first['active'] == false ? ' (archived)' : ''}';
  }

  Future<void> addBranch(Map<String, dynamic> b) async {
    final name = await ask('New online branch', 'Branch name');
    if (name == null || !mounted) {
      return;
    }
    await run(() async {
      await OnlineAccounts.client.rpc(
        'tp_branch_create',
        params: {'p_business': b['id'], 'p_name': name},
      );
      await refresh();
    });
  }

  Future<void> updateBranch(Map<String, dynamic> br, {bool? active}) async {
    String? name = br['name'] as String;
    if (active == null) {
      name = await ask('Rename online branch', 'Branch name', initial: name);
      if (name == null || !mounted) {
        return;
      }
    } else {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => DesktopDialog(
          title: Text(active ? 'Restore branch?' : 'Archive branch?'),
          content: Text(
            active
                ? '${br['name']} will become available again. Previous invitations and devices remain revoked.'
                : '${br['name']} will stop accepting invitations and device approvals. Move or suspend its active staff first. Device registrations will be revoked.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (answer != true || !mounted) {
        return;
      }
    }
    await run(() async {
      await OnlineAccounts.client.rpc(
        'tp_branch_update',
        params: {
          'p_branch': br['id'],
          'p_name': name,
          'p_active': active ?? br['active'],
        },
      );
      await refresh();
    });
  }

  Future<void> cancelInvitation(Map<String, dynamic> invitation) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: const Text('Cancel invitation?'),
        content: Text('${invitation['contact']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel invitation'),
          ),
        ],
      ),
    );
    if (answer != true || !mounted) {
      return;
    }
    await run(() async {
      await OnlineAccounts.client.rpc(
        'tp_cancel_invitation',
        params: {'p_invitation': invitation['id']},
      );
      await refresh();
    });
  }

  Future<void> configurePermissions(Map<String, dynamic> b) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OnlinePermissionsPage(
          businessId: b['id'] as String,
          businessName: b['name'] as String,
        ),
      ),
    );
    if (mounted) {
      await refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ready ? OnlineAccounts.client.auth.currentUser : null;
    final matches = businesses.where((r) => r['id'] == selected);
    final b = matches.isEmpty ? null : matches.first;
    final owner = b?['role'] == 'owner';
    return DesktopListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          bt('Members & roles', 'အဖွဲ့ဝင်နှင့် ခွင့်ပြုချက်များ'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (busy || !ready) const LinearProgressIndicator(),
        if (error != null)
          SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!ready)
          TextButton(
            onPressed: initialize,
            child: const Text('Retry connection'),
          ),
        if (ready && user == null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Email / Gmail OTP'),
                selected: !phone,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        phone = false;
                        otpContact = null;
                        code.clear();
                      }),
              ),
              ChoiceChip(
                label: const Text('Phone SMS OTP'),
                selected: phone,
                onSelected: busy
                    ? null
                    : (_) => setState(() {
                        phone = true;
                        otpContact = null;
                        code.clear();
                      }),
              ),
            ],
          ),
          TextField(
            controller: contact,
            enabled: !busy,
            keyboardType: phone
                ? TextInputType.phone
                : TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: phone ? 'Phone (+959…)' : 'Email address',
            ),
          ),
          Text(
            phone ? 'SMS provider must be configured in Supabase first.' : 'Enter the code sent to your email. Email OTP template must be configured first.',
          ),
          FilledButton(
            onPressed: busy || cooldown > 0 ? null : sendOtp,
            child: Text(
              cooldown > 0 ? 'Resend in ${cooldown}s' : 'Send OTP / Register',
            ),
          ),
          if (otpContact != null) ...[
            Text('Code sent to $otpContact'),
            TextField(
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'OTP code'),
            ),
            FilledButton(
              onPressed: busy ? null : verify,
              child: const Text('Verify & sign in'),
            ),
          ],
        ],
        if (user != null) ...[
          Wrap(
            spacing: 8,
            children: [
              if (businesses.isEmpty)
                OutlinedButton(
                  onPressed: busy ? null : createBusiness,
                  child: Text(bt('Set up a shop', 'ဆိုင်ဖွင့်ရန်')),
                ),
              OutlinedButton(
                onPressed: busy ? null : join,
                child: Text(
                  bt('Join with invitation', 'ဖိတ်ခေါ်ကုဒ်ဖြင့် ဝင်ရန်'),
                ),
              ),
              TextButton(
                onPressed: busy ? null : refresh,
                child: Text(bt('Refresh', 'ပြန်စစ်မည်')),
              ),
            ],
          ),
          if (businesses.length > 1)
            DropdownButton<String>(
              isExpanded: true,
              value: selected,
              items: businesses
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['id'] as String,
                      child: Text(r['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => selected = v),
            ),
        ],
        if (b != null) ...[
          Card(
            child: DesktopListTile(
              leading: const Icon(Icons.store_outlined),
              title: Text('${b['name']}'),
              subtitle: Text(
                '${b['role']} · ${b['active'] == true ? bt('Active', 'အသုံးပြုနိုင်') : bt('Suspended', 'ခေတ္တပိတ်')}',
              ),
            ),
          ),
          if (owner)
            FilledButton.icon(
              onPressed: busy ? null : () => invite(b),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(bt('Invite staff', 'ဝန်ထမ်းဖိတ်ခေါ်ရန်')),
            ),
          const SizedBox(height: 12),
          ...rows(b, 'members').map(
            (m) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m['contact']} · ${m['role']} · ${m['active'] == true ? 'Active' : 'Suspended'}',
                    ),
                    Text(branchName(b, m['branch_id'])),
                    if (owner && m['role'] != 'owner')
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: busy ? null : () => editMember(b, m),
                            child: const Text('Change role / branch'),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => editMember(
                                    b,
                                    m,
                                    active: m['active'] != true,
                                  ),
                            child: Text(
                              m['active'] == true ? 'Suspend' : 'Restore',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (owner) ...[
            const Text('Pending invitations'),
            if (rows(b, 'invitations').isEmpty)
              const Text('No pending invitations'),
            ...rows(b, 'invitations').map(
              (inv) => Card(
                child: DesktopListTile(
                  title: Text('${inv['contact']} · ${inv['role']}'),
                  subtitle: Text(
                    '${branchName(b, inv['branch_id'])}\nExpires: ${DateTime.parse(inv['expires_at'] as String).toLocal()}',
                  ),
                  trailing: IconButton(
                    onPressed: busy ? null : () => cancelInvitation(inv),
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: 'Cancel invitation',
                  ),
                ),
              ),
            ),
          ],
          Card(
            child: DesktopSection(
              title: Text(bt('Branch management', 'ဆိုင်ခွဲစီမံရန်')),
              children: [
                Text(
                  'Online branches · ${rows(b, 'branches').where((br) => br['active'] != false).length} active${owner ? ' / ${b['branch_limit'] ?? 'Unlimited'} plan allowance' : ''}',
                ),
                if (owner)
                  OutlinedButton(
                    onPressed: busy ? null : () => addBranch(b),
                    child: const Text('Add online branch'),
                  ),
                ...rows(b, 'branches').map(
                  (br) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${br['name']} · ${br['active'] == false ? 'Archived' : 'Active'}',
                          ),
                          if (owner)
                            Text(
                              '${rows(b, 'devices').where((d) => d['branch_id'] == br['id'] && d['status'] == 'approved').length} approved devices / 3',
                            ),
                          if (owner)
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => updateBranch(br),
                                  child: const Text('Rename'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => updateBranch(
                                          br,
                                          active: br['active'] == false,
                                        ),
                                  child: Text(
                                    br['active'] == false
                                        ? 'Restore'
                                        : 'Archive',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: DesktopSection(
              title: Text(bt('Role permissions', 'Role ခွင့်ပြုချက်များ')),
              children: [
                Text(
                  bt(
                    'Online roles do not restrict every local POS screen yet.',
                    'Online Role များသည် Local POS စာမျက်နှာတိုင်းကို မကန့်သတ်နိုင်သေးပါ။',
                  ),
                ),
                ...OnlineAccounts.roleDescriptions.values.map(
                  (v) => Text('• $v'),
                ),
                if (owner)
                  OutlinedButton(
                    onPressed: busy ? null : () => configurePermissions(b),
                    child: const Text('Configure role permissions'),
                  ),
              ],
            ),
          ),
          if (owner) ...[
            Card(
              child: DesktopSection(
                title: Text(bt('Account activity', 'အကောင့်မှတ်တမ်း')),
                children: [
                  ...rows(b, 'events').map(
                    (e) => DesktopListTile(
                      title: Text('${e['action']}'),
                      subtitle: Text('${e['recorded_at']}\n${e['actor_id']}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
