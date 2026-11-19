import 'app_database.dart';
import 'desktop_ui.dart';
import 'pos_ui.dart';
import 'amount_input.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'invoice_void_dialog.dart';
import 'other_money_repository.dart';
import 'report_repository.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _direction(String value) =>
    value == 'in' ? _t('Money in', 'ငွေအဝင်') : _t('Money out', 'ငွေအထွက်');

Future<int?> _chooseAccount(
  BuildContext context,
  List<Map<String, Object?>> accounts, {
  bool allowAll = false,
}) async {
  var query = '';
  return showDialog<int>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => DesktopDialog(
        title: Text(_t('Choose account', 'အကောင့်ရွေးရန်')),
        content: SizedBox(
          width: 480,
          height: 380,
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: _t(
                    'Search account / branch',
                    'အကောင့် / ဆိုင်ခွဲ ရှာရန်',
                  ),
                ),
                onChanged: (v) => update(() => query = v.toLowerCase()),
              ),
              Expanded(
                child: DesktopListView(
                  children: [
                    if (allowAll)
                      DesktopListTile(
                        title: Text(_t('All accounts', 'အကောင့်အားလုံး')),
                        onTap: () => Navigator.pop(dialog, -1),
                      ),
                    for (final a in accounts.where(
                      (a) => '${a['name']} ${a['branch_name']} ${a['type']}'
                          .toLowerCase()
                          .contains(query),
                    ))
                      DesktopListTile(
                        title: Text('${a['name']} · ${a['type']}'),
                        subtitle: Text(
                          '${a['branch_name']}\n${AppCurrency.format(a['balance'] as int)}',
                        ),
                        onTap: () => Navigator.pop(dialog, a['id'] as int),
                      ),
                  ],
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
        ],
      ),
    ),
  );
}

class OtherMoneyPage extends StatefulWidget {
  const OtherMoneyPage({super.key});
  @override
  State<OtherMoneyPage> createState() => _OtherMoneyPageState();
}

class _OtherMoneyPageState extends State<OtherMoneyPage> {
  List<Map<String, Object?>> branches = [],
      accounts = [],
      categories = [],
      records = [];
  int? branch, account;
  String direction = 'all';
  String? category;
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  final search = TextEditingController();
  bool loading = true, includeVoid = true;
  String? error, loadedLabels;
  int request = 0;
  @override
  void initState() {
    super.initState();
    initializeDefaultBranch();
  }

  Future<void> initializeDefaultBranch() async {
    try {
      branch ??= await AppDatabase.instance.getDefaultBranchId();
    } catch (_) {
      /* The normal load shows any storage error. */
    }
    if (mounted) await load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    final start = _date(from), end = _date(to), query = search.text;
    final selectedBranch = branch, selectedAccount = account;
    final selectedDirection = direction,
        selectedCategory = category,
        showVoid = includeVoid;
    try {
      final options = await OtherMoneyRepository.options();
      final rows = await OtherMoneyRepository.list(
        branch: selectedBranch,
        account: selectedAccount,
        direction: selectedDirection == 'all' ? null : selectedDirection,
        category: selectedCategory,
        from: start,
        to: end,
        search: query,
        includeVoid: showVoid,
      );
      if (!mounted || token != request) return;
      setState(() {
        branches = options['branches']!;
        accounts = options['accounts']!;
        categories = options['category_filters']!;
        records = rows;
        loading = false;
        loadedLabels =
            '$start to $end | Branch #${selectedBranch ?? 'All'} | Account #${selectedAccount ?? 'All'} | '
            'Direction: $selectedDirection | Category: ${selectedCategory ?? 'All'} | Search: $query | Include VOID: $showVoid';
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

  Future<void> date(bool first) async {
    final value = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (first) {
        from = value;
        if (to.isBefore(from)) to = from;
      } else {
        to = value;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> chooseAccount() async {
    final selected = await _chooseAccount(
      context,
      accounts
          .where((a) => branch == null || a['branch_id'] == branch)
          .toList(),
      allowAll: true,
    );
    if (selected == null || !mounted) return;
    setState(() => account = selected == -1 ? null : selected);
    await load();
  }

  Future<void> create() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const _MoneyForm()),
    );
    if (!mounted || id == null) return;
    await load();
    if (mounted) await open(id);
  }

  Future<void> open(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _MoneyDetail(id: id)),
    );
    if (mounted) await load();
  }

  void export() {
    final ids = records.map((r) => r['id'] as int).toList(),
        labels = loadedLabels ?? '';
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Other Money In / Out',
          load: () => OtherMoneyRepository.report(ids, labels),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = accounts.where((a) => a['id'] == account);
    return DesktopScaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: loading ? null : create,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: DesktopListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey(branch),
              initialValue: branch ?? -1,
              isExpanded: true,
              decoration: InputDecoration(labelText: _t('Branch', 'ဆိုင်ခွဲ')),
              items: [
                DropdownMenuItem(
                  value: -1,
                  child: Text(_t('All branches', 'ဆိုင်ခွဲအားလုံး')),
                ),
                for (final b in branches)
                  DropdownMenuItem(
                    value: b['id'] as int,
                    child: Text('${b['name']} (${b['code']})'),
                  ),
              ],
              onChanged: (v) {
                setState(() {
                  branch = v == -1 ? null : v;
                  account = null;
                });
                load();
              },
            ),
            DesktopListTile(
              title: Text(_t('Account', 'ငွေအကောင့်')),
              subtitle: Text(
                matches.isEmpty
                    ? _t('All accounts', 'အကောင့်အားလုံး')
                    : '${matches.first['name']}',
              ),
              trailing: const Icon(Icons.search),
              onTap: chooseAccount,
            ),
            DropdownButtonFormField<String>(
              initialValue: direction,
              decoration: InputDecoration(
                labelText: _t('Direction', 'အဝင် / အထွက်'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text(_t('Money in + out', 'အဝင် + အထွက်')),
                ),
                DropdownMenuItem(value: 'in', child: Text(_direction('in'))),
                DropdownMenuItem(value: 'out', child: Text(_direction('out'))),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => direction = v);
                  load();
                }
              },
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(category),
              initialValue: category ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(_t('All categories', 'Category အားလုံး')),
                ),
                for (final c in categories)
                  DropdownMenuItem(
                    value: c['name'] as String,
                    child: Text(c['name'] as String),
                  ),
              ],
              onChanged: (v) {
                setState(() => category = v == '' ? null : v);
                load();
              },
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => date(true),
                    child: Text(_date(from)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => date(false),
                    child: Text(_date(to)),
                  ),
                ),
              ],
            ),
            TextField(
              controller: search,
              onSubmitted: (_) => load(),
              decoration: InputDecoration(
                labelText: _t(
                  'Search voucher / description / account',
                  'ဘောင်ချာ / အကြောင်းအရာ / အကောင့် ရှာရန်',
                ),
                suffixIcon: IconButton(
                  onPressed: load,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            SwitchListTile(
              title: Text(_t('Include VOID', 'VOID ပါပြရန်')),
              value: includeVoid,
              onChanged: (v) {
                setState(() => includeVoid = v);
                load();
              },
            ),
            OutlinedButton.icon(
              onPressed: loading || error != null ? null : export,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Excel / PDF / Print'),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: load, child: Text('Retry: $error')),
            if (!loading && error == null && records.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _t(
                    'No money vouchers in this period. Tap + to add one.',
                    'ဤရက်အတွင်း စာရင်းမရှိပါ။ အသစ်ထည့်ရန် + နှိပ်ပါ။',
                  ),
                ),
              ),
            if (!loading && error == null)
              DesktopInlineTable(
                columns: const [
                  "Voucher",
                  "Date",
                  "Direction",
                  "Category",
                  "Description",
                  "Branch",
                  "Account",
                  "Amount",
                  "Status",
                ],
                rows: [
                  for (final row in records)
                    Card(
                      child: DesktopListTile(
                        leading: Icon(
                          row['status'] == 'void'
                              ? Icons.block
                              : row['direction'] == 'in'
                              ? Icons.south_west
                              : Icons.north_east,
                        ),
                        title: Text(
                          '${voucherNo('MIO', row['id'])} · ${_direction(row['direction'] as String)} · ${AppCurrency.format(row['amount'] as int)}',
                        ),
                        subtitle: Text(
                          '${row['category']}\n${row['description']}\n${row['branch_name']} / ${row['account_name']}\n${row['entry_date']} · ${row['status']}',
                        ),
                        onTap: () => open(row['id'] as int),
                      ),
                    ),
                ],
                cells: [
                  for (final row in records)
                    [
                      desktopCellText(voucherNo('MIO', row['id'])),
                      desktopCellText(row['entry_date']),
                      desktopCellText(_direction(row['direction'] as String)),
                      desktopCellText(row['category']),
                      desktopCellText(row['description']),
                      desktopCellText(row['branch_name']),
                      desktopCellText(row['account_name']),
                      desktopMoney(row['amount']),
                      desktopCellText(row['status']),
                    ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MoneyForm extends StatefulWidget {
  const _MoneyForm({this.initial});
  final Map<String, Object?>? initial;
  @override
  State<_MoneyForm> createState() => _MoneyFormState();
}

class _MoneyFormState extends State<_MoneyForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), description = TextEditingController();
  late final String requestKey =
      'other-money-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  List<Map<String, Object?>> accounts = [], categories = [];
  int? account;
  String direction = 'in', category = 'Other income';
  late DateTime day = AppDateTime.today();
  bool loading = true, saving = false, categoryInitialized = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final old = widget.initial;
    if (old != null) {
      account = old['account_id'] as int;
      direction = old['direction'] as String;
      category = old['category'] as String;
      categoryInitialized = true;
      amount.text = AppCurrency.input(old['amount'] as int);
      description.text = old['description'] as String;
      day = DateTime.parse(old['entry_date'] as String);
    }
    load();
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  String defaultCategory(String value) {
    final preferredId = value == 'in' ? 5 : 6;
    final active = categories.where((c) => c['active'] == 1).toList();
    final preferred = active.where((c) => c['id'] == preferredId);
    return preferred.isNotEmpty
        ? preferred.first['name'] as String
        : active.isEmpty
        ? ''
        : active.first['name'] as String;
  }

  Future<void> load() async {
    try {
      final options = await OtherMoneyRepository.options();
      if (mounted) {
        setState(() {
          accounts = options['accounts']!;
          categories = options['categories']!;
          loading = false;
          error = null;
          if (!categoryInitialized) {
            category = defaultCategory(direction);
            categoryInitialized = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> chooseAccount() async {
    final selected = await _chooseAccount(context, accounts);
    if (selected != null && mounted) setState(() => account = selected);
  }

  Future<void> chooseCategory() async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DesktopDialog(
          title: const Text('Category'),
          content: SizedBox(
            width: 480,
            height: 380,
            child: Column(
              children: [
                TextField(
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Search / enter new category',
                      'ရှာရန် / Category အသစ်ရေးရန်',
                    ),
                  ),
                  onChanged: (v) => update(() => query = v),
                ),
                Expanded(
                  child: DesktopListView(
                    children: [
                      for (final c in categories.where(
                        (c) =>
                            (c['active'] == 1 || c['name'] == category) &&
                            '${c['name']}'.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                      ))
                        DesktopListTile(
                          title: Text(c['name'] as String),
                          onTap: () =>
                              Navigator.pop(dialog, c['name'] as String),
                        ),
                    ],
                  ),
                ),
                if (query.trim().isNotEmpty &&
                    !categories.any(
                      (c) =>
                          '${c['name']}'.toLowerCase() ==
                          query.trim().toLowerCase(),
                    ))
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(dialog, query.trim()),
                    icon: const Icon(Icons.add),
                    label: Text(
                      _t('Use as new category', 'Category အသစ်အဖြစ် သုံးမည်'),
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
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => category = selected);
  }

  Future<void> date() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (selected != null && mounted) setState(() => day = selected);
  }

  Future<void> save() async {
    if (saving || loading || !form.currentState!.validate()) return;
    if (account == null || category.trim().isEmpty) {
      setState(
        () => error = _t(
          'Choose an account and category',
          'အကောင့်နှင့် အမျိုးအစားရွေးပါ',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await OtherMoneyRepository.save(
        id: widget.initial?['id'] as int?,
        expectedRevision: widget.initial?['revision'] as int?,
        requestKey: requestKey,
        account: account!,
        direction: direction,
        amount: AppCurrency.parse(amount.text),
        date: _date(day),
        category: category,
        description: description.text,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = accounts.where((a) => a['id'] == account);
    return PopScope(
      canPop: !saving,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(
            widget.initial == null
                ? _t('New Money In / Out', 'အခြားငွေအဝင် / အထွက်အသစ်')
                : _t('Edit Money Voucher', 'ငွေဘောင်ချာပြင်ရန်'),
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: form,
                child: DesktopListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _t(
                        'These entries change account balances. Record a sale, purchase or business expense in its own module to include it in the matching summary.',
                        'ဤစာရင်းက အကောင့်လက်ကျန်ကို ပြောင်းပေးပါသည်။ အရောင်း၊ အဝယ်၊ အသုံးစရိတ်များကို သက်ဆိုင်ရာစာရင်းချုပ်ထဲ ပါစေရန် မူရင်း module တွင် မှတ်ပါ။',
                      ),
                    ),
                    DesktopListTile(
                      title: Text(_t('Account', 'ငွေအကောင့်')),
                      subtitle: Text(
                        rows.isEmpty
                            ? _t('Choose account', 'အကောင့်ရွေးရန်')
                            : '${rows.first['branch_name']} / ${rows.first['name']}\n${AppCurrency.format(rows.first['balance'] as int)}',
                      ),
                      trailing: const Icon(Icons.search),
                      onTap: saving ? null : chooseAccount,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: direction,
                      decoration: InputDecoration(
                        labelText: _t('Direction', 'အဝင် / အထွက်'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'in',
                          child: Text(_direction('in')),
                        ),
                        DropdownMenuItem(
                          value: 'out',
                          child: Text(_direction('out')),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() {
                                  final wasDefault =
                                      category == defaultCategory(direction) ||
                                      category.isEmpty;
                                  direction = v;
                                  if (wasDefault) {
                                    category = defaultCategory(v);
                                  }
                                });
                              }
                            },
                    ),
                    DesktopListTile(
                      title: const Text('Category'),
                      subtitle: Text(
                        category.isEmpty
                            ? _t('Choose category', 'အမျိုးအစားရွေးရန်')
                            : category,
                      ),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: saving ? null : chooseCategory,
                    ),
                    TextFormField(
                      controller: description,
                      enabled: !saving,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Description / purpose',
                          'အကြောင်းအရာ / ရည်ရွယ်ချက်',
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: amount,
                      enabled: !saving,
                      inputFormatters: const [AmountInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${_t('Amount', 'ငွေပမာဏ')} (${AppCurrency.displayCode})',
                      ),
                      validator: (v) =>
                          (AppCurrency.tryParse(v ?? '') ?? 0) <= 0
                          ? _t('Enter a valid amount', 'ငွေပမာဏမှန်ထည့်ပါ')
                          : null,
                    ),
                    DesktopListTile(
                      title: Text('${_t('Date', 'ရက်စွဲ')}: ${_date(day)}'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: saving ? null : date,
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (saving) const LinearProgressIndicator(),
                    TextButton(
                      onPressed: saving ? null : load,
                      child: Text(
                        _t(
                          'Refresh account balances',
                          'အကောင့်လက်ကျန် ပြန်ဖတ်ရန်',
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: saving || accounts.isEmpty ? null : save,
                      child: Text(_t('Save voucher', 'ဘောင်ချာသိမ်းမည်')),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MoneyDetail extends StatefulWidget {
  const _MoneyDetail({required this.id});
  final int id;
  @override
  State<_MoneyDetail> createState() => _MoneyDetailState();
}

class _MoneyDetailState extends State<_MoneyDetail> {
  Map<String, Object?>? header;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final row = await OtherMoneyRepository.get(widget.id);
      if (mounted) {
        setState(() {
          header = row;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> edit() async {
    if (busy || header == null) return;
    setState(() => busy = true);
    try {
      await Navigator.push<int>(
        context,
        MaterialPageRoute(builder: (_) => _MoneyForm(initial: header)),
      );
      if (mounted) await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> voidVoucher() async {
    if (busy || header == null) return;
    setState(() => busy = true);
    try {
      final reason = await askInvoiceVoidReason(
        context,
        _t('Void money voucher?', 'ငွေဘောင်ချာကို VOID လုပ်မလား?'),
      );
      if (reason == null || !mounted) return;
      await OtherMoneyRepository.voidVoucher(
        id: widget.id,
        expectedRevision: header!['revision'] as int,
        reason: reason,
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> delete() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final removed = await deleteVoucherWithPrompt(
        context,
        kind: 'other_money',
        id: widget.id,
        number: voucherNo('MIO', widget.id),
      );
      if (removed && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void report() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: voucherNo('MIO', widget.id),
          load: () => OtherMoneyRepository.report([
            widget.id,
          ], 'Full voucher and revision history'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(voucherNo('MIO', widget.id)),
      actions: [
        if (header?['status'] == 'posted')
          IconButton(
            tooltip: _t('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
            icon: const Icon(Icons.lock_outline),
            onPressed: busy ? null : edit,
          ),
      ],
    ),
    body: header == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : TextButton(onPressed: load, child: Text('Retry: $error')),
          )
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_direction(header!['direction'] as String)} · ${header!['status']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              MoneyText(
                header!['amount'] as int,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              DesktopListTile(
                title: Text(_t('Account', 'ငွေအကောင့်')),
                subtitle: Text(
                  '${header!['branch_name']} / ${header!['account_name']}',
                ),
              ),
              DesktopListTile(
                title: const Text('Category'),
                subtitle: Text('${header!['category']}'),
              ),
              DesktopListTile(
                title: Text(_t('Description', 'အကြောင်းအရာ')),
                subtitle: Text('${header!['description']}'),
              ),
              Text('${_t('Date', 'ရက်စွဲ')}: ${header!['entry_date']}'),
              Text(
                '${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(header!['created_at'])}',
              ),
              if (header!['status'] == 'void')
                Text('VOID: ${header!['void_reason']}'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
              if (header!['status'] == 'posted')
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(_t('Edit', 'ပြင်ရန်')),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : voidVoucher,
                      icon: const Icon(Icons.undo),
                      label: const Text('VOID'),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : delete,
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(_t('Delete permanently', 'အပြီးတိုင်ဖျက်ရန်')),
              ),
              FilledButton.icon(
                onPressed: busy ? null : report,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Excel / PDF / Print / History'),
              ),
            ],
          ),
  );
}
