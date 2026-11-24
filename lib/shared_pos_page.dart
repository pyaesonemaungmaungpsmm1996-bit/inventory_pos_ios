import 'dart:async';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_language.dart';
import 'shared_pos_session.dart';

enum SharedPosPageKind {
  dashboard,
  sale,
  purchase,
  sales,
  purchases,
  stock,
  accounts,
  transfer,
  customerBalances,
  supplierBalances,
  expense,
  expenses,
}

class SharedPosPage extends StatefulWidget {
  const SharedPosPage({super.key, required this.session, required this.kind, this.voucherReference, this.filterCounterparty = false, this.counterparty});
  final SharedPosSession session;
  final SharedPosPageKind kind;
  final String? voucherReference;
  final bool filterCounterparty;
  final String? counterparty;

  @override
  State<SharedPosPage> createState() => _SharedPosPageState();
}

class _SharedPosPageState extends State<SharedPosPage> {
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _serialInput = TextEditingController();
  final _paymentAmount = TextEditingController();
  final _discount = TextEditingController();
  final _counterparty = TextEditingController();
  final _lines = <SharedPosLine>[];
  final _payments = <String, int>{};
  String? _selectedSerial;
  Map<String, dynamic>? _view;
  Map<String, dynamic>? _dashboard;
  List<Map> _openBalances = [];
  bool _thisMonth = true;
  String? _product, _account, _message;
  bool _busy = false, _pending = false;
  Timer? _timer;

  bool get _sale => widget.kind == SharedPosPageKind.sale;
  bool get _entry => _sale || widget.kind == SharedPosPageKind.purchase;
  bool get _balancePage =>
      widget.kind == SharedPosPageKind.customerBalances ||
      widget.kind == SharedPosPageKind.supplierBalances;

  List<Map> _rows(String key) => (_view?[key] as List? ?? []).cast<Map>();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_entry) unawaited(_run());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _quantity.dispose();
    _price.dispose();
    _serialInput.dispose();
    _paymentAmount.dispose();
    _discount.dispose();
    _counterparty.dispose();
    super.dispose();
  }

  Future<void> _run([Future<void> Function()? action]) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (action != null) await action();
      final view = await widget.session.load();
      final dashboard = widget.kind == SharedPosPageKind.dashboard
          ? await widget.session.dashboard()
          : null;
      final balances = _balancePage
          ? await widget.session.openBalances(
              widget.kind == SharedPosPageKind.customerBalances
                  ? 'sale'
                  : 'purchase',
            )
          : <Map>[];
      if (mounted) {
        setState(() {
          _view = view;
          _dashboard = dashboard;
          _openBalances = widget.filterCounterparty
              ? balances.where((row) => row['counterparty'] == widget.counterparty).toList()
              : balances;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      try {
        final pending = await widget.session.hasPending();
        if (mounted) setState(() => _pending = pending);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  String _money(Object? amount) => AppCurrency.format(
    (amount as num?)?.toInt() ?? 0,
    currency: _view?['currency'] as String?,
    decimalPlaces: 0,
  );

  void _resetLine() {
    _quantity.text = '1';
    _product = null;
    _price.clear();
    _serialInput.clear();
    _selectedSerial = null;
  }

  void _resetVoucher() {
    _lines.clear();
    _payments.clear();
    _paymentAmount.clear();
    _discount.clear();
    _counterparty.clear();
    _account = null;
    _resetLine();
  }

  Widget _approve() {
    final products = _rows('stock');
    final accounts = _rows('accounts');
    final subtotal = _lines.fold<int>(
      0,
      (total, line) => total + line.quantity * line.unitPrice,
    );
    final discount = _discount.text.isEmpty ? 0 : int.tryParse(_discount.text);
    final total = subtotal - (discount ?? 0);
    final paid = _payments.values.fold<int>(
      0,
      (total, amount) => total + amount,
    );
    final payment = int.tryParse(_paymentAmount.text) ?? 0;
    final quantity = int.tryParse(_quantity.text) ?? 0;
    final price = int.tryParse(_price.text) ?? 0;
    final availableSerials = (_view?['serials'] as Map?)?[_product] as List?;
    final tracked = availableSerials != null;
    final serials = !tracked
        ? null
        : _sale
        ? [?_selectedSerial]
        : _serialInput.text
              .split('\n')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
    return Column(
      children: [
        for (final line in _lines)
          ListTile(
            title: Text(line.label),
            subtitle: Text('${line.quantity} × ${_money(line.unitPrice)}'),
            trailing: IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.close),
              onPressed: _busy || _pending
                  ? null
                  : () => setState(() => _lines.remove(line)),
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey(_product),
          initialValue: _product,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Item'),
          items: [
            for (final row in products)
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text(
                  '${row['code']} · ${row['name']} (${row['available_online']})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy || _pending
              ? null
              : (id) => setState(() {
                  _product = id;
                  _selectedSerial = null;
                  _serialInput.clear();
                  if (_sale) {
                    _price.text =
                        '${products.firstWhere((row) => row['id'] == id)['price']}';
                  }
                }),
        ),
        TextField(
          controller: _quantity,
          keyboardType: TextInputType.number,
          enabled: !_busy && !_pending,
          decoration: const InputDecoration(labelText: 'Quantity'),
          onChanged: (_) => setState(() {}),
        ),
        if (tracked && _sale)
          DropdownButtonFormField<String>(
            key: ValueKey('serial:$_product'),
            initialValue: _selectedSerial,
            decoration: const InputDecoration(labelText: 'Serial number'),
            items: [
              for (final serial in availableSerials.cast<String>())
                DropdownMenuItem(value: serial, child: Text(serial)),
            ],
            onChanged: _busy || _pending
                ? null
                : (serial) => setState(() {
                    _selectedSerial = serial;
                    _quantity.text = '1';
                  }),
          ),
        if (tracked && !_sale)
          TextField(
            controller: _serialInput,
            enabled: !_busy && !_pending,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Serials, one per line',
            ),
            onChanged: (_) => setState(() {}),
          ),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          enabled: !_sale && !_busy && !_pending,
          decoration: const InputDecoration(labelText: 'Unit price'),
          onChanged: (_) => setState(() {}),
        ),
        OutlinedButton(
          onPressed:
              _busy ||
                  _pending ||
                  _product == null ||
                  _lines.length >= 100 ||
                  quantity <= 0 ||
                  quantity > 999999999 ||
                  price <= 0 ||
                  price > 9999999999999 ~/ quantity ||
                  subtotal + quantity * price > 9999999999999 ||
                  _lines.any((line) => line.product == _product) ||
                  (serials != null && serials.length != quantity)
              ? null
              : () => setState(() {
                  final productId = _product!;
                  final row = products.firstWhere(
                    (row) => row['id'] == productId,
                  );
                  _lines.add((
                    product: productId,
                    label: '${row['code']} · ${row['name']}',
                    quantity: quantity,
                    unitPrice: price,
                    serials: serials,
                  ));
                  _resetLine();
                }),
          child: const Text('Add item'),
        ),
        if (_sale)
          TextField(
            controller: _discount,
            keyboardType: TextInputType.number,
            enabled: !_busy && !_pending,
            decoration: const InputDecoration(labelText: 'Discount amount'),
            onChanged: (_) => setState(() {}),
          ),
        for (final entry in _payments.entries)
          ListTile(
            title: Text(
              '${accounts.firstWhere((row) => row['id'] == entry.key)['name']}',
            ),
            subtitle: Text(_money(entry.value)),
            trailing: IconButton(
              tooltip: 'Remove payment',
              icon: const Icon(Icons.close),
              onPressed: _busy || _pending
                  ? null
                  : () => setState(() => _payments.remove(entry.key)),
            ),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('account:$_account'),
          initialValue: _account,
          decoration: const InputDecoration(labelText: 'Payment account'),
          items: [
            for (final row in accounts)
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text('${row['name']}'),
              ),
          ],
          onChanged: _busy || _pending
              ? null
              : (id) => setState(() {
                  _account = id;
                  if (total > paid) _paymentAmount.text = '${total - paid}';
                }),
        ),
        TextField(
          controller: _paymentAmount,
          enabled: !_busy && !_pending,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Payment amount'),
          onChanged: (_) => setState(() {}),
        ),
        OutlinedButton(
          onPressed:
              _busy ||
                  _pending ||
                  _account == null ||
                  _payments.length >= 20 ||
                  _payments.containsKey(_account) ||
                  payment <= 0 ||
                  payment > total - paid
              ? null
              : () => setState(() {
                  _payments[_account!] = payment;
                  _account = null;
                  _paymentAmount.clear();
                }),
          child: const Text('Add payment'),
        ),
        Text('Total: ${_money(total)} · Paid: ${_money(paid)}'),
        if (total > paid)
          TextField(
            controller: _counterparty,
            enabled: !_busy && !_pending,
            maxLength: 150,
            decoration: InputDecoration(
              labelText: _sale
                  ? 'Customer name for credit sale'
                  : 'Supplier name for credit purchase',
            ),
            onChanged: (_) => setState(() {}),
          ),
        if (_pending)
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await widget.session.retry();
                    if (mounted) setState(_resetVoucher);
                  }),
            child: const Text('Retry pending voucher'),
          )
        else
          FilledButton(
            onPressed:
                _busy ||
                    _lines.isEmpty ||
                    _product != null ||
                    discount == null ||
                    discount < 0 ||
                    total <= 0 ||
                    paid > total ||
                    (paid < total && _counterparty.text.trim().isEmpty)
                ? null
                : () => _run(() async {
                    await widget.session.post(
                      kind: _sale ? 'sale' : 'purchase',
                      lines: _lines,
                      payments: _payments,
                      discount: discount,
                      counterparty: _counterparty.text,
                    );
                    if (mounted) {
                      setState(_resetVoucher);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Voucher saved')),
                      );
                    }
                  }),
            child: Text(_sale ? 'Confirm sale' : 'Confirm purchase'),
          ),
      ],
    );
  }

  Future<void> _settle(Map voucher) async {
    final accounts = _rows('accounts');
    final due = voucher['due'] as int;
    var amount = due;
    String? account;
    final payment = await showDialog<({String account, int amount})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            voucher['kind'] == 'sale'
                ? 'Receive payment'
                : 'Record supplier payment',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Payment account'),
                items: [
                  for (final row in accounts)
                    DropdownMenuItem(
                      value: row['id'] as String,
                      child: Text('${row['name']}'),
                    ),
                ],
                onChanged: (id) => update(() => account = id),
              ),
              TextFormField(
                initialValue: '$due',
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    update(() => amount = int.tryParse(value) ?? 0),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: account == null || amount <= 0 || amount > due
                  ? null
                  : () => Navigator.pop(context, (
                      account: account!,
                      amount: amount,
                    )),
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || payment == null) return;
    await _run(
      () => widget.session.settle(
        (voucher['archive_key'] ?? voucher['id']) as String,
        payment.account,
        payment.amount,
        archived: voucher['archived'] == true,
      ),
    );
  }

  Future<void> _voidVoucher(Map voucher) async {
    var reason = '';
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Void this voucher?'),
          content: TextField(
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Void reason'),
            onChanged: (value) => update(() => reason = value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: reason.isEmpty
                  ? null
                  : () => Navigator.pop(context, reason),
              child: const Text('Void voucher'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed == null) return;
    await _run(
      () => widget.session.voidVoucher(voucher['id'] as String, confirmed),
    );
  }

  Future<void> _addExpense() async {
    String? account;
    var amount = 0;
    var note = '';
    final expense =
        await showDialog<({String account, int amount, String note})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('Add expense'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Payment account',
                      ),
                      items: [
                        for (final row in _rows('accounts'))
                          DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text('${row['name']}'),
                          ),
                      ],
                      onChanged: (value) => update(() => account = value),
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          update(() => amount = int.tryParse(value) ?? 0),
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      maxLength: 300,
                      onChanged: (value) => update(() => note = value.trim()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: account == null || amount <= 0 || note.isEmpty
                      ? null
                      : () => Navigator.pop(context, (
                          account: account!,
                          amount: amount,
                          note: note,
                        )),
                  child: const Text('Save expense'),
                ),
              ],
            ),
          ),
        );
    if (!mounted || expense == null) return;
    await _run(
      () =>
          widget.session.expense(expense.account, expense.amount, expense.note),
    );
  }

  Future<void> _transfer() async {
    String? source, destination;
    var amount = 0;
    final transfer =
        await showDialog<({String source, String destination, int amount})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) {
              final accounts = [
                for (final row in _rows('accounts'))
                  DropdownMenuItem(
                    value: row['id'] as String,
                    child: Text('${row['name']}'),
                  ),
              ];
              return AlertDialog(
                title: const Text('Account transfer'),
                content: SingleChildScrollView(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'From account',
                        ),
                        items: accounts,
                        onChanged: (value) => update(() => source = value),
                      ),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'To account',
                        ),
                        items: accounts,
                        onChanged: (value) => update(() => destination = value),
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'Amount'),
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            update(() => amount = int.tryParse(value) ?? 0),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        source == null ||
                            destination == null ||
                            source == destination ||
                            amount <= 0
                        ? null
                        : () => Navigator.pop(context, (
                            source: source!,
                            destination: destination!,
                            amount: amount,
                          )),
                    child: const Text('Record transfer'),
                  ),
                ],
              );
            },
          ),
        );
    if (!mounted || transfer == null) return;
    await _run(
      () => widget.session.transfer(
        transfer.source,
        transfer.destination,
        transfer.amount,
      ),
    );
  }

  int _remainingReturn(Map voucher, Map line) {
    final returned = (voucher['returns'] as List? ?? []).cast<Map>();
    return (line['qty'] as int) -
        returned
            .where((row) => row['product_id'] == line['product_id'])
            .fold<int>(0, (total, row) => total + (row['quantity'] as int));
  }

  Future<void> _returnLine(Map voucher, Map line) async {
    final maxUnits = _remainingReturn(voucher, line);
    final returnedSerials = {
      for (final row in (voucher['returns'] as List? ?? []).cast<Map>())
        if (row['product_id'] == line['product_id'])
          ...(row['serials'] as List).cast<String>(),
    };
    final sold = line['serials'] as List?;
    final serialOptions = sold?.cast<String>().where(
      (value) => !returnedSerials.contains(value.trim().toUpperCase()),
    );
    String? account, serial;
    var units = 1;
    int? amount;
    final result =
        await showDialog<
          ({String account, int units, int amount, String? serial})
        >(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text('Return ${line['item_code']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (serialOptions != null)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Serial number',
                        ),
                        items: [
                          for (final value in serialOptions)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) => update(() => serial = value),
                      )
                    else
                      TextFormField(
                        initialValue: '1',
                        decoration: InputDecoration(
                          labelText: 'Quantity (up to $maxUnits)',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            update(() => units = int.tryParse(value) ?? 0),
                      ),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Refund account',
                      ),
                      items: [
                        for (final row in _rows('accounts'))
                          DropdownMenuItem(
                            value: row['id'] as String,
                            child: Text('${row['name']}'),
                          ),
                      ],
                      onChanged: (value) => update(() => account = value),
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Refund amount',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          update(() => amount = int.tryParse(value)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed:
                      units < 1 ||
                          units > maxUnits ||
                          account == null ||
                          (serialOptions != null && serial == null) ||
                          amount == null ||
                          amount! < 0
                      ? null
                      : () => Navigator.pop(context, (
                          account: account!,
                          units: units,
                          amount: amount!,
                          serial: serial,
                        )),
                  child: const Text('Confirm return'),
                ),
              ],
            ),
          ),
        );
    if (!mounted || result == null) return;
    await _run(
      () => widget.session.returnSale(
        sale: voucher['id'] as String,
        product: line['product_id'] as String,
        account: result.account,
        units: result.units,
        refund: result.amount,
        serials: [?result.serial],
      ),
    );
  }

  List<Widget> _dashboardOverview(
    Map<String, dynamic> dashboard,
    List<Map> accounts,
    List<Map> vouchers,
  ) {
    String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
    Widget amount(IconData icon, String label, Object? value) => Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(
          _money(value),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
    final recent = [...vouchers]..sort(
      (a, b) => '${b['occurred_at']}'.compareTo('${a['occurred_at']}'),
    );
    final empty =
        accounts.isEmpty && vouchers.isEmpty && _rows('stock').isEmpty;
    return [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(value: false, label: Text(t('Today', 'ဒီနေ့'))),
          ButtonSegment(value: true, label: Text(t('This month', 'ဒီလ'))),
        ],
        selected: {_thisMonth},
        onSelectionChanged: (value) => setState(() => _thisMonth = value.single),
      ),
      if (empty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(t(
            'No stock, accounts or recent vouchers are available in this cloud branch. If your records are on Windows, ask the owner to import the opening records.',
            'ဒီ cloud ဆိုင်ခွဲမှာ လက်ကျန်၊ ငွေအကောင့်နဲ့ လတ်တလောဘောင်ချာတွေ မရှိသေးပါ။ စာရင်းတွေ Windows မှာရှိရင် Owner က အဖွင့်စာရင်းတင်ပေးနိုင်ပါတယ်။',
          )),
        ),
      amount(
        Icons.trending_up,
        t('Sales after refunds', 'ပြန်အမ်းငွေနုတ်ပြီး အရောင်း'),
        dashboard[_thisMonth ? 'sales_month' : 'sales_today'],
      ),
      amount(
        Icons.receipt_long_outlined,
        t('Expenses', 'အသုံးစရိတ်'),
        dashboard[_thisMonth ? 'expenses_month' : 'expenses_today'],
      ),
      amount(
        Icons.account_balance_wallet_outlined,
        t('Current account balance', 'လက်ရှိငွေအကောင့်လက်ကျန်'),
        dashboard['balance'],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(t('Recent transactions', 'လတ်တလောစာရင်းများ'),
            style: Theme.of(context).textTheme.titleMedium),
      ),
      if (vouchers.isEmpty)
        Text(t('No recent transactions.', 'လတ်တလောစာရင်းမရှိသေးပါ။')),
      for (final row in recent.take(5))
        ListTile(
          title: Text('${row['number'] ?? row['note'] ?? row['kind']}'),
          subtitle: Text('${row['invoice_date'] ?? row['occurred_at']}'),
          trailing: Text(_money(row['total'])),
        ),
    ];
  }
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final accounts = _rows('accounts');
    final vouchers = _rows('vouchers');
    final visibleVouchers = _balancePage
        ? _openBalances
        : vouchers.where(
            (row) => kind == SharedPosPageKind.sales
                ? row['kind'] == 'sale'
                : row['kind'] == 'purchase',
          );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          title: Text('Shared POS · ${widget.session.connection.branchCode}'),
          trailing: IconButton(
            onPressed: _busy ? null : () => _run(),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) SelectableText(_message!),
        if (!_entry && _pending)
          FilledButton(
            onPressed: _busy ? null : () => _run(widget.session.retry),
            child: const Text('Retry pending transaction'),
          ),
        if (_view != null && _entry) _approve(),
        if (_view != null && kind == SharedPosPageKind.expense)
          FilledButton(
            onPressed: _busy || _pending ? null : _addExpense,
            child: const Text('Add expense'),
          ),
        if (kind == SharedPosPageKind.expense ||
            kind == SharedPosPageKind.expenses)
          for (final row in vouchers.where((row) => row['kind'] == 'expense'))
            ListTile(
              title: Text('${row['note'] ?? 'Expense'}'),
              subtitle: Text('${row['occurred_at']}'),
              trailing: Text(_money(row['total'])),
            ),
        if (_dashboard case final dashboard?)
          ..._dashboardOverview(dashboard, accounts, vouchers),
        if (kind == SharedPosPageKind.stock)
          for (final row in _rows('stock'))
            ListTile(
              title: Text('${row['code']} · ${row['name']}'),
              trailing: Text('${row['on_hand']}'),
            ),
        if (_view != null && kind == SharedPosPageKind.transfer)
          FilledButton(
            onPressed: _busy || _pending || accounts.length < 2
                ? null
                : _transfer,
            child: const Text('New account transfer'),
          ),
        if (kind == SharedPosPageKind.accounts ||
            kind == SharedPosPageKind.transfer)
          for (final row in accounts)
            ListTile(
              title: Text('${row['name']}'),
              trailing: Text(_money(row['balance'])),
            ),
        if (_balancePage && _view != null)
          ListTile(
            title: Text(
              kind == SharedPosPageKind.customerBalances
                  ? 'Customer balances due'
                  : 'Supplier balances due',
            ),
            trailing: Text(
              _money(
                _openBalances.fold<int>(
                  0,
                  (sum, row) => sum + (row['due'] as int),
                ),
              ),
            ),
          ),
        if (_balancePage ||
            kind == SharedPosPageKind.sales ||
            kind == SharedPosPageKind.purchases)
          for (final row in visibleVouchers.where((row) =>
              widget.voucherReference == null || row['number'] == widget.voucherReference))
            ExpansionTile(
              title: Text('${row['number'] ?? row['occurred_at']}'),
              subtitle: row['status'] == 'void'
                  ? const Text('Voided')
                  : row['archived'] == true
                  ? Text('${row['invoice_date']}')
                  : null,
              trailing: Text(_money(row['total'])),
              children: [
                for (final line in (row['lines'] as List? ?? []).cast<Map>())
                  ListTile(
                    title: Text('${line['item_code']} · ${line['item_name']}'),
                    subtitle: Text(
                      '${line['qty']} × ${_money(line['unit_price'])}',
                    ),
                    trailing:
                        row['can_return'] == true &&
                            _remainingReturn(row, line) > 0
                        ? TextButton(
                            onPressed: _busy || _pending
                                ? null
                                : () => _returnLine(row, line),
                            child: const Text('Return'),
                          )
                        : Text(_money(line['amount'])),
                  ),
                ListTile(
                  title: Text('Paid: ${_money(row['paid'])}'),
                  subtitle: Text('Balance due: ${_money(row['due'])}'),
                ),
                if ((row['returns'] as List?)?.isNotEmpty == true)
                  ListTile(title: Text('Refunded: ${_money(row['refunded'])}')),
                if (row['counterparty'] case final String name)
                  ListTile(title: Text(name)),
                if (row['void_reason'] case final String reason)
                  ListTile(
                    title: const Text('Void reason'),
                    subtitle: Text(reason),
                  ),
                if (row['can_void'] == true)
                  OutlinedButton(
                    onPressed: _busy || _pending
                        ? null
                        : () => _voidVoucher(row),
                    child: const Text('Void voucher'),
                  ),
                if ((row['archive_key'] != null || row['id'] != null) &&
                    (row['due'] as int) > 0)
                  OutlinedButton(
                    onPressed: _busy || _pending ? null : () => _settle(row),
                    child: Text(
                      row['kind'] == 'sale'
                          ? 'Receive payment'
                          : 'Record supplier payment',
                    ),
                  ),
              ],
            ),
      ],
    );
  }
}
