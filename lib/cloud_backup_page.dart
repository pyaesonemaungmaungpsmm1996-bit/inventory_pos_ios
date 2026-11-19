import 'desktop_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_database.dart';
import 'auto_backup_page.dart';
import 'app_language.dart';
import 'cloud_backup_record.dart';
import 'cloud_backup_service.dart';
import 'online_account_service.dart';
import 'online_accounts_page.dart';

class CloudBackupPage extends StatefulWidget {
  const CloudBackupPage({super.key, required this.openLocalBackups});
  final VoidCallback openLocalBackups;
  @override
  State<CloudBackupPage> createState() => _CloudBackupPageState();
}

class _CloudBackupPageState extends State<CloudBackupPage> {
  List<Map<String, dynamic>> businesses = [];
  List<CloudBackupRecord> backups = [];
  Map<String, dynamic>? policy;
  StreamSubscription<AuthState>? auth;
  String? selected, error, message;
  bool ready = false, loading = true, busy = false;
  int generation = 0;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
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
      auth = OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
        refresh();
      });
      setState(() => ready = true);
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> refresh() async {
    if (!ready || !mounted) {
      return;
    }
    final request = ++generation;
    final user = OnlineAccounts.client.auth.currentUser;
    setState(() {
      loading = true;
      error = null;
      backups = [];
    });
    if (user == null) {
      setState(() {
        businesses = [];
        selected = null;
        loading = false;
      });
      return;
    }
    try {
      final owned = (await OnlineAccounts.snapshot())
          .where((b) => b['role'] == 'owner' && b['active'] == true)
          .toList();
      final chosen = owned.any((b) => b['id'] == selected)
          ? selected
          : owned.isEmpty
          ? null
          : owned.first['id'] as String;
      final rules = chosen == null
          ? null
          : Map<String, dynamic>.from(
              await OnlineAccounts.client.rpc(
                'tp_license_snapshot',
                params: {'p_business': chosen},
              ) as Map,
            );
      final rows = chosen == null
          ? <CloudBackupRecord>[]
          : await CloudBackupService.list(chosen, user.id);
      if (!mounted ||
          request != generation ||
          OnlineAccounts.client.auth.currentUser?.id != user.id) {
        return;
      }
      setState(() {
        policy = rules;
        businesses = owned;
        selected = chosen;
        backups = rows;
        loading = false;
      });
    } catch (e) {
      if (mounted && request == generation) {
        setState(() {
          businesses = [];
          backups = [];
          selected = null;
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> run(Future<String> Function() operation) async {
    if (busy || loading) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
      error = null;
    });
    try {
      final result = await operation();
      if (mounted) {
        setState(() => message = result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = '$e');
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

  Future<void> signIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DesktopScaffold(
          appBar: AppBar(title: const Text('Login & Online Accounts')),
          body: const OnlineAccountsPage(),
        ),
      ),
    );
    if (mounted) {
      await refresh();
    }
  }

  Future<void> upload() async {
    final matches = businesses.where((b) => b['id'] == selected);
    final business = matches.isEmpty ? null : matches.first;
    final user = OnlineAccounts.client.auth.currentUser;
    if (business == null || user == null || busy || loading) {
      return;
    }
    try {
      final profile = await AppDatabase.instance.getBusinessProfile();
      if (!mounted) {
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => DesktopDialog(
          title: Text(
            t('Upload a new cloud backup?', 'Cloud Backup အသစ်တင်မလား?'),
          ),
          content: SingleChildScrollView(
            child: Text(
              '${t('Local data', 'ဖုန်းထဲက လုပ်ငန်း')}: ${profile['name']}\n'
              '${t('Cloud business', 'Cloud လုပ်ငန်း')}: ${business['name']}\n\n'
              '${t('Confirm this entire local database belongs to the selected business. All local branches, invoices and stored photos are included. This does not link local branches, synchronize records or restore anything. Files are private to the Owner account but are not end-to-end encrypted.', 'ရွေးထားသော Cloud လုပ်ငန်းသည် ဤဒေတာပိုင်ရှင်ဖြစ်ကြောင်း စစ်ပါ။ ဖုန်းထဲက ဆိုင်ခွဲအားလုံး၊ ဘောင်ချာနှင့် ပုံများ ပါပါမည်။ ဆိုင်ခွဲချိတ်ခြင်း၊ ဒေတာ Sync သို့မဟုတ် Restore လုပ်ခြင်း မဟုတ်ပါ။ Owner သာကြည့်နိုင်သော်လည်း End-to-end encryption မပါပါ။')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm & upload'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) {
        return;
      }
      await run(() async {
        await CloudBackupService.upload(business['id'] as String, user.id);
        return t(
          'Cloud backup is Ready. A local snapshot has also been kept.',
          'Cloud Backup Ready ဖြစ်ပါပြီ။ ဖုန်းထဲမှာလည်း မိတ္တူသိမ်းထားပါသည်။',
        );
      });
    } catch (e) {
      if (mounted) {
        setState(() => message = '$e');
      }
    }
  }

  Future<void> download(CloudBackupRecord record) async {
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null) {
      return;
    }
    await run(() async {
      await CloudBackupService.download(record, user.id);
      return t(
        'Downloaded and checksum verified. Open Local Backup & Restore to inspect or save the file. No data has been restored.',
        'Download နှင့် Checksum စစ်ခြင်း အောင်မြင်ပါပြီ။ Local Backup & Restore ထဲမှာ ဖိုင်ကို စစ်/သိမ်းနိုင်ပါသည်။ ဒေတာ Restore မလုပ်ရသေးပါ။',
      );
    });
  }

  Future<void> finish(CloudBackupRecord record) async {
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null) {
      return;
    }
    await run(() async {
      await CloudBackupService.finish(record, user.id);
      return t(
        'Upload verified and marked Ready.',
        'Upload စစ်ပြီး Ready သတ်မှတ်ပြီးပါပြီ။',
      );
    });
  }

  Future<void> remove(CloudBackupRecord record) async {
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text(t('Delete this cloud copy?', 'Cloud မိတ္တူကို ဖျက်မလား?')),
        content: Text(
          '${record.sourceBusiness}\n${record.createdAt.toLocal()}\n\n${t('This removes only this cloud backup. Local POS data and downloaded copies remain.', 'ဤ Cloud Backup တစ်ခုကိုသာ ဖျက်ပါမည်။ ဖုန်းထဲက POS စာရင်းနှင့် Download မိတ္တူများ ဆက်ရှိပါမည်။')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete cloud copy'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    await run(() async {
      await CloudBackupService.delete(record, user.id);
      return t('Cloud copy deleted.', 'Cloud မိတ္တူ ဖျက်ပြီးပါပြီ။');
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ready ? OnlineAccounts.client.auth.currentUser : null;
    return PopScope(
      canPop: !busy,
      child: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t('Owner Cloud Backup', 'Owner အတွက် Cloud Backup'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            t(
              'Manual or automatic cloud copies for the whole local database. This is not live synchronization between branches/devices.',
              'ဖုန်းထဲက ဒေတာအားလုံးကို လက်ဖြင့် သို့မဟုတ် အလိုအလျောက် Cloud Backup သိမ်းရန်ဖြစ်ပါသည်။ ဆိုင်ခွဲ/ဖုန်းအချင်းချင်း Live Sync မဟုတ်သေးပါ။',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t(
              'Pilot limits: 20 MB per file and 10 cloud entries per business, including incomplete uploads. These are separate from paid subscription plans.',
              'စမ်းသပ်ကန့်သတ်ချက် — ဖိုင်တစ်ခု 20 MB၊ လုပ်ငန်းတစ်ခု 10 မိတ္တူအထိ (Upload မပြီးသေးတာများပါ)။ Paid Plan နှင့် မချိတ်ရသေးပါ။',
            ),
          ),
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(message!),
            ),
          if (user != null)
            Text('Signed in: ${user.email ?? user.phone ?? user.id}'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy || loading ? null : signIn,
                child: Text(
                  user == null ? 'Sign in as Owner' : 'Online Accounts',
                ),
              ),
              TextButton(
                onPressed: busy || loading
                    ? null
                    : ready
                    ? refresh
                    : initialize,
                child: const Text('Refresh'),
              ),
            ],
          ),
          if (!loading && user != null && businesses.isEmpty && error == null)
            const Text(
              'This account has no owned online business. Open Online Accounts to create one or sign in as its Owner.',
            ),
          if (businesses.isNotEmpty) ...[
            DropdownButton<String>(
              isExpanded: true,
              value: selected,
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
                  : (value) {
                      setState(() => selected = value);
                      refresh();
                    },
            ),
            OutlinedButton.icon(
              onPressed: busy || loading || user == null || selected == null
                  ? null
                  : () async {
                      final chosen = businesses.firstWhere(
                        (b) => b['id'] == selected,
                      );
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AutoBackupPage(
                            business: chosen['id'] as String,
                            businessName: chosen['name'] as String,
                            owner: user.id,
                            canUpload: policy?['cloud_write'] == true,
                          ),
                        ),
                      );
                      if (mounted) {
                        await refresh();
                      }
                    },
              icon: const Icon(Icons.schedule),
              label: const Text('Auto Cloud Backup'),
            ),
            FilledButton.icon(
              onPressed:
                  busy ||
                      loading ||
                      backups.length >= 10 ||
                      policy?['cloud_write'] != true
                  ? null
                  : upload,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Create & upload new backup'),
            ),
            if (policy?['cloud_write'] != true)
              Text(
                t(
                  'Cloud uploads require an active Premium or Trial plan. Existing backups are kept.',
                  'Cloud Upload အတွက် Premium သို့မဟုတ် Trial သက်တမ်းရှိရန် လိုပါသည်။ အဟောင်းမိတ္တူများကို ဆက်သိမ်းထားပါသည်။',
                ),
              ),
            Text('${backups.length} / 10 cloud entries'),
            ...backups.map(
              (record) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.sourceBusiness,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${record.state.toUpperCase()} · ${record.createdAt.toLocal()}',
                      ),
                      Text(
                        'Database v${record.dbVersion} · ${(record.bytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                      ),
                      Text(
                        record.counts.entries
                            .map((e) => '${e.key}: ${e.value}')
                            .join(' · '),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (record.state == 'ready')
                            OutlinedButton(
                              onPressed:
                                  busy ||
                                      loading ||
                                      policy?['cloud_read'] != true
                                  ? null
                                  : () => download(record),
                              child: const Text('Download copy'),
                            ),
                          if (record.state == 'pending')
                            OutlinedButton(
                              onPressed: busy || loading
                                  ? null
                                  : () => finish(record),
                              child: const Text('Finish upload'),
                            ),
                          TextButton(
                            onPressed: busy || loading
                                ? null
                                : () => remove(record),
                            child: Text(
                              record.state == 'deleting'
                                  ? 'Retry delete'
                                  : 'Delete cloud copy',
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
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : widget.openLocalBackups,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Open Local Backup & Restore'),
          ),
        ],
      ),
    );
  }
}
