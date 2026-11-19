import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'billing_forms.dart';
import 'online_account_service.dart';
import 'subscription_billing_service.dart';

class BusinessLocationPage extends StatefulWidget {
  const BusinessLocationPage({super.key});
  @override
  State<BusinessLocationPage> createState() => _BusinessLocationPageState();
}

class _BusinessLocationPageState extends State<BusinessLocationPage> {
  List<Map<String, dynamic>> businesses = [];
  String? selected, error;
  bool busy = true;
  final township = TextEditingController(),
      city = TextEditingController(),
      region = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    township.dispose();
    city.dispose();
    region.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    try {
      await OnlineAccounts.initialize();
      final rows = (await OnlineAccounts.snapshot())
          .where((r) => r['role'] == 'owner' && r['active'] == true)
          .toList();
      final chosen = rows.any((r) => r['id'] == selected)
          ? selected
          : rows.isEmpty
          ? null
          : rows.first['id'] as String;
      final r = chosen == null
          ? {}
          : await OnlineAccounts.client.rpc(
              'tp_business_contact',
              params: {'p_business': chosen},
            );
      if (mounted) {
        setState(() {
          businesses = rows;
          selected = chosen;
          township.text = '${r['township'] ?? ''}';
          city.text = '${r['city'] ?? ''}';
          region.text = '${r['region'] ?? ''}';
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = BillingService.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (selected == null || busy) return;
    setState(() => busy = true);
    try {
      await OnlineAccounts.client.rpc(
        'tp_business_contact_save',
        params: {
          'p_business': selected,
          'p_township': township.text.trim(),
          'p_city': city.text.trim(),
          'p_region': region.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bt('Business location saved.', 'လုပ်ငန်းတည်နေရာ သိမ်းပြီးပါပြီ။'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = BillingService.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text(bt('Business location', 'လုပ်ငန်းတည်နေရာ'))),
    body: DesktopListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          bt(
            'Enter your shop township, city and region for support and the provider business directory. GPS is not collected. This does not change existing invoice address snapshots.',
            'Support နှင့် Provider လုပ်ငန်းစာရင်းအတွက် ဆိုင်၏ မြို့နယ်၊ မြို့နှင့် တိုင်း/ပြည်နယ်ကို ဖြည့်ပါ။ GPS မကောက်ယူပါ။ ဘောင်ချာဟောင်း၏ လိပ်စာမပြောင်းပါ။',
          ),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(selected),
          initialValue: selected,
          isExpanded: true,
          items: [
            for (final b in businesses)
              DropdownMenuItem(
                value: b['id'] as String,
                child: Text('${b['name']}'),
              ),
          ],
          onChanged: busy
              ? null
              : (v) {
                  selected = v;
                  load();
                },
        ),
        for (final field in [
          (township, bt('Township', 'မြို့နယ်')),
          (city, bt('City', 'မြို့')),
          (region, bt('Region / State', 'တိုင်း / ပြည်နယ်')),
        ])
          TextField(
            controller: field.$1,
            enabled: !busy,
            maxLength: 100,
            decoration: InputDecoration(labelText: field.$2),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        FilledButton(
          onPressed: busy || selected == null ? null : save,
          child: Text(bt('Save', 'သိမ်းမည်')),
        ),
      ],
    ),
  );
}
