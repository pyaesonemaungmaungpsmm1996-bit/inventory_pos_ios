import 'app_capabilities.dart';
import 'desktop_ui.dart';
import 'sale_invoice_details.dart';
import 'pos_ui.dart';
import 'product_details_form.dart';
import 'amount_input.dart';

import 'package:flutter/material.dart';

import 'voucher_pdf_preview.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'invoice_pdf.dart';
import 'invoice_print_settings.dart';
import 'invoice_void_dialog.dart';

String _tr(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _no(String prefix, int id) => '$prefix-${id.toString().padLeft(6, '0')}';

class SaleReturnsPage extends StatefulWidget {
  const SaleReturnsPage({super.key});
  @override
  State<SaleReturnsPage> createState() => _SaleReturnsPageState();
}

class _SaleReturnsPageState extends State<SaleReturnsPage> {
  List<Map<String, Object?>> branches = [], returns = [];
  int? branchId;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final db = AppDatabase.instance;
      final found = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final chosen = found.any((row) => row['id'] == preferred)
          ? preferred
          : (found.isEmpty ? null : found.first['id'] as int);
      final rows = chosen == null
          ? <Map<String, Object?>>[]
          : await db.getSaleReturns(branchId: chosen);
      if (mounted) {
        setState(() {
          branches = found;
          branchId = chosen;
          returns = rows;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> create() async {
    if (branchId == null) return;
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => _NewSaleReturn(branchId: branchId!)),
    );
    if (!mounted) return;
    await load();
    if (id != null && mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => _ReturnDetail(returnId: id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<int>(
            initialValue: branchId,
            isExpanded: true,
            decoration: InputDecoration(labelText: _tr('Branch', 'ဆိုင်ခွဲ')),
            items: branches
                .map(
                  (b) => DropdownMenuItem(
                    value: b['id'] as int,
                    child: Text('${b['name']} (${b['code']})'),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) {
                      branchId = v;
                      load();
                    }
                  },
          ),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        Expanded(
          child: busy
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: load,
                  child: DesktopListView.builder(
                    desktopColumns: const [
                      "Return No.",
                      "Invoice No.",
                      "Date",
                      "Customer",
                      "Total",
                      "Status",
                    ],
                    desktopCells: (context, index) {
                      final r = returns[index];
                      return [
                        desktopCellText('RET-${r['id']}'),
                        desktopCellText('INV-${r['sale_id']}'),
                        desktopCellText(r['return_date']),
                        desktopCellText(r['customer_name']),
                        desktopMoney(
                          r['total'],
                          currency: r['currency_code'] as String?,
                          digits: r['currency_digits'] as int?,
                        ),
                        desktopCellText(r['status']),
                      ];
                    },

                    itemCount: returns.length,
                    itemBuilder: (context, i) {
                      final r = returns[i];
                      return DesktopListTile(
                        leading: const Icon(Icons.assignment_return_outlined),
                        title: Text(_no('RET', r['id'] as int)),
                        subtitle: Text(
                          '${r['return_date']} · ${_no('INV', r['sale_id'] as int)} · ${r['customer_name']}'
                          '${r['status'] == 'void' ? ' · VOID' : ''}',
                        ),
                        trailing: MoneyText(
                          r['total'] as int,
                          currency: r['currency_code'] as String,
                          decimalPlaces: r['currency_digits'] as int,
                        ),
                        onTap: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _ReturnDetail(returnId: r['id'] as int),
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
    floatingActionButton: FloatingActionButton(
      onPressed: busy || branchId == null ? null : create,
      child: const Icon(Icons.add),
    ),
  );
}

class _RefundInput {
  _RefundInput(this.accountId);
  int accountId;
  final amount = TextEditingController();
  void dispose() => amount.dispose();
}

class _NewSaleReturn extends StatefulWidget {
  const _NewSaleReturn({required this.branchId, this.existing});
  final int branchId;
  final Map<String, Object?>? existing;
  @override
  State<_NewSaleReturn> createState() => _NewSaleReturnState();
}

class _NewSaleReturnState extends State<_NewSaleReturn> {
  List<Map<String, Object?>> sales = [],
      accounts = [],
      employees = [],
      items = [];
  List<Map<String, Object?>> allItems = [];
  Map<int, int> previousQty = {};
  final quantities = <int, TextEditingController>{};
  final refunds = <_RefundInput>[];
  final reason = TextEditingController();
  int? saleId;
  int? employeeId;
  int saleTotal = 0, saleSubtotal = 0;
  DateTime date = AppDateTime.today();
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in quantities.values) {
      c.dispose();
    }
    for (final r in refunds) {
      r.dispose();
    }
    reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final found = await db.getConfirmedSales(branchId: widget.branchId);
      final money = await db.getMoneyAccounts(branchId: widget.branchId);
      final staff = await db.getEmployees(
        branchId: widget.branchId,
        activeOnly: true,
      );
      if (mounted) {
        setState(() {
          sales = found
              .where(
                (s) =>
                    s['status'] == 'posted' &&
                    s['balance_due'] == 0 &&
                    (s['total'] as int) > 0,
              )
              .toList();
          accounts = money;
          employees = staff;
          if (money.isNotEmpty) {
            refunds.add(_RefundInput(money.first['id'] as int));
          }
          busy = false;
        });
      }
      if (widget.existing != null && mounted) {
        final old = widget.existing!;
        await chooseSale(old['sale_id'] as int);
        if (!mounted) return;
        final oldRefunds = (old['refunds'] as List)
            .cast<Map<String, Object?>>();
        final previous = refunds.toList();
        refunds.clear();
        for (final payment in oldRefunds) {
          final row = _RefundInput(payment['account_id'] as int);
          row.amount.text = AppCurrency.input(payment['amount'] as int);
          refunds.add(row);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final input in previous) {
            input.dispose();
          }
        });
        for (final item in old['items'] as List) {
          final row = item as Map<String, Object?>;
          quantities[row['sale_item_id'] as int]?.text = '${row['qty']}';
        }
        reason.text = old['reason'] as String;
        date = DateTime.parse(old['return_date'] as String);
        setState(
          () => employeeId = employees.any((e) => e['id'] == old['employee_id'])
              ? old['employee_id'] as int
              : null,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> chooseSale(int id) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final sale = await AppDatabase.instance.getConfirmedSale(id);
      final old = await AppDatabase.instance.getSaleReturns(
        branchId: widget.branchId,
      );
      final returned = <int, int>{};
      for (final r in old.where(
        (row) =>
            row['sale_id'] == id &&
            row['status'] == 'posted' &&
            row['id'] != widget.existing?['id'],
      )) {
        final detail = await AppDatabase.instance.getSaleReturn(r['id'] as int);
        for (final item in detail['items'] as List) {
          final line = item as Map<String, Object?>;
          final key = line['sale_item_id'] as int;
          returned[key] = (returned[key] ?? 0) + (line['qty'] as int);
        }
      }
      final previousControllers = quantities.values.toList();
      quantities.clear();
      final available = (sale['items'] as List)
          .cast<Map<String, Object?>>()
          .map(
            (item) => {
              ...item,
              'remaining': (item['qty'] as int) - (returned[item['id']] ?? 0),
            },
          )
          .where((item) => (item['remaining'] as int) > 0)
          .toList();
      for (final item in available) {
        quantities[item['id'] as int] = TextEditingController(text: '0');
      }
      if (mounted) {
        setState(() {
          saleId = id;
          items = available;
          employeeId = employees.any((e) => e['id'] == sale['employee_id'])
              ? sale['employee_id'] as int
              : null;
          allItems = (sale['items'] as List).cast<Map<String, Object?>>();
          previousQty = returned;
          saleTotal = sale['total'] as int;
          saleSubtotal = sale['subtotal'] as int;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in previousControllers) {
          c.dispose();
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || saleId == null || employeeId == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final qty = <int, int>{};
      for (final item in items) {
        final id = item['id'] as int;
        final n = int.tryParse(quantities[id]!.text.trim());
        if (n == null || n < 0 || n > (item['remaining'] as int)) {
          throw const FormatException('Invalid return quantity');
        }
        if (n > 0) qty[id] = n;
      }
      final payments = <Map<String, int>>[];
      for (final r in refunds) {
        final amount = AppCurrency.tryParse(
          r.amount.text.trim().replaceAll(',', ''),
        );
        if (amount == null || amount <= 0) {
          throw const FormatException('Enter positive refund amounts');
        }
        payments.add({'account_id': r.accountId, 'amount': amount});
      }
      final trackedReturns = <int, String>{};
      for (final item in items) {
        final itemId = item['id'] as int;
        final n = qty[itemId] ?? 0;
        if (n <= 0) continue;
        final chosen = await pickSaleLots(
          context,
          item['product_id'] as int,
          widget.branchId,
          n,
          null,
          saleItem: itemId,
          excludeReturn: widget.existing?['id'] as int?,
        );
        if (chosen == null || !mounted) return;
        trackedReturns[itemId] = chosen;
      }
      final id = widget.existing == null
          ? await AppDatabase.instance.postSaleReturn(
              saleId: saleId!,
              returnDate: _day(date),
              reason: reason.text,
              employeeId: employeeId!,
              itemQuantities: qty,
              refunds: payments,
              trackedReturns: trackedReturns,
            )
          : await AppDatabase.instance.replaceSaleReturn(
              id: widget.existing!['id'] as int,
              returnDate: _day(date),
              reason: reason.text,
              employeeId: employeeId!,
              itemQuantities: qty,
              refunds: payments,
              trackedReturns: trackedReturns,
            );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void selectReturnItems(bool all) {
    setState(() {
      for (final item in items) {
        quantities[item['id'] as int]!.text = all
            ? item['remaining'].toString()
            : '0';
      }
      if (refunds.length == 1) {
        refunds.first.amount.text = all
            ? AppCurrency.input(expectedRefund)
            : '';
      }
    });
  }

  int get expectedRefund {
    if (saleSubtotal <= 0) return 0;
    var total = 0;
    final netLines = SaleInvoiceDetails.lineNets(allItems, saleTotal);
    for (var i = 0; i < allItems.length; i++) {
      final item = allItems[i];
      final line = netLines[i];
      final beforeQty = previousQty[item['id'] as int] ?? 0;
      final qty = int.tryParse(quantities[item['id'] as int]?.text ?? '') ?? 0;
      if (qty > 0 && qty <= (item['qty'] as int) - beforeQty) {
        final sold = BigInt.from(item['qty'] as int);
        total +=
            (BigInt.from(line) * BigInt.from(beforeQty + qty) ~/ sold).toInt() -
            (BigInt.from(line) * BigInt.from(beforeQty) ~/ sold).toInt();
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null
            ? _tr('New Sale Return', 'အရောင်းပြန်အပ်အသစ်')
            : _tr('Correct Sale Return', 'အရောင်းပြန်အပ် ပြန်ပြင်ရန်'),
      ),
    ),
    body: busy && sales.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<int>(
                key: ValueKey('sale-$saleId'),
                initialValue: saleId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _tr(
                    'Original sale invoice',
                    'မူရင်းအရောင်းဘောင်ချာ',
                  ),
                ),
                items: sales
                    .map(
                      (s) => DropdownMenuItem(
                        value: s['id'] as int,
                        child: Text(
                          '${_no('INV', s['id'] as int)} · ${s['customer_name']}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy || widget.existing != null
                    ? null
                    : (v) {
                        if (v != null) chooseSale(v);
                      },
              ),
              const SizedBox(height: 12),
              if (sales.isEmpty)
                Text(
                  _tr(
                    'No fully paid invoices in this branch.',
                    'ဤဆိုင်ခွဲတွင် ငွေရှင်းပြီး အရောင်းဘောင်ချာ မရှိသေးပါ။',
                  ),
                ),
              if (saleId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _tr(
                      'Select items to return',
                      'ပြန်အပ်မည့်ပစ္စည်းကို ရွေးပါ',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              if (saleId != null && items.isEmpty)
                Text(
                  _tr(
                    'All items on this invoice were returned.',
                    'ဤဘောင်ချာရှိ ပစ္စည်းအားလုံးကို ပြန်အပ်ပြီးပါပြီ။',
                  ),
                ),
              if (saleId != null)
                DropdownButtonFormField<int>(
                  key: ValueKey('staff-$saleId'),
                  initialValue: employeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'Sale person handling return',
                      'ပြန်အပ်မှု တာဝန်ယူသည့် Sale person',
                    ),
                  ),
                  items: employees
                      .map(
                        (e) => DropdownMenuItem<int>(
                          value: e['id'] as int,
                          child: Text(e['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => employeeId = v),
                ),
              if (saleId != null && items.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('return-all-remaining'),
                      onPressed: busy ? null : () => selectReturnItems(true),
                      icon: const Icon(Icons.select_all),
                      label: Text(
                        _tr(
                          'Return all remaining items',
                          'ကျန်ပစ္စည်းအားလုံး ပြန်အပ်ရန်',
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('return-selected-only'),
                      onPressed: busy ? null : () => selectReturnItems(false),
                      icon: const Icon(Icons.checklist),
                      label: Text(
                        _tr(
                          'Choose individual items',
                          'ပစ္စည်းတစ်မျိုးချင်း ရွေးရန်',
                        ),
                      ),
                    ),
                  ],
                ),
              if (AppCapabilities.windows)
                DesktopInlineTable(
                  columns: const [
                    'Select',
                    'Item code',
                    'Item name',
                    'Sold qty',
                    'Available to return',
                    'Return qty',
                  ],
                  flexes: const [1, 2, 4, 1, 2, 2],
                  rows: List.generate(
                    items.length,
                    (_) => const DesktopListTile(),
                  ),
                  cells: [
                    for (final item in items)
                      [
                        Checkbox(
                          value:
                              (int.tryParse(quantities[item['id']]!.text) ??
                                  0) >
                              0,
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () => quantities[item['id']]!.text = v == true
                                      ? '1'
                                      : '0',
                                ),
                        ),
                        desktopCellText(item['item_code']),
                        desktopCellText(item['item_name']),
                        desktopCellText(item['qty']),
                        desktopCellText(item['remaining']),
                        TextField(
                          controller: quantities[item['id']],
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: _tr('Return qty', 'ပြန်အပ်ဦးရေ'),
                            helperText:
                                _tr('Maximum: ', 'အများဆုံး: ') +
                                item['remaining'].toString(),
                          ),
                        ),
                      ],
                  ],
                )
              else ...[
                for (final item in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${item['item_code']} · ${item['item_name']}',
                            ),
                            subtitle: Text(
                              '${_tr('Sold at', 'ရောင်းဈေး')}: ${AppCurrency.format(item['price'] as int)}  ·  '
                              '${_tr('Sold', 'ရောင်းခဲ့')}: ${item['qty']}  ·  '
                              '${_tr('Available to return', 'ပြန်အပ်နိုင်')}: ${item['remaining']}',
                            ),
                            value:
                                (int.tryParse(
                                      quantities[item['id'] as int]!.text,
                                    ) ??
                                    0) >
                                0,
                            onChanged: busy
                                ? null
                                : (selected) => setState(() {
                                    quantities[item['id'] as int]!.text =
                                        selected == true ? '1' : '0';
                                  }),
                          ),
                          if ((int.tryParse(
                                    quantities[item['id'] as int]!.text,
                                  ) ??
                                  0) >
                              0)
                            TextField(
                              controller: quantities[item['id'] as int],
                              onChanged: (_) => setState(() {}),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: _tr(
                                  'Return quantity',
                                  'ပြန်အပ်အရေအတွက်',
                                ),
                                helperText:
                                    '${_tr('Maximum', 'အများဆုံး')}: ${item['remaining']}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLength: 500,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _tr('Return reason', 'ပြန်အပ်ရသည့်အကြောင်းရင်း'),
                ),
              ),
              Text(
                '${_tr('Estimated refund', 'ခန့်မှန်းပြန်အမ်းငွေ')}: ${AppCurrency.format(expectedRefund)}',
              ),
              if (refunds.length == 1)
                TextButton(
                  onPressed: () => setState(
                    () => refunds.first.amount.text = AppCurrency.input(
                      expectedRefund,
                    ),
                  ),
                  child: Text(
                    _tr(
                      'Use this refund amount',
                      'ဤပြန်အမ်းငွေပမာဏကို သုံးမည်',
                    ),
                  ),
                ),
              DesktopListTile(
                title: Text(
                  '${_tr('Return date', 'ပြန်အပ်ရက်')}: ${_day(date)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && mounted) setState(() => date = picked);
                },
              ),
              Text(_tr('Refund from accounts', 'ငွေပြန်အမ်းမည့် အကောင့်များ')),
              for (var i = 0; i < refunds.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: refunds[i].accountId,
                        isExpanded: true,
                        items: accounts
                            .map(
                              (a) => DropdownMenuItem(
                                value: a['id'] as int,
                                child: Text(
                                  '${a['name']} · ${AppCurrency.format(a['balance'] as int)}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => refunds[i].accountId = v);
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: refunds[i].amount,
                        inputFormatters: const [AmountInputFormatter()],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _tr('Amount', 'ပမာဏ'),
                        ),
                      ),
                    ),
                    if (refunds.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: busy
                            ? null
                            : () {
                                final removed = refunds.removeAt(i);
                                setState(() {});
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => removed.dispose(),
                                );
                              },
                      ),
                  ],
                ),
              TextButton.icon(
                onPressed: busy || accounts.isEmpty
                    ? null
                    : () => setState(
                        () => refunds.add(
                          _RefundInput(accounts.first['id'] as int),
                        ),
                      ),
                icon: const Icon(Icons.add),
                label: Text(
                  _tr(
                    'Add refund account',
                    'ငွေပြန်အမ်းမည့်အကောင့် ထပ်ထည့်ရန်',
                  ),
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed:
                    busy ||
                        saleId == null ||
                        employeeId == null ||
                        items.isEmpty ||
                        accounts.isEmpty
                    ? null
                    : save,
                child: Text(
                  widget.existing == null
                      ? _tr(
                          'Confirm return and refund',
                          'ပစ္စည်းပြန်ယူ၊ ငွေပြန်အမ်းရန် အတည်ပြု',
                        )
                      : _tr(
                          'Void old and issue corrected return',
                          'အဟောင်းပယ်ဖျက်၍ ပြင်ထားသောဘောင်ချာထုတ်ရန်',
                        ),
                ),
              ),
            ],
          ),
  );
}

class _ReturnDetail extends StatefulWidget {
  const _ReturnDetail({required this.returnId});
  final int returnId;
  @override
  State<_ReturnDetail> createState() => _ReturnDetailState();
}

class _ReturnDetailState extends State<_ReturnDetail> {
  Map<String, Object?>? detail;
  String? error;
  bool printing = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await AppDatabase.instance.getSaleReturn(widget.returnId);
      if (mounted) setState(() => detail = value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> linkReplacement() async {
    if (printing || detail == null) return;
    setState(() {
      printing = true;
      error = null;
    });
    try {
      final candidates = await AppDatabase.instance.getSaleExchangeCandidates(
        widget.returnId,
      );
      if (!mounted) return;
      var search = '';
      final chosen = await showDialog<int>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => DesktopDialog(
            title: Text(
              _tr('Link replacement sale', 'အစားထိုးပေးသည့် အရောင်းချိတ်ရန်'),
            ),
            content: SizedBox(
              width: 480,
              height: 380,
              child: Column(
                children: [
                  Text(
                    _tr(
                      'Reporting link only. Record the return/refund and replacement sale first. Same branch/customer; replacement date must be on or after return.',
                      'Report အတွက် ချိတ်မှတ်ခြင်းသာဖြစ်သည်။ Return နှင့် အစားထိုးအရောင်းကို အရင်သိမ်းပါ။ ဆိုင်ခွဲ/ဝယ်သူတူပြီး အစားထိုးအရောင်းရက်သည် Return ရက်ထက် မစောရပါ။',
                    ),
                  ),
                  TextField(
                    decoration: InputDecoration(
                      labelText: _tr(
                        'Search invoice / customer',
                        'ဘောင်ချာ / ဝယ်သူ ရှာရန်',
                      ),
                    ),
                    onChanged: (v) => update(() => search = v.toLowerCase()),
                  ),
                  Expanded(
                    child: DesktopListView(
                      children: [
                        DesktopListTile(
                          title: Text(
                            _tr(
                              'Remove exchange link',
                              'အစားထိုးချိတ်မှတ်မှု ဖြုတ်ရန်',
                            ),
                          ),
                          onTap: () => Navigator.pop(dialog, -1),
                        ),
                        for (final row in candidates.where(
                          (r) =>
                              '${_no('INV', r['id'] as int)} ${r['customer_name']}'
                                  .toLowerCase()
                                  .contains(search),
                        ))
                          DesktopListTile(
                            title: Text(
                              '${_no('INV', row['id'] as int)} · ${row['customer_name']}',
                            ),
                            subtitle: Text(
                              '${row['invoice_date']} · ${AppCurrency.format(row['total'] as int)}',
                            ),
                            onTap: () =>
                                Navigator.pop(dialog, row['id'] as int),
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
                child: Text(_tr('Cancel', 'မလုပ်တော့')),
              ),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      await AppDatabase.instance.linkSaleExchange(
        returnId: widget.returnId,
        replacementSaleId: chosen == -1 ? null : chosen,
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> preview() async {
    if (printing || detail == null) return;
    setState(() {
      printing = true;
      error = null;
    });
    try {
      final settings = await InvoicePrintSettings.load();
      final pdf = await buildSaleReturnPdf(
        returned: detail!,
        settings: settings,
        myanmar:
            settings.language == 'my' ||
            (settings.language == 'app' && AppLanguage.current.value == 'my'),
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(title: Text('${_no('RET', widget.returnId)} · PDF')),
            body: VoucherPdfPreview(
              bytes: pdf.bytes,
              format: pdf.format,
              name: "${_no('RET', widget.returnId)}.pdf",
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> correct() async {
    if (detail == null || detail!['status'] != 'posted') return;
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => _NewSaleReturn(
          branchId: detail!['branch_id'] as int,
          existing: detail,
        ),
      ),
    );
    if (!mounted || id == null) return;
    await load();
    if (!mounted) return;
    await Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(builder: (_) => _ReturnDetail(returnId: id)),
    );
  }

  Future<void> voidReturn() async {
    if (detail == null || detail!['status'] != 'posted') return;
    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(_tr('Void Sale Return', 'ပြန်အပ်ဘောင်ချာ ပယ်ဖျက်ရန်')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tr(
                'This reverses the refund and removes the returned items from stock. The invoice remains in history.',
                'ပြန်အမ်းထားသောငွေကို အကောင့်ထဲပြန်ထည့်ပြီး ပြန်ဝင်ထားသောပစ္စည်းကို Stock မှ နုတ်ပါမည်။ ဘောင်ချာမှတ်တမ်းကျန်ပါမည်။',
              ),
            ),
            TextFormField(
              maxLength: 300,
              onChanged: (v) => reason = v,
              decoration: InputDecoration(
                labelText: _tr('Reason', 'ပယ်ဖျက်ရသည့်အကြောင်းရင်း'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(_tr('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(_tr('Void', 'ပယ်ဖျက်မည်')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      printing = true;
      error = null;
    });
    try {
      await AppDatabase.instance.voidSaleReturn(
        id: widget.returnId,
        reason: reason,
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(_no('RET', widget.returnId)),
      actions: [
        if (detail?['status'] == 'posted')
          IconButton(
            tooltip: _tr('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
            icon: const Icon(Icons.lock_outline),
            onPressed: printing ? null : correct,
          ),
      ],
    ),
    body: detail == null
        ? Center(child: Text(error ?? _tr('Loading…', 'ဖတ်နေသည်…')))
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _tr('Sale Return Invoice', 'အရောင်းပြန်အပ် ဘောင်ချာ'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (detail!['status'] == 'void')
                Text(
                  'VOID · ${detail!['void_reason']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (detail!['replacement_id'] != null)
                Text(
                  '${_tr('Corrected by', 'ပြင်ဆင်ပြီးဘောင်ချာ')}: '
                  '${_no('RET', detail!['replacement_id'] as int)}',
                ),
              Text(
                '${_tr('Original', 'မူရင်း')}: ${_no('INV', detail!['sale_id'] as int)}',
              ),
              Text(
                '${_tr('Return date', 'ပြန်အပ်ရက်')}: ${AppDateTime.format(detail!['created_at'])}',
              ),
              Text(
                '${_tr('Sale person', 'အရောင်းဝန်ထမ်း')}: '
                '${(detail!['employee_name'] as String).isEmpty ? '—' : detail!['employee_name']}',
              ),
              Text('${_tr('Reason', 'အကြောင်းရင်း')}: ${detail!['reason']}'),
              const Divider(),
              for (final row in detail!['items'] as List)
                DesktopListTile(
                  title: Text('${row['item_code']} · ${row['item_name']}'),
                  subtitle: Text(
                    '${row['qty']} ${_tr('returned', 'ခု ပြန်ဝင်')}',
                  ),
                  trailing: MoneyText(
                    row['refund_amount'] as int,
                    currency: detail!['currency_code'] as String,
                    decimalPlaces: detail!['currency_digits'] as int,
                  ),
                ),
              const Divider(),
              Text(
                '${_tr('Refund', 'ပြန်အမ်းငွေ')}: ${AppCurrency.format(detail!['total'] as int, currency: detail!['currency_code'] as String, decimalPlaces: detail!['currency_digits'] as int)}',
              ),
              for (final row in detail!['refunds'] as List)
                Text(
                  '${row['account_name']}: ${AppCurrency.format(row['amount'] as int)}',
                ),
              if (detail!['exchange'] != null)
                Text(
                  '${_tr('Replacement invoice', 'အစားထိုးအရောင်းဘောင်ချာ')}: '
                  '${_no('INV', (detail!['exchange'] as Map)['replacement_sale_id'] as int)} · ${(detail!['exchange'] as Map)['status']}',
                ),
              if (detail!['status'] == 'posted' || detail!['exchange'] != null)
                TextButton.icon(
                  onPressed: printing ? null : linkReplacement,
                  icon: const Icon(Icons.link),
                  label: Text(
                    _tr(
                      'Link / unlink replacement sale',
                      'အစားထိုးအရောင်း ချိတ် / ဖြုတ်ရန်',
                    ),
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (detail!['status'] == 'posted')
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: printing ? null : correct,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(_tr('Correct', 'ပြန်ပြင်ရန်')),
                    ),
                    TextButton.icon(
                      onPressed: printing ? null : voidReturn,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(_tr('Void', 'ပယ်ဖျက်ရန်')),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(_tr('Delete permanently', 'အပြီးတိုင်ဖျက်ရန်')),
                onPressed: printing
                    ? null
                    : () async {
                        final ok = await deleteVoucherWithPrompt(
                          context,
                          kind: 'return',
                          id: widget.returnId,
                          number: _no('RET', widget.returnId),
                        );
                        if (ok && context.mounted) Navigator.pop(context);
                      },
              ),
              FilledButton.icon(
                onPressed: printing ? null : preview,
                icon: const Icon(Icons.print_outlined),
                label: Text(
                  _tr('Print / Save PDF', 'ဘောင်ချာထုတ် / PDF သိမ်း'),
                ),
              ),
            ],
          ),
  );
}
