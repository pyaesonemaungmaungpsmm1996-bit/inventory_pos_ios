import 'auto_backup_policy.dart';
import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'auto_backup_scheduler.dart';
import 'app_language.dart';
import 'auto_backup_store.dart';
import 'online_account_service.dart';

class AutoBackupPage extends StatefulWidget {
  const AutoBackupPage({
    super.key,
    required this.business,
    required this.businessName,
    required this.owner,
    this.canUpload = true,
  });
  final String business, businessName, owner;
  final bool canUpload;
  @override
  State<AutoBackupPage> createState() => _AutoBackupPageState();
}

class _AutoBackupPageState extends State<AutoBackupPage> {
  Map<String, dynamic> value = {};
  int minutes = 180;
  bool busy = false;
  String? error;
  Timer? timer;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  void languageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    AppLanguage.current.addListener(languageChanged);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      refresh();
    });
  }

  @override
  void dispose() {
    AppLanguage.current.removeListener(languageChanged);
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final row = await AutoBackupStore.read();
      if (mounted) {
        setState(() {
          value = row;
          if (row['enabled'] == true) {
            minutes = row['minutes'] as int;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not read backup status. Reopen this page.',
        );
      }
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (OnlineAccounts.client.auth.currentUser?.id != widget.owner) {
        throw StateError('Owner login changed. Reopen Cloud Backup');
      }
      await operation();
    } catch (e) {
      // Avoid rendering authentication responses (which can contain request URLs).
      if (mounted) {
        setState(
          () => error = e is StateError ? e.message : 'Could not complete setup. Check network, SQL 009 and Anonymous sign-ins, then retry.',
        );
      }
    } finally {
      await refresh();
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> enable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text(
          t('Enable Auto Cloud Backup?', 'Auto Cloud Backup ဖွင့်မလား?'),
        ),
        content: SingleChildScrollView(
          child: Text(
            '${t('Cloud business', 'Cloud လုပ်ငန်း')}: ${widget.businessName}\n\n'
            '${t('Confirm that all POS data on this device, including branches, invoices and photos, belongs to the selected business.', 'ဤဖုန်းထဲက POS ဒေတာအားလုံး (ဆိုင်ခွဲ၊ ဘောင်ချာ၊ ပုံများအပါအဝင်) သည် ရွေးထားသော လုပ်ငန်းပိုင်ဖြစ်ကြောင်း အတည်ပြုပါ။')}\n\n'
            '${t('Changed data is backed up when a reconnection is detected; otherwise the selected interval applies. Windows must stay open. Android may delay background jobs.', 'Internet ပြန်ရကြောင်း သိရှိချိန်တွင် ပြင်ထားသော Data ကို Backup တင်မည်။ အခြားအချိန်တွင် ရွေးထားသောအချိန်အလိုက် တင်မည်။ Windows App ဖွင့်ထားရသည်။ Android နောက်ခံအလုပ် နောက်ကျနိုင်သည်။')}\n\n'
            '${t('20 MB per file, up to 10 cloud entries per business. Backups pause when full. Old copies are not deleted automatically. This is not live sync.', '20 MB / ဖိုင်၊ လုပ်ငန်းတစ်ခု 10 မိတ္တူအထိ။ ပြည့်လျှင် ရပ်ပြီး အသိပေးပါမည်။ အဟောင်းများကို အလိုအလျောက် မဖျက်ပါ။ Live Sync မဟုတ်ပါ။')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Confirm & enable', 'အတည်ပြုပြီး ဖွင့်မည်')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    await run(
      () => AutoBackupScheduler.enable(
        widget.business,
        widget.businessName,
        widget.owner,
        minutes,
      ),
    );
  }

  String displayStatus(String? input) {
    final message = input ?? 'Not enabled';
    if (AppLanguage.current.value != 'my') {
      return message;
    }
    return const <String, String>{
          "Paused by subscription. Enable again after Premium or Trial is active.": "Plan ကြောင့် ရပ်ထားပါသည်။ Premium သို့မဟုတ် Trial သက်တမ်းရှိမှ ပြန်ဖွင့်ပါ။",
          "Not enabled": "မဖွင့်ရသေးပါ",
          "Queued — waiting for network / Android":
              "စောင့်ဆိုင်းနေသည် — Internet / Android အလုပ်စတင်ရန်",
          "Ready — cloud copy verified":
              "အောင်မြင်ပါပြီ — Cloud မိတ္တူ စစ်ဆေးပြီးပါပြီ",
          "Connecting / waiting for network":
              "ချိတ်ဆက်နေသည် / Internet စောင့်နေသည်",
          "Creating / checking snapshot": "ဒေတာမိတ္တူ ပြုလုပ် / စစ်ဆေးနေသည်",
          "Uploading / retrying pending backup":
              "မပြီးသေးသော Backup တင်နေသည် / ပြန်စမ်းနေသည်",
          "Disabled by Owner.": "Owner က ပိတ်ထားပါသည်။",
          "Owner login changed. Reopen Cloud Backup":
              "Owner အကောင့်ပြောင်းသွားပါသည်။ Cloud Backup ကို ပြန်ဝင်ပါ။",
          "Could not read backup status. Reopen this page.":
              "Backup အခြေအနေ မဖတ်နိုင်ပါ။ ဤစာမျက်နှာကို ပြန်ဝင်ပါ။",
          "Could not complete setup. Check network, SQL 009 and Anonymous sign-ins, then retry.": "Setup မပြီးပါ။ Internet၊ SQL 009 နှင့် Anonymous sign-ins ကို စစ်ပြီး ပြန်စမ်းပါ။",
          "Paused after restore. Confirm the local business and enable Auto Backup again.": "Restore လုပ်ပြီးနောက် ရပ်ထားပါသည်။ လုပ်ငန်းကို စစ်ပြီး Auto Backup ပြန်ဖွင့်ပါ။",
          "Paused because the signed-in account changed. Enable again as Owner.": "အကောင့်ပြောင်းသွားသောကြောင့် ရပ်ထားပါသည်။ Owner ဖြင့် ပြန်ဖွင့်ပါ။",
          "Paused after sign out. Enable again as Owner.":
              "Sign out လုပ်ပြီးနောက် ရပ်ထားပါသည်။ Owner ဖြင့် ပြန်ဖွင့်ပါ။",
          "Setup incomplete. Connect online and enable Auto Backup again.":
              "Setup မပြီးသေးပါ။ Internet ချိတ်ပြီး Auto Backup ပြန်ဖွင့်ပါ။",
          "Background sign-in failed. Check network or enable Auto Backup again.": "Background အကောင့်ဝင်မရပါ။ Internet စစ်ပါ သို့မဟုတ် Auto Backup ပြန်ဖွင့်ပါ။",
          "Cloud upload incomplete. Will retry; check network and cloud entries.": "Cloud Upload မပြီးပါ။ ပြန်စမ်းပါမည်။ Internet နှင့် Cloud မိတ္တူများကို စစ်ပါ။",
          "Backup interrupted. Will retry; check network and reopen the app.": "Backup ရပ်သွားပါသည်။ ပြန်စမ်းပါမည်။ Internet စစ်ပြီး App ပြန်ဖွင့်ပါ။",
        }[message] ??
        message;
  }

  Future<void> chooseInterval(int selected) async {
    setState(() => minutes = selected);
    if (value['enabled'] == true) {
      await run(() => AutoBackupScheduler.changeInterval(selected));
    }
  }

  Future<void> customInterval() async {
    final controller = TextEditingController(text: minutes.toString());
    final form = GlobalKey<FormState>();
    final selected = await showDialog<int>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(t('Custom backup interval', 'Backup အချိန်အပိုင်းအခြား')),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: t('Minutes', 'မိနစ်'),
              helperText: t(
                '15 minutes to 30 days. Android may delay background execution.',
                '၁၅ မိနစ်မှ ရက် ၃၀ အထိ။ Android နောက်ခံလုပ်ဆောင်မှု နောက်ကျနိုင်သည်။',
              ),
            ),
            validator: (v) =>
                AutoBackupPolicy.validMinutes(int.tryParse(v ?? ''))
                ? null
                : t(
                    'Enter 15 to 43200 minutes',
                    '၁၅ မှ ၄၃၂၀၀ မိနစ်အတွင်း ထည့်ပါ',
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialog, int.parse(controller.text));
              }
            },
            child: Text(t('Save', 'သိမ်းရန်')),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (selected != null && mounted) await chooseInterval(selected);
  }

  String time(dynamic input) =>
      DateTime.tryParse('$input')?.toLocal().toString().split('.').first ?? '—';
  @override
  Widget build(BuildContext context) {
    final enabled = value['enabled'] == true;
    final same =
        value['business'] == widget.business && value['owner'] == widget.owner;
    return PopScope(
      canPop: !busy,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(t('Auto Cloud Backup', 'အလိုအလျောက် Cloud Backup')),
        ),
        body: DesktopListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!AppCapabilities.backgroundBackup)
              Text(
                t(
                  'Auto Backup is available on Android and Windows.',
                  'Auto Backup ကို Android နှင့် Windows တွင် အသုံးပြုနိုင်သည်။',
                ),
              ),
            Text(
              widget.businessName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              t(
                'Back up automatically when internet returns. Keep the Windows app open; Android background execution depends on the OS. Backup is separate from device synchronization.',
                'Internet ပြန်ရချိန် အလိုအလျောက် Backup တင်ရန်။ Windows App ကို ဖွင့်ထားရသည်။ Android နောက်ခံလုပ်ဆောင်မှုမှာ OS အပေါ်မူတည်သည်။ Device Sync နှင့် သီးခြားဖြစ်သည်။',
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(displayStatus(error!)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enabled ? 'ON · ${value['businessName']}' : 'OFF',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${t('Status', 'အခြေအနေ')}: ${displayStatus(value['status'] as String?)}',
                    ),
                    Text(
                      '${t('Last snapshot captured', 'နောက်ဆုံးဒေတာရိုက်ယူချိန်')}: ${time(value['capturedAt'])}',
                    ),
                    Text(
                      '${t('Last cloud upload completed', 'နောက်ဆုံး Cloud တင်ပြီးချိန်')}: ${time(value['uploadedAt'])}',
                    ),
                    if (value['pending'] != null)
                      Text(
                        '${t('Pending snapshot', 'မပြီးသေးသော Snapshot')}: ${time((value['pending'] as Map)['captured'])}\n${t('The same file will resume uploading when internet is available.', 'မပြီးသေးသော ဖိုင်ကို Internet ရလျှင် ဆက်တင်ပါမည်။')}',
                      ),
                  ],
                ),
              ),
            ),
            DropdownButton<int>(
              value: minutes,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 60, child: Text(t('1 hour', '၁ နာရီ'))),
                DropdownMenuItem(
                  value: 180,
                  child: Text(t('3 hours', '၃ နာရီ')),
                ),
                DropdownMenuItem(value: 1440, child: Text(t('1 day', '၁ ရက်'))),
                if (![60, 180, 1440].contains(minutes))
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(
                      '${t('Custom', 'စိတ်ကြိုက်')} · $minutes min',
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      if (v != null) {
                        chooseInterval(v);
                      }
                    },
            ),
            TextButton.icon(
              onPressed: busy ? null : customInterval,
              icon: const Icon(Icons.schedule),
              label: Text(
                t('Custom interval…', 'အချိန်ကို စိတ်ကြိုက်ရွေးရန်…'),
              ),
            ),
            if (!widget.canUpload)
              Text(
                t(
                  'Cloud uploads require an active Premium or Trial plan. Local Backup remains available.',
                  'Cloud Upload အတွက် Premium သို့မဟုတ် Trial သက်တမ်းရှိရန် လိုပါသည်။ Local Backup ဆက်သုံးနိုင်ပါသည်။',
                ),
              ),
            if (enabled && !same)
              Text(
                t(
                  'Another business has an active schedule on this device. Check the account and business, then turn off that schedule first.',
                  'ဤဖုန်းတွင် အခြားလုပ်ငန်းအတွက် Schedule ဖွင့်ထားပါသည်။ Account / လုပ်ငန်းကို စစ်ပြီး အရင်ပိတ်ပါ။',
                ),
              ),
            if (!enabled)
              FilledButton(
                onPressed:
                    busy ||
                        !widget.canUpload ||
                        !AppCapabilities.backgroundBackup
                    ? null
                    : enable,
                child: Text(t('Enable Auto Backup', 'Auto Backup ဖွင့်မည်')),
              ),
            if (enabled && same)
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => run(AutoBackupScheduler.backupNow),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  t('Backup now / Retry', 'ယခု Backup တင်မည် / ပြန်စမ်းမည်'),
                ),
              ),
            if (enabled)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(
                        () => AutoBackupScheduler.disable('Disabled by Owner.'),
                      ),
                child: Text(t('Turn off Auto Backup', 'Auto Backup ပိတ်မည်')),
              ),
            const SizedBox(height: 12),
            Text(
              t(
                'Change the interval without disabling Auto Backup. Reopen the app after force stopping it. Windows runs backups while the app is open; Android battery settings and Doze can delay jobs.',
                'Auto Backup မပိတ်ဘဲ အချိန်ပြောင်းနိုင်သည်။ Force stop လုပ်ထားလျှင် App ပြန်ဖွင့်ပါ။ Windows App ဖွင့်ထားချိန် Backup လုပ်သည်။ Android Battery / Doze ကြောင့် နောက်ကျနိုင်သည်။',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Auto Backup pauses after a restore or account change. Confirm the business before enabling it again. Existing cloud copies are kept.',
                'Restore လုပ်ပြီးလျှင် သို့မဟုတ် Account ပြောင်းလျှင် Auto Backup ရပ်ပါမည်။ လုပ်ငန်းကို စစ်ပြီး ပြန်ဖွင့်ပါ။ Cloud အဟောင်းများကို ဤလုပ်ဆောင်ချက်က မဖျက်ပါ။',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Only the Owner can download cloud copies. End-to-end encryption is not included. Background uploads use a separate upload-only identity from the Owner login.',
                'Cloud copy သည် Owner သာ Download လုပ်နိုင်ပါသည်။ End-to-end encryption မပါပါ။ Background အတွက် သီးခြား Upload-only identity သုံးပြီး Owner login နှင့် ခွဲထားပါသည်။',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await AutoBackupScheduler.checkOwner();
                      await refresh();
                    },
              child: Text(t('Refresh status', 'အခြေအနေ ပြန်စစ်မည်')),
            ),
          ],
        ),
      ),
    );
  }
}
