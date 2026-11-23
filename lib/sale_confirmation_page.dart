import 'sale_linked_review.dart';
import 'sale_invoices_page.dart';
import 'desktop_ui.dart';
import 'desktop_commands.dart';
import 'pos_ui.dart';
import 'product_details_form.dart';
import 'amount_input.dart';

import 'dart:async';
import 'dart:convert';

import 'app_datetime.dart';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'invoice_printer_page.dart';
import 'app_database.dart';
import 'invoice_void_dialog.dart';
import 'voucher_code.dart';
import 'app_language.dart';
import 'stock_sync_checkout.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _money(int amount) => AppCurrency.format(amount);
String _invoice(int id) => 'INV-${id.toString().padLeft(6, '0')}';

class SaleConfirmationPage extends StatefulWidget {
  const SaleConfirmationPage({
    super.key,
    required this.draftId,
    this.offlineCheckout,
  });
  final int draftId;
  final StockSyncCheckout? offlineCheckout;
  @override
  State<SaleConfirmationPage> createState() => _SaleConfirmationPageState();
}

class _SaleConfirmationPageState extends State<SaleConfirmationPage>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  final paidFocus = FocusNode();
  final keyboardScroll = ScrollController();
  Map<String, Object?>? draft;
  List<Map<String, Object?>> accounts = [], customers = [];
  final controllers = <int, TextEditingController>{};
  int? customerId;
  int? revision;
  bool saveNew = false,
      loading = true,
      busy = false,
      ready = false,
      closing = false,
      allowPop = false,
      pending = false;
  String? error, autoError;
  DateTime paymentDate = AppDateTime.today();
  Timer? timer;
  Future<void> writes = Future<void>.value();
  int generation = 0;
  String get key => 'draft:${widget.draftId}';
  int get paid => controllers.values.fold<int>(
    0,
    (s, c) => s + (AppCurrency.tryParse(c.text.trim()) ?? 0),
  );
  int get total => draft?['total'] as int? ?? 0;
  SaleLinkedReview? linkedReview;
  int get allocated =>
      linkedReview?.allocated ?? draft?['linked_paid'] as int? ?? 0;
  int get due => total - paid - allocated;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  @override
  void dispose() {
    keyboardScroll.dispose();
    paidFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    for (final c in controllers.values) {
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
      final d = await db.getSaleDraft(widget.draftId);
      final allAccounts = await db.getMoneyAccounts(
        branchId: d['branch_id'] as int,
      );
      final pilot = widget.offlineCheckout;
      final a = pilot == null
          ? allAccounts
          : allAccounts
                .where(
                  (account) => pilot.cashAccounts.containsKey(account['id']),
                )
                .toList();
      final c = await db.getContacts(kind: 'customer', activeOnly: true);
      final r = await db.getSaleRecovery(key);
      Map<String, Object?>? p;
      if (r != null) {
        p = Map<String, Object?>.from(
          jsonDecode(r['payload'] as String) as Map,
        );
        if (p['stage'] != 'payment') {
          throw StateError(
            'Resume unfinished draft edits and Save Draft first.',
          );
        }
      }
      if (!mounted) return;
      draft = d;
      accounts = a;
      customers = c;
      customerId = p?['customer_id'] as int? ?? d['customer_id'] as int?;
      revision = p?['revision'] as int? ?? d['revision'] as int;
      saveNew = p?['save_customer'] as bool? ?? false;
      if (p != null) paymentDate = DateTime.parse(p['payment_date'] as String);
      // Saved draft payments are shared by desktop and phone. Recovery from an
      // interrupted payment form takes precedence, including intentionally blank fields.
      Map<String, Object?> staged = {};
      try {
        staged = Map<String, Object?>.from(
          jsonDecode(d['desktop_payment_json'] as String? ?? '{}') as Map,
        );
      } catch (_) {
        /* Older drafts have no staged payment metadata. */
      }
      if (p == null) {
        paymentDate = DateTime.tryParse('${staged['date']}') ?? paymentDate;
      }
      final stagedAccounts = <String, String>{};
      for (final split in staged['splits'] as List? ?? const []) {
        final row = split as Map;
        final id = '${row['account_id']}';
        final value = row['amount'];
        if (value is int && value >= 0) {
          final prior = AppCurrency.tryParse(stagedAccounts[id] ?? '0') ?? 0;
          stagedAccounts[id] = AppCurrency.input(prior + value);
        }
      }
      if (stagedAccounts.isEmpty && staged['account_id'] != null) {
        stagedAccounts['${staged['account_id']}'] = '${staged['text'] ?? ''}';
      }
      final saved = p?['accounts'] as Map? ?? stagedAccounts;
      for (final account in a) {
        final id = account['id'] as int;
        final controller = TextEditingController(
          text: saved[id.toString()] as String? ?? '',
        );
        controller.addListener(touch);
        controllers[id] = controller;
      }
      setState(() {
        loading = false;
        ready = true;
      });
      touch();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e is StateError
              ? e.message
              : _t(
                  'Could not load payment form.',
                  'ငွေရှင်းရန် မဖွင့်နိုင်ပါ။',
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
    final payload = jsonEncode({
      'stage': 'payment',
      'revision': revision,
      'customer_id': customerId,
      'save_customer': saveNew,
      'payment_date': _date(paymentDate),
      'accounts': controllers.map((id, c) => MapEntry(id.toString(), c.text)),
    });
    bool ok = false;
    final task = writes.then((_) async {
      try {
        await AppDatabase.instance.putSaleRecovery(
          key: key,
          sourceId: widget.draftId,
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

  Future<void> pop([int? result]) async {
    if (!mounted) return;
    setState(() {
      allowPop = true;
      busy = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
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

  Future<void> chooseCustomer([List<Map<String, Object?>>? matches]) async {
    String search = '';
    final rows = matches ?? customers;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, update) {
          final filtered = rows
              .where(
                (r) => '${r['name']} ${r['phone']}'.toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .toList();
          return DesktopDialog(
            title: Text(_t('Customer for credit', 'အကြွေးဝယ်သူ ရွေးရန်')),
            content: SizedBox(
              width: 420,
              height: 350,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => update(() => search = v),
                    decoration: InputDecoration(
                      hintText: _t('Search', 'ရှာရန်'),
                    ),
                  ),
                  Expanded(
                    child: DesktopListView(
                      children: [
                        for (final r in filtered)
                          DesktopListTile(
                            title: Text('${r['name']} (#${r['id']})'),
                            subtitle: Text(r['phone'] as String),
                            onTap: () => Navigator.pop(c, r),
                          ),
                      ],
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
    if (selected != null && mounted) {
      setState(() {
        customerId = selected['id'] as int;
        saveNew = false;
      });
      touch();
    }
  }

  Future<void> confirm() async {
    if (busy || !ready || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      linkedReview = null;
    });
    try {
      final d = draft!;
      if (d['correction_source_sale_id'] != null) {
        final branch = d['branch_id'] as int;
        final catalog = await AppDatabase.instance.getProducts(
          branchId: branch,
        );
        if (!mounted) return;
        final selection = await showSaleLinkedReview(
          context,
          draft: d,
          branchId: branch,
          products: catalog,
          lines: (d['items'] as List).cast<Map<String, Object?>>(),
        );
        if (!mounted || selection == null) return;
        linkedReview = selection;
      }
      if (paid < 0 ||
          due < 0 ||
          (due > 0 &&
              customerId == null &&
              (!saveNew || (d['customer_name'] as String).trim().isEmpty))) {
        setState(
          () => error = 'Check the payments and linked allocations. Credit sales require a customer.',
        );
        return;
      }
      if (due > 0 && customerId == null && saveNew) {
        final raw = draft!['customer_phone'] as String;
        final number = raw.replaceAll(RegExp(r'[^0-9+]'), '');
        if (number.isNotEmpty) {
          final all = await AppDatabase.instance.getContacts(kind: 'customer');
          final matches = all
              .where(
                (c) =>
                    (c['phone'] as String).replaceAll(RegExp(r'[^0-9+]'), '') ==
                    number,
              )
              .toList();
          if (!mounted) return;
          if (matches.isNotEmpty) {
            final choice = await showDialog<String>(
              context: context,
              builder: (c) => DesktopDialog(
                title: Text(
                  _t(
                    'Matching phone found',
                    'ဖုန်းနံပါတ်တူ ရှိပြီးသားဖြစ်ပါသည်။',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'existing'),
                    child: Text(_t('Use existing', 'ရှိပြီးသားသုံးမည်')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, 'new'),
                    child: Text(_t('Save new', 'အသစ်သိမ်းမည်')),
                  ),
                ],
              ),
            );
            if (!mounted || choice == null) return;
            if (choice == 'existing') {
              await chooseCustomer(matches);
              if (customerId == null) return;
            }
          }
        }
      }
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => DesktopDialog(
          title: Text(
            d['correction_source_sale_id'] != null
                ? 'Save changes to the original invoice?'
                : _t('Confirm this sale?', 'အရောင်းအတည်ပြုမလား?'),
          ),
          content: Text(
            '${_t('Total', 'ကျသင့်ငွေ')}: ${_money(total)}\n${_t('Paid', 'ပေးပြီးငွေ')}: ${_money(paid)}\n${_t('Credit due', 'အကြွေးကျန်')}: ${_money(due)}\n\n${_t('Stock will decrease and selected accounts will receive money.', 'Stock နုတ်ပြီး ရွေးထားသောငွေအကောင့်များသို့ ငွေဝင်မည်။')}',
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
      final saleId = await AppDatabase.instance.confirmSaleDraft(
        draftId: widget.draftId,
        offlineCheckout: widget.offlineCheckout,
        revision: revision!,
        paymentDate: _date(paymentDate),
        customerIdOverride: customerId,
        saveNewCustomer: saveNew,
        linkedResolutions: linkedReview?.resolutions ?? const {},
        linkedReceiptEdits: linkedReview?.receipts ?? const {},
        linkedReturnEdits: linkedReview?.returns ?? const {},
        linkedExchangeEdits: linkedReview?.exchanges ?? const {},
        payments: [
          for (final e in controllers.entries)
            if ((AppCurrency.tryParse(e.value.text.trim()) ?? 0) > 0)
              {
                'account_id': e.key,
                'amount': AppCurrency.parse(e.value.text.trim()),
              },
        ],
      );
      await pop(saleId);
    } catch (e) {
      closing = false;
      if (mounted) {
        touch();
        setState(
          () => error = e is StateError
              ? e.message
              : _t(
                  'Sale not posted. Check stock and payment values.',
                  'အရောင်းမတင်နိုင်ပါ။ Stock နှင့် ပေးချေငွေ စစ်ပါ။',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> focusPaid() => desktopFocusInScroll(paidFocus, keyboardScroll);

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: ready && !busy && !closing,
    onEscape: leave,
    commands: {
      DesktopCommand.saveDraft: () => persist(),
      DesktopCommand.contact: () => chooseCustomer(),
      DesktopCommand.paid: focusPaid,
      DesktopCommand.confirm: confirm,
    },
    child: PopScope<int>(
      canPop: allowPop && !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(leave());
      },
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(
            _t(
              'Payment & Confirm Sale',
              'ငွေရှင်းခြင်းနှင့် အရောင်းအတည်ပြုခြင်း',
            ),
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : !ready
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(error ?? 'Error'),
                ),
              )
            : Form(
                key: form,
                child: DesktopListView(
                  controller: keyboardScroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      autoError ??
                          (pending
                              ? _t('Auto-saving...', 'ယာယီသိမ်းနေသည်…')
                              : _t(
                                  'Payment entry auto-saved locally',
                                  'ငွေရှင်းရေးလက်စကို ဤစက်တွင်သိမ်းထားသည်',
                                )),
                    ),
                    if (autoError != null)
                      TextButton(
                        onPressed: busy ? null : () => unawaited(persist()),
                        child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                      ),
                    Text(
                      '${_t('Branch', 'ဆိုင်ခွဲ')}: ${draft!['branch_name']} (${draft!['branch_code']})',
                    ),
                    Text(
                      '${_t('Invoice date', 'ဘောင်ချာရက်')}: ${draft!['invoice_date']}',
                    ),
                    Text(
                      _t(
                        'Confirmation records the actual date and time automatically, separately from the invoice/payment business dates.',
                        'အတည်ပြုချိန်တွင် ရက်နှင့်အချိန်အမှန်ကို Auto မှတ်မည်။ ဘောင်ချာရက် / ငွေလက်ခံရက်နှင့် သီးခြားဖြစ်သည်။',
                      ),
                    ),
                    Text(
                      '${_t('Customer', 'ဝယ်သူ')}: ${draft!['customer_name']}',
                    ),
                    AmountSummary(
                      label: _t('Total amount', 'ကျသင့်ငွေ'),
                      amount: total,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        'Enter the amount received into each account. Leave blank for zero.',
                        'အကောင့်တစ်ခုချင်း လက်ခံရရှိငွေထည့်ပါ။ ငွေမဝင်သည့်အကောင့်ကို အလွတ်ထားပါ။',
                      ),
                    ),
                    for (final a in accounts)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          focusNode: a['id'] == accounts.first['id']
                              ? paidFocus
                              : null,
                          controller: controllers[a['id']],
                          enabled: !busy && !closing,
                          inputFormatters: const [AmountInputFormatter()],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                '${a['name']} (${AppCurrency.displayCode})',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = AppCurrency.tryParse(v.trim());
                            return n == null || n < 0 || n > 9000000000000
                                ? _t(
                                    'Enter a valid whole amount.',
                                    'ကျပ်ပြည့်ကိန်းပမာဏ ထည့်ပါ။',
                                  )
                                : null;
                          },
                        ),
                      ),
                    if (accounts.isEmpty)
                      Text(
                        _t(
                          'No money accounts in this branch. Add one under Account > Money Accounts for paid sales.',
                          'ဤဆိုင်ခွဲတွင် ငွေအကောင့်မရှိပါ။ ငွေလက်ခံရန် အကောင့် > ငွေအကောင့်များတွင် ထည့်ပါ။',
                        ),
                      ),
                    DesktopListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_t('Payment date', 'ငွေလက်ခံရက်')),
                      subtitle: Text(_date(paymentDate)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: busy || closing
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: paymentDate,
                                firstDate: DateTime(1900),
                                lastDate: AppDateTime.today(),
                              );
                              if (d != null && mounted) {
                                setState(() => paymentDate = d);
                                touch();
                              }
                            },
                    ),
                    Text('${_t('Paid', 'ပေးပြီးငွေ')}: ${_money(paid)}'),
                    Text(
                      '${_t('Credit due', 'အကြွေးကျန်')}: ${_money(due)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (due > 0) ...[
                      Text(
                        customerId == null
                            ? _t(
                                'Credit requires a saved customer.',
                                'အကြွေးအတွက် Customer Contact သိမ်းထားရန် လိုပါသည်။',
                              )
                            : '${_t('Linked customer ID', 'ချိတ်ထားသောဝယ်သူ ID')}: #$customerId',
                      ),
                      OutlinedButton(
                        onPressed: busy || closing
                            ? null
                            : () => chooseCustomer(),
                        child: Text(
                          _t(
                            'Choose customer for credit',
                            'အကြွေးဝယ်သူ ရွေးရန်',
                          ),
                        ),
                      ),
                      if (customerId == null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: saveNew,
                          title: Text(
                            _t(
                              'Save invoice customer to Contacts for credit',
                              'ဘောင်ချာမှဝယ်သူကို အကြွေးစာရင်းအတွက် သိမ်းမည်',
                            ),
                          ),
                          onChanged: busy || closing
                              ? null
                              : (v) {
                                  setState(() => saveNew = v ?? false);
                                  touch();
                                },
                        ),
                    ],
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
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: busy || closing ? null : confirm,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        busy
                            ? _t('Processing...', 'ဆောင်ရွက်နေသည်…')
                            : desktopHint(
                                _t('Confirm Sale', 'အရောင်းအတည်ပြုမည်'),
                                DesktopCommand.confirm,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}

class ConfirmedSalesPage extends StatefulWidget {
  const ConfirmedSalesPage({
    super.key,
    required this.initialBranchId,
    required this.branches,
  });
  final int initialBranchId;
  final List<Map<String, Object?>> branches;
  @override
  State<ConfirmedSalesPage> createState() => _ConfirmedSalesPageState();
}

class _ConfirmedSalesPageState extends State<ConfirmedSalesPage> {
  late int branchId;
  List<Map<String, Object?>> sales = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    branchId = widget.initialBranchId;
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await AppDatabase.instance.getConfirmedSales(
        branchId: branchId,
      );
      if (mounted) {
        setState(() {
          sales = rows;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t('Could not load sales.', 'အရောင်းစာရင်း မဖတ်နိုင်ပါ။');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(_t('Confirmed Sales', 'အတည်ပြုပြီးအရောင်းများ')),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButton<int>(
            value: branchId,
            isExpanded: true,
            items: widget.branches
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
                      branchId = id;
                      load();
                    }
                  },
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(child: Text(error!))
              : sales.isEmpty
              ? Center(
                  child: Text(
                    _t('No confirmed sales.', 'အတည်ပြုပြီးအရောင်း မရှိသေးပါ။'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: DesktopListView.builder(
                    desktopColumns: const [
                      "Invoice No.",
                      "Date",
                      "Customer",
                      "Total",
                      "Outstanding",
                      "Confirmed at",
                      "Status",
                    ],
                    desktopCells: (context, index) {
                      final r = sales[index];
                      return [
                        desktopCellText('INV-${r['id']}'),
                        desktopCellText(r['invoice_date']),
                        desktopCellText(r['customer_name']),
                        desktopMoney(r['total']),
                        desktopMoney(r['balance_due']),
                        desktopDate(r['confirmed_at']),
                        desktopCellText(r['status']),
                      ];
                    },

                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: sales.length,
                    itemBuilder: (context, i) {
                      final s = sales[i];
                      return DesktopListTile(
                        title: Text(_invoice(s['id'] as int)),
                        subtitle: Text(
                          '${s['status'] == 'void' ? 'VOID · ' : ''}${s['customer_name']} · ${s['invoice_date']}\n${_t('Confirmed at', 'အတည်ပြုချိန်')}: ${AppDateTime.format(s['confirmed_at'])}\n${_t('Credit due', 'အကြွေးကျန်')}: ${_money(s['balance_due'] as int)}',
                        ),
                        trailing: MoneyText(s['total'] as int),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConfirmedSaleDetailPage(
                                saleId: s['id'] as int,
                              ),
                            ),
                          );
                          if (context.mounted) await load();
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class ConfirmedSaleDetailPage extends StatefulWidget {
  const ConfirmedSaleDetailPage({super.key, required this.saleId});
  final int saleId;
  @override
  State<ConfirmedSaleDetailPage> createState() =>
      _ConfirmedSaleDetailPageState();
}

class _ConfirmedSaleDetailPageState extends State<ConfirmedSaleDetailPage> {
  String _money(int amount) => AppCurrency.format(
    amount,
    currency: sale?['currency_code'] as String? ?? AppCurrency.code,
    decimalPlaces: sale?['currency_digits'] as int? ?? AppCurrency.digits,
  );

  Map<String, Object?>? sale;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final s = await AppDatabase.instance.getConfirmedSale(widget.saleId);
      if (mounted) {
        setState(() {
          sale = s;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = _t('Could not load invoice.', 'ဘောင်ချာ မဖတ်နိုင်ပါ။'),
        );
      }
    }
  }

  Future<void> openPrint() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePrintPage(saleId: widget.saleId),
      ),
    );
    if (mounted) await load();
  }

  Future<void> voidInvoice() async {
    if (sale?['status'] != 'posted') return;
    final reason = await askInvoiceVoidReason(
      context,
      _t('Void sale invoice?', 'အရောင်းဘောင်ချာ ပယ်ဖျက်မလား?'),
    );
    if (reason == null || !mounted) return;
    try {
      await AppDatabase.instance.voidSaleInvoice(
        id: widget.saleId,
        reason: reason,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool _openingEdit = false;

  Future<void> editInvoice() async {
    final invoice = sale;
    if (_openingEdit || invoice == null || invoice['status'] != 'posted') {
      return;
    }
    _openingEdit = true;
    try {
      final draftId = await AppDatabase.instance.createSaleCorrectionDraft(
        id: widget.saleId,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(
              title: Text(
                'Edit invoice · ${VoucherCode.displayNumber(invoice)}',
              ),
            ),
            body: SaleInvoicesPage(
              initialBranchId: invoice['branch_id'] as int,
              initialDraftId: draftId,
            ),
          ),
        ),
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      _openingEdit = false;
    }
  }

  Future<void> deleteInvoice() async {
    if (sale == null) return;
    final ok = await deleteVoucherWithPrompt(
      context,
      kind: 'sale',
      id: widget.saleId,
      number: VoucherCode.displayNumber(sale!),
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: sale != null && error == null,
    commands: {DesktopCommand.print: openPrint},
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(
          sale == null
              ? _invoice(widget.saleId)
              : VoucherCode.displayNumber(sale!),
        ),
        actions: [
          if (sale?['status'] == 'posted')
            IconButton(
              tooltip: _t('Unlock to edit invoice', 'သော့ဖွင့်ပြင်ရန်'),
              icon: const Icon(Icons.lock_outline),
              onPressed: editInvoice,
            ),
          IconButton(
            tooltip: _t('Print / PDF', 'Print / PDF'),
            icon: const Icon(Icons.print_outlined),
            onPressed: sale == null || error != null ? null : openPrint,
          ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!))
          : sale == null
          ? const Center(child: CircularProgressIndicator())
          : DesktopListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (sale!['status'] == 'void')
                  Text(
                    'VOID · ${sale!['void_reason']}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (sale!['replacement_id'] != null)
                  Text(
                    '${_t('Corrected by', 'ပြင်ဆင်ပြီးဘောင်ချာ')}: '
                    '${_invoice(sale!['replacement_id'] as int)}',
                  ),
                Text(
                  '${_t('Invoice date', 'ဘောင်ချာရက်')}: ${sale!['invoice_date']}',
                ),
                Text(
                  '${_t('Sale confirmed at', 'အရောင်းအတည်ပြုချိန်')}: ${AppDateTime.format(sale!['confirmed_at'])}',
                ),
                Text(
                  '${_t('Branch', 'ဆိုင်ခွဲ')}: ${sale!['branch_name_snapshot']} (${sale!['branch_code_snapshot']})',
                ),
                Text('${_t('Customer', 'ဝယ်သူ')}: ${sale!['customer_name']}'),
                Text(
                  '${sale!['customer_phone']}\n${sale!['customer_company']}\n${sale!['customer_address']}',
                ),
                Text(
                  '${_t('Sale person', 'အရောင်းဝန်ထမ်း')}: ${sale!['employee_name']}',
                ),
                const Divider(),
                for (final item in sale!['items'] as List)
                  DesktopListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () =>
                        showProductTracking(context, item['tracking_json']),
                    title: Text('${item['item_code']} · ${item['item_name']}'),
                    subtitle: Text(
                      '${item['qty']} × ${_money(item['price'] as int)}',
                    ),
                    trailing: MoneyText(item['amount'] as int),
                  ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_t('Subtotal', 'စုစုပေါင်း')}: '
                        '${_money(sale!['subtotal'] as int)}',
                        textAlign: TextAlign.right,
                      ),
                      Text(
                        '${_t('Discount', 'လျှော့ဈေး')}: '
                        '${_money(sale!['discount_amount'] as int)}',
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_t('Total', 'ကျသင့်ငွေ')}: '
                        '${_money(sale!['total'] as int)}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      for (final p in sale!['payments'] as List)
                        Text(
                          '${p['payment_date']} · ${p['account_name']}: '
                          '${_money(p['amount'] as int)}\n'
                          '${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(p['created_at'])}',
                          textAlign: TextAlign.right,
                        ),
                      for (final r in sale!['collections'] as List)
                        Text(
                          "${r['payment_date']} · RCPT-${(r['receipt_id'] as int).toString().padLeft(6, '0')}: "
                          "${_money(r['amount'] as int)}${r['status'] == 'void' ? _t(' (VOID)', ' (ပယ်ဖျက်ထား)') : ''}\n"
                          '${_t('Recorded at', 'သိမ်းချိန်')}: ${AppDateTime.format(r['received_at'])}',
                          textAlign: TextAlign.right,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '${_t('Paid', 'ပေးပြီးငွေ')}: '
                        '${_money(sale!['paid'] as int)}',
                        textAlign: TextAlign.right,
                      ),
                      Text(
                        '${_t('Credit due', 'အကြွေးကျန်')}: '
                        '${_money(sale!['balance_due'] as int)}',
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (sale!['status'] == 'posted')
                  OutlinedButton.icon(
                    onPressed: voidInvoice,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      _t('Void sale invoice', 'အရောင်းဘောင်ချာ ပယ်ဖျက်ရန်'),
                    ),
                  ),
                if (sale!['status'] == 'posted')
                  OutlinedButton.icon(
                    onPressed: editInvoice,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      _t('Edit sale invoice', 'အရောင်းဘောင်ချာ ပြန်ပြင်ရန်'),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: deleteInvoice,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(_t('Delete permanently', 'အပြီးတိုင်ဖျက်ရန်')),
                ),
                FilledButton.icon(
                  onPressed: openPrint,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_t('Print / PDF', 'Print / PDF')),
                ),
              ],
            ),
    ),
  );
}
