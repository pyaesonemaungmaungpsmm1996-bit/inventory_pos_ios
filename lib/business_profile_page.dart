import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'business_countries.dart';
import 'business_timezones.dart';
import 'app_datetime.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class BusinessProfilePage extends StatefulWidget {
  const BusinessProfilePage({super.key, this.requiredSetup = false});
  final bool requiredSetup;
  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  String? country;
  String? timezoneId;
  String currency = 'MMK', originalCurrency = 'MMK';
  bool loading = true, saving = false, locked = true, saved = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final profile = await AppDatabase.instance.getBusinessProfile();
      if (!mounted) return;
      setState(() {
        name.text = profile['name'] as String;
        final code = profile['country_code'] as String;
        country = businessCountries.containsKey(code) ? code : null;
        timezoneId =
            profile['timezone_id'] as String? ?? defaultBusinessTimeZone(code);
        currency = profile['currency_code'] as String;
        originalCurrency = currency;
        locked = profile['currency_locked'] as bool;
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t(
            'Could not load business settings. Retry.',
            'လုပ်ငန်းဆက်တင်များ မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
          );
        });
      }
    }
  }

  Future<void> chooseCountry() async {
    String query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final matches = businessCountries.entries
              .where(
                (e) => '${e.key} ${e.value}'.toLowerCase().contains(
                  query.trim().toLowerCase(),
                ),
              )
              .toList();
          return DesktopDialog(
            title: Text(_t('Country / Region', 'နိုင်ငံ / ဒေသ')),
            content: SizedBox(
              width: 420,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _t(
                        'Search country or code',
                        'နိုင်ငံအမည် သို့မဟုတ် ကုဒ်ဖြင့်ရှာရန်',
                      ),
                    ),
                    onChanged: (value) => update(() => query = value),
                  ),
                  Expanded(
                    child: DesktopListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (c, i) {
                        final entry = matches[i];
                        return DesktopListTile(
                          title: Text(entry.value),
                          subtitle: Text(entry.key),
                          trailing: country == entry.key
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(c, entry.key),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      country = selected;
      timezoneId = defaultBusinessTimeZone(selected);
      // Country and currency are independent; suggestions never change existing data.
      if (!locked) {
        currency =
            const {
              'MM': 'MMK',
              'US': 'USD',
              'TH': 'THB',
              'CN': 'CNY',
              'JP': 'JPY',
            }[selected] ??
            currency;
      }
    });
  }

  Future<void> save() async {
    if (saving || loading || !form.currentState!.validate()) return;
    if (country == null) {
      setState(
        () => error = _t('Choose a country / region.', 'နိုင်ငံ / ဒေသ ရွေးပါ။'),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (currency != originalCurrency) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => DesktopDialog(
            title: Text(
              _t('Set business currency?', 'လုပ်ငန်းငွေကြေး သတ်မှတ်မလား?'),
            ),
            content: Text(
              _t(
                'Use ${AppCurrency.display(currency)} for all product prices, invoices and money accounts. Currency becomes locked once records are added. This does not perform currency exchange.',
                'ပစ္စည်းဈေး၊ Invoice နှင့် ငွေအကောင့်အားလုံးတွင် ${AppCurrency.display(currency)} သုံးမည်။ စာရင်းထည့်ပြီးလျှင် ငွေကြေးပြန်ပြောင်းမရပါ။ ငွေလဲနှုန်းဖြင့် ပြောင်းတွက်ခြင်း မဟုတ်ပါ။',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(_t('Use this currency', 'ဤငွေကြေးသုံးမည်')),
              ),
            ],
          ),
        );
        if (!mounted || yes != true) return;
      }
      final result = await AppDatabase.instance.saveBusinessProfile(
        name: name.text,
        countryCode: country!,
        currencyCode: currency,
        timezoneId: timezoneId,
      );
      AppDateTime.configure(result['timezone_id'] as String);
      AppCurrency.apply(result);
      if (!mounted) return;
      setState(() {
        saved = true;
        saving = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? _t(
                  'Currency is locked because records already exist. Reopen this page to refresh.',
                  'စာရင်းရှိပြီးဖြစ်၍ ငွေကြေးပြောင်းမရပါ။ ဤစာမျက်နှာကို ပြန်ဖွင့်ပါ။',
                )
              : _t(
                  'Could not save business settings. Please retry.',
                  'လုပ်ငန်းဆက်တင်များ မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။',
                ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !saving && (!widget.requiredSetup || saved),
    child: loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: form,
            child: DesktopListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _t('Business Profile', 'လုပ်ငန်းအချက်အလက်'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (widget.requiredSetup)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _t(
                        'Choose your business country and check the currency before continuing.',
                        'ဆက်မသုံးမီ လုပ်ငန်း၏နိုင်ငံကို ရွေးပြီး ငွေကြေးကို စစ်ပါ။',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  enabled: !saving,
                  maxLength: 150,
                  decoration: InputDecoration(
                    labelText: _t('Business name', 'လုပ်ငန်းအမည်'),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? _t('Enter business name.', 'လုပ်ငန်းအမည် ထည့်ပါ။')
                      : null,
                ),
                DesktopListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public),
                  title: Text(_t('Country / Region', 'နိုင်ငံ / ဒေသ')),
                  subtitle: Text(
                    country == null
                        ? _t('Tap to choose', 'နှိပ်ပြီးရွေးပါ')
                        : '${businessCountries[country]} ($country)',
                  ),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: saving ? null : chooseCountry,
                ),
                const SizedBox(height: 12),
                if (country != null)
                  DropdownButtonFormField<String>(
                    key: ValueKey('$country:$timezoneId'),
                    initialValue: timezoneId,
                    decoration: InputDecoration(
                      labelText: _t('Business time zone', 'လုပ်ငန်း Time Zone'),
                    ),
                    isExpanded: true,
                    items: (businessTimeZones[country] ?? const <String>[])
                        .map(
                          (zone) => DropdownMenuItem(
                            value: zone,
                            child: Text(zone, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (zone) {
                            if (zone != null) setState(() => timezoneId = zone);
                          },
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(currency),
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: _t('Business currency', 'လုပ်ငန်းငွေကြေး'),
                  ),
                  isExpanded: true,
                  items: AppCurrency.names.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            '${AppCurrency.display(e.key)} — ${e.value}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving || locked
                      ? null
                      : (value) {
                          if (value != null) setState(() => currency = value);
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  AppCurrency.precision[currency] == 0
                      ? _t(
                          'Whole amounts only (${AppCurrency.display(currency)}).',
                          'ပြည့်ကိန်းငွေပမာဏသာ သုံးမည် (${AppCurrency.display(currency)})။',
                        )
                      : _t(
                          'Supports up to 2 decimal places (${AppCurrency.display(currency)}), e.g. 12.50.',
                          'ဒဿမ ၂ နေရာအထိ ထည့်နိုင်သည် (${AppCurrency.display(currency)})။ ဥပမာ 12.50။',
                        ),
                ),
                Text(
                  '${_t('Example', 'ဥပမာ')}: ${AppCurrency.format(AppCurrency.precision[currency] == 0 ? 1250 : 125050, currency: currency)}',
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _t(
                        'Currency is locked to protect existing product, account and invoice amounts. Country and business name can still be edited.',
                        'ရှိပြီးသား ပစ္စည်းဈေး၊ ငွေအကောင့်နှင့် Invoice ပမာဏများ မမှားရန် ငွေကြေးကို ပိတ်ထားပါသည်။ နိုင်ငံနှင့် လုပ်ငန်းအမည်ကို ပြင်နိုင်ပါသည်။',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  _t(
                    'Country records the location you choose for this business. It is separate from language. Online country usage reports will require the future account/sync service.',
                    'နိုင်ငံသည် ဤလုပ်ငန်းအတွက် သင်ရွေးထားသောတည်နေရာ ဖြစ်ပါသည်။ ဘာသာစကားနှင့် သီးခြားဖြစ်သည်။ နိုင်ငံအလိုက် အသုံးပြုမှုစာရင်းချုပ်အတွက် နောက်ပိုင်း Online Account / Sync လိုပါမည်။',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t(
                    'Recorded UTC instants display in the chosen business time zone. Countries with multiple zones can choose a city above.',
                    'သိမ်းထားသော UTC အချိန်ကို ရွေးထားသော လုပ်ငန်း Time Zone ဖြင့်ပြမည်။ ဇုန်အများကြီးရှိသော နိုင်ငံတွင် အပေါ်က မြို့ကို ရွေးနိုင်သည်။',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    saving
                        ? _t('Saving...', 'သိမ်းနေသည်…')
                        : _t('Save', 'သိမ်းမည်'),
                  ),
                ),
                TextButton(
                  onPressed: saving ? null : load,
                  child: Text(_t('Reload settings', 'ဆက်တင်များ ပြန်ဖတ်ရန်')),
                ),
              ],
            ),
          ),
  );
}
