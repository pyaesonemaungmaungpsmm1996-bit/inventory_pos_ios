import 'app_database.dart';
import 'desktop_ui.dart';
import 'pos_ui.dart';
import 'amount_input.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'balance_check_repository.dart';
import 'invoice_void_dialog.dart';
import 'report_repository.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _status(String value) => switch (value) {
  'open' => _t('Open count', 'စစ်ဆေးမှတ်တမ်း'),
  'adjusted' => _t('Applied / checked', 'ညှိပြီး / စစ်ပြီး'),
  _ => 'VOID',
};

Future<int?> _accountPicker(
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
          height: 360,
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
                    for (final row in accounts.where(
                      (r) => '${r['name']} ${r['branch_name']} ${r['type']}'
                          .toLowerCase()
                          .contains(query),
                    ))
                      DesktopListTile(
                        title: Text('${row['name']} · ${row['type']}'),
                        subtitle: Text(
                          '${row['branch_name']}\n${AppCurrency.format(row['balance'] as int)}',
                        ),
                        onTap: () => Navigator.pop(dialog, row['id'] as int),
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

class BalanceCheckPage extends StatefulWidget {
  const BalanceCheckPage({super.key});
  @override
  State<BalanceCheckPage> createState() => _BalanceCheckPageState();
}

class _BalanceCheckPageState extends State<BalanceCheckPage> {
  List<Map<String, Object?>> branches = [], accounts = [], records = [];
  int? branch, account;
  String status = 'all';
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  final search = TextEditingController();
  bool loading = true;
  int request = 0;
  String? error, labels;
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
    final first = _date(from), last = _date(to), query = search.text;
    final selectedBranch = branch,
        selectedAccount = account,
        selectedStatus = status;
    try {
      final options = await BalanceCheckRepository.options();
      final rows = await BalanceCheckRepository.list(
        branch: selectedBranch,
        account: selectedAccount,
        status: selectedStatus == 'all' ? null : selectedStatus,
        from: first,
        to: last,
        search: query,
      );
      if (!mounted || token != request) return;
      setState(() {
        branches = options['branches']!;
        accounts = options['accounts']!;
        records = rows;
        loading = false;
        labels =
            '$first to $last | Branch #${selectedBranch ?? 'All'} | Account #${selectedAccount ?? 'All'} | Status: $selectedStatus | Search: $query';
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
    final chosen = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      if (first) {
        from = chosen;
        if (to.isBefore(from)) to = from;
      } else {
        to = chosen;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> chooseAccount() async {
    final chosen = await _accountPicker(
      context,
      accounts
          .where((a) => branch == null || a['branch_id'] == branch)
          .toList(),
      allowAll: true,
    );
    if (chosen == null || !mounted) return;
    setState(() => account = chosen == -1 ? null : chosen);
    await load();
  }

  Future<void> create() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const _CheckForm()),
    );
    if (!mounted || id == null) return;
    await load();
    if (mounted) await open(id);
  }

  Future<void> open(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _CheckDetail(id: id)),
    );
    if (mounted) await load();
  }

  void export() {
    final ids = records.map((r) => r['id'] as int).toList(),
        caption = labels ?? '';
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Balance Checks',
          load: () => BalanceCheckRepository.report(ids, caption),
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
              initialValue: status,
              decoration: InputDecoration(labelText: _t('Status', 'အခြေအနေ')),
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text(_t('All statuses', 'အခြေအနေအားလုံး')),
                ),
                for (final s in ['open', 'adjusted', 'void'])
                  DropdownMenuItem(value: s, child: Text(_status(s))),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => status = v);
                  load();
                }
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
                  'Search check / note / account',
                  'စစ်ဆေးမှတ်တမ်း / မှတ်ချက် / အကောင့် ရှာရန်',
                ),
                suffixIcon: IconButton(
                  onPressed: load,
                  icon: const Icon(Icons.search),
                ),
              ),
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
                    'No checks in this period. Tap + to count an account.',
                    'ဤရက်အတွင်း မှတ်တမ်းမရှိပါ။ အကောင့်စစ်ရန် + နှိပ်ပါ။',
                  ),
                ),
              ),
            if (!loading && error == null)
              DesktopInlineTable(
                columns: const [
                  "Voucher",
                  "Date",
                  "Branch",
                  "Account",
                  "Book balance",
                  "Actual balance",
                  "Difference",
                  "Status",
                ],
                rows: [
                  for (final row in records)
                    Card(
                      child: DesktopListTile(
                        leading: Icon(
                          row['status'] == 'void'
                              ? Icons.block
                              : row['status'] == 'adjusted'
                              ? Icons.check_circle_outline
                              : Icons.fact_check_outlined,
                        ),
                        title: Text(
                          '${voucherNo('BLC', row['id'])} · ${_status(row['status'] as String)}',
                        ),
                        subtitle: Text(
                          '${row['branch_name']} / ${row['account_name']}\n${row['check_date']}\n'
                          '${_t('Book', 'စာရင်းလက်ကျန်')}: ${AppCurrency.format(row['book_balance'] as int)} · '
                          '${_t('Actual', 'တကယ်ရှိငွေ')}: ${AppCurrency.format(row['actual_balance'] as int)}\n'
                          '${_t('Difference', 'ကွာဟချက်')}: ${AppCurrency.format(row['difference'] as int)}',
                        ),
                        onTap: () => open(row['id'] as int),
                      ),
                    ),
                ],
                cells: [
                  for (final row in records)
                    [
                      desktopCellText(voucherNo('BLC', row['id'])),
                      desktopCellText(row['check_date']),
                      desktopCellText(row['branch_name']),
                      desktopCellText(row['account_name']),
                      desktopMoney(row['book_balance']),
                      desktopMoney(row['actual_balance']),
                      desktopMoney(row['difference']),
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

class _CheckForm extends StatefulWidget {
  const _CheckForm({this.initial});
  final Map<String, Object?>? initial;
  @override
  State<_CheckForm> createState() => _CheckFormState();
}

class _CheckFormState extends State<_CheckForm> {
  final form = GlobalKey<FormState>();
  final actual = TextEditingController(),
      note = TextEditingController(),
      reason = TextEditingController();
  late final String requestKey =
      'balance-check-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  List<Map<String, Object?>> accounts = [];
  int? account;
  late DateTime day = AppDateTime.today();
  Map<String, Object?>? bookSnapshot;
  bool loading = true, previewBusy = false, saving = false;
  int previewRequest = 0;
  String? error;
  bool get applied => widget.initial?['status'] == 'adjusted';
  @override
  void initState() {
    super.initState();
    final old = widget.initial;
    if (old != null) {
      account = old['account_id'] as int;
      day = DateTime.parse(old['check_date'] as String);
      actual.text = AppCurrency.input(old['actual_balance'] as int);
      note.text = old['note'] as String;
      reason.text = (old['adjust_reason'] as String).trim().isEmpty
          ? 'Edited using voucher unlock'
          : old['adjust_reason'] as String;
    }
    load();
  }

  @override
  void dispose() {
    actual.dispose();
    note.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final options = await BalanceCheckRepository.options();
      if (!mounted) return;
      setState(() {
        accounts = options['accounts']!;
        loading = false;
      });
      await refreshSnapshot();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> refreshSnapshot() async {
    final token = ++previewRequest;
    setState(() {
      bookSnapshot = null;
      previewBusy = account != null;
      error = null;
    });
    if (account == null) return;
    try {
      final value = await BalanceCheckRepository.snapshot(
        account!,
        _date(day),
        excluding: widget.initial?['id'] as int?,
      );
      if (!mounted || token != previewRequest) return;
      setState(() {
        bookSnapshot = value;
        previewBusy = false;
      });
    } catch (e) {
      if (mounted && token == previewRequest) {
        setState(() {
          previewBusy = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> chooseAccount() async {
    final selected = await _accountPicker(context, accounts);
    if (selected == null || !mounted) return;
    setState(() => account = selected);
    await refreshSnapshot();
  }

  Future<void> date() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (selected == null || !mounted) return;
    setState(() => day = selected);
    await refreshSnapshot();
  }

  Future<void> save() async {
    if (saving || loading || previewBusy || !form.currentState!.validate()) {
      return;
    }
    if (account == null || bookSnapshot == null) {
      setState(
        () => error = _t(
          'Choose account and refresh the book balance',
          'အကောင့်ရွေးပြီး စာရင်းလက်ကျန် ပြန်ဖတ်ပါ',
        ),
      );
      return;
    }
    final snap = Map<String, Object?>.of(bookSnapshot!);
    final counted = AppCurrency.parse(actual.text);
    final difference = balanceCheckDifference(
      snap['book_balance'] as int,
      counted,
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (applied) {
        final approved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialog) => DesktopDialog(
            title: Text(
              _t(
                'Replace applied adjustment?',
                'ညှိပြီးသော စာရင်းကို ပြန်ပြင်မလား?',
              ),
            ),
            content: Text(
              '${snap['branch_name']} / ${snap['account_name']}\n'
              '${_t('Book excluding this check', 'ဤစစ်ဆေးမှု၏ ညှိငွေမပါသောလက်ကျန်')}: ${AppCurrency.format(snap['book_balance'] as int)}\n'
              '${_t('Actual', 'တကယ်ရှိငွေ')}: ${AppCurrency.format(counted)}\n'
              '${_t('New adjustment', 'ညှိငွေအသစ်')}: ${AppCurrency.format(difference)}\n'
              '${_t('Previous adjustment', 'မူရင်းညှိငွေ')}: ${AppCurrency.format(widget.initial!['difference'] as int)}\n\n'
              '${_t('This reverses the previous adjustment on its old date and posts the corrected one on the selected date. Verify the actual balance after any other transactions.', 'ဤလုပ်ဆောင်မှုက မူရင်းညှိငွေကို အဟောင်းရက်တွင် ပြန်လှန်ပြီး အသစ်ကို ရွေးထားသောရက်တွင် တင်ပါမည်။ အခြားငွေလှုပ်ရှားမှုများရှိပါက တကယ်ရှိငွေကို ပြန်စစ်ပါ။')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(_t('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(_t('Confirm correction', 'ပြင်ဆင်မှု အတည်ပြုမည်')),
              ),
            ],
          ),
        );
        if (approved != true || !mounted) return;
      }
      final id = await BalanceCheckRepository.save(
        id: widget.initial?['id'] as int?,
        expectedRevision: widget.initial?['revision'] as int?,
        requestKey: requestKey,
        account: account!,
        date: _date(day),
        actual: counted,
        expectedBook: snap['book_balance'] as int,
        expectedEntry: snap['snapshot_entry_id'] as int,
        note: note.text,
        reason: reason.text,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = accounts.where((a) => a['id'] == account);
    final counted = AppCurrency.tryParse(actual.text);
    final difference = counted == null || bookSnapshot == null
        ? null
        : balanceCheckDifference(bookSnapshot!['book_balance'] as int, counted);
    return PopScope(
      canPop: !saving,
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(
            widget.initial == null
                ? _t('New Balance Check', 'လက်ကျန်စစ်ဆေးမှုအသစ်')
                : _t('Edit Balance Check', 'လက်ကျန်စစ်ဆေးမှု ပြင်ရန်'),
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
                      applied
                          ? _t(
                              'Saving this applied check corrects its existing adjustment after confirmation.',
                              'ဤညှိပြီးမှတ်တမ်းကို သိမ်းလျှင် အတည်ပြုပြီးမှ မူရင်းညှိငွေကို ပြန်ပြင်ပါမည်။',
                            )
                          : _t(
                              'Saving records the count only. Apply the difference separately after verifying it.',
                              'သိမ်းခြင်းက စစ်ထားသောငွေကို မှတ်ထားရုံသာဖြစ်သည်။ ကွာဟချက်ကို စစ်ပြီးမှ သီးခြား Apply လုပ်ပါ။',
                            ),
                    ),
                    DesktopListTile(
                      title: Text(_t('Account', 'ငွေအကောင့်')),
                      subtitle: Text(
                        rows.isEmpty
                            ? _t('Choose account', 'အကောင့်ရွေးရန်')
                            : '${rows.first['branch_name']} / ${rows.first['name']}',
                      ),
                      trailing: const Icon(Icons.search),
                      onTap: saving ? null : chooseAccount,
                    ),
                    DesktopListTile(
                      title: Text(
                        '${_t('Check date', 'စစ်ဆေးရက်')}: ${_date(day)}',
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: saving ? null : date,
                    ),
                    if (previewBusy) const LinearProgressIndicator(),
                    if (bookSnapshot != null)
                      DesktopListTile(
                        title: Text(
                          _t(
                            'Book balance before this adjustment',
                            'ဤညှိငွေမပါသော စာရင်းလက်ကျန်',
                          ),
                        ),
                        subtitle: MoneyText(
                          bookSnapshot!['book_balance'] as int,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: saving ? null : refreshSnapshot,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _t('Refresh book balance', 'စာရင်းလက်ကျန် ပြန်ဖတ်ရန်'),
                      ),
                    ),
                    TextFormField(
                      controller: actual,
                      enabled: !saving,
                      inputFormatters: const [AmountInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${_t('Actual counted / statement balance', 'တကယ်ရှိငွေ / Statement လက်ကျန်')} (${AppCurrency.displayCode})',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => AppCurrency.tryParse(v ?? '') == null
                          ? _t(
                              'Enter actual balance; zero is allowed',
                              'တကယ်ရှိငွေ ထည့်ပါ။ သုညလည်း ရပါသည်။',
                            )
                          : null,
                    ),
                    if (difference != null)
                      DesktopListTile(
                        title: Text(
                          _t(
                            'Difference: actual − book',
                            'ကွာဟချက်: တကယ်ရှိငွေ − စာရင်းလက်ကျန်',
                          ),
                        ),
                        subtitle: MoneyText(
                          difference,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    TextFormField(
                      controller: note,
                      enabled: !saving,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Count note / statement reference',
                          'စစ်ဆေးမှတ်ချက် / Statement အညွှန်း',
                        ),
                      ),
                    ),
                    if (applied && widget.initial == null)
                      TextFormField(
                        controller: reason,
                        enabled: !saving,
                        maxLength: 300,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: _t(
                            'Adjustment reason',
                            'ညှိရသည့်အကြောင်းရင်း',
                          ),
                        ),
                        validator: (v) =>
                            difference != null &&
                                difference != 0 &&
                                (v ?? '').trim().isEmpty
                            ? _t('Enter a reason', 'အကြောင်းရင်းထည့်ပါ')
                            : null,
                      ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (saving) const LinearProgressIndicator(),
                    FilledButton(
                      onPressed: saving || previewBusy || bookSnapshot == null
                          ? null
                          : save,
                      child: Text(
                        applied
                            ? _t(
                                'Review and save correction',
                                'ပြင်ဆင်မှု စစ်ပြီးသိမ်းမည်',
                              )
                            : _t('Save check only', 'စစ်ဆေးမှတ်တမ်း သိမ်းမည်'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CheckDetail extends StatefulWidget {
  const _CheckDetail({required this.id});
  final int id;
  @override
  State<_CheckDetail> createState() => _CheckDetailState();
}

class _CheckDetailState extends State<_CheckDetail> {
  Map<String, Object?>? header;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final row = await BalanceCheckRepository.get(widget.id);
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
        MaterialPageRoute(builder: (_) => _CheckForm(initial: header)),
      );
      if (mounted) await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    if (busy || header == null) return;
    final row = Map<String, Object?>.of(header!);
    final key = GlobalKey<FormState>();
    var reason = '';
    final difference = row['difference'] as int;
    setState(() => busy = true);
    try {
      final approved = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => DesktopDialog(
          title: Text(
            difference == 0
                ? _t(
                    'Confirm matched balance?',
                    'လက်ကျန်ကိုက်ညီမှု အတည်ပြုမလား?',
                  )
                : _t('Apply balance adjustment?', 'လက်ကျန်ညှိမလား?'),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['branch_name']} / ${row['account_name']}\n${row['check_date']}\n'
                    '${_t('Book', 'စာရင်းလက်ကျန်')}: ${AppCurrency.format(row['book_balance'] as int)}\n'
                    '${_t('Actual', 'တကယ်ရှိငွေ')}: ${AppCurrency.format(row['actual_balance'] as int)}\n'
                    '${_t('Adjustment', 'ညှိငွေ')}: ${AppCurrency.format(difference)}',
                  ),
                  if (difference != 0)
                    TextFormField(
                      maxLength: 300,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Adjustment reason',
                          'ညှိရသည့်အကြောင်းရင်း',
                        ),
                      ),
                      onChanged: (v) => reason = v,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? _t('Enter a reason', 'အကြောင်းရင်းထည့်ပါ')
                          : null,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_t('Cancel', 'မလုပ်တော့')),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) {
                  Navigator.pop(dialog, reason.trim());
                }
              },
              child: Text(_t('Confirm', 'အတည်ပြုမည်')),
            ),
          ],
        ),
      );
      if (approved == null || !mounted) return;
      await BalanceCheckRepository.apply(
        id: widget.id,
        expectedRevision: row['revision'] as int,
        reason: approved,
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> voidCheck() async {
    if (busy || header == null) return;
    setState(() => busy = true);
    try {
      final reason = await askInvoiceVoidReason(
        context,
        _t('Void balance check?', 'လက်ကျန်စစ်ဆေးမှုကို VOID လုပ်မလား?'),
      );
      if (reason == null || !mounted) return;
      await BalanceCheckRepository.voidCheck(
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
        kind: 'balance_check',
        id: widget.id,
        number: voucherNo('BLC', widget.id),
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
          title: voucherNo('BLC', widget.id),
          load: () => BalanceCheckRepository.report([
            widget.id,
          ], 'Full count and adjustment history'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(voucherNo('BLC', widget.id)),
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
                _status(header!['status'] as String),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DesktopListTile(
                title: Text(_t('Account', 'ငွေအကောင့်')),
                subtitle: Text(
                  '${header!['branch_name']} / ${header!['account_name']}',
                ),
              ),
              Text(
                '${_t('Check date', 'စစ်ဆေးရက်')}: ${header!['check_date']}',
              ),
              DesktopListTile(
                title: Text(
                  _t(
                    'Book before this adjustment',
                    'ဤညှိငွေမပါသော စာရင်းလက်ကျန်',
                  ),
                ),
                subtitle: MoneyText(header!['book_balance'] as int),
              ),
              DesktopListTile(
                title: Text(_t('Actual counted', 'စစ်ထားသော တကယ်ရှိငွေ')),
                subtitle: MoneyText(header!['actual_balance'] as int),
              ),
              DesktopListTile(
                title: Text(_t('Difference', 'ကွာဟချက်')),
                subtitle: MoneyText(
                  header!['difference'] as int,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text('${header!['note']}'),
              if ((header!['adjust_reason'] as String).isNotEmpty)
                Text(
                  '${_t('Adjustment reason', 'ညှိရသည့်အကြောင်းရင်း')}: ${header!['adjust_reason']}',
                ),
              Text(
                '${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(header!['created_at'])}',
              ),
              if (header!['applied_at'] != null)
                Text(
                  '${_t('Applied at', 'ညှိချိန်')}: ${AppDateTime.format(header!['applied_at'])}',
                ),
              if (header!['status'] == 'void')
                Text('VOID: ${header!['void_reason']}'),
              Text(
                _t(
                  'This is a recorded count snapshot. Later transactions can change the live account balance.',
                  'ဤမှတ်တမ်းသည် စစ်ထားသည့်အချိန်က လက်ကျန်ဖြစ်သည်။ နောက်ထပ်ငွေလှုပ်ရှားမှုများကြောင့် လက်ရှိငွေ ပြောင်းနိုင်ပါသည်။',
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
              if (header!['status'] == 'open')
                FilledButton.icon(
                  onPressed: busy ? null : apply,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    header!['difference'] == 0
                        ? _t(
                            'Confirm matched balance',
                            'လက်ကျန်ကိုက်ညီမှု အတည်ပြုရန်',
                          )
                        : _t('Apply adjustment', 'ကွာဟချက် ညှိရန်'),
                  ),
                ),
              if (header!['status'] != 'void')
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        _t('Edit / refresh count', 'ပြင်ရန် / ပြန်စစ်ရန်'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : voidCheck,
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
              OutlinedButton.icon(
                onPressed: busy ? null : report,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Excel / PDF / Print / History'),
              ),
            ],
          ),
  );
}
