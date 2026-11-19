part of 'stock_balance_page.dart';

extension _DesktopStockBalance on _StockBalancePageState {
  Widget desktopStockBalance(List<Map<String, Object?>> shown, int total) =>
      DesktopScaffold(
        appBar: AppBar(
          title: Text(t('Balance Stock', 'ပစ္စည်းလက်ကျန်')),
          actions: [
            IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 230,
                    child: filter(
                      t('Branch', 'ဆိုင်ခွဲ'),
                      branch,
                      branches,
                      (v) => branch = v,
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: filter(
                      t('Category', 'အမျိုးအစား'),
                      category,
                      categories,
                      (v) {
                        category = v;
                        brand = 0;
                      },
                    ),
                  ),
                  SizedBox(
                    width: 230,
                    child: filter('Brand', brand, brands, (v) => brand = v),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      onChanged: (v) => updateDesktopStock(() => search = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        labelText: t(
                          'Search item / code / color / size',
                          'ပစ္စည်း / ကုဒ် / အရောင် / အရွယ် ရှာရန်',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error.isNotEmpty) SelectableText(error),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                '${t('Total quantity', 'စုစုပေါင်းအရေအတွက်')}: $total',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: DesktopGrid(
                key: const ValueKey('desktop-stock-balance'),
                minWidth: 1000,
                columns: [
                  t('Branch', 'ဆိုင်ခွဲ'),
                  'Item code',
                  t('Item Name', 'ပစ္စည်းအမည်'),
                  t('Category', 'အမျိုးအစား'),
                  'Brand',
                  t('Color / Size', 'အရောင် / အရွယ်'),
                  t('Stock', 'လက်ကျန်'),
                  t('Expired units', 'သက်တမ်းလွန်အရေအတွက်'),
                ],
                flexes: const [2, 2, 5, 2, 2, 2, 1, 2],
                rows: [
                  for (final r in shown)
                    [
                      Text('${r['branch_name']}'),
                      Text('${r['item_code']}'),
                      Text('${r['name']}'),
                      Text('${r['category_name'] ?? '-'}'),
                      Text('${r['brand_name'] ?? '-'}'),
                      Text('${r['color'] ?? ''} / ${r['size'] ?? ''}'),
                      Text('${r['stock']}'),
                      Text('${r['expired_qty']}'),
                    ],
                ],
                onRowTap: (index) => showLots(shown[index]),
              ),
            ),
          ],
        ),
      );
}
