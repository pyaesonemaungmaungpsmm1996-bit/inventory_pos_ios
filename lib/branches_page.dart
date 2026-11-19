import 'desktop_ui.dart';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_language.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});
  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  List<Map<String, Object?>> branches = [];
  int? defaultId;
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await AppDatabase.instance.getBranches();
      final id = await AppDatabase.instance.getDefaultBranchId();
      if (!mounted) return;
      setState(() {
        branches = rows;
        defaultId = id;
        loading = false;
        error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = _t('Could not load branches.', 'ဆိုင်ခွဲစာရင်း မဖတ်နိုင်ပါ။');
      });
    }
  }

  Future<void> edit([Map<String, Object?>? branch]) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BranchForm(branch: branch),
      );
      if (saved == true) await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> setDefault(int id) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await AppDatabase.instance.setDefaultBranch(id);
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not save default branch.',
                'မူလဆိုင်ခွဲ မသိမ်းနိုင်ပါ။',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DesktopScaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!),
                  TextButton(
                    onPressed: load,
                    child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _t(
                      'Tap a branch to edit. Tap the star to set the default branch for this device.',
                      'ဆိုင်ခွဲကိုနှိပ်ပြီး ပြင်နိုင်ပါသည်။ ကြယ်ကိုနှိပ်ပြီး ဤစက်အတွက် မူလဆိုင်ခွဲ သတ်မှတ်ပါ။',
                    ),
                  ),
                ),
                Expanded(
                  child: branches.isEmpty
                      ? Center(
                          child: Text(
                            _t(
                              'Tap + to add your first branch.',
                              'ပထမဆိုင်ခွဲထည့်ရန် + ကိုနှိပ်ပါ။',
                            ),
                          ),
                        )
                      : DesktopListView.builder(
                          desktopColumns: const [
                            "Code",
                            "Branch",
                            "Phone",
                            "Address",
                            "Default",
                          ],
                          desktopCells: (context, index) {
                            final r = branches[index];
                            return [
                              desktopCellText(r['code']),
                              desktopCellText(r['name']),
                              desktopCellText(r['phone']),
                              desktopCellText(r['address']),
                              desktopCellText(
                                r['id'] == defaultId ? 'Default' : '',
                              ),
                            ];
                          },

                          itemCount: branches.length,
                          itemBuilder: (context, index) {
                            final b = branches[index];
                            final isDefault = b['id'] == defaultId;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              child: DesktopListTile(
                                onTap: busy ? null : () => edit(b),
                                leading: const Icon(Icons.store_outlined),
                                title: Text('${b['name']} (${b['code']})'),
                                subtitle: Text(
                                  [
                                    if (isDefault)
                                      _t('Default branch', 'မူလဆိုင်ခွဲ'),
                                    if ((b['phone'] as String).isNotEmpty)
                                      b['phone'] as String,
                                    if ((b['address'] as String).isNotEmpty)
                                      b['address'] as String,
                                  ].join('\n'),
                                ),
                                trailing: IconButton(
                                  tooltip: _t(
                                    'Set as default',
                                    'မူလဆိုင်ခွဲ သတ်မှတ်ရန်',
                                  ),
                                  onPressed: busy || isDefault
                                      ? null
                                      : () => setDefault(b['id'] as int),
                                  icon: Icon(
                                    isDefault ? Icons.star : Icons.star_border,
                                  ),
                                ),
                              ),
                            );
                          },
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

class _BranchForm extends StatefulWidget {
  const _BranchForm({this.branch});
  final Map<String, Object?>? branch;
  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController code;
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController address;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    code = TextEditingController(text: widget.branch?['code'] as String? ?? '');
    name = TextEditingController(text: widget.branch?['name'] as String? ?? '');
    phone = TextEditingController(
      text: widget.branch?['phone'] as String? ?? '',
    );
    address = TextEditingController(
      text: widget.branch?['address'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await AppDatabase.instance.saveBranch(
        id: widget.branch?['id'] as int?,
        code: code.text,
        name: name.text,
        phone: phone.text,
        address: address.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e is DatabaseException && e.isUniqueConstraintError()
            ? _t(
                'This branch code already exists.',
                'ဤဆိုင်ခွဲကုဒ် ရှိပြီးသားဖြစ်ပါသည်။',
              )
            : _t('Could not save. Please retry.', 'မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။');
      });
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int maxLength = 100,
    TextInputType? keyboard,
    int? lines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLength: maxLength,
        keyboardType: keyboard,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            required && (value == null || value.trim().isEmpty)
            ? _t('Required', 'ဖြည့်ရန်လိုအပ်ပါသည်။')
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !saving,
      child: DesktopDialog(
        title: Text(
          widget.branch == null
              ? _t('Add Branch', 'ဆိုင်ခွဲအသစ်')
              : _t('Edit Branch', 'ဆိုင်ခွဲပြင်ရန်'),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(
                  code,
                  _t('Branch code (blank = automatic)', 'ဆိုင်ခွဲကုဒ်'),
                  maxLength: 30,
                ),
                field(name, _t('Branch name', 'ဆိုင်ခွဲအမည်'), required: true),
                field(
                  phone,
                  _t(
                    'Phone numbers · one per line',
                    'ဖုန်းနံပါတ်များ · တစ်ကြောင်းတစ်ခု',
                  ),
                  maxLength: 2000,
                  keyboard: TextInputType.multiline,
                  lines: null,
                ),
                field(
                  address,
                  _t('Address', 'လိပ်စာ'),
                  maxLength: 300,
                  keyboard: TextInputType.streetAddress,
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
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
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
