import 'dart:async';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'shared_pos_session.dart';

enum SharedPosPageKind {
  dashboard,
  sale,
  purchase,
  sales,
  purchases,
  stock,
  accounts,
}

class SharedPosPage extends StatefulWidget {
  const SharedPosPage({super.key, required this.session, required this.kind});
  final SharedPosSession session;
  final SharedPosPageKind kind;

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
  String? _product, _account, _message;
  bool _busy = false, _pending = false;
  Timer? _timer;

  bool get _sale => widget.kind == SharedPosPageKind.sale;
  bool get _entry => _sale || widget.kind == SharedPosPageKind.purchase;

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
      if (mounted) setState(() => _view = view);
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
        voucher['id'] as String,
        payment.account,
        payment.amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final accounts = _rows('accounts');
    final vouchers = _rows('vouchers');
    final visibleVouchers = vouchers.where(
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
        if (_view != null && kind == SharedPosPageKind.dashboard)
          ListTile(
            title: const Text('Current account balance'),
            trailing: Text(
              _money(
                accounts.fold<int>(
                  0,
                  (sum, row) => sum + (row['balance'] as int),
                ),
              ),
            ),
          ),
        if (kind == SharedPosPageKind.stock)
          for (final row in _rows('stock'))
            ListTile(
              title: Text('${row['code']} · ${row['name']}'),
              trailing: Text('${row['on_hand']}'),
            ),
        if (kind == SharedPosPageKind.accounts)
          for (final row in accounts)
            ListTile(
              title: Text('${row['name']}'),
              trailing: Text(_money(row['balance'])),
            ),
        if (kind == SharedPosPageKind.sales ||
            kind == SharedPosPageKind.purchases)
          for (final row in visibleVouchers)
            ExpansionTile(
              title: Text('${row['number'] ?? row['occurred_at']}'),
              subtitle: row['archived'] == true
                  ? Text('${row['invoice_date']} · ${row['status']}')
                  : null,
              trailing: Text(_money(row['total'])),
              children: [
                for (final line in (row['lines'] as List? ?? []).cast<Map>())
                  ListTile(
                    title: Text('${line['item_code']} · ${line['item_name']}'),
                    subtitle: Text(
                      '${line['qty']} × ${_money(line['unit_price'])}',
                    ),
                    trailing: Text(_money(line['amount'])),
                  ),
                ListTile(
                  title: Text('Paid: ${_money(row['paid'])}'),
                  subtitle: Text('Balance due: ${_money(row['due'])}'),
                ),
                if (row['counterparty'] case final String name)
                  ListTile(title: Text(name)),
                if (row['archived'] != true && (row['due'] as int) > 0)
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
