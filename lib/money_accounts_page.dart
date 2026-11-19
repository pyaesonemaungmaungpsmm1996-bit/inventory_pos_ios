import 'branch_reuse.dart';
import 'branch_reuse_picker.dart';
import 'desktop_ui.dart';
import 'amount_input.dart';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app_datetime.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_language.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _money(int amount) => AppCurrency.format(amount);
String _type(String value) => switch (value) {
  'cash' => _t('Cash', 'ငွေသား'),
  'bank' => _t('Bank', 'ဘဏ်'),
  _ => _t('Wallet', 'မိုဘိုင်းပိုက်ဆံအိတ်'),
};

class MoneyAccountsPage extends StatefulWidget {
  const MoneyAccountsPage({super.key});
  @override
  State<MoneyAccountsPage> createState() => _MoneyAccountsPageState();
}

class _MoneyAccountsPageState extends State<MoneyAccountsPage> {
  List<Map<String, Object?>> branches = [];
  List<Map<String, Object?>> accounts = [];
  int? branchId;
  bool loading = true;
  bool busy = false;
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
      final rows = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final selected = rows.any((b) => b['id'] == preferred)
          ? preferred
          : (rows.isEmpty ? null : rows.first['id'] as int);
      final money = selected == null
          ? <Map<String, Object?>>[]
          : await db.getMoneyAccounts(branchId: selected);
      if (!mounted || ticket != request) return;
      setState(() {
        branches = rows;
        branchId = selected;
        accounts = money;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t(
          'Could not load accounts. Please retry.',
          'ငွေအကောင့်များ မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
        );
      });
    }
  }

  Future<void> edit([Map<String, Object?>? account]) async {
    if (busy || loading || branchId == null) return;
    setState(() => busy = true);
    try {
      final saved = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MoneyForm(
          branches: branches,
          initialBranchId: branchId!,
          account: account,
        ),
      );
      if (saved != null && mounted) {
        setState(() => branchId = saved);
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reuse() async {
    if (busy || loading || branchId == null) return;
    final target = branchId!;
    setState(() => busy = true);
    try {
      final available = await BranchReuse.accounts(target);
      if (!mounted) return;
      final source = await pickBranchDefinition(
        context,
        title: _t(
          'Use account details from another branch',
          'အခြားဆိုင်ခွဲမှ အကောင့်အချက်အလက် သုံးရန်',
        ),
        rows: available,
        money: true,
      );
      if (source == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => DesktopDialog(
          title: Text(
            _t('Use these account details?', 'ဤအကောင့်အချက်အလက် သုံးမလား။'),
          ),
          content: Text(
            _t(
              'A separate ledger for this branch starts at zero. No money or opening balance is copied.',
              'ဤဆိုင်ခွဲအတွက် ငွေစာရင်းကို သုညမှစသည်။ အခြားဆိုင်ခွဲ၏ ငွေ သို့မဟုတ် အဖွင့်လက်ကျန်ကို မကူးပါ။',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Use account', 'အကောင့်သုံးရန်')),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await BranchReuse.account(source, target);
        if (mounted) await load();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : _t('Could not reuse account', 'အကောင့် ပြန်သုံးမရပါ'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = accounts.fold<int>(
      0,
      (sum, a) => sum + (a['balance'] as int),
    );
    return DesktopScaffold(
      body: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy || loading || branchId == null ? null : reuse,
              icon: const Icon(Icons.copy_outlined),
              label: Text(
                _t(
                  'Use existing account details',
                  'ရှိပြီးသားအကောင့်အချက်အလက် သုံးရန်',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                        accounts = [];
                      });
                      load();
                    },
            ),
          ),
          if (!loading && error == null && branches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${_t('Branch total balance', 'ဆိုင်ခွဲ စုစုပေါင်းလက်ကျန်')}: ${_money(total)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
                      _t(
                        'Add a branch in Account > Branches first.',
                        'အကောင့် > ဆိုင်ခွဲများတွင် ဆိုင်ခွဲအရင်ထည့်ပါ။',
                      ),
                    ),
                  )
                : accounts.isEmpty
                ? Center(
                    child: Text(
                      _t(
                        'Tap + to add a money account.',
                        'ငွေအကောင့်ထည့်ရန် + ကိုနှိပ်ပါ။',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: DesktopListView.builder(
                      desktopColumns: const [
                        "Account name",
                        "Type",
                        "Account holder",
                        "Account number",
                        "Balance",
                        "Created at",
                      ],
                      desktopCells: (context, index) {
                        final r = accounts[index];
                        return [
                          desktopCellText(r['name']),
                          desktopCellText(r['type']),
                          desktopCellText(r['account_holder']),
                          desktopCellText(r['account_number']),
                          desktopMoney(r['balance']),
                          desktopDate(r['created_at']),
                        ];
                      },

                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: accounts.length,
                      itemBuilder: (context, index) {
                        final a = accounts[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: DesktopListTile(
                            isThreeLine: true,
                            onTap: busy ? null : () => edit(a),
                            leading: Icon(
                              a['type'] == 'cash'
                                  ? Icons.payments_outlined
                                  : Icons.account_balance_wallet_outlined,
                            ),
                            title: Text(a['name'] as String),
                            subtitle: Text(
                              '${a['account_holder'] ?? ''} · ${a['account_number'] ?? ''}\n${_type(a['type'] as String)}\n${_money(a['balance'] as int)}\n${_t('Created at', 'စတင်သိမ်းချိန်')}: ${AppDateTime.format(a['created_at'])}',
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

class _MoneyForm extends StatefulWidget {
  const _MoneyForm({
    required this.branches,
    required this.initialBranchId,
    this.account,
  });
  final List<Map<String, Object?>> branches;
  final int initialBranchId;
  final Map<String, Object?>? account;
  @override
  State<_MoneyForm> createState() => _MoneyFormState();
}

class _MoneyFormState extends State<_MoneyForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController holder;
  late final TextEditingController number;
  late final TextEditingController remark;
  late final TextEditingController opening;
  late final TextEditingController correctionReason;
  late int branchId;
  late String type;
  late DateTime openingDate;
  bool saving = false;
  String? error;
  bool get editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    branchId = a?['branch_id'] as int? ?? widget.initialBranchId;
    type = a?['type'] as String? ?? 'cash';
    openingDate = a == null
        ? AppDateTime.today()
        : DateTime.parse(a['opening_date'] as String);
    name = TextEditingController(text: a?['name'] as String? ?? '');
    holder = TextEditingController(text: a?['account_holder'] as String? ?? '');
    number = TextEditingController(text: a?['account_number'] as String? ?? '');
    remark = TextEditingController(text: a?['remark'] as String? ?? '');
    opening = TextEditingController(
      text: AppCurrency.input(a?['opening_balance'] as int? ?? 0),
    );
    correctionReason = TextEditingController();
    opening.addListener(_refreshCorrection);
  }

  void _refreshCorrection() {
    if (mounted && editing) setState(() {});
  }

  @override
  void dispose() {
    opening.removeListener(_refreshCorrection);
    name.dispose();
    holder.dispose();
    number.dispose();
    remark.dispose();
    opening.dispose();
    correctionReason.dispose();
    super.dispose();
  }

  Future<void> showCorrectionHistory() async {
    try {
      final rows = await AppDatabase.instance.getOpeningCorrections(
        widget.account!['id'] as int,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => DesktopDialog(
          title: Text(
            _t('Opening balance changes', 'အဖွင့်လက်ကျန် ပြင်ဆင်မှုမှတ်တမ်း'),
          ),
          content: SizedBox(
            width: 400,
            height: 320,
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      _t('No corrections yet', 'ပြင်ဆင်မှုမရှိသေးပါ'),
                    ),
                  )
                : DesktopListView(
                    children: [
                      for (final row in rows)
                        DesktopListTile(
                          title: Text(
                            '${_money(row['previous_amount'] as int)} → ${_money(row['new_amount'] as int)}',
                          ),
                          subtitle: Text(
                            '${row['reason']}\n${AppDateTime.format(row['created_at'])}',
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('Close', 'ပိတ်မည်')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = _t(
            'Could not load correction history.',
            'ပြင်ဆင်မှုမှတ်တမ်း ဖတ်မရပါ။',
          ),
        );
      }
    }
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await AppDatabase.instance.saveMoneyAccount(
        id: widget.account?['id'] as int?,
        branchId: branchId,
        name: name.text,
        type: type,
        accountNumber: number.text,
        remark: remark.text,
        openingBalance: AppCurrency.parse(opening.text.trim()),
        openingDate: _date(openingDate),
        expectedOpeningBalance: widget.account?['opening_balance'] as int?,
        correctionReason: correctionReason.text,
        accountHolder: holder.text,
      );
      if (!mounted) return;
      Navigator.pop(context, branchId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = e is DatabaseException && e.isUniqueConstraintError()
            ? _t(
                'This account name already exists in this branch.',
                'ဤဆိုင်ခွဲတွင် ငွေအကောင့်အမည် ရှိပြီးသားဖြစ်ပါသည်။',
              )
            : e is StateError
            ? _t(
                e.message,
                'လက်ကျန်ငွေ ပြောင်းထားပြီးဖြစ်နိုင်သည်။ အကောင့်ကို ပြန်ဖွင့်ပြီး စမ်းပါ။',
              )
            : _t('Could not save. Please retry.', 'မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။');
      });
    }
  }

  Widget textField(
    TextEditingController controller,
    String label, {
    int maxLength = 100,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLength: maxLength,
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
          editing
              ? _t('Edit Money Account', 'ငွေအကောင့်ပြင်ရန်')
              : _t('Add Money Account', 'ငွေအကောင့်အသစ်'),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: branchId,
                    decoration: InputDecoration(
                      labelText: _t('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    isExpanded: true,
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
                    onChanged: saving || editing
                        ? null
                        : (id) {
                            if (id != null) setState(() => branchId = id);
                          },
                  ),
                  textField(
                    name,
                    _t('Account name', 'ငွေအကောင့်အမည်'),
                    required: true,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: _t('Type', 'အမျိုးအစား'),
                    ),
                    items: ['cash', 'bank', 'wallet']
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(_type(v))),
                        )
                        .toList(),
                    onChanged: saving || editing
                        ? null
                        : (v) {
                            if (v != null) setState(() => type = v);
                          },
                  ),
                  textField(
                    holder,
                    _t(
                      'Account Name (duplicates allowed)',
                      'အကောင့်ပိုင်ရှင်အမည် (တူနိုင်သည်)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  textField(
                    number,
                    _t(
                      'Account No. / Phone (optional)',
                      'အကောင့်နံပါတ် / ဖုန်း (မဖြစ်မနေမလို)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: opening,
                    enabled: !saving,
                    inputFormatters: const [AmountInputFormatter()],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${_t('Opening balance', 'အဖွင့်လက်ကျန်')} (${AppCurrency.displayCode})',
                      helperText: editing
                          ? _t(
                              'Enter the new total (e.g. 1,000 + 500 → 1,500). The difference is recorded today.',
                              'လက်ကျန်အသစ် စုစုပေါင်းထည့်ပါ (ဥပမာ ၁,၀၀၀ + ၅၀၀ → ၁,၅၀၀)။ ကွာခြားချက်ကို ယနေ့ရက်ဖြင့်မှတ်မည်။',
                            )
                          : null,
                    ),
                    validator: (s) {
                      final value = AppCurrency.tryParse(s?.trim() ?? '');
                      return value == null || value < 0 || value > 9000000000000
                          ? '${_t('Enter a valid amount. Maximum', 'မှန်ကန်သောငွေပမာဏထည့်ပါ။ အများဆုံး')}: ${_money(9000000000000)}'
                          : null;
                    },
                  ),
                  DesktopListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Opening date', 'အဖွင့်ရက်')),
                    subtitle: Text(_date(openingDate)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: saving || editing
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: openingDate,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2200, 12, 31),
                            );
                            if (date != null && mounted) {
                              setState(() => openingDate = date);
                            }
                          },
                  ),
                  if (editing)
                    Text(
                      '${_t('Account created at', 'အကောင့်စတင်သိမ်းချိန်')}: ${AppDateTime.format(widget.account!['created_at'])}',
                    ),
                  if (editing &&
                      opening.text.trim() !=
                          AppCurrency.input(
                            widget.account!['opening_balance'] as int,
                          ))
                    textField(
                      correctionReason,
                      _t(
                        'Reason for balance correction',
                        'လက်ကျန်ပြင်သည့် အကြောင်းရင်း',
                      ),
                      maxLength: 300,
                      required: true,
                    ),
                  if (editing)
                    TextButton.icon(
                      onPressed: saving ? null : showCorrectionHistory,
                      icon: const Icon(Icons.history),
                      label: Text(
                        _t(
                          'View correction history',
                          'ပြင်ဆင်မှုမှတ်တမ်းကြည့်ရန်',
                        ),
                      ),
                    ),
                  if (editing)
                    Text(
                      _t(
                        'Branch, type and opening date remain fixed. Amount changes are recorded as adjustments.',
                        'ဆိုင်ခွဲ၊ အမျိုးအစားနှင့် အဖွင့်ရက် မပြောင်းပါ။ ငွေပမာဏပြောင်းမှုကို Adjustment အဖြစ် မှတ်မည်။',
                      ),
                    ),
                  textField(remark, _t('Remark', 'မှတ်ချက်'), maxLength: 300),
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
