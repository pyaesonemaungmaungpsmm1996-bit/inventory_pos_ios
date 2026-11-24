import 'shared_pos_page.dart';
import 'shared_pos_session.dart';
import 'desktop_ui.dart';
import 'pos_ui.dart';
import 'amount_input.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'app_datetime.dart';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'sale_confirmation_page.dart';
import 'invoice_void_dialog.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _no(String prefix, int id) => '$prefix-${id.toString().padLeft(6, '0')}';
String _money(int amount) => AppCurrency.format(amount);
List<Map<String, Object?>> _rows(Object? value) =>
    (value as List).map((r) => Map<String, Object?>.from(r as Map)).toList();

class CustomerLedgerPage extends StatefulWidget {
  const CustomerLedgerPage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<CustomerLedgerPage> createState() => _CustomerLedgerPageState();
}

class _CustomerLedgerPageState extends State<CustomerLedgerPage> {
  List<Map<String, Object?>> branches = [], customers = [];
  int? branchId;
  bool loading = true, debtOnly = true;
  String search = '';
  String? error;
  int request = 0;
  late final SharedPosSession? _shared = SharedPosSession.current;
  Timer? _sharedRefresh;
  @override
  void initState() {
    super.initState();
    branchId = widget.initialBranchId;
    if (_shared != null) {
      _sharedRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!loading) unawaited(load(background: true));
      });
    }
    load();
  }

  @override
  void dispose() {
    _sharedRefresh?.cancel();
    super.dispose();
  }

  Future<void> load({bool background = false}) async {
    final ticket = ++request;
    setState(() {
      if (!background) loading = true;
      error = null;
    });
    try {
      final db = AppDatabase.instance;
      if (_shared case final session?) {
        final open = await session.openBalances('sale');
        if (!mounted || ticket != request) return;
        final code = session.connection.branchCode;
        final totals = <String?, int>{};
        for (final row in open) {
          final name = row['counterparty'] as String?;
          totals.update(name, (total) => total + (row['due'] as int),
              ifAbsent: () => row['due'] as int);
        }
        setState(() {
          branchId = 0;
          branches = [{'id': 0, 'name': code, 'code': code}];
          customers = [
            for (final entry in totals.entries)
              {
                'name': entry.key ?? '—', 'cloud_name': entry.key,
                'phone': '', 'company': '', 'balance_due': entry.value,
              },
          ];
          loading = false;
        });
        return;
      }
      final b = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final selected = b.any((r) => r['id'] == preferred)
          ? preferred
          : (b.isEmpty ? null : b.first['id'] as int);
      final c = selected == null
          ? <Map<String, Object?>>[]
          : await db.getCustomerBalances(branchId: selected);
      if (!mounted || ticket != request) return;
      setState(() {
        branches = b;
        branchId = selected;
        customers = c;
        loading = false;
      });
    } catch (_) {
      if (mounted && ticket == request) {
        setState(() {
          loading = false;
          error = _t(
            'Could not load customer ledger.',
            'ဝယ်သူစာရင်း မဖတ်နိုင်ပါ။',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final visible = customers
        .where(
          (c) =>
              (!debtOnly || (c['balance_due'] as int) > 0) &&
              '${c['name']} ${c['phone']} ${c['company']}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    final total = visible.fold<int>(
      0,
      (sum, c) => sum + (c['balance_due'] as int),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<int>(
            isExpanded: true,
            value: branchId,
            hint: Text(_t('Branch', 'ဆိုင်ခွဲ')),
            items: branches
                .map(
                  (b) => DropdownMenuItem<int>(
                    value: b['id'] as int,
                    child: Text('${b['name']} (${b['code']})'),
                  ),
                )
                .toList(),
            onChanged: loading
                ? null
                : (id) {
                    if (id != null) {
                      setState(() {
                        branchId = id;
                        customers = [];
                      });
                      load();
                    }
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _t(
                'Customer / phone / company',
                'ဝယ်သူ / ဖုန်း / ကုမ္ပဏီ',
              ),
            ),
          ),
        ),
        SwitchListTile(
          title: Text(
            _t('Outstanding customers only', 'အကြွေးကျန်ရှိသူများသာ'),
          ),
          value: debtOnly,
          onChanged: (v) => setState(() => debtOnly = v),
        ),
        if (!loading && error == null)
          Text(
            '${_t('Filtered credit due', 'ရွေးထားသော အကြွေးကျန်')}: ${_money(total)}',
          ),
        Expanded(
          child: loading
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
              : visible.isEmpty
              ? Center(
                  child: Text(
                    _t(
                      'No matching customer balances.',
                      'ကိုက်ညီသော ဝယ်သူစာရင်း မရှိပါ။',
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: DesktopListView.builder(
                    desktopColumns: const [
                      "Customer",
                      "Phone",
                      "Company",
                      "Outstanding",
                    ],
                    desktopCells: (context, index) {
                      final r = visible[index];
                      return [
                        desktopCellText(r['name']),
                        desktopCellText(r['phone']),
                        desktopCellText(r['company']),
                        desktopMoney(r['balance_due']),
                      ];
                    },

                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final c = visible[i];
                      return DesktopListTile(
                        title: Text(_shared == null ? '${c['name']} (#${c['id']})' : '${c['name']}'),
                        subtitle: Text('${c['phone']}\n${c['company']}'),
                        trailing: MoneyText(c['balance_due'] as int),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _shared != null
                                  ? Scaffold(
                                      appBar: AppBar(title: Text('${c['name']}')),
                                      body: SharedPosPage(
                                        session: _shared!,
                                        kind: SharedPosPageKind.customerBalances,
                                        filterCounterparty: true,
                                        counterparty: c['cloud_name'] as String?,
                                      ),
                                    )
                                  : _CustomerDetail(
                                customerId: c['id'] as int,
                                branchId: branchId!,
                              ),
                            ),
                          );
                          if (mounted) await load();
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _CustomerDetail extends StatefulWidget {
  const _CustomerDetail({required this.customerId, required this.branchId});
  final int customerId, branchId;
  @override
  State<_CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends State<_CustomerDetail> {
  Map<String, Object?>? data;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await AppDatabase.instance.getCustomerLedger(
        customerId: widget.customerId,
        branchId: widget.branchId,
      );
      if (mounted) {
        setState(() {
          data = d;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t('Could not load ledger.', 'စာရင်း မဖတ်နိုင်ပါ။');
        });
      }
    }
  }

  Future<void> receive() async {
    final receiptId = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => _ReceivePayment(
          customerId: widget.customerId,
          branchId: widget.branchId,
        ),
      ),
    );
    if (!mounted) return;
    if (receiptId != null) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => ReceiptDetail(receiptId: receiptId)),
      );
    }
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final invoices = data == null
        ? <Map<String, Object?>>[]
        : _rows(data!['invoices']);
    final receipts = data == null
        ? <Map<String, Object?>>[]
        : _rows(data!['receipts']);
    final due = invoices.fold<int>(0, (s, i) => s + (i['balance_due'] as int));
    return DesktopScaffold(
      appBar: AppBar(title: Text(_t('Customer Ledger', 'ဝယ်သူစာရင်း'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : RefreshIndicator(
              onRefresh: load,
              child: DesktopListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    (data!['customer'] as Map)['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${_t('Credit due', 'အကြွေးကျန်')}: ${_money(due)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilledButton.icon(
                    onPressed: due > 0 ? receive : null,
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(_t('Receive Payment', 'အကြွေးငွေလက်ခံရန်')),
                  ),
                  const Divider(),
                  Text(_t('Invoices', 'အရောင်းဘောင်ချာများ')),
                  DesktopInlineTable(
                    columns: const [
                      "Invoice",
                      "Date",
                      "Total",
                      "Paid",
                      "Balance",
                      "Confirmed at",
                    ],
                    rows: [
                      for (final i in invoices)
                        DesktopListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${_no('INV', i['id'] as int)} · ${i['invoice_date']}',
                          ),
                          subtitle: Text(
                            '${_t('Total / Paid', 'ကျသင့် / ပေးပြီး')}: ${_money(i['total'] as int)} / ${_money(i['paid'] as int)}\n${_t('Confirmed at', 'အတည်ပြုချိန်')}: ${AppDateTime.format(i['confirmed_at'])}',
                          ),
                          trailing: MoneyText(i['balance_due'] as int),
                          onTap: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConfirmedSaleDetailPage(
                                saleId: i['id'] as int,
                              ),
                            ),
                          ),
                        ),
                    ],
                    cells: [
                      for (final i in invoices)
                        [
                          desktopCellText(_no('INV', i['id'] as int)),
                          desktopCellText(i['invoice_date']),
                          desktopMoney(i['total']),
                          desktopMoney(i['paid']),
                          desktopMoney(i['balance_due']),
                          desktopDate(i['confirmed_at']),
                        ],
                    ],
                  ),
                  const Divider(),
                  Text(
                    _t(
                      'Later payment receipts',
                      'နောက်မှငွေရှင်းသည့် မှတ်တမ်းများ',
                    ),
                  ),
                  DesktopInlineTable(
                    columns: const [
                      "Receipt",
                      "Payment date",
                      "Total",
                      "Status",
                      "Recorded at",
                    ],
                    rows: [
                      for (final r in receipts)
                        DesktopListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${_no('RCPT', r['id'] as int)} · ${r['payment_date']}',
                          ),
                          subtitle: Text(
                            "${r['status'] == 'void' ? _t('VOID', 'ပယ်ဖျက်ထား') : _t('Received', 'လက်ခံပြီး')}\n${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(r['created_at'])}",
                          ),
                          trailing: MoneyText(r['total'] as int),
                          onTap: () async {
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReceiptDetail(receiptId: r['id'] as int),
                              ),
                            );
                            if (mounted) await load();
                          },
                        ),
                    ],
                    cells: [
                      for (final r in receipts)
                        [
                          desktopCellText(_no('RCPT', r['id'] as int)),
                          desktopCellText(r['payment_date']),
                          desktopMoney(r['total']),
                          desktopCellText(r['status']),
                          desktopDate(r['created_at']),
                        ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _ReceivePayment extends StatefulWidget {
  const _ReceivePayment({required this.customerId, required this.branchId});
  final int customerId, branchId;
  @override
  State<_ReceivePayment> createState() => _ReceivePaymentState();
}

class _ReceivePaymentState extends State<_ReceivePayment>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  final note = TextEditingController();
  final allocation = <int, TextEditingController>{},
      payment = <int, TextEditingController>{};
  List<Map<String, Object?>> invoices = [], accounts = [], employees = [];
  int? employeeId;
  String customerName = '', branchName = '';
  String? error, autoError;
  bool loading = true,
      ready = false,
      busy = false,
      closing = false,
      allowPop = false,
      pending = false;
  DateTime date = AppDateTime.today();
  late String requestKey;
  Timer? timer;
  Future<void> writes = Future<void>.value();
  int generation = 0;
  int sum(Map<int, TextEditingController> rows) => rows.values.fold<int>(
    0,
    (s, c) => s + (AppCurrency.tryParse(c.text.trim()) ?? 0),
  );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final random = Random.secure();
    requestKey =
        'rcpt-${DateTime.now().microsecondsSinceEpoch}-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    note.removeListener(touch);
    note.dispose();
    for (final c in [...allocation.values, ...payment.values]) {
      c.removeListener(touch);
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(persist());
  }

  Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final ledger = await db.getCustomerLedger(
        customerId: widget.customerId,
        branchId: widget.branchId,
      );
      final a = await db.getMoneyAccounts(branchId: widget.branchId);
      final e = await db.getEmployees(
        branchId: widget.branchId,
        activeOnly: true,
      );
      final branches = await db.getBranches();
      final recovery = await db.getReceiptWork(
        branchId: widget.branchId,
        customerId: widget.customerId,
      );
      final r = recovery == null ? null : jsonDecode(recovery) as Map;
      if (!mounted) return;
      customerName = (ledger['customer'] as Map)['name'] as String;
      final b = branches.firstWhere((b) => b['id'] == widget.branchId);
      branchName = '${b['name']} (${b['code']})';
      invoices = _rows(ledger['invoices']);
      if (r != null &&
          (r['request_key'] as String).startsWith('rcpt-correction-')) {
        final id = int.parse((r['request_key'] as String).split('-')[2]);
        final old = await (await db.database).query(
          'receipt_allocations',
          where: 'receipt_id=?',
          whereArgs: [id],
        );
        for (final i in invoices) {
          i['balance_due'] =
              (i['balance_due'] as int) +
              old
                  .where((a) => a['sale_id'] == i['id'])
                  .fold<int>(0, (sum, a) => sum + (a['amount'] as int));
        }
      }
      invoices.removeWhere((i) => (i['balance_due'] as int) <= 0);
      accounts = a;
      employees = e;
      if (r != null) {
        requestKey = r['request_key'] as String;
        date = DateTime.parse(r['date'] as String);
        employeeId = r['employee_id'] as int?;
        note.text = r['note'] as String;
      }
      if (!employees.any((e) => e['id'] == employeeId)) employeeId = null;
      for (final i in invoices) {
        final id = i['id'] as int;
        final c = TextEditingController(
          text: (r?['allocation'] as Map?)?[id.toString()] as String? ?? '',
        );
        c.addListener(touch);
        allocation[id] = c;
      }
      for (final a in accounts) {
        final id = a['id'] as int;
        final c = TextEditingController(
          text: (r?['payment'] as Map?)?[id.toString()] as String? ?? '',
        );
        c.addListener(touch);
        payment[id] = c;
      }
      note.addListener(touch);
      setState(() {
        loading = false;
        ready = true;
      });
      touch();
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t(
            'Could not load receipt form.',
            'ငွေလက်ခံရန် မဖွင့်နိုင်ပါ။',
          );
        });
      }
    }
  }

  void touch() {
    if (!ready || closing || !mounted) return;
    generation++;
    timer?.cancel();
    setState(() => pending = true);
    timer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(persist()),
    );
  }

  Future<bool> persist() async {
    timer?.cancel();
    if (!ready || closing) return true;
    final ticket = generation;
    bool ok = false;
    final payload = jsonEncode({
      'request_key': requestKey,
      'date': _date(date),
      'employee_id': employeeId,
      'note': note.text,
      'allocation': allocation.map((id, c) => MapEntry(id.toString(), c.text)),
      'payment': payment.map((id, c) => MapEntry(id.toString(), c.text)),
    });
    final task = writes.then((_) async {
      try {
        await AppDatabase.instance.putReceiptWork(
          branchId: widget.branchId,
          customerId: widget.customerId,
          payload: payload,
        );
        ok = true;
        if (mounted && ticket == generation) {
          setState(() {
            pending = false;
            autoError = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            pending = false;
            autoError = _t(
              'Auto-save failed. Retry before leaving.',
              'ယာယီသိမ်းမရပါ။ မထွက်မီ ပြန်စမ်းပါ။',
            );
          });
        }
      }
    });
    writes = task;
    await task;
    return ok;
  }

  Future<void> pop([int? id]) async {
    if (!mounted) return;
    setState(() {
      allowPop = true;
      busy = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, id);
  }

  Future<void> leave() async {
    if (busy || closing) return;
    setState(() => busy = true);
    if (!await persist()) {
      if (mounted) setState(() => busy = false);
      return;
    }
    closing = true;
    timer?.cancel();
    await writes;
    await pop();
  }

  Future<void> save() async {
    if (busy || !ready || !form.currentState!.validate()) return;
    if (sum(allocation) <= 0 ||
        sum(allocation) != sum(payment) ||
        sum(allocation) > 9000000000000) {
      setState(
        () => error = _t(
          'Allocated invoice amounts and received amounts must match and be positive.',
          'Invoice ရှင်းငွေနှင့် အကောင့်ဝင်ငွေ တူညီပြီး သုညထက်များရပါမည်။',
        ),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => DesktopDialog(
          title: Text(_t('Confirm debt payment?', 'အကြွေးငွေလက်ခံမလား?')),
          content: Text(
            '$customerName\n$branchName\n${_money(sum(allocation))}\n${_t('Customer debt will decrease and receiving account balances will increase.', 'ဝယ်သူအကြွေးလျော့ပြီး ရွေးထားသောငွေအကောင့်များ တိုးမည်။')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(_t('Confirm', 'အတည်ပြုမည်')),
            ),
          ],
        ),
      );
      if (!mounted || yes != true) return;
      await persist();
      closing = true;
      timer?.cancel();
      await writes;
      final id = await AppDatabase.instance.receiveCustomerPayment(
        requestKey: requestKey,
        customerId: widget.customerId,
        branchId: widget.branchId,
        employeeId: employeeId!,
        paymentDate: _date(date),
        note: note.text,
        allocations: [
          for (final e in allocation.entries)
            if ((AppCurrency.tryParse(e.value.text.trim()) ?? 0) > 0)
              {
                'sale_id': e.key,
                'amount': AppCurrency.parse(e.value.text.trim()),
              },
        ],
        payments: [
          for (final e in payment.entries)
            if ((AppCurrency.tryParse(e.value.text.trim()) ?? 0) > 0)
              {
                'account_id': e.key,
                'amount': AppCurrency.parse(e.value.text.trim()),
              },
        ],
      );
      await pop(id);
    } catch (e) {
      closing = false;
      if (mounted) {
        touch();
        setState(
          () => error = e is StateError
              ? e.message
              : _t(
                  'Payment not saved. Refresh the ledger and retry.',
                  'ငွေလက်ခံမသိမ်းနိုင်ပါ။ စာရင်းပြန်ဖွင့်ပြီး စမ်းပါ။',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? validateAmount(String? value, int max) {
    if (value == null || value.trim().isEmpty) return null;
    final n = AppCurrency.tryParse(value.trim());
    return n == null || n < 0 || n > max
        ? _t(
            'Amount exceeds limit or is invalid.',
            'ပမာဏမမှန်ပါ သို့မဟုတ် ကျန်ငွေထက်များပါသည်။',
          )
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope<int>(
    canPop: allowPop && !busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(leave());
    },
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(_t('Receive Customer Payment', 'အကြွေးငွေလက်ခံရန်')),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : !ready
          ? Center(child: Text(error ?? 'Error'))
          : Form(
              key: form,
              child: DesktopListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    customerName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(branchName),
                  Text(
                    autoError ??
                        (pending
                            ? _t('Auto-saving...', 'ယာယီသိမ်းနေသည်…')
                            : _t(
                                'Entry saved on this device',
                                'ရေးလက်စကို ဤစက်တွင်သိမ်းထားသည်',
                              )),
                  ),
                  if (autoError != null)
                    TextButton(
                      onPressed: busy ? null : () => unawaited(persist()),
                      child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                    ),
                  DesktopListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('Payment date', 'ငွေလက်ခံရက်')),
                    subtitle: Text(_date(date)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: busy || closing
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(1900),
                              lastDate: AppDateTime.today(),
                            );
                            if (d != null && mounted) {
                              setState(() => date = d);
                              touch();
                            }
                          },
                  ),
                  Text(
                    _t(
                      'Choose invoice amounts to settle',
                      'Invoice အလိုက် ရှင်းမည့်ငွေထည့်ရန်',
                    ),
                  ),
                  Text(
                    _t(
                      'The actual save time is recorded automatically, separately from the selected payment date.',
                      'ရွေးထားသော ငွေလက်ခံရက်နှင့် သီးခြား အမှန်တကယ်သိမ်းချိန်ကို Auto မှတ်မည်။',
                    ),
                  ),
                  for (final i in invoices)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_no('INV', i['id'] as int)} · ${i['invoice_date']}',
                            ),
                            Text(
                              '${_t('Due', 'ကျန်ငွေ')}: ${_money(i['balance_due'] as int)}',
                            ),
                            TextFormField(
                              controller: allocation[i['id']],
                              enabled: !busy && !closing,
                              inputFormatters: const [AmountInputFormatter()],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${_t('Amount to settle', 'ရှင်းမည့်ငွေ')} (${AppCurrency.displayCode})',
                                suffixIcon: IconButton(
                                  tooltip: _t('Full balance', 'ကျန်ငွေအပြည့်'),
                                  onPressed: busy || closing
                                      ? null
                                      : () => allocation[i['id']]!.text =
                                            AppCurrency.input(
                                              i['balance_due'] as int,
                                            ),
                                  icon: const Icon(Icons.done_all),
                                ),
                              ),
                              validator: (v) =>
                                  validateAmount(v, i['balance_due'] as int),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(),
                  Text(
                    _t(
                      'Money received into accounts',
                      'အကောင့်အလိုက် လက်ခံရရှိငွေ',
                    ),
                  ),
                  for (final a in accounts)
                    TextFormField(
                      controller: payment[a['id']],
                      enabled: !busy && !closing,
                      inputFormatters: const [AmountInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '${a['name']} (${AppCurrency.displayCode})',
                      ),
                      validator: (v) => validateAmount(v, 9000000000000),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '${_t('Allocated', 'Invoice ရှင်းငွေ')}: ${_money(sum(allocation))}',
                  ),
                  Text(
                    '${_t('Received', 'အကောင့်ဝင်ငွေ')}: ${_money(sum(payment))}',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: employeeId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('Receiving employee', 'ငွေလက်ခံဝန်ထမ်း'),
                    ),
                    items: employees
                        .map(
                          (e) => DropdownMenuItem<int>(
                            value: e['id'] as int,
                            child: Text('${e['name']} (${e['code']})'),
                          ),
                        )
                        .toList(),
                    onChanged: busy || closing
                        ? null
                        : (id) {
                            setState(() => employeeId = id);
                            touch();
                          },
                    validator: (id) => id == null
                        ? _t(
                            'Select active employee.',
                            'အသုံးပြုဆဲဝန်ထမ်း ရွေးပါ။',
                          )
                        : null,
                  ),
                  TextFormField(
                    controller: note,
                    enabled: !busy && !closing,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: _t('Remark', 'မှတ်ချက်'),
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: busy || closing || invoices.isEmpty
                        ? null
                        : save,
                    child: Text(
                      busy
                          ? _t('Saving...', 'သိမ်းနေသည်…')
                          : _t('Receive Payment', 'ငွေလက်ခံမည်'),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

class ReceiptDetail extends StatefulWidget {
  const ReceiptDetail({super.key, required this.receiptId});
  final int receiptId;
  @override
  State<ReceiptDetail> createState() => _ReceiptDetailState();
}

class _ReceiptDetailState extends State<ReceiptDetail> {
  Map<String, Object?>? receipt;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await AppDatabase.instance.getCustomerReceipt(widget.receiptId);
      if (mounted) {
        setState(() {
          receipt = r;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = _t(
            'Could not load receipt.',
            'ငွေလက်ခံမှတ်တမ်း မဖတ်နိုင်ပါ။',
          ),
        );
      }
    }
  }

  Future<void> cancelReceipt() async {
    String reason = '';
    final key = GlobalKey<FormState>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(_t('Void this receipt?', 'ဤငွေလက်ခံမှုကို ပယ်ဖျက်မလား?')),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _t(
                  'Debt will be restored. Received amounts will be reversed from the accounts.',
                  'အကြွေးပြန်တိုးပြီး လက်ခံထားသောငွေကို အကောင့်များမှ ပြန်နုတ်မည်။',
                ),
              ),
              TextFormField(
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: _t('Reason', 'အကြောင်းပြချက်'),
                ),
                onChanged: (v) => reason = v,
                validator: (v) => v == null || v.trim().isEmpty
                    ? _t('Required', 'ဖြည့်ရန်လိုပါသည်။')
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_t('Keep receipt', 'မပယ်ဖျက်ပါ')),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(c, true);
            },
            child: Text(_t('Void receipt', 'ပယ်ဖျက်မည်')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await AppDatabase.instance.voidCustomerReceipt(
        receiptId: widget.receiptId,
        reason: reason,
      );
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Could not void receipt.', 'ပယ်ဖျက်မရပါ။')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> correctReceipt() async {
    if (receipt?['status'] != 'posted' || busy) return;
    const reason = 'Edited using voucher unlock';
    setState(() => busy = true);
    try {
      await AppDatabase.instance.createCustomerReceiptCorrectionWork(
        id: widget.receiptId,
        reason: reason,
      );
      if (!mounted) return;
      final id = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => _ReceivePayment(
            customerId: receipt!['customer_id'] as int,
            branchId: receipt!['branch_id'] as int,
          ),
        ),
      );
      if (!mounted) return;
      await load();
      if (id != null && mounted) {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => ReceiptDetail(receiptId: id)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(_no('RCPT', widget.receiptId)),
      actions: [
        if (receipt?['status'] == 'posted')
          IconButton(
            tooltip: _t('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
            icon: const Icon(Icons.lock_outline),
            onPressed: busy ? null : correctReceipt,
          ),
      ],
    ),
    body: error != null
        ? Center(child: Text(error!))
        : receipt == null
        ? const Center(child: CircularProgressIndicator())
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${receipt!['customer_name']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${receipt!['branch_name']} (${receipt!['branch_code']})'),
              Text(
                '${receipt!['payment_date']} · ${receipt!['employee_name']}',
              ),
              Text(
                '${_t('Payment recorded at', 'ငွေလက်ခံမှုသိမ်းချိန်')}: ${AppDateTime.format(receipt!['created_at'])}',
              ),
              Text('${receipt!['note']}'),
              if (receipt!['status'] == 'void')
                Text(
                  '${_t('VOID', 'ပယ်ဖျက်ထား')}\n${receipt!['void_reason']}\n${AppDateTime.format(receipt!['voided_at'])}',
                ),
              if (receipt!['replacement_id'] != null)
                Text(
                  '${_t('Corrected by', 'ပြင်ဆင်ပြီးဘောင်ချာ')}: '
                  '${_no('RCPT', receipt!['replacement_id'] as int)}',
                ),
              const Divider(),
              Text(_t('Settled invoices', 'ရှင်းထားသောဘောင်ချာများ')),
              for (final a in _rows(receipt!['allocations']))
                DesktopListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_no('INV', a['sale_id'] as int)),
                  trailing: MoneyText(a['amount'] as int),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ConfirmedSaleDetailPage(saleId: a['sale_id'] as int),
                    ),
                  ),
                ),
              const Divider(),
              Text(_t('Receiving accounts', 'လက်ခံငွေအကောင့်များ')),
              for (final p in _rows(receipt!['payments']))
                DesktopListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p['account_name'] as String),
                  trailing: MoneyText(p['amount'] as int),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: AmountSummary(
                  label: _t('Total', 'စုစုပေါင်း'),
                  amount: receipt!['total'] as int,
                ),
              ),
              const SizedBox(height: 16),
              if (receipt!['status'] == 'posted')
                OutlinedButton(
                  onPressed: busy ? null : cancelReceipt,
                  child: Text(_t('Void receipt', 'ငွေလက်ခံမှု ပယ်ဖျက်ရန်')),
                ),
              if (receipt!['status'] == 'posted')
                OutlinedButton(
                  onPressed: busy ? null : correctReceipt,
                  child: Text(_t('Correct receipt', 'ငွေလက်ခံမှု ပြန်ပြင်ရန်')),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(_t('Delete permanently', 'အပြီးတိုင်ဖျက်ရန်')),
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await deleteVoucherWithPrompt(
                          context,
                          kind: 'receipt',
                          id: widget.receiptId,
                          number: _no('RCPT', widget.receiptId),
                        );
                        if (ok && context.mounted) Navigator.pop(context);
                      },
              ),
            ],
          ),
  );
}
