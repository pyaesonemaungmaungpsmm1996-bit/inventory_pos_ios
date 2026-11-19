import 'desktop_ui.dart';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_language.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});
  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<Map<String, Object?>> branches = [];
  List<Map<String, Object?>> employees = [];
  int? branchId;
  bool loading = true;
  bool busy = false;
  bool activeOnly = false;
  String search = '';
  String? error;
  int request = 0;

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
      final db = AppDatabase.instance;
      final branchRows = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final selected = branchRows.any((b) => b['id'] == preferred)
          ? preferred
          : (branchRows.isEmpty ? null : branchRows.first['id'] as int);
      final rows = selected == null
          ? <Map<String, Object?>>[]
          : await db.getEmployees(branchId: selected);
      if (!mounted || ticket != request) return;
      setState(() {
        branches = branchRows;
        branchId = selected;
        employees = rows;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t(
          'Could not load employees. Please retry.',
          'ဝန်ထမ်းစာရင်း မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
        );
      });
    }
  }

  Future<void> edit([Map<String, Object?>? employee]) async {
    if (busy || loading || branchId == null) return;
    setState(() => busy = true);
    try {
      final savedBranch = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EmployeeForm(
          branches: branches,
          initialBranchId: branchId!,
          employee: employee,
        ),
      );
      if (savedBranch != null && mounted) {
        setState(() => branchId = savedBranch);
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = search.trim().toLowerCase();
    final visible = employees
        .where(
          (e) =>
              (!activeOnly || e['active'] == 1) &&
              [
                'code',
                'name',
                'phone',
                'position',
              ].any((key) => (e[key] as String).toLowerCase().contains(needle)),
        )
        .toList();
    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButton<int>(
              value: branches.any((b) => b['id'] == branchId) ? branchId : null,
              isExpanded: true,
              hint: Text(_t('Select branch', 'ဆိုင်ခွဲရွေးရန်')),
              items: branches
                  .map(
                    (b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text(
                        "${b['name']} (${b['code']})",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: loading || busy
                  ? null
                  : (id) {
                      if (id == null || id == branchId) return;
                      setState(() {
                        branchId = id;
                        employees = [];
                      });
                      load();
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => search = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _t(
                  'Search name, code or phone',
                  'အမည်၊ ကုဒ်၊ ဖုန်းဖြင့် ရှာရန်',
                ),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(
              _t('Active employees only', 'အသုံးပြုဆဲ ဝန်ထမ်းများသာ'),
            ),
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
                : branches.isEmpty
                ? Center(
                    child: Text(
                      _t('Add a branch first.', 'ဆိုင်ခွဲအရင်ထည့်ပါ။'),
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _t(
                        'No matching employees. Tap + to add.',
                        'ဝန်ထမ်းမတွေ့ပါ။ အသစ်ထည့်ရန် + ကိုနှိပ်ပါ။',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: DesktopListView.builder(
                      desktopColumns: const [
                        "Code",
                        "Name",
                        "Position",
                        "Phone",
                        "Status",
                      ],
                      desktopCells: (context, index) {
                        final r = visible[index];
                        return [
                          desktopCellText(r['code']),
                          desktopCellText(r['name']),
                          desktopCellText(r['position']),
                          desktopCellText(r['phone']),
                          desktopActive(r['active']),
                        ];
                      },

                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final e = visible[index];
                        final active = e['active'] == 1;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: DesktopListTile(
                            onTap: busy ? null : () => edit(e),
                            leading: Icon(
                              active
                                  ? Icons.badge_outlined
                                  : Icons.person_off_outlined,
                            ),
                            title: Text("${e['name']} (${e['code']})"),
                            subtitle: Text(
                              [
                                active
                                    ? _t('Active', 'အသုံးပြုဆဲ')
                                    : _t('Inactive', 'အသုံးပြုမှုရပ်ထား'),
                                if ((e['position'] as String).isNotEmpty)
                                  e['position'] as String,
                                if ((e['phone'] as String).isNotEmpty)
                                  e['phone'] as String,
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
        onPressed: loading || busy || branchId == null || error != null
            ? null
            : () => edit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({
    required this.branches,
    required this.initialBranchId,
    this.employee,
  });
  final List<Map<String, Object?>> branches;
  final int initialBranchId;
  final Map<String, Object?>? employee;
  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController code;
  late final TextEditingController name;
  late final TextEditingController phone;
  late final TextEditingController position;
  late final TextEditingController remark;
  late int branchId;
  late bool active;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    code = TextEditingController(text: e?['code'] as String? ?? '');
    name = TextEditingController(text: e?['name'] as String? ?? '');
    phone = TextEditingController(text: e?['phone'] as String? ?? '');
    position = TextEditingController(text: e?['position'] as String? ?? '');
    remark = TextEditingController(text: e?['remark'] as String? ?? '');
    branchId = e?['default_branch_id'] as int? ?? widget.initialBranchId;
    active = e == null || e['active'] == 1;
  }

  @override
  void dispose() {
    code.dispose();
    name.dispose();
    phone.dispose();
    position.dispose();
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
      await AppDatabase.instance.saveEmployee(
        id: widget.employee?['id'] as int?,
        code: code.text,
        name: name.text,
        phone: phone.text,
        position: position.text,
        branchId: branchId,
        active: active,
        remark: remark.text,
      );
      if (!mounted) return;
      Navigator.pop(context, branchId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e is DatabaseException && e.isUniqueConstraintError()
            ? _t(
                'This employee code already exists.',
                'ဤဝန်ထမ်းကုဒ် ရှိပြီးသားဖြစ်ပါသည်။',
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLength: maxLength,
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
    return PopScope(
      canPop: !saving,
      child: DesktopDialog(
        title: Text(
          widget.employee == null
              ? _t('Add Employee', 'ဝန်ထမ်းအသစ်')
              : _t('Edit Employee', 'ဝန်ထမ်းပြင်ရန်'),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: branchId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('Default Branch', 'မူလဆိုင်ခွဲ'),
                    ),
                    items: widget.branches
                        .map(
                          (b) => DropdownMenuItem<int>(
                            value: b['id'] as int,
                            child: Text(
                              "${b['name']} (${b['code']})",
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (id) {
                            if (id != null) setState(() => branchId = id);
                          },
                  ),
                  field(
                    code,
                    _t('Employee Code', 'ဝန်ထမ်းကုဒ်'),
                    required: true,
                    maxLength: 30,
                  ),
                  field(
                    name,
                    _t('Employee Name', 'ဝန်ထမ်းအမည်'),
                    required: true,
                  ),
                  field(
                    phone,
                    _t('Phone', 'ဖုန်းနံပါတ်'),
                    maxLength: 40,
                    keyboard: TextInputType.phone,
                  ),
                  field(
                    position,
                    _t(
                      'Position (not app permissions)',
                      'ရာထူး (App အသုံးပြုခွင့်မဟုတ်ပါ)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Active', 'အသုံးပြုဆဲ')),
                    value: active,
                    onChanged: saving
                        ? null
                        : (value) => setState(() => active = value),
                  ),
                  field(remark, _t('Remark', 'မှတ်ချက်'), maxLength: 300),
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
