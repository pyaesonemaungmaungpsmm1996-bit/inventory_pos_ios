import 'desktop_ui.dart';
import 'stock_balance_filter.dart';
import 'product_tracking.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'app_capabilities.dart';
import 'branch_records_sync.dart';
import 'synced_branch_balance_page.dart';
import 'shared_pos_page.dart';
import 'shared_pos_session.dart';
part 'desktop_stock_balance.dart';

class StockBalancePage extends StatefulWidget {
  const StockBalancePage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<StockBalancePage> createState() => _StockBalancePageState();
}

class _StockBalancePageState extends State<StockBalancePage> {
  List<Map<String, Object?>> rows = [],
      branches = [],
      categories = [],
      brands = [];
  int branch = 0, category = 0, brand = 0;
  String search = '', error = '';
  bool loading = true;
  bool branchInitialized = false;
  int request = 0;
  String t(String e, String m) => AppLanguage.current.value == 'my' ? m : e;
  @override
  void initState() {
    super.initState();
    branch = widget.initialBranchId ?? 0;
    if (BranchRecordsSync.reader == null) load();
  }

  Future<void> load() async {
    final token = ++request;
    if (!branchInitialized) {
      branchInitialized = true;
      if (widget.initialBranchId == null) {
        branch = await AppDatabase.instance.getDefaultBranchId() ?? 0;
      }
      if (!mounted || token != request) return;
    }
    final selectedBranch = branch,
        selectedCategory = category,
        selectedBrand = brand;
    setState(() => loading = true);
    try {
      final db = await AppDatabase.instance.database;
      final b = await db.query('branches', orderBy: 'name'),
          c = await db.query('product_categories', orderBy: 'name'),
          br = await db.query('product_brands', orderBy: 'name');
      final r = await db.rawQuery(
        '''SELECT p.id,p.name,p.item_code,p.color,p.size,p.tracking,c.name category_name,br.name brand_name,b.name branch_name,b.id branch_id,COALESCE(s.stock,0) stock,
    COALESCE((SELECT SUM(l.available) FROM stock_lots l WHERE l.product_id=p.id AND l.branch_id=b.id AND l.expires_on IS NOT NULL AND l.expires_on<?),0) expired_qty
    FROM products p CROSS JOIN branches b LEFT JOIN branch_stocks s ON s.product_id=p.id AND s.branch_id=b.id
    LEFT JOIN product_categories c ON c.id=p.category_id LEFT JOIN product_brands br ON br.id=p.brand_id
    WHERE (?=0 OR b.id=?) AND (?=0 OR p.category_id=?) AND (?=0 OR p.brand_id=?)
    ORDER BY c.name,br.name,p.name,b.name''',
        [
          ProductTracking.today(),
          selectedBranch,
          selectedBranch,
          selectedCategory,
          selectedCategory,
          selectedBrand,
          selectedBrand,
        ],
      );
      if (mounted && token == request) {
        setState(() {
          branches = b;
          categories = c;
          brands = br;
          rows = r;
          error = '';
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Widget filter(
    String title,
    int value,
    List<Map<String, Object?>> data,
    void Function(int) change,
  ) => StockBalanceFilter(
    title: title,
    value: value,
    data: data,
    loading: loading,
    onChanged: (v) {
      change(v);
      load();
    },
  );
  @override
  Widget build(BuildContext context) {
    if (SharedPosSession.current case final session?) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLanguage.text('Balance Stock'))),
        body: SharedPosPage(session: session, kind: SharedPosPageKind.stock),
      );
    }
    if (BranchRecordsSync.reader case final reader?) {
      return SyncedBranchBalancePage(reader: reader, accounts: false);
    }
    final query = search.toLowerCase();
    final shown = rows
        .where(
          (r) => '${r['name']} ${r['item_code']} ${r['color']} ${r['size']}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    final total = shown.fold<int>(0, (s, r) => s + (r['stock'] as int));
    if (AppCapabilities.windows) return desktopStockBalance(shown, total);
    return DesktopScaffold(
      appBar: AppBar(
        title: Text(t('Balance Stock', 'ပစ္စည်းလက်ကျန်')),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          filter(t('Branch', 'ဆိုင်ခွဲ'), branch, branches, (v) => branch = v),
          filter(t('Category', 'အမျိုးအစား'), category, categories, (v) {
            category = v;
            brand = 0;
          }),
          filter('Brand', brand, brands, (v) => brand = v),
          TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: t(
                'Search item / code / color / size',
                'ပစ္စည်း / ကုဒ် / အရောင် / ဆိုဒ် ရှာရန်',
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error.isNotEmpty) Text(error),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              t(
                'Total quantity: $total · ${shown.length} item/branch rows',
                'စုစုပေါင်းအရေအတွက်: $total · ${shown.length} ပစ္စည်း/ဆိုင်ခွဲလိုင်း',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final r in shown)
            Card(
              child: DesktopListTile(
                title: Text('${r['item_code']} · ${r['name']}'),
                subtitle: Text(
                  '${r['branch_name']}\n${r['category_name']} · ${r['brand_name'] ?? '—'}\n${r['color']} ${r['size']}${(r['expired_qty'] as int) > 0 ? '\n${t('Expired units', 'သက်တမ်းကုန်လက်ကျန်')}: ${r['expired_qty']}' : ''}',
                ),
                trailing: Text(
                  '${r['stock']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                onTap: () => showLots(r),
              ),
            ),
        ],
      ),
    );
  }

  void updateDesktopStock(VoidCallback update) => setState(update);
  Future<void> showLots(Map row) async {
    final db = await AppDatabase.instance.database;
    final lots = await db.query(
      'stock_lots',
      where: 'product_id=? AND branch_id=? AND available>0',
      whereArgs: [row['id'], row['branch_id']],
      orderBy: 'expires_on,id',
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text('${row['name']}'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lots.isEmpty)
                  Text(
                    t(
                      'This item has no tracked lots.',
                      'ဤပစ္စည်းတွင် အသုတ်/Serial မှတ်တမ်းမရှိပါ။',
                    ),
                  ),
                for (final l in lots)
                  DesktopListTile(
                    title: SelectableText(
                      '${l['serial'] ?? ''} ${l['imei'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${t('Expiry', 'သက်တမ်းကုန်')}: ${l['expires_on'] ?? '—'}\n${t('Warranty days', 'အာမခံရက်')}: ${l['warranty_days']}',
                    ),
                    trailing: Text('${l['available']}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('Close', 'ပိတ်မည်')),
          ),
        ],
      ),
    );
  }
}
