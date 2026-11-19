part of 'purchase_page.dart';

extension _DesktopPurchaseHistory on _PurchaseHistoryPageState {
  Widget desktopHistory() {
    final visible = purchases.where((p) {
      final q = historySearch.toLowerCase().trim();
      final date = p['invoice_date'].toString();
      final due = p['balance_due'] as int;
      final total = p['total'] as int;
      return (historySupplier == null || p['supplier_id'] == historySupplier) &&
          HistoryDates.includes(date, historyFrom, historyTo) &&
          (historyStatus == 'all' ||
              (historyStatus == 'paid' && due == 0) ||
              (historyStatus == 'partial' && due > 0 && due < total) ||
              (historyStatus == 'unpaid' && due == total)) &&
          (q.isEmpty ||
              '${_no(p['id'] as int)} ${p['supplier_name']}'
                  .toLowerCase()
                  .contains(q));
    }).toList();
    final suppliers = {
      for (final p in purchases) p['supplier_id']: p['supplier_name'],
    };
    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(branchId),
                    initialValue: branchId,
                    decoration: InputDecoration(
                      labelText: _t('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text(b['name'].toString()),
                        ),
                    ],
                    onChanged: loading
                        ? null
                        : (v) {
                            updateHistory(() {
                              branchId = v;
                              historySupplier = null;
                            });
                            load();
                          },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('supplier:$branchId:$historySupplier'),
                    initialValue: historySupplier,
                    decoration: InputDecoration(
                      labelText: _t('Supplier', 'ကုန်ပေးသူ'),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('All'),
                      ),
                      for (final p in suppliers.entries)
                        DropdownMenuItem(
                          value: p.key as int,
                          child: Text(p.value.toString()),
                        ),
                    ],
                    onChanged: (v) => updateHistory(() => historySupplier = v),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (v) => updateHistory(() => historySearch = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _t(
                        'Invoice / Supplier',
                        'ဘောင်ချာ / ကုန်ပေးသူ',
                      ),
                    ),
                  ),
                ),
                HistoryDateFilter(
                  from: historyFrom,
                  to: historyTo,
                  onChanged: (from, to) => updateHistory(() {
                    historyFrom = from;
                    historyTo = to;
                  }),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(historyStatus),
                    initialValue: historyStatus,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                    ),
                    items: [
                      for (final v in ['all', 'paid', 'partial', 'unpaid'])
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) =>
                        updateHistory(() => historyStatus = v ?? 'all'),
                  ),
                ),
                TextButton(
                  onPressed: () => updateHistory(() {
                    historyFrom = null;
                    historyTo = null;
                    historySupplier = null;
                    historyStatus = 'all';
                  }),
                  child: const Text('Clear filters'),
                ),
                if (widget.allowDraftEditing)
                  FilledButton.icon(
                    onPressed: loading ? null : create,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('New Purchase'),
                  ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) TextButton(onPressed: load, child: Text(error!)),
          Expanded(
            child: DesktopGrid(
              minWidth: 1150,
              columns: const [
                'Invoice No.',
                'Date',
                'Branch',
                'Supplier',
                'Total',
                'Paid',
                'Balance',
                'Status',
                'Actions',
              ],
              rows: [
                for (final p in visible)
                  [
                    Text(_no(p['id'] as int)),
                    Text(p['invoice_date'].toString()),
                    Text(
                      (branches
                                  .where((b) => b['id'] == p['branch_id'])
                                  .firstOrNull?['name'] ??
                              '')
                          .toString(),
                    ),
                    Text(p['supplier_name'].toString()),
                    Text(_money(p['total'] as int)),
                    Text(
                      _money((p['total'] as int) - (p['balance_due'] as int)),
                    ),
                    Text(_money(p['balance_due'] as int)),
                    Text(
                      p['status'] == 'void'
                          ? 'Void'
                          : (p['balance_due'] as int) == 0
                          ? 'Paid'
                          : (p['balance_due'] as int) == p['total']
                          ? 'Unpaid'
                          : 'Partial',
                    ),
                    IconButton(
                      tooltip: 'Open voucher',
                      onPressed: () => detail(p['id'] as int),
                      icon: const Icon(Icons.open_in_new, size: 17),
                    ),
                  ],
              ],
              onRowTap: (i) => detail(visible[i]['id'] as int),
            ),
          ),
        ],
      ),
    );
  }
}
