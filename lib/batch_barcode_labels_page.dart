import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'barcode_label_page.dart';
import 'desktop_ui.dart';

class BatchBarcodeLabelsPage extends StatefulWidget {
  const BatchBarcodeLabelsPage({super.key});
  @override
  State<BatchBarcodeLabelsPage> createState() => _BatchBarcodeLabelsPageState();
}

class _BatchBarcodeLabelsPageState extends State<BatchBarcodeLabelsPage> {
  List<Map<String, Object?>> products = [];
  final quantities = <int, String>{};
  String search = '';
  bool loading = true, opening = false;
  String? error;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final branch = await AppDatabase.instance.getDefaultBranchId();
      final rows = branch == null
          ? <Map<String, Object?>>[]
          : await AppDatabase.instance.getProducts(branchId: branch);
      if (mounted) {
        setState(() {
          products = rows;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = t(
            'Could not load items. Retry.',
            'ပစ္စည်းစာရင်း ဖတ်မရပါ။ ပြန်စမ်းပါ။',
          );
        });
      }
    }
  }

  void toggle(int id, bool selected) => setState(() {
    if (selected) {
      quantities.putIfAbsent(id, () => '1');
    } else {
      quantities.remove(id);
    }
  });
  Future<void> customize() async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    try {
      final byId = {for (final p in products) p['id'] as int: p};
      final selected = [
        for (final entry in quantities.entries)
          BarcodeLabelSelection(
            product: byId[entry.key]!,
            count: int.tryParse(entry.value) ?? 0,
          ),
      ];
      BarcodeLabelSelection.validate(selected);
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => BarcodeLabelPage(
            product: selected.first.product,
            batch: selected,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => error = t(
            'Check selected items and quantities (1–10000 labels per job).',
            'ရွေးထားသောပစ္စည်းနှင့် အရေအတွက် စစ်ပါ။ တစ်ကြိမ်တွင် Label ၁–၁၀၀၀၀ အတွင်း ထုတ်ပါ။',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Widget quantity(Map p) {
    final id = p['id'] as int;
    final selected = quantities.containsKey(id);
    return SizedBox(
      width: 100,
      child: TextFormField(
        key: ValueKey('batch-qty-$id-$selected'),
        initialValue: quantities[id] ?? '1',
        enabled: selected,
        keyboardType: TextInputType.number,
        onChanged: (v) => quantities[id] = v,
        decoration: InputDecoration(
          isDense: true,
          labelText: t('Labels', 'Label ဦးရေ'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final visible = products
        .where(
          (p) =>
              q.isEmpty ||
              [
                p['name'],
                p['item_code'],
                p['barcode'],
                p['color'],
                p['size'],
              ].any((v) => v.toString().toLowerCase().contains(q)),
        )
        .toList();
    return DesktopScaffold(
      appBar: AppBar(
        title: Text(t('Batch Barcode Labels', 'Barcode Label အစုလိုက်ထုတ်ရန်')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: t(
                        'Search item name / code / barcode',
                        'ပစ္စည်းအမည် / ကုဒ် / Barcode ရှာရန်',
                      ),
                    ),
                    onChanged: (v) => setState(() => search = v),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => quantities.clear()),
                  child: Text(t('Clear selection', 'ရွေးထားသည်များဖယ်ရန်')),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : DesktopListView.builder(
                    itemCount: visible.length,
                    desktopColumns: const [
                      'Select',
                      'Item code',
                      'Item name',
                      'Color / Size',
                      'Labels',
                    ],
                    desktopFlexes: const [1, 2, 4, 2, 2],
                    desktopCells: (context, i) {
                      final p = visible[i];
                      final id = p['id'] as int;
                      return [
                        Checkbox(
                          value: quantities.containsKey(id),
                          onChanged: (v) => toggle(id, v ?? false),
                        ),
                        desktopCellText(p['item_code']),
                        desktopCellText(p['name']),
                        desktopCellText(
                          [p['color'], p['size']]
                              .where(
                                (v) => v != null && v.toString().isNotEmpty,
                              )
                              .join(' / '),
                        ),
                        quantity(p),
                      ];
                    },
                    itemBuilder: (context, i) {
                      final p = visible[i];
                      final id = p['id'] as int;
                      return DesktopListTile(
                        leading: Checkbox(
                          value: quantities.containsKey(id),
                          onChanged: (v) => toggle(id, v ?? false),
                        ),
                        title: Text(p['name'].toString()),
                        subtitle: Text(p['item_code'].toString()),
                        trailing: quantity(p),
                        onTap: () => toggle(id, !quantities.containsKey(id)),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('Selected items: ', 'ရွေးထားသောပစ္စည်း: ') +
                        quantities.length.toString(),
                  ),
                ),
                FilledButton.icon(
                  onPressed: loading || opening || quantities.isEmpty
                      ? null
                      : customize,
                  icon: const Icon(Icons.tune),
                  label: Text(t('Customize / Print', 'ပုံစံပြင် / Print')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
