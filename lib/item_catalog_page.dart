import 'desktop_ui.dart';
import 'desktop_commands.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'app_currency.dart';
import 'product_photo.dart';
import 'product_editor_page.dart';
import 'barcode_label_page.dart';
import 'barcode_scan_page.dart';
import 'app_capabilities.dart';
import 'inventory_page.dart';
part 'desktop_catalog.dart';

class ItemCatalogPage extends StatefulWidget {
  const ItemCatalogPage({super.key});
  @override
  State<ItemCatalogPage> createState() => _ItemCatalogPageState();
}

class _ItemCatalogPageState extends State<ItemCatalogPage> {
  List<Map<String, Object?>> items = [],
      branches = [],
      categories = [],
      brands = [];
  int branch = 0, category = 0, brand = 0;
  bool loading = true, hideZero = false;
  bool branchInitialized = false;
  String search = '';
  final selectedLabels = <int, int>{};
  Future<void> printSelectedLabels() async {
    final batch = [
      for (final p in items)
        if (selectedLabels.containsKey(p['id']))
          BarcodeLabelSelection(product: p, count: selectedLabels[p['id']]!),
    ];
    if (batch.isEmpty) return;
    try {
      BarcodeLabelSelection.validate(batch);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Enter valid label quantities (1–10000).',
              'Label အရေအတွက် ၁ မှ ၁၀၀၀၀ အတွင်း ဖြည့်ပါ။',
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BarcodeLabelPage(product: batch.first.product, batch: batch),
      ),
    );
  }

  String? error;
  final searchFocus = FocusNode();
  final searchController = TextEditingController();
  int generation = 0;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    generation++;
    searchFocus.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final ticket = ++generation;
    setState(() => loading = true);
    try {
      if (!branchInitialized) {
        branchInitialized = true;
        branch = await AppDatabase.instance.getDefaultBranchId() ?? 0;
      }
      final db = await AppDatabase.instance.database;
      final all = await db.rawQuery(
        '''SELECT p.*,c.name category_name,b.name brand_name,
     COALESCE((SELECT SUM(s.stock) FROM branch_stocks s WHERE s.product_id=p.id AND (?=0 OR s.branch_id=?)),0) stock_balance,
     EXISTS(SELECT 1 FROM product_images i WHERE i.product_id=p.id) has_image
     FROM products p LEFT JOIN product_categories c ON c.id=p.category_id
     LEFT JOIN product_brands b ON b.id=p.brand_id WHERE (?=0 OR EXISTS(SELECT 1 FROM branch_stocks a WHERE a.product_id=p.id AND a.branch_id=?)) ORDER BY p.name COLLATE NOCASE,p.id''',
        [branch, branch, branch, branch],
      );
      final br = await db.query('branches', orderBy: 'name');
      final cats = await db.query('product_categories', orderBy: 'name');
      final bs = await db.query('product_brands', orderBy: 'name');
      if (mounted && ticket == generation) {
        setState(() {
          items = all;
          branches = br;
          categories = cats;
          brands = bs;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          loading = false;
          error = t(
            'Could not load items. Retry.',
            'ပစ္စည်းမဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
          );
        });
      }
    }
  }

  Widget filter(
    String label,
    int value,
    List<Map<String, Object?>> rows,
    void Function(int) change,
  ) => DropdownButtonFormField<int>(
    key: ValueKey('$label:$value'),
    initialValue: rows.any((r) => r['id'] == value) ? value : 0,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: 0, child: Text(t('All', 'အားလုံး'))),
      for (final row in rows)
        DropdownMenuItem(
          value: row['id'] as int,
          child: Text('${row['name']}', overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: loading
        ? null
        : (v) {
            if (v != null) change(v);
          },
  );
  @override
  Widget build(BuildContext context) {
    final q = search.toLowerCase().trim();
    final visible = items
        .where(
          (p) =>
              (category == 0 || p['category_id'] == category) &&
              (brand == 0 || p['brand_id'] == brand) &&
              (q.isEmpty ||
                  [
                    'name',
                    'item_code',
                    'barcode',
                  ].any((k) => '${p[k] ?? ''}'.toLowerCase().contains(q))),
        )
        .toList();
    if (AppCapabilities.windows) return desktopCatalog(visible);
    return DesktopCommandScope(
      commands: {
        DesktopCommand.search: () => searchFocus.requestFocus(),
        DesktopCommand.barcode: () => searchFocus.requestFocus(),
      },
      child: DesktopScaffold(
        appBar: AppBar(
          title: Text(t('Item Name', 'ပစ္စည်းစာရင်း')),
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
              child: Column(
                children: [
                  TextField(
                    focusNode: searchFocus,
                    controller: searchController,
                    onChanged: (v) => setState(() => search = v),
                    decoration: InputDecoration(
                      labelText: t(
                        'Name / Item Code / Barcode',
                        'အမည် / Item Code / Barcode',
                      ),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final v = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BarcodeScanPage(),
                            ),
                          );
                          if (v != null && mounted) {
                            setState(() {
                              searchController.text = v;
                              search = v;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  filter(t('Branch', 'ဆိုင်ခွဲ'), branch, branches, (v) {
                    setState(() => branch = v);
                    load();
                  }),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: filter(
                          t('Category', 'အမျိုးအစား'),
                          category,
                          categories,
                          (v) => setState(() {
                            category = v;
                            brand = 0;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: filter(
                          'Brand',
                          brand,
                          brands
                              .where(
                                (b) =>
                                    category == 0 ||
                                    b['category_id'] == category,
                              )
                              .toList(),
                          (v) => setState(() => brand = v),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('mobile-catalog-new'),
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
                        icon: const Icon(Icons.add),
                        label: Text(t('New item', 'ပစ္စည်းအသစ်')),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('mobile-catalog-print-selected'),
                        onPressed: selectedLabels.isEmpty
                            ? null
                            : printSelectedLabels,
                        icon: const Icon(Icons.print_outlined),
                        label: Text(
                          '${t('Print selected', 'ရွေးထားသည်များ Print ထုတ်မည်')} (${selectedLabels.length})',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null) TextButton(onPressed: load, child: Text(error!)),
            Expanded(
              child: DesktopListView.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final p = visible[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: DesktopListTile(
                      leading: Checkbox(
                        value: selectedLabels.containsKey(p['id']),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            selectedLabels[p['id'] as int] = 1;
                          } else {
                            selectedLabels.remove(p['id']);
                          }
                        }),
                      ),
                      title: Text('${p['name']}'),
                      subtitle: Text(
                        '${p['item_code']} · ${p['brand_name'] ?? p['category_name'] ?? ''}\n${AppCurrency.format(p['price'] as int)}',
                      ),
                      onTap: () async {
                        await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductEditorPage(product: p),
                          ),
                        );
                        if (mounted) await load();
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.print_outlined),
                        onPressed: () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BarcodeLabelPage(product: p),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void updateDesktopCatalog(VoidCallback update) => setState(update);
}
