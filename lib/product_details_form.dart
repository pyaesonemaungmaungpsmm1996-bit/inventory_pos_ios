import 'dart:async';

import 'package:flutter/services.dart';

import 'desktop_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_database.dart';
import 'product_tracking.dart';
import 'brand_store.dart';
import 'barcode_scan_page.dart';
import 'app_currency.dart';
import 'amount_input.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
Future<Map<String, Object?>?> purchaseProductDetails(
  BuildContext context,
  Map<String, Object?> item, {
  Map<String, Object?>? previous,
  Map<String, Object?>? product,
  Widget Function(BuildContext, StateSetter, Future<bool> Function(int))?
  entryBuilder,
  bool Function()? validateEntry,
  Map<String, Object?> Function()? readEntry,
  String? title,
  String? actionLabel,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final capturedThemes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  final db = await AppDatabase.instance.database;
  var categoryId = item['category_id'] as int;
  final categoryRows = await db.query(
    'product_categories',
    columns: ['name'],
    where: 'id=?',
    whereArgs: [categoryId],
  );
  var categoryName = categoryRows.isEmpty
      ? 'Category unavailable'
      : '${categoryRows.single['name']}';
  final brands = (await BrandStore.list(db, categoryId)).toList();
  if (!context.mounted) return null;
  final base = <String, Object?>{
    ...?product,
    if (previous?['product_id'] == item['product_id']) ...?previous,
  };
  var mode = '${base['tracking'] ?? 'none'}';
  int? brand = base['brand_id'] as int?;
  if (!brands.any((b) => b['id'] == brand)) brand = null;
  final color = TextEditingController(text: '${base['color'] ?? ''}'),
      size = TextEditingController(text: '${base['size'] ?? ''}'),
      warranty = TextEditingController(text: '${base['warranty_days'] ?? 0}');
  final prior = ProductTracking.decode(previous?['lots']);
  final expiry = TextEditingController(
    text: prior.isEmpty ? '' : '${prior.first['expires_on'] ?? ''}',
  );
  final identities = TextEditingController(
    text: prior
        .map(
          (l) => mode == 'both'
              ? '${l['serial']},${l['imei']}'
              : mode == 'imei'
              ? '${l['imei']}'
              : '${l['serial'] ?? ''}',
        )
        .join('\n'),
  );
  String? error;
  bool savingBrand = false, submitting = false, finished = false;
  DialogRoute<Map<String, Object?>>? editorRoute;
  try {
    editorRoute = DialogRoute<Map<String, Object?>>(
      context: context,
      themes: capturedThemes,
      barrierDismissible: entryBuilder == null,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, update) {
          void cancelEntry() {
            if (finished || submitting) return;
            finished = true;
            Navigator.pop(dialog);
          }

          Future<void> submitEntry() async {
            if (savingBrand || submitting || finished) return;
            submitting = true;
            try {
              if (validateEntry != null && !validateEntry()) return;
              final submittedItem = readEntry?.call() ?? item;
              final qty = submittedItem['qty'] as int;
              final days = int.tryParse(warranty.text.trim());
              if (days == null || days < 0 || days > 36500) {
                update(
                  () => error = _t(
                    'Enter warranty days from 0 to 36500.',
                    'အာမခံရက် 0 မှ 36500 အတွင်းထည့်ပါ။',
                  ),
                );
                return;
              }
              if (mode == 'none' && days > 0) {
                update(
                  () => error = _t(
                    'Choose Batch or Serial tracking for warranty.',
                    'အာမခံအတွက် Batch သို့မဟုတ် Serial tracking ရွေးပါ။',
                  ),
                );
                return;
              }
              final lots = <Map<String, Object?>>[];
              final exp = expiry.text.trim();
              if (mode == 'batch') {
                lots.add({'qty': qty, 'expires_on': exp});
              }
              if (mode != 'none' && mode != 'batch') {
                final entries = identities.text
                    .split('\n')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toList();
                if (entries.length != qty || entries.length > 500) {
                  update(
                    () => error = _t(
                      'Number of serial/IMEI lines must match quantity (maximum 500).',
                      'Serial/IMEI အကြောင်းရေသည် အရေအတွက်နှင့် တူရပါမည် (အများဆုံး 500)။',
                    ),
                  );
                  return;
                }
                final seen = <String>{};
                for (final line in entries) {
                  final parts = line.split(',').map((s) => s.trim()).toList();
                  final serial = mode == 'imei' ? '' : parts.first;
                  final imei = mode == 'both'
                      ? (parts.length == 2 ? parts[1] : '')
                      : mode == 'imei'
                      ? line
                      : '';
                  if ((mode != 'imei' &&
                          (serial.isEmpty ||
                              serial.length > 100 ||
                              !seen.add('s:${serial.toLowerCase()}'))) ||
                      (mode != 'serial' &&
                          (!RegExp(r'^\d{15}$').hasMatch(imei) ||
                              !seen.add('i:$imei')))) {
                    update(
                      () => error = _t(
                        'Check duplicate serial numbers and 15-digit IMEIs.',
                        'Serial ထပ်နေခြင်းနှင့် IMEI ဂဏန်း ၁၅ လုံးကို စစ်ပါ။',
                      ),
                    );
                    return;
                  }
                  lots.add({
                    'qty': 1,
                    'serial': serial,
                    'imei': imei,
                    'expires_on': exp,
                  });
                }
              }
              final separate =
                  product != null &&
                  (mode != '${product['tracking'] ?? 'none'}' ||
                      color.text.trim() != '${product['color'] ?? ''}' ||
                      size.text.trim() != '${product['size'] ?? ''}');
              if (separate) {
                final yes = await showDialog<bool>(
                  context: ctx,
                  builder: (c) => DesktopDialog(
                    title: Text(
                      _t(
                        'Create a separate tracked / variant item?',
                        'Tracking / Variant အတွက် ပစ္စည်းသီးခြားဖန်တီးမလား?',
                      ),
                    ),
                    content: Text(
                      _t(
                        'This purchase will use a new item code. Existing stock and history remain on ${product['name']}. No existing stock is converted or assigned invented identifiers.',
                        'ဤအဝယ်ကို ပစ္စည်းကုဒ်အသစ်ဖြင့် သိမ်းပါမည်။ ${product['name']} ၏ လက်ကျန်နှင့် မှတ်တမ်းဟောင်းကို မပြောင်းပါ။ ပစ္စည်းဟောင်းကို Serial အတုဖြင့် မသတ်မှတ်ပါ။',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(_t('Cancel', 'မလုပ်တော့')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(
                          _t('Create separate item', 'ပစ္စည်းသီးခြားဖန်တီးမည်'),
                        ),
                      ),
                    ],
                  ),
                );
                if (yes != true || !ctx.mounted) return;
              }
              finished = true;
              Navigator.pop(dialog, <String, Object?>{
                ...submittedItem,
                'create_separate_sku': separate,
                'brand_id': brand,
                'color': color.text.trim(),
                'size': size.text.trim(),
                'tracking': mode,
                'warranty_days': days,
                'lots': lots,
              });
            } finally {
              submitting = false;
            }
          }

          final detailFields = <Widget>[
            Text('${_t('Category', 'အမျိုးအစား')}: $categoryName'),
            if (savingBrand) const LinearProgressIndicator(),
            if (brands.isEmpty)
              Text(
                _t(
                  'No brands in this category yet. Tap Add brand below.',
                  'ဤ Category တွင် Brand မရှိသေးပါ။ အောက်ရှိ Add brand နှိပ်၍ ထည့်ပါ။',
                ),
              ),
            DropdownButtonFormField<int>(
              key: ValueKey(brand),
              initialValue: brand ?? 0,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Brand'),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(_t('No brand', 'Brand မရှိ')),
                ),
                for (final b in brands)
                  DropdownMenuItem(
                    value: b['id'] as int,
                    child: Text('${b['name']}'),
                  ),
              ],
              onChanged: (v) => update(() => brand = v == 0 ? null : v),
            ),
            TextButton.icon(
              onPressed: savingBrand
                  ? null
                  : () async {
                      var value = '';
                      final entered = await showDialog<String>(
                        context: ctx,
                        builder: (c) => DesktopDialog(
                          title: Text(
                            _t(
                              'Add brand in this category',
                              'ဤ Category တွင် Brand ထည့်ရန်',
                            ),
                          ),
                          content: TextField(
                            autofocus: true,
                            maxLength: 100,
                            onChanged: (v) => value = v,
                            decoration: const InputDecoration(
                              labelText: 'Brand',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: Text(_t('Cancel', 'မလုပ်တော့')),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, value.trim()),
                              child: Text(_t('Add', 'ထည့်မည်')),
                            ),
                          ],
                        ),
                      );
                      if (entered == null || entered.isEmpty || !ctx.mounted) {
                        return;
                      }
                      update(() => savingBrand = true);
                      try {
                        final id = await BrandStore.save(
                          db,
                          categoryId,
                          entered,
                        );
                        final fresh = await BrandStore.list(db, categoryId);
                        if (ctx.mounted) {
                          update(() {
                            brands.clear();
                            brands.addAll(fresh);
                            brand = id;
                            error = null;
                          });
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          final detail = BrandStore.errorText(e);
                          update(() => error = detail);
                          await showDialog<void>(
                            context: ctx,
                            builder: (c) => DesktopDialog(
                              title: Text(
                                _t('Could not add brand', 'Brand ထည့်မရပါ'),
                              ),
                              content: SelectableText(detail),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        }
                      } finally {
                        if (ctx.mounted) {
                          update(() => savingBrand = false);
                        }
                      }
                    },
              icon: const Icon(Icons.add),
              label: Text(_t('Add brand', 'Brand အသစ်ထည့်ရန်')),
            ),
            TextField(
              controller: color,
              enabled: true,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: _t(
                  'Color · separate SKU',
                  'အရောင် · သီးခြားပစ္စည်းကုဒ်',
                ),
              ),
            ),
            TextField(
              controller: size,
              enabled: true,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: _t(
                  'Size · separate SKU',
                  'ဆိုဒ် · သီးခြားပစ္စည်းကုဒ်',
                ),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: mode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _t('Tracking mode', 'ပစ္စည်းလိုက်မှတ်တမ်း'),
              ),
              items: [
                for (final entry in {
                  'none': _t('No tracking', 'သီးခြားမမှတ်'),
                  'batch': _t('Batch / expiry', 'အသုတ် / သက်တမ်းကုန်ရက်'),
                  'serial': 'Serial number',
                  'imei': 'IMEI',
                  'both': 'Serial + IMEI',
                }.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) => update(() {
                mode = v!;
                error = null;
              }),
            ),
            TextField(
              controller: warranty,
              enabled: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _t(
                  'Warranty days · 0 = none',
                  'အာမခံရက် · မရှိလျှင် 0',
                ),
              ),
            ),
          ];
          final view = DesktopDialog(
            title: entryBuilder == null
                ? Text(
                    title ??
                        _t(
                          'Brand, variant & tracking',
                          'Brand၊ အရောင်/ဆိုဒ်နှင့် ပစ္စည်းစစ်ဆေးမှု',
                        ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          title ?? _t('Purchase item', 'အဝယ်ပစ္စည်း'),
                        ),
                      ),
                      IconButton(
                        tooltip: _t('Close item', 'ပစ္စည်း Popup ပိတ်ရန်'),
                        onPressed: savingBrand ? null : cancelEntry,
                        icon: const Icon(Icons.close, size: 19),
                      ),
                    ],
                  ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entryBuilder != null)
                      entryBuilder(ctx, update, (id) async {
                        if (savingBrand) return false;
                        update(() => savingBrand = true);
                        try {
                          final rows = await db.query(
                            'product_categories',
                            columns: ['name'],
                            where: 'id=? AND active=1',
                            whereArgs: [id],
                          );
                          if (rows.isEmpty) {
                            throw StateError('Choose an active category');
                          }
                          final fresh = await BrandStore.list(db, id);
                          if (!ctx.mounted) return false;
                          update(() {
                            categoryId = id;
                            categoryName = rows.single['name'].toString();
                            brands
                              ..clear()
                              ..addAll(fresh);
                            if (!brands.any((b) => b['id'] == brand)) {
                              brand = null;
                            }
                            error = null;
                          });
                          return true;
                        } catch (_) {
                          if (ctx.mounted) {
                            update(
                              () => error = _t(
                                'Could not load this category. Retry.',
                                'ဤ Category ကို ဖတ်မရပါ။ ပြန်စမ်းပါ။',
                              ),
                            );
                          }
                          return false;
                        } finally {
                          if (ctx.mounted) update(() => savingBrand = false);
                        }
                      }),
                    if (entryBuilder == null)
                      ...detailFields
                    else
                      DesktopSection(
                        title: Text(
                          _t(
                            'More item details · Brand / Color / Size / Tracking',
                            'အသေးစိတ် · Brand / အရောင် / ဆိုဒ် / Tracking',
                          ),
                        ),
                        initiallyExpanded: false,
                        children: detailFields,
                      ),
                    if (mode != 'none') ...[
                      TextField(
                        controller: expiry,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: _t(
                            'Expiry date · optional',
                            'သက်တမ်းကုန်ရက် · မရှိလျှင် ချန်ထား',
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => update(() => expiry.clear()),
                            icon: const Icon(Icons.clear),
                          ),
                        ),
                        onTap: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(expiry.text) ?? now,
                            firstDate: DateTime(now.year - 10),
                            lastDate: DateTime(now.year + 100),
                          );
                          if (d != null) {
                            update(
                              () => expiry.text = d.toIso8601String().substring(
                                0,
                                10,
                              ),
                            );
                          }
                        },
                      ),
                      if (mode != 'batch')
                        TextField(
                          controller: identities,
                          minLines: 3,
                          maxLines: 8,
                          decoration: InputDecoration(
                            labelText: mode == 'both'
                                ? 'Serial,IMEI · one item per line'
                                : mode == 'imei'
                                ? 'IMEI · one per line'
                                : 'Serial · one per line',
                            helperText: _t(
                              'One line for EACH unit. IMEI: 15 digits.',
                              'ပစ္စည်းတစ်လုံးလျှင် တစ်ကြောင်း။ IMEI: ဂဏန်း ၁၅ လုံး။',
                            ),
                          ),
                        ),
                    ],
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    Text(
                      _t(
                        'Brand can be updated on an existing item. Changing its tracking mode, Color or Size creates a separate item code for this incoming purchase; old stock and invoices stay with the original item.',
                        'Brand ကို ပစ္စည်းဟောင်းတွင် ပြင်နိုင်ပါသည်။ Tracking၊ အရောင် သို့မဟုတ် ဆိုဒ် ပြောင်းလျှင် ဤအဝယ်အတွက် ကုဒ်အသစ်ဖြင့် သီးခြားပစ္စည်း ဖန်တီးပါမည်။ လက်ကျန်နှင့် ဘောင်ချာအဟောင်းများ မူရင်းပစ္စည်းတွင် ဆက်ရှိပါမည်။',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: savingBrand ? null : cancelEntry,
                child: Text(_t('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: savingBrand ? null : submitEntry,
                child: Text(actionLabel ?? _t('Apply', 'သတ်မှတ်မည်')),
              ),
            ],
          );
          return entryBuilder == null
              ? view
              : CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      control: true,
                    ): () =>
                        unawaited(submitEntry()),
                  },
                  child: view,
                );
        },
      ),
    );
    return await navigator.push<Map<String, Object?>>(editorRoute);
  } finally {
    if (editorRoute != null) await editorRoute.completed;
    for (final c in [color, size, warranty, expiry, identities]) {
      c.dispose();
    }
  }
}

Future<String?> pickSaleLots(
  BuildContext context,
  int product,
  int branch,
  int qty,
  Object? prior, {
  int? saleItem,
  int? excludeReturn,
  int? editingSaleId,
  int? unitPrice,
  void Function(int quantity, int price)? onDetails,
}) async {
  final db = await AppDatabase.instance.database;
  final p = (await db.query(
    'products',
    where: 'id=?',
    whereArgs: [product],
  )).single;
  final tracked = ProductTracking.tracked(p);
  final variants = [
    'color',
    'size',
  ].where((f) => '${p[f] ?? ''}'.isNotEmpty).toList();
  if (!tracked && variants.isEmpty && onDetails == null) return '[]';
  final form = GlobalKey<FormState>();
  final lots = !tracked
      ? <Map<String, Object?>>[]
      : editingSaleId != null
      ? await db.rawQuery(
          '''SELECT l.*, l.available + COALESCE((SELECT SUM(a.quantity) FROM sale_lot_allocations a JOIN sale_items i ON i.id=a.sale_item_id WHERE a.lot_id=l.id AND i.sale_id=?),0) AS available
          FROM stock_lots l WHERE l.product_id=? AND l.branch_id=? AND (l.expires_on IS NULL OR l.expires_on>=?) ORDER BY l.id''',
          [editingSaleId, product, branch, ProductTracking.today()],
        )
      : saleItem == null
      ? await db.query(
          'stock_lots',
          where: 'product_id=? AND branch_id=? AND available>0 AND (expires_on IS NULL OR expires_on>=?)',
          whereArgs: [product, branch, ProductTracking.today()],
          orderBy: 'expires_on IS NULL,expires_on,id',
        )
      : await db.rawQuery(
          "SELECT l.*,a.quantity-COALESCE((SELECT SUM(x.quantity) FROM return_lot_allocations x JOIN sale_returns r ON r.id=x.return_id WHERE r.status='posted' AND r.id<>? AND x.sale_item_id=a.sale_item_id AND x.lot_id=l.id),0) AS available FROM sale_lot_allocations a JOIN stock_lots l ON l.id=a.lot_id WHERE a.sale_item_id=? ORDER BY l.id",
          [excludeReturn ?? -1, saleItem],
        );
  if (!context.mounted) return null;
  final previous = {
    for (final a in ProductTracking.decode(prior)) a['lot_id']: a['qty'],
  };
  final controllers = {
    for (final l in lots)
      l['id'] as int: TextEditingController(text: '${previous[l['id']] ?? 0}'),
  };
  final search = TextEditingController();
  String? error;
  int selectedCount() => controllers.values.fold(
    0,
    (sum, c) => sum + (int.tryParse(c.text.trim()) ?? 0),
  );
  bool matches(Map l) {
    final query = search.text.trim().toLowerCase();
    return query.isEmpty ||
        '${l['serial'] ?? ''}'.toLowerCase().contains(query) ||
        '${l['imei'] ?? ''}'.toLowerCase().contains(query);
  }

  try {
    return await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (ctx, update) {
          final visible = lots.where(matches).toList();
          void choose(Map<String, Object?> lot, {bool scanned = false}) {
            final controller = controllers[lot['id']]!;
            final current = int.tryParse(controller.text) ?? 0;
            update(() {
              error = null;
              if (current > 0) {
                if (!scanned) controller.text = '0';
              } else if ((lot['available'] as int) < 1) {
                error = 'This item is unavailable.';
              } else if (qty == 1) {
                for (final c in controllers.values) {
                  c.text = '0';
                }
                controller.text = '1';
              } else if (selectedCount() < qty) {
                controller.text = '1';
              } else {
                error = 'The required quantity is already selected.';
              }
              if (scanned) search.clear();
            });
          }

          void scan(String code) {
            final exact = lots
                .where(
                  (l) => ['serial', 'imei'].any(
                    (f) =>
                        '${l[f] ?? ''}'.toLowerCase() ==
                        code.trim().toLowerCase(),
                  ),
                )
                .toList();
            if (code.trim().isNotEmpty && exact.length == 1) {
              choose(exact.single, scanned: true);
            } else {
              update(
                () => error = 'Scan an exact eligible Serial / IMEI for this item and branch.',
              );
            }
          }

          return DesktopDialog(
            title: Text(
              _t(
                'Select exact items · $qty required',
                'ပစ္စည်း ရွေးရန် · $qty ခု',
              ),
            ),
            content: SizedBox(
              width: 500,
              height: MediaQuery.sizeOf(ctx).height * 0.55,
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text('${p['name']}'),
                      if (onDetails != null)
                        TextFormField(
                          key: const ValueKey('sale-item-quantity'),
                          initialValue: '$qty',
                          decoration: InputDecoration(
                            labelText: _t('Qty', 'အရေအတွက်'),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) =>
                              update(() => qty = int.tryParse(v) ?? 0),
                          validator: (v) => qty < 1 || qty > 2147483647
                              ? 'Enter a positive whole quantity.'
                              : null,
                        ),
                      if (onDetails != null)
                        TextFormField(
                          key: const ValueKey('sale-item-price'),
                          initialValue: AmountInputFormatter.group(
                            AppCurrency.input(unitPrice ?? 0),
                          ),
                          inputFormatters: const [AmountInputFormatter()],
                          decoration: InputDecoration(
                            labelText: _t('Price', 'ဈေးနှုန်း'),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => unitPrice = AppCurrency.tryParse(v),
                          validator: (v) =>
                              unitPrice == null ||
                                  unitPrice! < 0 ||
                                  unitPrice! > 2147483647
                              ? 'Enter a valid price.'
                              : null,
                        ),
                      for (final field in variants)
                        DropdownButtonFormField<String>(
                          key: ValueKey('sale-required-$field'),
                          decoration: InputDecoration(
                            labelText: field == 'color'
                                ? _t('Choose color', 'အရောင်ရွေးပါ')
                                : _t('Choose size', 'အရွယ်အစားရွေးပါ'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '${p[field]}',
                              child: Text('${p[field]}'),
                            ),
                          ],
                          onChanged: (_) {},
                          validator: (v) => v == null
                              ? _t('Required', 'မဖြစ်မနေရွေးပါ')
                              : null,
                        ),
                      if (tracked)
                        TextField(
                          autofocus: true,
                          controller: search,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) => update(() {}),
                          textInputAction: TextInputAction.search,
                          onSubmitted: scan,
                          decoration: InputDecoration(
                            labelText: _t(
                              'Search Serial / IMEI',
                              'Serial / IMEI ရှာရန်',
                            ),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              onPressed: () {
                                search.clear();
                                update(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                          ),
                        ),
                      if (tracked)
                        TextButton.icon(
                          onPressed: () async {
                            final code = await Navigator.of(ctx).push<String>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const BarcodeScanPage(identity: true),
                              ),
                            );
                            if (code == null || !ctx.mounted) return;
                            scan(code);
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(
                            _t(
                              'Scan Serial / IMEI',
                              'Serial / IMEI Scan ဖတ်ရန်',
                            ),
                          ),
                        ),
                      if (tracked)
                        Text(
                          '${_t('Selected', 'ရွေးထားသည်')}: ${selectedCount()} / $qty · ${_t('Matches', 'တွေ့ရှိသည်')}: ${visible.length}',
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      if (tracked)
                        SizedBox(
                          height: 240,
                          child: visible.isEmpty
                              ? Center(
                                  child: Text(
                                    lots.isEmpty
                                        ? _t(
                                            'No eligible stock. Check expired batches.',
                                            'ရောင်းနိုင်သော လက်ကျန်မရှိပါ။ သက်တမ်းကုန်အသုတ်များ စစ်ပါ။',
                                          )
                                        : _t(
                                            'No matches. Clear search to see all items.',
                                            'မတွေ့ပါ။ စာရင်းအားလုံးကြည့်ရန် Search ဖျက်ပါ။',
                                          ),
                                  ),
                                )
                              : DesktopListView.builder(
                                  itemCount: visible.length,
                                  itemBuilder: (c, index) {
                                    final l = visible[index];
                                    final identity =
                                        '${l['serial'] ?? ''} ${l['imei'] ?? ''}'
                                            .trim();
                                    if (identity.isNotEmpty) {
                                      return CheckboxListTile(
                                        key: ValueKey('sale-lot-${l['id']}'),
                                        value:
                                            (int.tryParse(
                                                  controllers[l['id']]!.text,
                                                ) ??
                                                0) >
                                            0,
                                        onChanged: (_) => choose(l),
                                        title: Text(identity),
                                        subtitle: Text(
                                          'Available: ${l['available']}',
                                        ),
                                      );
                                    }
                                    return Padding(
                                      key: ValueKey(l['id']),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${l['serial'] ?? ''} ${l['imei'] ?? ''} · ${_t('Available', 'လက်ကျန်')}: ${l['available']}\n${_t('Expiry', 'သက်တမ်းကုန်')}: ${l['expires_on'] ?? '—'}',
                                          ),
                                          TextField(
                                            controller: controllers[l['id']],
                                            onChanged: (_) => update(() {}),
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              labelText: saleItem == null
                                                  ? _t(
                                                      'Quantity to sell',
                                                      'ရောင်းမည့်အရေအတွက်',
                                                    )
                                                  : _t(
                                                      'Quantity to return',
                                                      'ပြန်ယူမည့်အရေအတွက်',
                                                    ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(_t('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: () {
                  var total = 0;
                  if (!form.currentState!.validate()) return;
                  final chosen = <Map<String, int>>[];
                  // Validate every selection, including rows hidden by the current search.
                  for (final l in lots) {
                    final n = int.tryParse(controllers[l['id']]!.text.trim());
                    if (n == null || n < 0 || n > (l['available'] as int)) {
                      update(
                        () => error = _t(
                          'Check selected quantities.',
                          'ရွေးထားသည့် အရေအတွက်စစ်ပါ။',
                        ),
                      );
                      return;
                    }
                    if (n > 0) {
                      chosen.add({'lot_id': l['id'] as int, 'qty': n});
                      total += n;
                    }
                  }
                  if (tracked && total != qty) {
                    update(
                      () => error = _t(
                        'Select exactly $qty items.',
                        '$qty ခု အတိအကျရွေးပါ။',
                      ),
                    );
                    return;
                  }
                  onDetails?.call(qty, unitPrice ?? 0);
                  Navigator.pop(dialog, jsonEncode(chosen));
                },
                child: Text(_t('Select', 'ရွေးမည်')),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    search.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
  }
}

Future<void> showProductTracking(BuildContext context, Object? data) async {
  final rows = ProductTracking.decode(data);
  await showDialog<void>(
    context: context,
    builder: (c) => DesktopDialog(
      title: Text(_t('Item tracking details', 'ပစ္စည်းအသေးစိတ်မှတ်တမ်း')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rows.isEmpty)
                Text(
                  _t(
                    'No serial or batch tracking for this item.',
                    'ဤပစ္စည်းတွင် Serial / အသုတ်မှတ်တမ်းမရှိပါ။',
                  ),
                ),
              for (final r in rows)
                DesktopListTile(
                  title: SelectableText(
                    [
                      if ('${r['serial'] ?? ''}'.isNotEmpty)
                        'Serial: ${r['serial']}',
                      if ('${r['imei'] ?? ''}'.isNotEmpty) 'IMEI: ${r['imei']}',
                    ].join('\n'),
                  ),
                  subtitle: Text(
                    '${_t('Quantity', 'အရေအတွက်')}: ${r['qty']}\n${_t('Expiry', 'သက်တမ်းကုန်')}: ${r['expires_on'] ?? '—'}\n${_t('Warranty until', 'အာမခံနောက်ဆုံးရက်')}: ${r['warranty_until'] ?? '—'}',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(_t('Close', 'ပိတ်မည်')),
        ),
      ],
    ),
  );
}
