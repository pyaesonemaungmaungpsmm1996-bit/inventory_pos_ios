import 'contact_search.dart';
import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key, required this.kind})
    : assert(kind == 'customer' || kind == 'supplier');
  final String kind;
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<Map<String, Object?>> contacts = [];
  bool loading = true;
  bool busy = false;
  bool activeOnly = true;
  String search = '';
  String? error;
  int request = 0;
  bool get customer => widget.kind == 'customer';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final ticket = ++request;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final rows = await AppDatabase.instance.getContacts(kind: widget.kind);
      if (!mounted || ticket != request) return;
      setState(() {
        contacts = rows;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t(
          'Could not load contacts. Please retry.',
          'စာရင်း မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
        );
      });
    }
  }

  Future<void> edit([Map<String, Object?>? contact]) async {
    if (busy || loading) return;
    setState(() => busy = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ContactForm(kind: widget.kind, contact: contact),
      );
      if (saved == true) await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = search.trim().toLowerCase();
    final visible = contacts
        .where(
          (c) =>
              (!activeOnly || c['active'] == 1) &&
              ContactSearch.matches(c, needle),
        )
        .toList();
    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              _t(
                'Shared contact list for your business branches.',
                'လုပ်ငန်း၏ ဆိုင်ခွဲများ မျှဝေသုံးသည့် ဆက်သွယ်ရန်စာရင်းဖြစ်ပါသည်။',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _t(
                  'Search customer ID, name, phone or company',
                  'Customer ID၊ အမည်၊ ဖုန်း၊ ကုမ္ပဏီဖြင့် ရှာရန်',
                ),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(_t('Active contacts only', 'အသုံးပြုဆဲစာရင်းသာ')),
            value: activeOnly,
            onChanged: (value) => setState(() => activeOnly = value),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(error!),
                        ),
                        TextButton(
                          onPressed: load,
                          child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                        ),
                      ],
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _t(
                        'No matching contacts. Tap + to add.',
                        'စာရင်းမတွေ့ပါ။ အသစ်ထည့်ရန် + ကိုနှိပ်ပါ။',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: DesktopListView.builder(
                      desktopColumns: const [
                        "Customer ID",
                        "Name",
                        "Phone",
                        "Company",
                        "Address",
                        "Status",
                      ],
                      desktopCells: (context, index) {
                        final r = visible[index];
                        return [
                          desktopCellText(
                            ContactSearch.code(r['id'], kind: widget.kind),
                          ),
                          desktopCellText(r['name']),
                          desktopCellText(r['phone']),
                          desktopCellText(r['company']),
                          desktopCellText(r['address']),
                          desktopActive(r['active']),
                        ];
                      },

                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final c = visible[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: DesktopListTile(
                            onTap: busy ? null : () => edit(c),
                            leading: Icon(
                              customer
                                  ? Icons.person_outline
                                  : Icons.local_shipping_outlined,
                            ),
                            title: Text("${c['name']} (#${c['id']})"),
                            subtitle: Text(
                              [
                                if (c['active'] == 0)
                                  _t('Inactive', 'အသုံးပြုမှုရပ်ထား'),
                                if ((c['company'] as String).isNotEmpty)
                                  c['company'] as String,
                                if ((c['phone'] as String).isNotEmpty)
                                  c['phone'] as String,
                                if ((c['address'] as String).isNotEmpty)
                                  c['address'] as String,
                              ].join('\n'),
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: loading || busy || error != null ? null : () => edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ContactForm extends StatefulWidget {
  const _ContactForm({required this.kind, this.contact});
  final String kind;
  final Map<String, Object?>? contact;
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController company;
  late final TextEditingController address;
  late final TextEditingController remark;
  late bool active;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    name = TextEditingController(text: c?['name'] as String? ?? '');
    phone = TextEditingController(text: c?['phone'] as String? ?? '');
    company = TextEditingController(text: c?['company'] as String? ?? '');
    address = TextEditingController(text: c?['address'] as String? ?? '');
    remark = TextEditingController(text: c?['remark'] as String? ?? '');
    active = c == null || c['active'] == 1;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    company.dispose();
    address.dispose();
    remark.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await AppDatabase.instance.saveContact(
        id: widget.contact?['id'] as int?,
        kind: widget.kind,
        name: name.text,
        phone: phone.text,
        company: company.text,
        address: address.text,
        remark: remark.text,
        active: active,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = _t(
          'Could not save. Please retry.',
          'မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။',
        );
      });
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label),
        validator: (s) => required && (s == null || s.trim().isEmpty)
            ? _t('Required', 'ဖြည့်ရန်လိုအပ်ပါသည်။')
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.kind == 'customer';
    final title = widget.contact == null
        ? (customer
              ? _t('Add Customer', 'ဝယ်သူအသစ်')
              : _t('Add Supplier', 'ပစ္စည်းပေးသွင်းသူအသစ်'))
        : (customer
              ? _t('Edit Customer', 'ဝယ်သူပြင်ရန်')
              : _t('Edit Supplier', 'ပစ္စည်းပေးသွင်းသူပြင်ရန်'));
    return PopScope(
      canPop: !saving,
      child: DesktopDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(name, _t('Name', 'အမည်'), required: true),
                  field(
                    phone,
                    _t('Phone', 'ဖုန်းနံပါတ်'),
                    maxLength: 80,
                    keyboard: TextInputType.phone,
                  ),
                  field(company, _t('Company', 'ကုမ္ပဏီ'), maxLength: 150),
                  field(
                    address,
                    _t('Address', 'လိပ်စာ'),
                    maxLength: 500,
                    maxLines: 3,
                    keyboard: TextInputType.multiline,
                  ),
                  field(
                    remark,
                    _t('Remark', 'မှတ်ချက်'),
                    maxLength: 500,
                    maxLines: 2,
                    keyboard: TextInputType.multiline,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Active', 'အသုံးပြုဆဲ')),
                    value: active,
                    onChanged: saving
                        ? null
                        : (value) => setState(() => active = value),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(
              saving ? _t('Saving...', 'သိမ်းနေသည်…') : _t('Save', 'သိမ်းမည်'),
            ),
          ),
        ],
      ),
    );
  }
}
