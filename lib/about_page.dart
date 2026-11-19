import 'desktop_ui.dart';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_language.dart';
import 'brand_logo.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? info;
  bool loading = true;
  bool failed = false;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final value = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          info = value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text(t('About', 'App အကြောင်း'))),
    body: DesktopListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 24),
        const Center(child: BrandLogo()),
        const SizedBox(height: 14),
        Text(
          'TP POS',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'PSM IT Company',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              DesktopListTile(
                title: Text(t('Developed by', 'ထုတ်လုပ်သူ')),
                subtitle: const Text('PSM IT Company'),
              ),
              const Divider(height: 1),
              DesktopListTile(
                title: Text(t('App Version', 'App ဗားရှင်း')),
                subtitle: Text(
                  loading
                      ? '…'
                      : info?.version.isNotEmpty == true
                      ? info!.version
                      : t('Unavailable', 'မဖတ်နိုင်သေးပါ'),
                ),
              ),
              const Divider(height: 1),
              DesktopListTile(
                title: Text(t('Build Number', 'Build နံပါတ်')),
                subtitle: Text(
                  loading
                      ? '…'
                      : info?.buildNumber.isNotEmpty == true
                      ? info!.buildNumber
                      : t('Unavailable', 'မဖတ်နိုင်သေးပါ'),
                ),
              ),
            ],
          ),
        ),
        if (loading) const LinearProgressIndicator(),
        if (failed)
          TextButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: Text(t('Retry version check', 'ဗားရှင်းပြန်ဖတ်ရန်')),
          ),
        const SizedBox(height: 24),
        Text(
          '© PSM IT Company',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
