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
        final pending = _entry && await widget.session.hasPending();
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

  Widget _approve() {
    final products = _rows('stock');
    final accounts = _rows('accounts')
        .where((row) => row['kind'] == 'cash')
        .toList();
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
        DropdownButtonFormField<String>(
          initialValue: _account,
          decoration: const InputDecoration(labelText: 'Cash account'),
          items: [
            for (final row in accounts)
              DropdownMenuItem(
                value: row['id'] as String,
                child: Text('${row['name']}'),
              ),
          ],
          onChanged: _busy || _pending
              ? null
              : (id) => setState(() => _account = id),
        ),
        Text(_money(quantity * price)),
        if (_pending)
          FilledButton(
            onPressed: _busy ? null : () => _run(widget.session.retry),
            child: const Text('Retry pending voucher'),
          )
        else
          FilledButton(
            onPressed:
                _busy ||
                    _product == null ||
                    _account == null ||
                    quantity <= 0 ||
                    price <= 0 ||
                    (serials != null && serials.length != quantity)
                ? null
                : () => _run(() async {
                    await widget.session.post(
                      kind: _sale ? 'sale' : 'purchase',
                      product: _product!,
                      account: _account!,
                      quantity: quantity,
                      unitPrice: price,
                      serials: serials,
                    );
                    if (mounted) {
                      _quantity.text = '1';
                      _product = null;
                      _price.clear();
                      _serialInput.clear();
                      _selectedSerial = null;
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
            ListTile(
              title: Text('${row['number'] ?? row['occurred_at']}'),
              subtitle: row['archived'] == true
                  ? Text('${row['invoice_date']} · ${row['status']}')
                  : null,
              trailing: Text(_money(row['total'])),
            ),
      ],
    );
  }
}
