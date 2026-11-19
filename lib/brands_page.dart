import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'brand_store.dart';

class BrandsPage extends StatefulWidget {
  const BrandsPage({super.key, this.categoryId});
  final int? categoryId;
  @override
  State<BrandsPage> createState() => _BrandsPageState();
}

class _BrandsPageState extends State<BrandsPage> {
  List<Map<String, Object?>> rows = [], categories = [];
  int? category;
  bool loading = true, busy = false;
  int request = 0;
  String? error;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    category = widget.categoryId;
    load();
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final choices = await AppDatabase.instance.getProductCategories();
      if (!mounted || token != request) return;
      final chosen = choices.any((c) => c['id'] == category)
          ? category
          : choices.isEmpty
          ? null
          : choices.first['id'] as int;
      // Keep category choices visible even if loading brands fails.
      setState(() {
        categories = choices;
        category = chosen;
        rows = [];
      });
      final brands = chosen == null
          ? <Map<String, Object?>>[]
          : await BrandStore.list(db, chosen, includeArchived: true);
      if (mounted && token == request) {
        setState(() {
          rows = brands;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = BrandStore.errorText(e);
          loading = false;
        });
      }
    }
  }

  Future<String?> askName(String title, [String initial = '']) async {
    var name = initial;
    final form = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: TextFormField(
            initialValue: initial,
            autofocus: true,
            maxLength: 100,
            onChanged: (v) => name = v,
            validator: (v) => (v ?? '').trim().isEmpty
                ? t('Enter a name', 'အမည်ထည့်ပါ')
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(t('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(c, name.trim());
            },
            child: Text(t('Save', 'သိမ်းမည်')),
          ),
        ],
      ),
    );
  }

  Future<void> showError(Object e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(t('Could not save', 'သိမ်းမရပါ')),
        content: SelectableText(BrandStore.errorText(e)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> addCategory() async {
    if (busy || loading) return;
    final name = await askName(
      t('New product category', 'ပစ္စည်းအမျိုးအစားအသစ်'),
    );
    if (name == null || !mounted) return;
    setState(() => busy = true);
    try {
      await AppDatabase.instance.saveProductCategory(name: name);
      final choices = await AppDatabase.instance.getProductCategories();
      final match = choices.where(
        (c) => '${c['name']}'.toLowerCase() == name.toLowerCase(),
      );
      if (match.isNotEmpty) category = match.first['id'] as int;
      if (mounted) await load();
    } catch (e) {
      await showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, Object?>? row]) async {
    if (busy || loading) return;
    final selected = category;
    if (selected == null) {
      await addCategory();
      return;
    }
    final value = await askName(
      t('Brand name', 'Brand အမည်'),
      '${row?['name'] ?? ''}',
    );
    if (value == null || !mounted) return;
    setState(() => busy = true);
    try {
      final db = await AppDatabase.instance.database;
      await BrandStore.save(db, selected, value, id: row?['id'] as int?);
      if (mounted) await load();
    } catch (e) {
      await showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(Map<String, Object?> row) async {
    if (busy || loading) return;
    setState(() => busy = true);
    try {
      final db = await AppDatabase.instance.database;
      await db.update(
        'product_brands',
        {'active': row['active'] == 1 ? 0 : 1},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      if (mounted) await load();
    } catch (e) {
      await showError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(t('Brands within categories', 'အမျိုးအစားအလိုက် Brand များ')),
      actions: [
        IconButton(
          onPressed: busy || loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      tooltip: category == null
          ? t('Add category', 'Category အသစ်')
          : t('Add brand', 'Brand အသစ်'),
      onPressed: busy || loading ? null : () => edit(),
      icon: const Icon(Icons.add),
      label: Text(
        category == null
            ? t('Add category', 'Category ထည့်ရန်')
            : t('Add brand', 'Brand ထည့်ရန်'),
      ),
    ),
    body: DesktopListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (loading || busy) const LinearProgressIndicator(),
        if (error != null) ...[
          SelectableText(error!),
          TextButton(
            onPressed: busy || loading ? null : load,
            child: Text(t('Retry', 'ပြန်စမ်းရန်')),
          ),
        ],
        DropdownButtonFormField<int>(
          key: ValueKey(category),
          initialValue: category,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('Category', 'အမျိုးအစား')),
          items: [
            for (final c in categories)
              DropdownMenuItem(
                value: c['id'] as int,
                child: Text('${c['name']}'),
              ),
          ],
          onChanged: loading || busy || categories.isEmpty
              ? null
              : (v) {
                  setState(() => category = v);
                  load();
                },
        ),
        TextButton.icon(
          onPressed: busy || loading ? null : addCategory,
          icon: const Icon(Icons.add),
          label: Text(t('Add category', 'Category ထည့်ရန်')),
        ),
        if (!loading && categories.isEmpty)
          Text(
            t(
              'No active product categories. Add a category first.',
              'အသုံးပြုနိုင်သော Category မရှိပါ။ Category အရင်ထည့်ပါ။',
            ),
          ),
        if (!loading && error == null && category != null && rows.isEmpty)
          Text(
            t(
              'No brands in this category. Tap Add brand.',
              'ဤ Category တွင် Brand မရှိသေးပါ။ Add brand နှိပ်ပါ။',
            ),
          ),
        DesktopInlineTable(
          columns: const ["Brand", "Status"],
          rows: [
            for (final r in rows)
              Card(
                child: DesktopListTile(
                  title: Text('${r['name']}'),
                  subtitle: Text(
                    r['active'] == 1
                        ? t('Active', 'အသုံးပြုနိုင်')
                        : t('Archived', 'ပိတ်ထားသည်'),
                  ),
                  onTap: busy || loading ? null : () => edit(r),
                  trailing: IconButton(
                    onPressed: busy || loading ? null : () => toggle(r),
                    icon: Icon(
                      r['active'] == 1
                          ? Icons.archive_outlined
                          : Icons.unarchive_outlined,
                    ),
                  ),
                ),
              ),
          ],
          cells: [
            for (final r in rows)
              [desktopCellText(r['name']), desktopActive(r['active'])],
          ],
        ),
      ],
    ),
  );
}
