import 'desktop_ui.dart';

import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'backup_service.dart';
import 'sqlite_backup.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.onRestored});
  final VoidCallback onRestored;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<File> files = [];
  BackupInfo? selected;
  String? imported, message;
  bool busy = false;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  @override
  void dispose() {
    final file = imported;
    if (file != null) {
      unawaited(cleanImported(file));
    }
    super.dispose();
  }

  Future<void> cleanImported(String path) async {
    try {
      if (await File(path).exists()) {
        await File(path).delete();
      }
    } catch (_) {
      /* Temporary import cleanup can be retried later. */
    }
  }

  Future<void> load() async {
    final result = await BackupService.files();
    if (mounted) {
      setState(() => files = result);
    }
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> create() => run(() async {
    final result = await BackupService.create();
    await load();
    if (mounted) {
      setState(() {
        selected = result;
        message = t(
          'Backup created inside app storage. Use Save file to keep a copy outside the app.',
          'App ထဲမှာ Backup သိမ်းပြီးပါပြီ။ App ပြင်ပတွင်ပါ သိမ်းရန် Save file နှိပ်ပါ။',
        );
      });
    }
  });
  Future<void> choose() => run(() async {
    final path = await BackupService.importFile();
    if (path == null) {
      return;
    }
    final previous = imported;
    if (previous != null && await File(previous).exists()) {
      await File(previous).delete();
    }
    imported = path;
    final info = await BackupService.inspect(path);
    if (mounted) {
      setState(() => selected = info);
    }
  });
  Future<void> save() => run(() async {
    final snapshot = selected;
    if (snapshot == null) {
      return;
    }
    if (snapshot.bytes > 64 * 1024 * 1024) {
      throw StateError('Use Share file for backups larger than 64 MB');
    }
    final destination = await FilePicker.saveFile(
      fileName: 'toe_pwar_pos_${DateTime.now().millisecondsSinceEpoch}.tppos',
      bytes: await File(snapshot.path).readAsBytes(),
      dialogTitle: 'Save Toe Pwar POS backup',
    );
    if (mounted) {
      setState(
        () => message = destination == null
            ? t('Save cancelled.', 'သိမ်းခြင်း ပယ်ဖျက်လိုက်ပါသည်။')
            : t(
                'Backup file saved to the selected destination.',
                'ရွေးထားသောနေရာတွင် Backup ဖိုင် သိမ်းပြီးပါပြီ။',
              ),
      );
    }
  });
  Future<void> share() => run(() async {
    if (selected == null) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(selected!.path)],
        fileNameOverrides: [
          selected!.path.endsWith('.tppos')
              ? p.basename(selected!.path)
              : 'toe_pwar_pos_imported_backup.tppos',
        ],
        text: 'Toe Pwar POS database backup',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
    if (mounted) {
      setState(
        () => message = t(
          'Share sheet opened. Keep a copy outside this app.',
          'Share မှတစ်ဆင့် App ပြင်ပတွင် Backup ဖိုင် သိမ်းထားပါ။',
        ),
      );
    }
  });
  Future<void> restore() async {
    final snapshot = selected;
    if (snapshot == null || busy) {
      return;
    }
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text(
          t(
            'Replace ALL local POS data?',
            'ဖုန်းထဲက POS ဒေတာအားလုံးကို အစားထိုးမလား?',
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            '${snapshot.businessName} · ${snapshot.currency}\n\n${t('Current local records and photos will be replaced by this backup, not merged. Changes made after the backup will not be in the restored database. A pre-restore copy will be retained. Online account settings and other devices are not restored.', 'လက်ရှိဖုန်းထဲက စာရင်းနှင့်ပုံအားလုံးကို Backup ထဲက ဒေတာဖြင့် အစားထိုးပါမည်။ ပေါင်းထည့်ခြင်း မဟုတ်ပါ။ Backup ယူပြီးနောက် ပြောင်းထားသောစာရင်းများ မပါဝင်ပါ။ မူလဒေတာကိုလည်း သီးသန့်သိမ်းထားပါမည်။ Online account နှင့် အခြားဖုန်းဒေတာကို မပြောင်းပါ။')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Replace & restore', 'အစားထိုးပြီး Restore လုပ်မည်')),
          ),
        ],
      ),
    );
    if (answer != true || !mounted) {
      return;
    }
    await run(() async {
      await AppDatabase.instance.restoreLocalBackup(snapshot.path);
      if (!mounted) {
        return;
      }
      widget.onRestored();
    });
  }

  Future<void> delete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: const Text('Delete this local backup copy?'),
        content: Text(p.basename(file.path)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete copy'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await run(() async {
      await file.delete();
      if (selected?.path == file.path && mounted) {
        setState(() => selected = null);
      }
      await load();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: DesktopListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t('Local Backup & Restore', 'ဖုန်းထဲက ဒေတာ Backup / Restore'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          t(
            'Includes all local database records, drafts and photos stored in SQLite. Online accounts, OTP sessions, theme/language and printer preferences are not included. Automatic cloud backup/sync is not connected yet.',
            'SQLite ထဲက စာရင်း၊ Draft နှင့် ပုံများပါဝင်ပါသည်။ Online account၊ OTP session၊ Theme/Language နှင့် Printer preference မပါပါ။ အလိုအလျောက် Cloud backup/sync မချိတ်ရသေးပါ။',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'Backup files contain business data and are not encrypted. Keep them in a private location. App-internal copies are lost when uninstalling or clearing app data.',
            'Backup ဖိုင်တွင် လုပ်ငန်းဒေတာပါပြီး Encryption မလုပ်ထားပါ။ သီးသန့်နေရာတွင် သိမ်းပါ။ App ကို uninstall / clear data လုပ်ရင် App ထဲက Backup မိတ္တူများလည်း ပျောက်ပါမည်။',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : create,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Create backup'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : choose,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Choose backup file'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(message!),
          ),
        if (selected != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${selected!.businessName} · ${selected!.currency}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Database v${selected!.version} · ${(selected!.bytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                  ),
                  ...selected!.counts.entries.map(
                    (e) => Text('${e.key}: ${e.value}'),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy ? null : save,
                        child: const Text('Save file'),
                      ),
                      OutlinedButton(
                        onPressed: busy ? null : share,
                        child: const Text('Share file'),
                      ),
                      FilledButton(
                        onPressed: busy ? null : restore,
                        child: const Text('Restore this backup'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Divider(),
        Text(
          t(
            'Backups on this installation',
            'ဒီ App ထဲတွင် သိမ်းထားသော Backup မိတ္တူများ',
          ),
        ),
        if (files.isEmpty && !busy) const Text('No local backups yet.'),
        ...files.map(
          (file) => DesktopListTile(
            title: Text(p.basename(file.path)),
            subtitle: file.path.contains('.before_restore.')
                ? const Text('Safety copy from before a restore')
                : null,
            onTap: busy
                ? null
                : () => run(() async {
                    final result = await BackupService.inspect(file.path);
                    if (mounted) {
                      setState(() => selected = result);
                    }
                  }),
            trailing: IconButton(
              onPressed: busy ? null : () => delete(file),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete this backup copy',
            ),
          ),
        ),
      ],
    ),
  );
}
