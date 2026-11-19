import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'barcode_scan_page.dart';
import 'invoice_void_dialog.dart';

class StockAdjustmentPage extends StatefulWidget {
  const StockAdjustmentPage({super.key});
  @override
  State<StockAdjustmentPage> createState() => _StockAdjustmentPageState();
}

class _StockAdjustmentPageState extends State<StockAdjustmentPage> {
  List<Map<String, Object?>> branches = [], products = [], records = [];
  int? branchId;
  bool loading = true;
  String? error;
  String tr(String en, String my) =>
      AppLanguage.current.value == 'my' ? my : en;
  String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final b = await db.getBranches();
      final defaultId = branchId ?? await db.getDefaultBranchId();
      final selected = b.any((row) => row['id'] == defaultId)
          ? defaultId
          : (b.isEmpty ? null : b.first['id'] as int);
      final p = selected == null
          ? <Map<String, Object?>>[]
          : await db.getProducts(branchId: selected);
      final a = selected == null
          ? <Map<String, Object?>>[]
          : await db.getStockAdjustments(selected);
      if (!mounted) return;
      setState(() {
        branches = b;
        branchId = selected;
        products = p;
        records = a;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e.toString();
        });
      }
    }
  }

  Future<Map<String, Object?>?> chooseProduct(BuildContext parent) async {
    String query = '';
    return showDialog<Map<String, Object?>>(
      context: parent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          final matches = products
              .where(
                (p) => '${p['item_code']} ${p['name']} ${p['barcode'] ?? ''}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              )
              .toList();
          return DesktopDialog(
            title: Text(tr('Choose product', 'ပစ္စည်းရွေးရန်')),
            content: SizedBox(
              width: double.maxFinite,
              height: 370,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => update(() => query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr(
                        'Code / name / barcode',
                        'ကုဒ် / အမည် / Barcode',
                      ),
                    ),
                  ),
                  Expanded(
                    child: DesktopListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final p = matches[i];
                        return DesktopListTile(
                          title: Text('${p['item_code']} · ${p['name']}'),
                          subtitle: Text(
                            '${tr('Current stock', 'လက်ရှိလက်ကျန်')}: ${p['stock']}',
                          ),
                          onTap: () => Navigator.pop(dialogContext, p),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('Cancel', 'မလုပ်တော့')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> add({Map<String, Object?>? editing}) async {
    if (branchId == null) return;
    Map<String, Object?>? product = editing == null
        ? null
        : (products.any((p) => p['id'] == editing['product_id'])
              ? products.firstWhere((p) => p['id'] == editing['product_id'])
              : null);
    final productText = TextEditingController(),
        count = TextEditingController();
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    var reason = editing?['reason'] as String? ?? 'count';
    if (editing != null) {
      count.text = '${editing['counted_stock']}';
      note.text = '${editing['note']}';
      if (product != null) {
        productText.text = '${product['item_code']} · ${product['name']}';
      }
    }
    DateTime selectedDate = editing == null
        ? AppDateTime.today()
        : (DateTime.tryParse('${editing['adjustment_date']}') ??
              AppDateTime.today());
    bool saving = false;
    var unlocked = editing == null;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: DesktopDialog(
            title: Row(
              children: [
                Expanded(
                  child: Text(tr('Stock Adjustment', 'Stock ချိန်ညှိခြင်း')),
                ),
                if (editing != null)
                  IconButton(
                    tooltip: tr('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
                    onPressed: saving
                        ? null
                        : () => update(() => unlocked = !unlocked),
                    icon: Icon(unlocked ? Icons.lock_open : Icons.lock_outline),
                  ),
              ],
            ),
            content: AbsorbPointer(
              absorbing: !unlocked,
              child: FocusScope(
                canRequestFocus: unlocked,
                child: SingleChildScrollView(
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: productText,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: tr('Product', 'ပစ္စည်း'),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              tooltip: tr('Scan barcode', 'Barcode ဖတ်ရန်'),
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final code = await Navigator.push<String>(
                                        dialogContext,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const BarcodeScanPage(),
                                        ),
                                      );
                                      if (code == null ||
                                          !dialogContext.mounted) {
                                        return;
                                      }
                                      try {
                                        final p = await AppDatabase.instance
                                            .getProductByBarcode(
                                              branchId: branchId!,
                                              barcode: code,
                                            );
                                        if (!dialogContext.mounted) return;
                                        if (p == null) {
                                          throw StateError('Product not found');
                                        }
                                        update(() {
                                          product = p;
                                          productText.text =
                                              '${p['item_code']} · ${p['name']}';
                                        });
                                      } catch (e) {
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(dialogContext)
                                              .showSnackBar(
                                                SnackBar(content: Text('$e')),
                                              );
                                        }
                                      }
                                    },
                            ),
                          ),
                          onTap: saving
                              ? null
                              : () async {
                                  final chosen = await chooseProduct(
                                    dialogContext,
                                  );
                                  if (chosen != null && dialogContext.mounted) {
                                    update(() {
                                      product = chosen;
                                      productText.text =
                                          '${chosen['item_code']} · ${chosen['name']}';
                                    });
                                  }
                                },
                          validator: (_) => product == null
                              ? tr('Choose a product', 'ပစ္စည်းရွေးပါ')
                              : null,
                        ),
                        if (product != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '${tr('Current stock', 'လက်ရှိလက်ကျန်')}: ${product!['stock']}',
                            ),
                          ),
                        TextFormField(
                          controller: count,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr(
                              'Counted actual stock',
                              'အမှန်တကယ်ရှိသည့် လက်ကျန်',
                            ),
                          ),
                          validator: (v) {
                            final n = int.tryParse(v?.trim() ?? '');
                            if (n == null || n < 0 || n > 2147483647) {
                              return tr(
                                'Enter a valid count',
                                'လက်ကျန်အရေအတွက် မှန်ကန်စွာဖြည့်ပါ',
                              );
                            }
                            if (editing == null &&
                                product != null &&
                                n == product!['stock']) {
                              return tr(
                                'Count matches current stock',
                                'လက်ရှိလက်ကျန်နှင့် တူနေသည်',
                              );
                            }
                            return null;
                          },
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: reason,
                          decoration: InputDecoration(
                            labelText: tr(
                              'Reason type',
                              'အကြောင်းရင်းအမျိုးအစား',
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'count',
                              child: Text(
                                tr('Stock count correction', 'စာရင်းကွာဟချက်'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'damage',
                              child: Text(tr('Damaged', 'ပျက်စီး')),
                            ),
                            DropdownMenuItem(
                              value: 'loss',
                              child: Text(tr('Lost', 'ပျောက်ဆုံး')),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(tr('Other', 'အခြား')),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (v) => update(() => reason = v ?? reason),
                        ),
                        TextFormField(
                          controller: note,
                          maxLength: 500,
                          decoration: InputDecoration(
                            labelText: tr('Explanation', 'ရှင်းလင်းချက်'),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? tr('Explain the change', 'အကြောင်းရင်းဖြည့်ပါ')
                              : null,
                        ),
                        DesktopListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${tr('Adjustment date', 'ညှိသည့်ရက်')}: ${day(selectedDate)}',
                          ),
                          trailing: const Icon(Icons.calendar_today_outlined),
                          onTap: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: dialogContext,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2000),
                                    lastDate: AppDateTime.today(),
                                  );
                                  if (picked != null && dialogContext.mounted) {
                                    update(() => selectedDate = picked);
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(tr('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: saving || !unlocked
                    ? null
                    : () async {
                        if (!form.currentState!.validate() || product == null) {
                          return;
                        }
                        update(() => saving = true);
                        try {
                          if (editing == null) {
                            await AppDatabase.instance.postStockAdjustment(
                              branchId: branchId!,
                              productId: product!['id'] as int,
                              countedStock: int.parse(count.text.trim()),
                              reason: reason,
                              note: note.text,
                              adjustmentDate: day(selectedDate),
                            );
                          } else {
                            await AppDatabase.instance.correctStockAdjustment(
                              id: editing['id'] as int,
                              branchId: branchId!,
                              productId: product!['id'] as int,
                              countedStock: int.parse(count.text.trim()),
                              reason: reason,
                              note: note.text,
                              adjustmentDate: day(selectedDate),
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                            ScaffoldMessenger.of(dialogContext)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                child: Text(tr('Save Adjustment', 'ညှိနှိုင်းမှု သိမ်းရန်')),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) await load();
  }

  Future<void> voidRecord(Map<String, Object?> record) async {
    final text = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => DesktopDialog(
        title: Text(tr('Void adjustment?', 'ညှိနှိုင်းမှု ပယ်ဖျက်မလား?')),
        content: TextField(
          controller: text,
          maxLength: 300,
          decoration: InputDecoration(
            labelText: tr('Reason', 'အကြောင်းပြချက်'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () {
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, text.text);
              }
            },
            child: Text(tr('Void', 'ပယ်ဖျက်ရန်')),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await AppDatabase.instance.voidStockAdjustment(
        id: record['id'] as int,
        reason: reason,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    floatingActionButton: branchId == null
        ? null
        : FloatingActionButton(onPressed: add, child: const Icon(Icons.add)),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : Column(
            children: [
              if (branches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<int>(
                    initialValue: branchId,
                    decoration: InputDecoration(
                      labelText: tr('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    items: branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text(b['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        branchId = v;
                        loading = true;
                      });
                      load();
                    },
                  ),
                ),
              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Text(
                          tr('No adjustments yet', 'လက်ကျန်ညှိမှု မရှိသေးပါ'),
                        ),
                      )
                    : DesktopListView.builder(
                        desktopColumns: const [
                          "Date",
                          "Item code",
                          "Item Name",
                          "Previous stock",
                          "Counted stock",
                          "Difference",
                          "Reason",
                          "Note",
                          "Status",
                        ],
                        desktopCells: (context, index) {
                          final r = records[index];
                          return [
                            desktopCellText(r['adjustment_date']),
                            desktopCellText(r['item_code']),
                            desktopCellText(r['product_name']),
                            desktopCellText(r['previous_stock']),
                            desktopCellText(r['counted_stock']),
                            desktopCellText(r['difference']),
                            desktopCellText(r['reason']),
                            desktopCellText(r['note']),
                            desktopCellText(r['status']),
                          ];
                        },

                        itemCount: records.length,
                        itemBuilder: (context, i) {
                          final row = records[i];
                          final delta = row['difference'] as int;
                          return Card(
                            child: DesktopListTile(
                              leading: Icon(
                                delta > 0
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                              ),
                              title: Text(
                                '${row['item_code']} · ${row['product_name']} '
                                '${delta > 0 ? '+' : ''}$delta',
                              ),
                              subtitle: Text(
                                '${row['previous_stock']} → ${row['counted_stock']} · '
                                '${row['reason']} · ${row['adjustment_date']}\n'
                                '${row['note']}${row['status'] == 'void' ? '\nVOID: ${row['void_reason']}' : ''}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (row['status'] == 'posted')
                                    IconButton(
                                      tooltip: tr(
                                        'Correct (Owner)',
                                        'ပြင်ရန် (Owner)',
                                      ),
                                      onPressed: () => add(editing: row),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  if (row['status'] == 'posted')
                                    IconButton(
                                      tooltip: tr('Void', 'ပယ်ဖျက်ရန်'),
                                      onPressed: () => voidRecord(row),
                                      icon: const Icon(Icons.undo),
                                    ),
                                  IconButton(
                                    tooltip: tr(
                                      'Delete permanently',
                                      'အပြီးတိုင်ဖျက်ရန်',
                                    ),
                                    onPressed: () async {
                                      final ok = await deleteVoucherWithPrompt(
                                        context,
                                        kind: 'adjustment',
                                        id: row['id'] as int,
                                        number: 'ADJ-${row['id']}',
                                      );
                                      if (ok && mounted) await load();
                                    },
                                    icon: const Icon(
                                      Icons.delete_forever_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
  );
}
