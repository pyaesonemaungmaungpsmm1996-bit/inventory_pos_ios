import 'app_database.dart';
import 'desktop_ui.dart';
import 'pos_ui.dart';
import 'amount_input.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'account_transfer_repository.dart';
import 'app_currency.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'invoice_void_dialog.dart';
import 'report_repository.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class AccountTransferPage extends StatefulWidget {
  const AccountTransferPage({super.key});
  @override
  State<AccountTransferPage> createState() => _AccountTransferPageState();
}

class _AccountTransferPageState extends State<AccountTransferPage> {
  List<Map<String, Object?>> branches = [], records = [];
  int? branch;
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
    final selected = branch, showVoid = includeVoid;
    try {
      final options = await AccountTransferRepository.options();
      final rows = await AccountTransferRepository.list(
        branch: selected,
        from: start,
        to: end,
        search: query,
        includeVoid: showVoid,
      );
      if (!mounted || token != request) return;
      setState(() {
        branches = options['branches']!;
        records = rows;
        loading = false;
        loadedLabels =
            '$start to $end | Either source or destination branch #${selected ?? 'All'} | Search: $query | Include VOID: $showVoid';
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
    final selected = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (first) {
        from = selected;
        if (to.isBefore(from)) to = from;
      } else {
        to = selected;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> create() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const _TransferForm()),
    );
    if (!mounted || id == null) return;
    await load();
    if (mounted) await open(id);
  }

  Future<void> open(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => _TransferDetail(id: id)),
    );
    if (mounted) await load();
  }

  void export() {
    final ids = records.map((r) => r['id'] as int).toList();
    final labels = loadedLabels ?? '';
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Account Transfers',
          load: () => AccountTransferRepository.report(ids, labels),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
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
            decoration: InputDecoration(
              labelText: _t(
                'Source / destination branch',
                'ပို့ / လက်ခံ ဆိုင်ခွဲ',
              ),
            ),
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
              setState(() => branch = v == -1 ? null : v);
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
                'Search voucher / account / note',
                'ဘောင်ချာ / အကောင့် / မှတ်ချက် ရှာရန်',
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
          if (!loading && records.isEmpty && error == null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _t(
                  'No transfers in this date range. Tap + to transfer money.',
                  'ဤရက်အတွင်း ငွေလွှဲမရှိပါ။ ငွေလွှဲရန် + နှိပ်ပါ။',
                ),
              ),
            ),
          if (!loading && error == null)
            DesktopInlineTable(
              columns: const [
                "Voucher",
                "Date",
                "From branch",
                "From account",
                "To branch",
                "To account",
                "Amount",
                "Status",
                "Note",
              ],
              rows: [
                for (final row in records)
                  Card(
                    child: DesktopListTile(
                      leading: Icon(
                        row['status'] == 'void'
                            ? Icons.block
                            : Icons.swap_horiz,
                      ),
                      title: Text(
                        '${voucherNo('ACT', row['id'])} · ${AppCurrency.format(row['amount'] as int)}',
                      ),
                      subtitle: Text(
                        '${row['from_branch_name']} / ${row['from_account_name']} → '
                        '${row['to_branch_name']} / ${row['to_account_name']}\n${row['transfer_date']} · ${row['status']}\n${row['note']}',
                      ),
                      onTap: () => open(row['id'] as int),
                    ),
                  ),
              ],
              cells: [
                for (final row in records)
                  [
                    desktopCellText(voucherNo('ACT', row['id'])),
                    desktopCellText(row['transfer_date']),
                    desktopCellText(row['from_branch_name']),
                    desktopCellText(row['from_account_name']),
                    desktopCellText(row['to_branch_name']),
                    desktopCellText(row['to_account_name']),
                    desktopMoney(row['amount']),
                    desktopCellText(row['status']),
                    desktopCellText(row['note']),
                  ],
              ],
            ),
        ],
      ),
    ),
  );
}

class _TransferForm extends StatefulWidget {
  const _TransferForm({this.initial});
  final Map<String, Object?>? initial;
  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  late final String requestKey =
      'account-transfer-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  List<Map<String, Object?>> accounts = [];
  int? source, target;
  late DateTime day = AppDateTime.today();
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final old = widget.initial;
    if (old != null) {
      source = old['from_account_id'] as int;
      target = old['to_account_id'] as int;
      amount.text = AppCurrency.input(old['amount'] as int);
      note.text = old['note'] as String;
      day = DateTime.parse(old['transfer_date'] as String);
    }
    load();
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final options = await AccountTransferRepository.options();
      if (mounted) {
        setState(() {
          accounts = options['accounts']!;
          loading = false;
          error = null;
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

  String label(int? id) {
    final rows = accounts.where((a) => a['id'] == id);
    return rows.isEmpty
        ? _t('Choose account', 'အကောင့်ရွေးရန်')
        : '${rows.first['branch_name']} / ${rows.first['name']}\n${_t('Current balance', 'လက်ရှိလက်ကျန်')}: ${AppCurrency.format(rows.first['balance'] as int)}';
  }

  Future<void> pick(bool first) async {
    var query = '';
    final excluded = first ? target : source;
    final selected = await showDialog<int>(
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
                      for (final a in accounts.where(
                        (a) =>
                            a['id'] != excluded &&
                            '${a['name']} ${a['branch_name']} ${a['type']}'
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
    if (selected != null && mounted) {
      setState(() {
        if (first) {
          source = selected;
        } else {
          target = selected;
        }
      });
    }
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
    if (source == null || target == null || source == target) {
      setState(
        () => error = _t(
          'Choose two different accounts',
          'မတူညီသည့် အကောင့်နှစ်ခု ရွေးပါ',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final id = await AccountTransferRepository.save(
        id: widget.initial?['id'] as int?,
        expectedRevision: widget.initial?['revision'] as int?,
        requestKey: requestKey,
        fromAccount: source!,
        toAccount: target!,
        amount: AppCurrency.parse(amount.text),
        date: _date(day),
        note: note.text,
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null
              ? _t('New Account Transfer', 'ငွေလွှဲအသစ်')
              : _t('Edit Account Transfer', 'ငွေလွှဲပြင်ရန်'),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: form,
              child: DesktopListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DesktopListTile(
                    title: Text(_t('From account', 'ငွေပို့အကောင့်')),
                    subtitle: Text(label(source)),
                    trailing: const Icon(Icons.search),
                    onTap: saving ? null : () => pick(true),
                  ),
                  const Icon(Icons.arrow_downward),
                  DesktopListTile(
                    title: Text(_t('To account', 'လက်ခံအကောင့်')),
                    subtitle: Text(label(target)),
                    trailing: const Icon(Icons.search),
                    onTap: saving ? null : () => pick(false),
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
                    validator: (v) => (AppCurrency.tryParse(v ?? '') ?? 0) <= 0
                        ? _t('Enter a valid amount', 'ငွေပမာဏမှန်ထည့်ပါ')
                        : null,
                  ),
                  DesktopListTile(
                    title: Text(
                      '${_t('Transfer date', 'ငွေလွှဲရက်')}: ${_date(day)}',
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: saving ? null : date,
                  ),
                  TextFormField(
                    controller: note,
                    enabled: !saving,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: _t('Note / reference', 'မှတ်ချက် / အညွှန်း'),
                    ),
                  ),
                  if (widget.initial != null)
                    Text(
                      _t(
                        'Edits reverse the original legs on their old date and post corrected legs on the selected date.',
                        'ပြင်ဆင်လျှင် အဟောင်းကို မူရင်းရက်တွင် ပြန်လှန်ပြီး အသစ်ကို ရွေးထားသောရက်တွင် တင်ပါမည်။',
                      ),
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
                  FilledButton.icon(
                    onPressed: saving || accounts.length < 2 ? null : save,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(_t('Save transfer', 'ငွေလွှဲသိမ်းမည်')),
                  ),
                  if (accounts.length < 2)
                    Text(
                      _t(
                        'Add at least two money accounts first.',
                        'ငွေအကောင့် အနည်းဆုံးနှစ်ခု အရင်ထည့်ပါ။',
                      ),
                    ),
                ],
              ),
            ),
    ),
  );
}

class _TransferDetail extends StatefulWidget {
  const _TransferDetail({required this.id});
  final int id;
  @override
  State<_TransferDetail> createState() => _TransferDetailState();
}

class _TransferDetailState extends State<_TransferDetail> {
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
      final row = await AccountTransferRepository.get(widget.id);
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
        MaterialPageRoute(builder: (_) => _TransferForm(initial: header)),
      );
      if (mounted) await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> voidTransfer() async {
    if (busy || header == null) return;
    setState(() => busy = true);
    try {
      final reason = await askInvoiceVoidReason(
        context,
        _t('Void account transfer?', 'ငွေလွှဲကို VOID လုပ်မလား?'),
      );
      if (reason == null || !mounted) return;
      await AccountTransferRepository.voidTransfer(
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
      final deleted = await deleteVoucherWithPrompt(
        context,
        kind: 'account_transfer',
        id: widget.id,
        number: voucherNo('ACT', widget.id),
      );
      if (deleted && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void report() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: voucherNo('ACT', widget.id),
          load: () => AccountTransferRepository.report([
            widget.id,
          ], 'Full transfer and revision history'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(voucherNo('ACT', widget.id)),
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
                '${header!['status']}'.toUpperCase(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              MoneyText(
                header!['amount'] as int,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              DesktopListTile(
                title: Text(_t('From', 'ပို့အကောင့်')),
                subtitle: Text(
                  '${header!['from_branch_name']} / ${header!['from_account_name']}',
                ),
              ),
              const Icon(Icons.arrow_downward),
              DesktopListTile(
                title: Text(_t('To', 'လက်ခံအကောင့်')),
                subtitle: Text(
                  '${header!['to_branch_name']} / ${header!['to_account_name']}',
                ),
              ),
              Text(
                '${_t('Transfer date', 'ငွေလွှဲရက်')}: ${header!['transfer_date']}',
              ),
              Text(
                '${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(header!['created_at'])}',
              ),
              Text('${header!['note']}'),
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
                      onPressed: busy ? null : voidTransfer,
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
