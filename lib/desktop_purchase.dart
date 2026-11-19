part of 'purchase_page.dart';

extension _DesktopPurchaseEditor on _PurchasePageState {
  List<Map<String, Object?>> purchaseMatches(String text) {
    final query = text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    bool exact(Map p) => [
      p['item_code'],
      p['barcode'],
    ].any((v) => v?.toString().toLowerCase() == query);
    final found = products
        .where(
          (p) => [
            p['name'],
            p['item_code'],
            p['barcode'],
            p['color'],
            p['size'],
          ].any((v) => v?.toString().toLowerCase().contains(query) ?? false),
        )
        .toList();
    found.sort((a, b) {
      final priority = (exact(a) ? 0 : 1).compareTo(exact(b) ? 0 : 1);
      return priority != 0
          ? priority
          : a['name'].toString().compareTo(b['name'].toString());
    });
    return found.take(30).toList();
  }

  FocusNode purchaseCellNode(Map<String, Object?> line, String field) =>
      purchaseCellNodes.putIfAbsent(
        '${identityHashCode(line)}:$field',
        () => FocusNode(),
      );
  Future<void> choosePurchaseItem([Map<String, Object?>? product]) async {
    if (loading || posting || choosingPurchaseItem || !ready) return;
    choosingPurchaseItem = true;
    try {
      final existing = product == null
          ? -1
          : lines.indexWhere((line) => line['product_id'] == product['id']);
      purchaseSearch.clear();
      desktopUpdate(() => purchaseLookupError = null);
      purchaseSearchFocus.unfocus();
      if (existing >= 0) desktopUpdate(() => selectedLine = existing);
      await addLine(
        existing < 0 ? null : existing,
        false,
        existing >= 0,
        product,
      );
    } finally {
      choosingPurchaseItem = false;
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        purchaseSearchFocus.requestFocus();
      }
    }
  }

  Widget purchaseEntryBar() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) => RawAutocomplete<Map<String, Object?>>(
            textEditingController: purchaseSearch,
            focusNode: purchaseSearchFocus,
            displayStringForOption: (p) => p['name'].toString(),
            optionsBuilder: (value) => purchaseMatches(value.text),
            onSelected: (product) => unawaited(choosePurchaseItem(product)),
            fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
              key: const ValueKey('purchase-item-search'),
              controller: controller,
              focusNode: focus,
              enabled: !posting && !loading,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                labelText: _t(
                  'Scan barcode or search item name / code',
                  'Barcode Scan သို့မဟုတ် ပစ္စည်းအမည် / ကုဒ် ရှာရန်',
                ),
                helperText: _t(
                  'Enter to choose · F2 / Ctrl+F to search · F3 for a new item',
                  'Enter ဖြင့်ရွေးရန် · F2 / Ctrl+F ရှာရန် · F3 ပစ္စည်းအသစ်',
                ),
                errorText: purchaseLookupError,
                suffixIcon: IconButton(
                  tooltip: _t('Clear search', 'ရှာထားသည်ဖယ်ရန်'),
                  icon: const Icon(Icons.close, size: 17),
                  onPressed: () {
                    purchaseSearch.clear();
                    desktopUpdate(() => purchaseLookupError = null);
                    purchaseSearchFocus.requestFocus();
                  },
                ),
              ),
              onChanged: (_) {
                if (purchaseLookupError != null) {
                  desktopUpdate(() => purchaseLookupError = null);
                }
              },
              onSubmitted: (text) {
                final matches = purchaseMatches(text);
                final q = text.trim().toLowerCase();
                final exact = matches
                    .where(
                      (p) => [
                        p['item_code'],
                        p['barcode'],
                      ].any((v) => v?.toString().toLowerCase() == q),
                    )
                    .toList();
                if (exact.length == 1) {
                  unawaited(choosePurchaseItem(exact.single));
                } else if (exact.length > 1) {
                  desktopUpdate(
                    () => purchaseLookupError = _t(
                      'Several items use this barcode. Select the correct item below.',
                      'ဤ Barcode သုံးထားသော ပစ္စည်းများရှိသည်။ အောက်မှ မှန်ကန်သောပစ္စည်း ရွေးပါ။',
                    ),
                  );
                } else if (matches.isNotEmpty) {
                  onSubmit();
                } else if (q.isNotEmpty) {
                  desktopUpdate(
                    () => purchaseLookupError = _t(
                      'No matching item. Use New item to create one.',
                      'ပစ္စည်းမတွေ့ပါ။ New item ဖြင့် အသစ်ထည့်နိုင်သည်။',
                    ),
                  );
                }
              },
            ),
            optionsViewBuilder: (context, onSelected, options) {
              final matches = options.toList();
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: (matches.length.clamp(1, 5) * 52).toDouble(),
                    child: ListView.builder(
                      key: const ValueKey('purchase-search-results'),
                      // Keep compatibility with the desktop SDK already used by this app.
                      // ignore: deprecated_member_use
                      cacheExtent: 2000,
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final p = matches[i];
                        final highlighted =
                            AutocompleteHighlightedOption.of(context) == i;
                        if (highlighted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (context.mounted) {
                              Scrollable.ensureVisible(
                                context,
                                duration: const Duration(milliseconds: 80),
                              );
                            }
                          });
                        }
                        return ListTile(
                          dense: true,
                          selected: highlighted,
                          title: Text(
                            p['name'].toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                                  p['item_code'],
                                  p['barcode'],
                                  p['color'],
                                  p['size'],
                                ]
                                .where(
                                  (v) => v != null && v.toString().isNotEmpty,
                                )
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => onSelected(p),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        key: const ValueKey('purchase-new-item'),
        onPressed: posting ? null : () => choosePurchaseItem(),
        icon: const Icon(Icons.add, size: 18),
        label: Text(_t('New item · F3', 'ပစ္စည်းအသစ် · F3')),
      ),
    ],
  );
  Widget purchaseNumberCell(
    Map<String, Object?> line,
    int index,
    String field,
  ) {
    final quantity = field == 'qty';
    final tracked = quantity && (line['tracking'] ?? 'none') != 'none';
    final value = line[field] as int?;
    return TextFormField(
      key: ValueKey('purchase-cell-$field-${identityHashCode(line)}'),
      focusNode: purchaseCellNode(line, field),
      initialValue: value == null
          ? ''
          : quantity
          ? value.toString()
          : AmountInputFormatter.group(AppCurrency.input(value)),
      enabled: !posting,
      readOnly: tracked,
      onTap: tracked ? () => addLine(index, false, true) : null,
      keyboardType: TextInputType.numberWithOptions(decimal: !quantity),
      inputFormatters: quantity ? null : const [AmountInputFormatter()],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (text) {
        final n = quantity
            ? int.tryParse(text?.trim() ?? '')
            : AppCurrency.tryParse(text?.trim() ?? '');
        if (!quantity && (text?.trim().isEmpty ?? true)) return null;
        return n != null && n >= (quantity ? 1 : 0) && n <= 2147483647
            ? null
            : _t('Invalid', 'မမှန်ပါ');
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        hintText: quantity ? '1' : _t('Price', 'ဈေး'),
        suffixIcon: tracked ? const Icon(Icons.edit_outlined, size: 14) : null,
      ),
      onChanged: (text) {
        final raw = text.trim();
        final number = quantity ? int.tryParse(raw) : AppCurrency.tryParse(raw);
        desktopUpdate(
          () => line[field] = quantity
              ? (number ?? 0)
              : raw.isEmpty
              ? (field == 'purchase_price' ? 0 : null)
              : (number ?? -1),
        );
        _touch();
      },
    );
  }

  Widget desktopPurchaseEditor() {
    Widget button(String label, IconData icon, VoidCallback? action) =>
        OutlinedButton.icon(
          onPressed: posting ? null : action,
          icon: Icon(icon, size: 17),
          label: Text(label),
        );
    return DesktopScaffold(
      body: DesktopVoucherWorkspace(
        commands: [
          button(_t('New', 'အသစ်'), Icons.note_add_outlined, discardWork),
          button(
            '${_t('Save Draft', 'Draft သိမ်းရန်')} · Ctrl+S',
            Icons.save_outlined,
            saveWork,
          ),
          button(
            '${_t('Add Item', 'ပစ္စည်းထည့်ရန်')} · F3',
            Icons.add,
            () => choosePurchaseItem(),
          ),
          button(
            _t('Barcode', 'ဘားကုဒ်'),
            Icons.qr_code_scanner,
            () => purchaseSearchFocus.requestFocus(),
          ),
          button(
            _t('Categories', 'အမျိုးအစားများ'),
            Icons.category_outlined,
            manageCategories,
          ),
          button(
            _t('Suppliers', 'ပေးသွင်းသူများ'),
            Icons.people_outline,
            manageSuppliers,
          ),
          button(_t('History', 'မှတ်တမ်း'), Icons.history, () async {
            await _saveNow();
            if (!mounted || saveFailed) return;
            await openPurchaseManager(
              _t('Purchase History', 'အဝယ်မှတ်တမ်း'),
              PurchaseHistoryPage(
                initialBranchId: branchId,
                allowDraftEditing: false,
              ),
            );
            if (mounted) await load();
          }),
          FilledButton.icon(
            onPressed: posting || lines.isEmpty ? null : keyboardPost,
            icon: const Icon(Icons.check, size: 17),
            label: Text(_t('Confirm Purchase', 'အဝယ်အတည်ပြုရန်')),
          ),
        ],
        metadata: [
          TextFormField(
            key: const ValueKey('purchase-invoice-number'),
            initialValue: _t('Assigned on confirm', 'အတည်ပြုချိန် နံပါတ်ရမည်'),
            readOnly: true,
            decoration: InputDecoration(
              labelText: _t('Invoice No.', 'ဘောင်ချာနံပါတ်'),
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: branchId,
            decoration: InputDecoration(labelText: _t('Branch', 'ဆိုင်ခွဲ')),
            items: [
              for (final b in branches)
                DropdownMenuItem(
                  value: b['id'] as int,
                  child: Text('${b['name']} (${b['code']})'),
                ),
            ],
            onChanged: posting || lines.isNotEmpty || paid != 0
                ? null
                : (id) async {
                    if (id == null || id == branchId) return;
                    for (final c in payments.values) {
                      c.dispose();
                    }
                    payments.clear();
                    desktopUpdate(() {
                      branchId = id;
                      accounts = [];
                    });
                    await load();
                    _touch();
                  },
          ),
          OutlinedButton.icon(
            onPressed: posting ? null : selectDate,
            icon: const Icon(Icons.calendar_month, size: 17),
            label: Text(
              '${_t('Purchase date', 'အဝယ်ရက်')}: ${_date(purchaseDate)}',
            ),
          ),
          DropdownButtonFormField<int>(
            focusNode: supplierFocus,
            initialValue: suppliers.any((s) => s['id'] == supplierId)
                ? supplierId
                : null,
            decoration: InputDecoration(
              labelText: _t('Supplier', 'ပေးသွင်းသူ'),
            ),
            items: [
              for (final s in suppliers)
                DropdownMenuItem(
                  value: s['id'] as int,
                  child: Text(
                    '${s['name']} · ${s['phone']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: posting
                ? null
                : (id) {
                    desktopUpdate(() => supplierId = id);
                    _touch();
                  },
          ),
        ],
        entry: purchaseEntryBar(),
        notice: saveFailed
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      _t(
                        'Auto-save failed. Retry before leaving.',
                        'အလိုအလျောက်သိမ်းမရပါ။ မထွက်မီ ပြန်စမ်းပါ။',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _saveNow(),
                    child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                  ),
                ],
              )
            : restored
            ? Text(
                _t(
                  'Unfinished purchase restored from this device.',
                  'ဤစက်ရှိ ရေးလက်စအဝယ်ကို ပြန်ဖွင့်ထားသည်။',
                ),
              )
            : null,
        table: Focus(
          focusNode: rowsFocus,
          child: Stack(
            children: [
              Positioned.fill(
                child: DesktopListView.builder(
                  controller: keyboardScroll,
                  itemCount: lines.length,
                  desktopColumns: const [
                    'Code',
                    'Item name',
                    'Color / Size',
                    'Serial / IMEI',
                    'Qty',
                    'Buy price',
                    'Sale price',
                    'Amount',
                  ],
                  desktopFlexes: const [1, 2, 1, 2, 1, 1, 1, 1],
                  desktopCells: (context, i) {
                    final l = lines[i];
                    return [
                      desktopCellText(l['item_code']),
                      desktopCellText(l['name']),
                      desktopCellText(
                        [l['color'], l['size']]
                            .where((v) => v != null && v.toString().isNotEmpty)
                            .join(' / '),
                      ),
                      desktopCellText(_purchaseIdentities(l['lots'])),
                      purchaseNumberCell(l, i, 'qty'),
                      purchaseNumberCell(l, i, 'purchase_price'),
                      purchaseNumberCell(l, i, 'sale_price'),
                      desktopMoney(
                        l['purchase_price'] is int
                            ? (l['purchase_price'] as int) * (l['qty'] as int)
                            : null,
                      ),
                    ];
                  },
                  itemBuilder: (context, i) => DesktopListTile(
                    selected: selectedLine == i,
                    onTap: posting
                        ? null
                        : () {
                            desktopUpdate(() => selectedLine = i);
                            addLine(i);
                          },
                    trailing: IconButton(
                      tooltip: _t('Remove item', 'ပစ္စည်းဖယ်ရန်'),
                      onPressed: posting
                          ? null
                          : () {
                              selectedLine = i;
                              removeSelected();
                            },
                      icon: const Icon(Icons.delete_outline, size: 17),
                    ),
                  ),
                ),
              ),
              if (lines.isEmpty)
                LayoutBuilder(
                  builder: (context, bounds) => bounds.maxHeight < 180
                      ? const SizedBox.shrink()
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.playlist_add, size: 30),
                                const SizedBox(height: 8),
                                Text(
                                  _t(
                                    'Search or scan an item above to start your purchase.',
                                    'အဝယ်ဖြည့်ရန် အပေါ်မှ ပစ္စည်းရှာပါ သို့မဟုတ် Barcode Scan လုပ်ပါ။',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _t(
                                    'Enter Qty, Buy price and Sale price directly in the table.',
                                    'ဇယားထဲတွင် Qty၊ အဝယ်ဈေးနှင့် အရောင်းဈေး တိုက်ရိုက်ဖြည့်နိုင်သည်။',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
        footer: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t(
                      'Payment accounts · blank means supplier credit',
                      'ပေးချေမည့်အကောင့်များ · အလွတ်ထားလျှင် Supplier အကြွေး',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DesktopPropertyFields(
                    children: [
                      for (final a in accounts)
                        TextField(
                          focusNode: a['id'] == accounts.first['id']
                              ? paidFocus
                              : null,
                          controller: payments[a['id']],
                          enabled: !posting,
                          inputFormatters: const [AmountInputFormatter()],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            desktopUpdate(() {});
                            _touch();
                          },
                          decoration: InputDecoration(
                            labelText: '${a['name']} (${a['type']})',
                            helperText:
                                '${_t('Available', 'လက်ကျန်')}: ${_money(a['balance'] as int)}',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopPurchaseTotal(
                    label: _t('Total', 'စုစုပေါင်း'),
                    amount: total,
                  ),
                  _DesktopPurchaseTotal(
                    label: _t('Paid', 'ပေးပြီး'),
                    amount: paid,
                  ),
                  _DesktopPurchaseTotal(
                    label: _t('Supplier credit due', 'Supplier အကြွေးကျန်'),
                    amount: total - paid,
                  ),
                  Text('${_t('Items', 'ပစ္စည်းအမျိုးအစား')}: ${lines.length}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _purchaseIdentities(Object? raw) {
  try {
    final lots = raw is String ? jsonDecode(raw) : raw;
    if (lots is! List) return '—';
    return lots
        .whereType<Map>()
        .map(
          (lot) => [
            lot['serial'],
            lot['imei'],
            lot['expires_on'],
          ].where((v) => v != null && v.toString().isNotEmpty).join(' / '),
        )
        .where((s) => s.isNotEmpty)
        .join(', ');
  } catch (_) {
    return '—';
  }
}

class _DesktopPurchaseTotal extends StatelessWidget {
  const _DesktopPurchaseTotal({required this.label, required this.amount});
  final String label;
  final int amount;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(_money(amount), style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}
