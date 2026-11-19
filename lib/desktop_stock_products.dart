part of 'inventory_page.dart';

extension _DesktopStock on _InventoryPageState {
  bool matchesStock(Map<String, Object?> p) {
    final q = searchText.trim().toLowerCase();
    final opening = stockMetrics[p['id']]?['opening_qty'] ?? 0;
    final sold = stockMetrics[p['id']]?['sale_qty'] ?? 0;
    final current = p['stock'] as int;
    final min = int.tryParse(minStock.text), max = int.tryParse(maxStock.text);
    return (stockCategory == 0 || p['category_id'] == stockCategory) &&
        (stockBrand == 0 || p['brand_id'] == stockBrand) &&
        (!hideZeroStock || current != 0) &&
        (min == null || current >= min) &&
        (max == null || current <= max) &&
        (!openingOnly || opening != 0) &&
        (!soldOnly || sold != 0) &&
        (q.isEmpty ||
            [
              'name',
              'item_code',
              'barcode',
            ].any((k) => (p[k] ?? '').toString().toLowerCase().contains(q)));
  }

  Widget stockDesktop() {
    final visible = products.where(matchesStock).toList();
    Widget choice(
      String label,
      int value,
      List<Map<String, Object?>> rows,
      ValueChanged<int> change,
    ) => SizedBox(
      width: 200,
      child: DropdownButtonFormField<int>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: 0, child: Text('All')),
          for (final r in rows)
            DropdownMenuItem(
              value: r['id'] as int,
              child: Text(
                r['name'].toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: loading ? null : (v) => updateStock(() => change(v ?? 0)),
      ),
    );
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
                  width: 240,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(selectedBranchId),
                    initialValue: selectedBranchId,
                    decoration: InputDecoration(
                      labelText: tr('Branch', 'ဆိုင်ခွဲ'),
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
                        : (id) {
                            updateStock(() => selectedBranchId = id);
                            loadProducts();
                          },
                  ),
                ),
                choice(
                  tr('Category', 'အမျိုးအစား'),
                  stockCategory,
                  stockCategories,
                  (v) {
                    stockCategory = v;
                    stockBrand = 0;
                  },
                ),
                choice(
                  'Brand',
                  stockBrand,
                  stockBrands
                      .where(
                        (r) =>
                            stockCategory == 0 ||
                            r['category_id'] == stockCategory,
                      )
                      .toList(),
                  (v) => stockBrand = v,
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (v) => updateStock(() => searchText = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr(
                        'Name / Code / Barcode',
                        'အမည် / Code / Barcode',
                      ),
                    ),
                  ),
                ),
                FilterChip(
                  label: Text(tr('Hide 0', 'သုညဖျောက်ရန်')),
                  selected: hideZeroStock,
                  onSelected: (v) => updateStock(() => hideZeroStock = v),
                ),
                FilterChip(
                  label: Text(tr('With opening stock', 'အဖွင့် Stock ရှိ')),
                  selected: openingOnly,
                  onSelected: (v) => updateStock(() => openingOnly = v),
                ),
                FilterChip(
                  label: Text(tr('With sales', 'ရောင်းပြီးရှိ')),
                  selected: soldOnly,
                  onSelected: (v) => updateStock(() => soldOnly = v),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: minStock,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => updateStock(() {}),
                    decoration: const InputDecoration(labelText: 'Min stock'),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: maxStock,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => updateStock(() {}),
                    decoration: const InputDecoration(labelText: 'Max stock'),
                  ),
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: loadProducts, child: Text(error!)),
          Expanded(
            child: DesktopGrid(
              columns: const [
                'Item code',
                'Item Name',
                'Category',
                'Brand',
                'Color / Size',
                'Opening Stock',
                'Sale Qty',
                'In Stock',
                'Actions',
              ],
              flexes: const [2, 5, 2, 2, 2, 2, 2, 2, 3],
              minWidth: 1150,
              rows: [
                for (final p in visible)
                  [
                    Text(p['item_code'].toString()),
                    Text(p['name'].toString()),
                    Text((p['category_name'] ?? '').toString()),
                    Text(
                      (stockBrands
                                  .where((b) => b['id'] == p['brand_id'])
                                  .firstOrNull?['name'] ??
                              '')
                          .toString(),
                    ),
                    Text('${p['color'] ?? ''} / ${p['size'] ?? ''}'),
                    Text('${stockMetrics[p['id']]?['opening_qty'] ?? 0}'),
                    Text('${stockMetrics[p['id']]?['sale_qty'] ?? 0}'),
                    Text('${p['stock']}'),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Stock history',
                          onPressed: () => showStockHistory(p),
                          icon: const Icon(Icons.history, size: 18),
                        ),
                        IconButton(
                          tooltip: 'Add stock',
                          onPressed: () => showStockIn(p),
                          icon: const Icon(Icons.add_box_outlined, size: 18),
                        ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
