part of 'inventory_page.dart';

extension _MobileStock on _InventoryPageState {
  Widget mobileStock() {
    final visible = products.where(matchesStock).toList();
    Widget choice(
      String label,
      int value,
      List<Map<String, Object?>> rows,
      ValueChanged<int> change,
    ) => DropdownButtonFormField<int>(
      key: ValueKey('$label:$value'),
      initialValue: rows.any((r) => r['id'] == value) ? value : 0,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: 0, child: Text(tr('All', 'အားလုံး'))),
        for (final row in rows)
          DropdownMenuItem(
            value: row['id'] as int,
            child: Text('${row['name']}'),
          ),
      ],
      onChanged: loading ? null : (v) => updateStock(() => change(v ?? 0)),
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey('mobile-stock-branch-$selectedBranchId'),
                    initialValue: selectedBranchId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text('${b['name']}'),
                        ),
                    ],
                    onChanged: loading
                        ? null
                        : (v) {
                            if (v == null || v == selectedBranchId) return;
                            updateStock(() => selectedBranchId = v);
                            loadProducts();
                          },
                  ),
                  TextField(
                    onChanged: (v) => updateStock(() => searchText = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: tr(
                        'Name / Code / Barcode',
                        'အမည် / Code / Barcode',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ExpansionTile(
              key: const ValueKey('mobile-stock-filters'),
              title: Text(tr('Filters', 'စစ်ထုတ်ရန်')),
              children: [
                SizedBox(
                  height: (box.maxHeight * .25).clamp(0.0, 210.0),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
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
                        Wrap(
                          spacing: 8,
                          children: [
                            FilterChip(
                              label: Text(tr('Hide 0', 'လက်ကျန် 0 ဖျောက်ရန်')),
                              selected: hideZeroStock,
                              onSelected: (v) =>
                                  updateStock(() => hideZeroStock = v),
                            ),
                            FilterChip(
                              label: Text(
                                tr('With opening stock', 'အဖွင့်လက်ကျန်ရှိ'),
                              ),
                              selected: openingOnly,
                              onSelected: (v) =>
                                  updateStock(() => openingOnly = v),
                            ),
                            FilterChip(
                              label: Text(
                                tr('With sales', 'ရောင်းပြီးပစ္စည်း'),
                              ),
                              selected: soldOnly,
                              onSelected: (v) =>
                                  updateStock(() => soldOnly = v),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: minStock,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => updateStock(() {}),
                                decoration: InputDecoration(
                                  labelText: tr(
                                    'Min stock',
                                    'အနည်းဆုံးလက်ကျန်',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: maxStock,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => updateStock(() {}),
                                decoration: InputDecoration(
                                  labelText: tr(
                                    'Max stock',
                                    'အများဆုံးလက်ကျန်',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: loadProducts, child: Text(error!)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: loadProducts,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: visible.isEmpty ? 1 : visible.length,
                  itemBuilder: (context, index) {
                    if (visible.isEmpty) {
                      return ListTile(
                        title: Text(
                          tr('No matching stock.', 'ကိုက်ညီသောပစ္စည်းမရှိပါ။'),
                        ),
                      );
                    }
                    final p = visible[index];
                    final m = stockMetrics[p['id']];
                    return Card(
                      child: ListTile(
                        title: Text('${p['item_code']} · ${p['name']}'),
                        subtitle: Text(
                          '${tr('Opening Stock', 'အဖွင့်လက်ကျန်')}: ${m?['opening_qty'] ?? 0}\n'
                          '${tr('Sale Qty', 'ရောင်းပြီးအရေအတွက်')}: ${m?['sale_qty'] ?? 0}\n'
                          '${tr('In Stock', 'လက်ကျန်')}: ${p['stock']} · ${p['color'] ?? ''} / ${p['size'] ?? ''}',
                        ),
                        onTap: () => showStockHistory(p),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_box_outlined),
                          tooltip: tr('Add stock', 'လက်ကျန်ထည့်ရန်'),
                          onPressed: () => showStockIn(p),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
