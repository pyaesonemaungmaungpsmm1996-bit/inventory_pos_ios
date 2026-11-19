part of 'item_catalog_page.dart';

extension _DesktopCatalog on _ItemCatalogPageState {
  Widget desktopCatalog(List<Map<String, Object?>> visible) {
    Future<void> edit(Map<String, Object?> product) async {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ProductEditorPage(product: product)),
      );
      if (mounted) await load();
    }

    void label(Map<String, Object?> product) => Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => BarcodeLabelPage(product: product)),
    );
    Widget filters() => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Filters', 'စစ်ထုတ်ရန်'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 14),
          filter(t('Branch', 'ဆိုင်ခွဲ'), branch, branches, (v) {
            updateDesktopCatalog(() {
              branch = v;
              selectedLabels.clear();
            });
            load();
          }),
          const SizedBox(height: 16),
          filter(
            t('Category', 'အမျိုးအစား'),
            category,
            categories,
            (v) => updateDesktopCatalog(() {
              category = v;
              brand = 0;
            }),
          ),
          const SizedBox(height: 16),
          filter(
            'Brand',
            brand,
            brands
                .where((b) => category == 0 || b['category_id'] == category)
                .toList(),
            (v) => updateDesktopCatalog(() => brand = v),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    Widget grid() => DesktopGrid(
      key: const ValueKey('desktop-item-catalog'),
      minWidth: 1000,
      columns: [
        'Select / Qty',
        'Item code',
        t('Item Name', 'ပစ္စည်းအမည်'),
        'Brand',
        t('Category', 'အမျိုးအစား'),
        t('Color / Size', 'အရောင် / အရွယ်'),
        t('Sale price', 'ရောင်းဈေး'),
        t('Actions', 'လုပ်ဆောင်ချက်'),
      ],
      flexes: const [2, 2, 5, 2, 2, 2, 2, 2],
      rows: [
        for (final p in visible)
          [
            Row(
              children: [
                Checkbox(
                  value: selectedLabels.containsKey(p['id']),
                  onChanged: (v) => updateDesktopCatalog(() {
                    if (v == true) {
                      selectedLabels[p['id'] as int] = 1;
                    } else {
                      selectedLabels.remove(p['id']);
                    }
                  }),
                ),
                if (selectedLabels.containsKey(p['id']))
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('label-count-${p['id']}'),
                      initialValue: '${selectedLabels[p['id']]}',
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        selectedLabels[p['id'] as int] = n ?? 0;
                      },
                    ),
                  ),
              ],
            ),
            Text('${p['item_code']}'),
            Row(
              children: [
                if (p['has_image'] == 1) ...[
                  ProductPhoto(
                    key: ValueKey('${p['id']}:$generation'),
                    productId: p['id'] as int,
                    hasImage: true,
                    size: 24,
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Tooltip(
                    message: '${p['name']}',
                    child: Text('${p['name']}'),
                  ),
                ),
              ],
            ),
            Text('${p['brand_name'] ?? '-'}'),
            Text('${p['category_name'] ?? '-'}'),
            Text('${p['color'] ?? ''} / ${p['size'] ?? ''}'),
            Text(AppCurrency.format(p['price'] as int)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: t('Edit', 'ပြင်ရန်'),
                  onPressed: loading ? null : () => edit(p),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
                IconButton(
                  tooltip: t('Print label', 'Label ထုတ်ရန်'),
                  onPressed: () => label(p),
                  icon: const Icon(Icons.print_outlined, size: 17),
                ),
              ],
            ),
          ],
      ],
      onRowTap: (index) => edit(visible[index]),
    );
    return DesktopCommandScope(
      commands: {
        DesktopCommand.search: () => searchFocus.requestFocus(),
        DesktopCommand.barcode: () => searchFocus.requestFocus(),
      },
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(t('Item Name', 'ပစ္စည်းအမည်')),
          actions: [
            IconButton(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: searchFocus,
                      controller: searchController,
                      onChanged: (v) => updateDesktopCatalog(() => search = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: t(
                          'Name / Item Code / Barcode',
                          'အမည် / ပစ္စည်းကုဒ် / Barcode',
                        ),
                        suffixIcon: IconButton(
                          tooltip: t('Scan barcode', 'Barcode ဖတ်ရန်'),
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          onPressed: () async {
                            final value = await Navigator.push<String>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const BarcodeScanPage(),
                              ),
                            );
                            if (value != null && mounted) {
                              updateDesktopCatalog(() {
                                searchController.text = value;
                                search = value;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    key: const ValueKey('print-selected-labels'),
                    onPressed: selectedLabels.isEmpty
                        ? null
                        : printSelectedLabels,
                    icon: const Icon(Icons.print_outlined, size: 17),
                    label: Text(t('Print selected', 'ရွေးထားသည်များ Print')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('catalog-new-item'),
                    onPressed: loading
                        ? null
                        : () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProductEditorPage(
                                  product: {
                                    'name': '',
                                    'item_code': '',
                                    'barcode': '',
                                    'price': 0,
                                    if (branch != 0) 'branch_id': branch,
                                  },
                                ),
                              ),
                            );
                            if (mounted) await load();
                          },
                    icon: const Icon(Icons.add, size: 17),
                    label: Text(t('New Item', 'ပစ္စည်းအသစ်')),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InventoryPage(),
                        ),
                      );
                      if (mounted) await load();
                    },
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(t('Stock & Products', 'ပစ္စည်းနှင့်လက်ကျန်')),
                  ),
                ],
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) TextButton(onPressed: load, child: Text(error!)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 950
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: grid()),
                          Container(
                            width: 230,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              border: Border(
                                left: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ),
                            child: Material(
                              color: Theme.of(context).colorScheme.surface,
                              child: filters(),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(
                            height: 152,
                            child: SingleChildScrollView(child: filters()),
                          ),
                          Expanded(child: grid()),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
