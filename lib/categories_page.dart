import 'branch_reuse.dart';
import 'branch_reuse_picker.dart';
import 'app_capabilities.dart';
import 'desktop_ui.dart';
import 'brands_page.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'categories_repository.dart';
import 'category_store.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _type(String kind) => switch (kind) {
  'product' => _t('Product categories', 'ပစ္စည်းအမျိုးအစားများ'),
  'expense' => _t('Expense categories', 'အသုံးစရိတ်အမျိုးအစားများ'),
  _ => _t('Other Money categories', 'အခြားငွေအဝင်/အထွက် အမျိုးအစားများ'),
};

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    super.key,
    this.initialKind = 'product',
    this.initialBranchId,
  });
  final String initialKind;
  final int? initialBranchId;
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  late String kind = widget.initialKind;
  late int? branch = widget.initialBranchId;
  List<Map<String, Object?>> branches = [], rows = [];
  final search = TextEditingController();
  bool archived = true, loading = true, busy = false;
  int request = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final token = ++request;
    final selectedKind = kind,
        selectedBranch = branch,
        query = search.text,
        showArchived = archived;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final all = await CategoriesRepository.branches();
      final preferred =
          selectedBranch ?? await AppDatabase.instance.getDefaultBranchId();
      final chosen = all.any((r) => r['id'] == preferred)
          ? preferred
          : (all.isEmpty ? null : all.first['id'] as int);
      final results = await CategoriesRepository.list(
        kind: selectedKind,
        branch: chosen,
        search: query,
        includeArchived: showArchived,
      );
      if (!mounted || token != request) return;
      setState(() {
        branches = all;
        branch = chosen;
        rows = results;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> reuseExpenseCategory() async {
    if (busy || loading || branch == null) return;
    final target = branch!;
    setState(() => busy = true);
    try {
      final available = await BranchReuse.expenseCategories(target);
      if (!mounted) return;
      final source = await pickBranchDefinition(
        context,
        title: _t(
          'Use an existing expense category',
          'ရှိပြီးသားအသုံးစရိတ်အမျိုးအစား သုံးရန်',
        ),
        rows: available,
      );
      if (source != null) {
        await BranchReuse.expenseCategory(source, target);
        if (mounted) await load();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, Object?>? row]) async {
    if (busy || loading) return;
    final selectedKind = kind, selectedBranch = branch;
    final maximum = CategoryStore.spec(selectedKind).$2;
    var value = row?['name'] as String? ?? '';
    final form = GlobalKey<FormState>();
    setState(() => busy = true);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialog) => DesktopDialog(
          title: Text(
            row == null
                ? _t('New category', 'အမျိုးအစားအသစ်')
                : _t('Rename category', 'အမျိုးအစားအမည် ပြင်ရန်'),
          ),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: value,
                  autofocus: true,
                  maxLength: maximum,
                  decoration: InputDecoration(labelText: _t('Name', 'အမည်')),
                  onChanged: (v) => value = v,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? _t('Enter a name', 'အမည်ထည့်ပါ')
                      : null,
                ),
                if (row != null)
                  Text(
                    _t(
                      'New selections use the new name. Existing voucher names remain as recorded.',
                      'အသစ်ရွေးရာတွင် အမည်အသစ်ကို သုံးပါမည်။ ဘောင်ချာအဟောင်း၏ အမည်ကို ဆက်ထိန်းပါမည်။',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_t('Cancel', 'မလုပ်တော့')),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialog, value.trim());
                }
              },
              child: Text(_t('Save', 'သိမ်းမည်')),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      await CategoriesRepository.save(
        kind: selectedKind,
        name: result,
        branch: selectedBranch,
        previous: row,
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(Map<String, Object?> row) async {
    if (busy || loading) return;
    final selectedKind = kind,
        selectedBranch = branch,
        restore = row['active'] != 1;
    setState(() => busy = true);
    try {
      final confirmed = restore
          ? true
          : await showDialog<bool>(
              context: context,
              builder: (dialog) => DesktopDialog(
                title: Text(
                  _t('Archive category?', 'အမျိုးအစားကို ပိတ်ထားမလား?'),
                ),
                content: Text(
                  '${row['name']}\n${_t('This hides it from new choices. Existing documents/products remain, and you can restore the category later.', 'အသစ်ရွေးချယ်စရာများမှ ဖျောက်ထားပါမည်။ ရှိပြီးသားစာရင်း/ပစ္စည်းများ ဆက်ရှိပြီး နောက်မှ Category ပြန်ဖွင့်နိုင်ပါသည်။')}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(_t('Cancel', 'မလုပ်တော့')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(_t('Archive', 'ပိတ်ထားမည်')),
                  ),
                ],
              ),
            );
      if (confirmed != true || !mounted) return;
      await CategoriesRepository.setActive(
        kind: selectedKind,
        branch: selectedBranch,
        previous: row,
        active: restore,
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Map<String, Object?> row) async {
    if (busy || loading) return;
    final selectedKind = kind, selectedBranch = branch;
    var typed = '';
    setState(() => busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => DesktopDialog(
            title: Text(
              _t(
                'Delete unused category?',
                'မသုံးရသေးသော အမျိုးအစားကို ဖျက်မလား?',
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t(
                    'Permanently delete this unused category. If it was used since this page loaded, it will be archived instead.',
                    'မသုံးရသေးသော အမျိုးအစားကို အပြီးတိုင်ဖျက်ပါမည်။ ဤစာမျက်နှာဖွင့်ပြီးနောက် အသုံးပြုထားပါက ပိတ်ထားပေးပါမည်။',
                  ),
                ),
                TextField(
                  onChanged: (v) => update(() => typed = v.trim()),
                  decoration: InputDecoration(
                    labelText:
                        '${_t('Type name to confirm', 'အတည်ပြုရန် အမည်ရိုက်ပါ')}: ${row['name']}',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(_t('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: typed == row['name']
                    ? () => Navigator.pop(dialog, true)
                    : null,
                child: Text(_t('Delete', 'ဖျက်မည်')),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await CategoriesRepository.remove(
        kind: selectedKind,
        branch: selectedBranch,
        previous: row,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'deleted'
                ? _t('Category deleted', 'အမျိုးအစား ဖျက်ပြီးပါပြီ')
                : _t(
                    'Used category archived',
                    'သုံးထားသော အမျိုးအစားကို ပိတ်ထားပြီးပါပြီ',
                  ),
          ),
        ),
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void report() {
    final selectedKind = kind,
        selectedBranch = branch,
        query = search.text,
        showArchived = archived;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Categories',
          load: () => CategoriesRepository.report(
            kind: selectedKind,
            branch: selectedBranch,
            search: query,
            includeArchived: showArchived,
            labels:
                'Type: $selectedKind | Scope: ${selectedKind == 'expense' ? 'Branch #$selectedBranch' : 'All branches'} | Search: $query | Include archived: $showArchived',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    floatingActionButton: FloatingActionButton(
      onPressed: busy || loading || (kind == 'expense' && branch == null)
          ? null
          : () => edit(),
      child: const Icon(Icons.add),
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: DesktopListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          if (kind == 'expense')
            TextButton.icon(
              onPressed: busy || loading || branch == null
                  ? null
                  : reuseExpenseCategory,
              icon: const Icon(Icons.copy_outlined),
              label: Text(
                _t(
                  'Use category from another branch',
                  'အခြားဆိုင်ခွဲမှ အမျိုးအစားသုံးရန်',
                ),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: kind,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('Category type', 'အမျိုးအစားစာရင်း'),
            ),
            items: [
              for (final k in ['product', 'expense', 'other_money'])
                DropdownMenuItem(value: k, child: Text(_type(k))),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) {
                      setState(() {
                        kind = v;
                        search.clear();
                      });
                      load();
                    }
                  },
          ),
          if (kind == 'product')
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BrandsPage()),
              ),
              icon: const Icon(Icons.sell_outlined),
              label: Text(
                _t(
                  'Manage brands within categories',
                  'Category အလိုက် Brand များ စီမံရန်',
                ),
              ),
            ),
          if (kind == 'expense' && branches.isNotEmpty)
            DropdownButtonFormField<int>(
              key: ValueKey(branch),
              initialValue: branch,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('Expense branch', 'အသုံးစရိတ် ဆိုင်ခွဲ'),
              ),
              items: [
                for (final b in branches)
                  DropdownMenuItem(
                    value: b['id'] as int,
                    child: Text('${b['name']} (${b['code']})'),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() => branch = v);
                      load();
                    },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              kind == 'expense'
                  ? _t(
                      'Expense categories belong to the selected branch.',
                      'အသုံးစရိတ်အမျိုးအစားများသည် ရွေးထားသောဆိုင်ခွဲအတွက် ဖြစ်သည်။',
                    )
                  : _t(
                      'These categories are shared by all branches.',
                      'ဤအမျိုးအစားများကို ဆိုင်ခွဲအားလုံးက မျှဝေသုံးပါသည်။',
                    ),
            ),
          ),
          TextField(
            controller: search,
            enabled: !busy,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: _t('Search name', 'အမည်ရှာရန်'),
              suffixIcon: IconButton(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(_t('Include archived', 'ပိတ်ထားသည်များပါ ပြရန်')),
            value: archived,
            onChanged: busy
                ? null
                : (v) {
                    setState(() => archived = v);
                    load();
                  },
          ),
          OutlinedButton.icon(
            onPressed: busy || loading || error != null ? null : report,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Excel / PDF / History'),
          ),
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(
              onPressed: busy ? null : load,
              child: Text('Retry: $error'),
            ),
          if (kind == 'expense' && branches.isEmpty)
            Text(_t('Add a branch first.', 'ဆိုင်ခွဲအရင်ထည့်ပါ။')),
          if (!loading && error == null && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _t(
                  'No matching categories. Tap + to add one.',
                  'ကိုက်ညီသော အမျိုးအစားမရှိပါ။ အသစ်ထည့်ရန် + နှိပ်ပါ။',
                ),
              ),
            ),
          if (!loading && error == null)
            if (AppCapabilities.windows)
              DesktopInlineTable(
                columns: const [
                  'Category',
                  'Status',
                  'Products',
                  'Vouchers',
                  'History',
                  'Draft lines',
                  'Protection',
                ],
                rows: [
                  for (final row in rows)
                    DesktopListTile(
                      onTap: busy ? null : () => edit(row),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _t('Rename', 'အမည်ပြင်ရန်'),
                            onPressed: busy ? null : () => edit(row),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                          ),
                          if (row['is_default'] != true || row['active'] != 1)
                            IconButton(
                              tooltip: row['active'] == 1
                                  ? _t('Archive', 'ပိတ်ထားရန်')
                                  : _t('Restore', 'ပြန်ဖွင့်ရန်'),
                              onPressed: busy ? null : () => toggle(row),
                              icon: Icon(
                                row['active'] == 1
                                    ? Icons.archive_outlined
                                    : Icons.unarchive_outlined,
                                size: 16,
                              ),
                            ),
                          if (row['is_default'] != true && row['used'] != true)
                            IconButton(
                              tooltip: _t('Delete', 'ဖျက်ရန်'),
                              onPressed: busy ? null : () => remove(row),
                              icon: const Icon(Icons.delete_outline, size: 16),
                            ),
                        ],
                      ),
                    ),
                ],
                cells: [
                  for (final row in rows)
                    [
                      desktopCellText(row['name']),
                      desktopActive(row['active']),
                      desktopCellText(row['product_refs']),
                      desktopCellText(row['document_refs']),
                      desktopCellText(row['history_refs']),
                      desktopCellText(row['draft_refs']),
                      desktopCellText(
                        row['uncertain'] == true
                            ? _t(
                                'Deletion blocked: unreadable history',
                                'မှတ်တမ်းဖတ်မရ၍ ဖျက်ခွင့်ပိတ်ထားသည်',
                              )
                            : row['is_default'] == true
                            ? 'Default'
                            : row['used'] == true
                            ? 'In use'
                            : '—',
                      ),
                    ],
                ],
              )
            else ...[
              for (final row in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['name']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          row['active'] == 1
                              ? _t('Active', 'အသုံးပြုနိုင်')
                              : _t('Archived', 'ပိတ်ထားသည်'),
                        ),
                        if (row['is_default'] == true)
                          Text(
                            _t(
                              'Default for products without another category. Keep available.',
                              'အခြားအမျိုးအစားမရွေးထားသော ပစ္စည်းများအတွက် Default ဖြစ်၍ ဆက်ဖွင့်ထားရပါမည်။',
                            ),
                          ),
                        Text(
                          '${_t('Products', 'ပစ္စည်း')}: ${row['product_refs']} · ${_t('Voucher references', 'ဘောင်ချာအညွှန်း')}: ${row['document_refs']}\n'
                          '${_t('History references', 'မှတ်တမ်းအညွှန်း')}: ${row['history_refs']} · ${_t('Unfinished purchase lines', 'ရေးလက်စအဝယ်လိုင်း')}: ${row['draft_refs']}',
                        ),
                        if (row['uncertain'] == true)
                          Text(
                            _t(
                              'Some history/draft data could not be read; deletion is blocked.',
                              'အချို့မှတ်တမ်း/ရေးလက်စကို ဖတ်မရသောကြောင့် ဖျက်ခွင့်ပိတ်ထားပါသည်။',
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: busy ? null : () => edit(row),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(_t('Rename', 'အမည်ပြင်ရန်')),
                            ),
                            if (row['is_default'] != true || row['active'] != 1)
                              TextButton.icon(
                                onPressed: busy ? null : () => toggle(row),
                                icon: Icon(
                                  row['active'] == 1
                                      ? Icons.archive_outlined
                                      : Icons.unarchive_outlined,
                                ),
                                label: Text(
                                  row['active'] == 1
                                      ? _t('Archive', 'ပိတ်ထားရန်')
                                      : _t('Restore', 'ပြန်ဖွင့်ရန်'),
                                ),
                              ),
                            if (row['is_default'] != true &&
                                row['used'] != true)
                              TextButton.icon(
                                onPressed: busy ? null : () => remove(row),
                                icon: const Icon(Icons.delete_forever_outlined),
                                label: Text(_t('Delete', 'ဖျက်ရန်')),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
        ],
      ),
    ),
  );
}
