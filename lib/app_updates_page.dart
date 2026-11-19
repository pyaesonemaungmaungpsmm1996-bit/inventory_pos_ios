import 'desktop_ui.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_update_service.dart';
import 'app_update_push.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class OptionalUpdateHost extends StatefulWidget {
  const OptionalUpdateHost({super.key, required this.child, this.service});
  final Widget child;
  final AppUpdateService? service;
  static AppUpdateService? serviceOf(BuildContext context) =>
      context.findAncestorStateOfType<_OptionalUpdateHostState>()?.service;
  @override
  State<OptionalUpdateHost> createState() => _OptionalUpdateHostState();
}

class _OptionalUpdateHostState extends State<OptionalUpdateHost>
    with WidgetsBindingObserver {
  late final AppUpdateService service;
  late final AppUpdatePush push;
  bool ownsService = false;
  @override
  void initState() {
    super.initState();
    service = widget.service ?? AppUpdateService();
    ownsService = widget.service == null;
    push = AppUpdatePush();
    push.onUpdate = () => check(force: true);
    WidgetsBinding.instance.addObserver(this);
    if (kReleaseMode) {
      unawaited(push.start());
      WidgetsBinding.instance.addPostFrameCallback((_) => check());
    }
  }

  void check({bool force = false}) {
    if (!mounted ||
        !kReleaseMode ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    unawaited(service.check(force: force));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      check();
      if (kReleaseMode) unawaited(push.start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(push.dispose());
    if (ownsService) service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder: (context, _) => Column(
      children: [
        if (service.visible)
          SafeArea(
            bottom: false,
            child: Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.ready
                          ? _t(
                              'Update downloaded. Restart when convenient.',
                              'Update ဒေါင်းပြီးပါပြီ။ အဆင်ပြေချိန် ပြန်စနိုင်ပါသည်။',
                            )
                          : _t(
                              'A new version is available. You can keep using the app.',
                              'ဗားရှင်းအသစ်ရပါပြီ။ လက်ရှိ App ကို ဆက်သုံးနိုင်ပါသည်။',
                            ),
                    ),
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: service.downloading
                              ? null
                              : service.ready
                              ? service.install
                              : service.download,
                          child: Text(
                            service.ready
                                ? _t(
                                    'Restart & update',
                                    'ပြန်စပြီး Update လုပ်မည်',
                                  )
                                : service.downloading
                                ? _t('Downloading…', 'ဒေါင်းနေသည်…')
                                : _t('Update', 'Update လုပ်မည်'),
                          ),
                        ),
                        TextButton(
                          onPressed: service.later,
                          child: Text(_t('Later', 'နောက်မှ')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    ),
  );
}

class AppUpdatesPage extends StatefulWidget {
  const AppUpdatesPage({super.key, this.service});
  final AppUpdateService? service;
  @override
  State<AppUpdatesPage> createState() => _AppUpdatesPageState();
}

class _AppUpdatesPageState extends State<AppUpdatesPage> {
  late final AppUpdateService service;
  final push = AppUpdatePush();
  bool enabled = false, busy = false, checked = false;
  String? notice;
  @override
  void initState() {
    super.initState();
    service = widget.service ?? AppUpdateService();
    load();
  }

  Future<void> load() async {
    try {
      final value = await push.enabled();
      if (mounted) setState(() => enabled = value);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.service == null) service.dispose();
    unawaited(push.dispose());
    super.dispose();
  }

  Future<void> check() async {
    await service.check(manual: true);
    if (mounted) setState(() => checked = true);
  }

  Future<void> notifications(bool value) async {
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      if (value) {
        final allowed = await push.enable();
        if (!mounted) return;
        setState(() {
          enabled = allowed;
          if (!allowed) {
            notice = _t(
              'Allow notifications in phone settings to receive update notices.',
              'Update အသိပေးချက်ရရန် ဖုန်းဆက်တင်တွင် Notification ခွင့်ပြုပါ။',
            );
          }
        });
      } else {
        await push.disable();
        if (mounted) setState(() => enabled = false);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => notice = AppUpdatePush.configured
              ? _t(
                  'Could not change notifications. Check your connection and retry.',
                  'Notification ဆက်တင်မပြောင်းနိုင်ပါ။ Internet စစ်ပြီး ပြန်စမ်းပါ။',
                )
              : _t(
                  'Update notifications are not connected yet. You can still check for updates.',
                  'Update notification မချိတ်ရသေးပါ။ Update ကို ကိုယ်တိုင် စစ်နိုင်ပါသည်။',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text(_t('App Updates', 'App Update များ'))),
    body: AnimatedBuilder(
      animation: service,
      builder: (context, _) => DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _t(
              'Updates are optional. Later keeps the app usable. Save your work before restarting.',
              'Update သည် မဖြစ်မနေ မဟုတ်ပါ။ နောက်မှ ရွေးပြီး ဆက်သုံးနိုင်ပါသည်။ ပြန်မစမီ ရေးလက်စကို သိမ်းပါ။',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                !service.supported || service.checking || service.downloading
                ? null
                : check,
            icon: const Icon(Icons.system_update),
            label: Text(
              service.checking
                  ? _t('Checking…', 'စစ်နေသည်…')
                  : _t('Check for updates', 'Update ရှိမရှိစစ်ရန်'),
            ),
          ),
          if (!service.supported)
            Text(
              _t(
                'Google Play update checks are available on Android.',
                'Google Play Update စစ်ဆေးခြင်းကို Android တွင် အသုံးပြုနိုင်ပါသည်။',
              ),
            ),
          if (service.visible) ...[
            Text(
              service.ready
                  ? _t(
                      'The update is ready to install.',
                      'Update တင်ရန် အဆင်သင့်ဖြစ်ပါပြီ။',
                    )
                  : _t(
                      'A new version is available.',
                      'ဗားရှင်းအသစ် ရရှိနိုင်ပါပြီ။',
                    ),
            ),
            FilledButton(
              onPressed: service.downloading
                  ? null
                  : service.ready
                  ? service.install
                  : service.download,
              child: Text(
                service.ready
                    ? _t('Restart & update', 'ပြန်စပြီး Update လုပ်မည်')
                    : _t('Update', 'Update လုပ်မည်'),
              ),
            ),
            TextButton(
              onPressed: service.later,
              child: Text(_t('Later', 'နောက်မှ')),
            ),
          ],
          if (service.downloading)
            Text(
              _t(
                'Downloading in the background. You can return to your work.',
                'နောက်ကွယ်တွင် ဒေါင်းနေပါသည်။ အလုပ်ပြန်ဆက်နိုင်ပါသည်။',
              ),
            ),
          if (checked &&
              !service.visible &&
              !service.availableUpdate &&
              !service.unavailable &&
              !service.checking)
            Text(
              _t(
                'No newer update is available to this device on Google Play.',
                'ဤစက်အတွက် Google Play တွင် Update အသစ် မရရှိသေးပါ။',
              ),
            ),
          if (service.unavailable)
            Text(
              _t(
                'Could not check Google Play. Check your internet connection. Directly installed APKs may not support this check.',
                'Google Play ကို မစစ်နိုင်သေးပါ။ Internet စစ်ပါ။ တိုက်ရိုက်ထည့်ထားသော APK တွင် ဤစစ်ဆေးမှု မရနိုင်ပါ။',
              ),
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_t('Update notifications', 'Update အသိပေးချက်များ')),
            subtitle: Text(
              _t(
                'Optional phone notifications when a release is announced.',
                'ဗားရှင်းအသစ်အကြောင်း ဖုန်းတွင် အသိပေးရန်။ ရွေးချယ်ခွင့်ရှိပါသည်။',
              ),
            ),
            value: enabled,
            onChanged: busy || !push.supported ? null : notifications,
          ),
          if (busy) const LinearProgressIndicator(),
          if (notice != null) Text(notice!),
        ],
      ),
    ),
  );
}
