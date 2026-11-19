import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_database.dart';
import 'app_currency.dart';
import 'app_language.dart';
import 'amount_input.dart';
import 'product_photo.dart';
import 'barcode_rules.dart';
import 'barcode_scan_page.dart';
import 'barcode_label_page.dart';

class ProductEditorPage extends StatefulWidget {
  const ProductEditorPage({super.key, required this.product});
  final Map<String, Object?> product;
  @override
  State<ProductEditorPage> createState() => _ProductEditorPageState();
}

class _ProductEditorPageState extends State<ProductEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, code, barcode, price, color, size;
  int? categoryId, brandId;
  List<Map<String, Object?>> categories = [], brands = [];
  Uint8List? photo;
  bool busy = false, remove = false, changed = false;
  String? error;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.product['name']}');
    code = TextEditingController(text: '${widget.product['item_code']}');
    barcode = TextEditingController(text: '${widget.product['barcode'] ?? ''}');
    price = TextEditingController(
      text: AppCurrency.input(widget.product['price'] as int),
    );
    color = TextEditingController(text: '${widget.product['color'] ?? ''}');
    size = TextEditingController(text: '${widget.product['size'] ?? ''}');
    categoryId = widget.product['category_id'] as int?;
    brandId = widget.product['brand_id'] as int?;
    load();
    loadGroups();
  }

  Future<void> loadGroups() async {
    try {
      final db = await AppDatabase.instance.database;
      final c = await db.query(
        'product_categories',
        where: 'active=1 OR id=?',
        whereArgs: [categoryId],
        orderBy: 'name',
      );
      final b = await db.query(
        'product_brands',
        where: 'active=1 OR id=?',
        whereArgs: [brandId],
        orderBy: 'name',
      );
      if (mounted) {
        setState(() {
          categories = c;
          brands = b;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> load() async {
    if (widget.product['id'] == null) return;
    try {
      final bytes = await AppDatabase.instance.getProductImage(
        widget.product['id'] as int,
      );
      if (mounted && !changed) setState(() => photo = bytes);
    } catch (_) {
      /* Photo is optional; metadata stays editable. */
    }
  }

  @override
  void dispose() {
    for (final c in [name, code, barcode, price, color, size]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 960,
        maxHeight: 960,
        imageQuality: 80,
      );
      if (file != null) {
        final bytes = await prepareProductPhoto(await file.readAsBytes());
        if (mounted) {
          setState(() {
            photo = bytes;
            changed = true;
            remove = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = t('Could not open photo.', 'ပုံမဖွင့်နိုင်ပါ။'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (widget.product['id'] == null) {
        final branch =
            widget.product['branch_id'] as int? ??
            await AppDatabase.instance.getDefaultBranchId();
        if (branch == null) throw StateError('Choose a branch first');
        await AppDatabase.instance.addProduct(
          name: name.text,
          price: AppCurrency.parse(price.text),
          stock: 0,
          branchId: branch,
          itemCode: code.text,
          barcode: barcode.text,
          categoryId: categoryId ?? 1,
          brandId: brandId,
          color: color.text,
          size: size.text,
          imageBytes: changed && !remove ? photo : null,
        );
      } else {
        await AppDatabase.instance.updateProduct(
          id: widget.product['id'] as int,
          name: name.text,
          price: AppCurrency.parse(price.text),
          itemCode: code.text,
          barcode: barcode.text,
          imageBytes: changed && !remove ? photo : null,
          removeImage: remove,
          categoryId: categoryId,
          brandId: brandId,
          changeBrand: brands.isNotEmpty,
          color: color.text,
          size: size.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(
          t(
            widget.product['id'] == null ? 'New Item' : 'Edit Item',
            'ပစ္စည်းပြင်ရန်',
          ),
        ),
      ),
      body: Form(
        key: form,
        child: DesktopListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (photo != null)
              Image.memory(photo!, height: 120, fit: BoxFit.contain),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : () => pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(t('Photo (optional)', 'ပုံ (မဖြစ်မနေမလို)')),
                ),
                if (AppCapabilities.camera)
                  TextButton(
                    onPressed: busy ? null : () => pick(ImageSource.camera),
                    child: Text(t('Camera', 'ကင်မရာ')),
                  ),
                if (photo != null)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            photo = null;
                            remove = true;
                            changed = true;
                          }),
                    child: Text(t('Remove photo', 'ပုံဖယ်ရန်')),
                  ),
              ],
            ),
            TextFormField(
              controller: name,
              enabled: !busy,
              maxLength: 150,
              decoration: InputDecoration(
                labelText: t('Item Name', 'ပစ္စည်းအမည်'),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? t('Required', 'ဖြည့်ရန်လိုပါသည်')
                  : null,
            ),
            TextFormField(
              controller: code,
              enabled: !busy,
              maxLength: 32,
              decoration: const InputDecoration(labelText: 'Item Code'),
              validator: (v) =>
                  (widget.product['id'] == null &&
                          (v?.trim().isEmpty ?? true)) ||
                      BarcodeRules.validItemCode(v?.trim() ?? '')
                  ? null
                  : t('Invalid code', 'ကုဒ်မမှန်ပါ'),
            ),
            TextFormField(
              controller: barcode,
              enabled: !busy,
              maxLength: 32,
              decoration: InputDecoration(
                labelText: t('Barcode (optional)', 'Barcode (မဖြစ်မနေမလို)'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: busy
                      ? null
                      : () async {
                          final value = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BarcodeScanPage(),
                            ),
                          );
                          if (value != null) barcode.text = value;
                        },
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty || BarcodeRules.valid(v.trim())
                  ? null
                  : t('Invalid barcode', 'Barcode မမှန်ပါ'),
            ),
            if (categories.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: categoryId,
                decoration: InputDecoration(
                  labelText: t('Category', 'အမျိုးအစား'),
                ),
                items: categories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text('${c['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        categoryId = v;
                        brandId = null;
                      }),
              ),
            if (categories.isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey('brand:$categoryId:$brandId'),
                initialValue: brandId ?? 0,
                decoration: InputDecoration(
                  labelText: t('Brand (optional)', 'Brand (မဖြစ်မနေမလို)'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(t('No brand', 'Brand မရွေး')),
                  ),
                  ...brands
                      .where((b) => b['category_id'] == categoryId)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text('${b['name']}'),
                        ),
                      ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() => brandId = v == 0 ? null : v),
              ),
            TextFormField(
              controller: color,
              enabled: !busy,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: t('Color (optional)', 'အရောင် (မဖြစ်မနေမလို)'),
              ),
            ),
            TextFormField(
              controller: size,
              enabled: !busy,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: t('Size (optional)', 'ဆိုဒ် (မဖြစ်မနေမလို)'),
              ),
            ),
            TextFormField(
              controller: price,
              enabled: !busy,
              inputFormatters: const [AmountInputFormatter()],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t('Selling price', 'အရောင်းဈေး'),
              ),
              validator: (v) {
                final n = AppCurrency.tryParse(v ?? '');
                return n == null || n < 0 || n > 2147483647
                    ? t('Invalid price', 'ဈေးမမှန်ပါ')
                    : null;
              },
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(t('Save', 'သိမ်းမည်')),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BarcodeLabelPage(product: widget.product),
                      ),
                    ),
              icon: const Icon(Icons.print_outlined),
              label: Text(
                t(
                  'Print label (saved details)',
                  'Label ထုတ်ရန် (သိမ်းပြီးအချက်အလက်)',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
