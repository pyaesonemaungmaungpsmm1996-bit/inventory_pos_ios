import 'desktop_ui.dart';
import 'app_capabilities.dart';
import 'amount_input.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_datetime.dart';

import 'app_currency.dart';
import 'barcode_rules.dart';
import 'barcode_scan_page.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'product_photo.dart';

part 'desktop_stock_products.dart';
part 'mobile_stock_products.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  List<Map<String, Object?>> products = [];
  bool loading = true;
  List<Map<String, Object?>> branches = [];
  int? selectedBranchId;
  void updateStock(VoidCallback change) => setState(change);
  int stockCategory = 0, stockBrand = 0;
  bool hideZeroStock = false, openingOnly = false, soldOnly = false;
  final minStock = TextEditingController(), maxStock = TextEditingController();
  List<Map<String, Object?>> stockCategories = [], stockBrands = [];
  Map<Object?, Map<String, Object?>> stockMetrics = {};
  @override
  void dispose() {
    minStock.dispose();
    maxStock.dispose();
    super.dispose();
  }

  int _loadRequest = 0;
  Uint8List? recoveredPhoto;
  int? recoveredProductId;

  String tr(String en, String my) =>
      AppLanguage.current.value == 'my' ? my : en;

  String get branchLabel {
    for (final b in branches) {
      if (b['id'] == selectedBranchId) return "${b['name']} (${b['code']})";
    }
    return '';
  }

  String searchText = '';
  String? error;

  @override
  void initState() {
    super.initState();
    loadProducts();
    _recoverPickedPhoto();
  }

  Future<void> _recoverPickedPhoto() async {
    if (AppCapabilities.windows) return;
    try {
      final picked = await ImagePicker().retrieveLostData();
      final prefs = SharedPreferencesAsync();
      final targetId = await prefs.getInt('product_photo_picker_target_v1');
      await prefs.remove('product_photo_picker_target_v1');
      if (targetId == null ||
          picked.isEmpty ||
          picked.files == null ||
          picked.files!.isEmpty) {
        return;
      }
      final file = picked.files!.first;
      if (await file.length() > 10000000) return;
      final normalized = await prepareProductPhoto(await file.readAsBytes());
      if (!mounted) return;
      setState(() {
        recoveredProductId = targetId;
        recoveredPhoto = normalized;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Photo recovered. Open the product form and Save to keep it.',
              'ပုံပြန်ရပါပြီ။ ပစ္စည်းဖောင်ဖွင့်ပြီး Save နှိပ်ပါ။',
            ),
          ),
        ),
      );
    } catch (_) {
      // A failed picker does not affect products, stock, or draft sales.
    }
  }

  Future<void> loadProducts() async {
    final request = ++_loadRequest;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final db = AppDatabase.instance;
      final branchRows = await db.getBranches();
      final defaultId = await db.getDefaultBranchId();
      final chosen = selectedBranchId ?? defaultId;
      final valid = branchRows.any((b) => b['id'] == chosen);
      final id = valid
          ? chosen
          : (branchRows.isEmpty ? null : branchRows.first['id'] as int);
      final rows = id == null
          ? <Map<String, Object?>>[]
          : await db.getProducts(branchId: id);
      final sql = await db.database;
      final metrics = await sql.rawQuery(
        "SELECT product_id, SUM(CASE WHEN kind='opening' THEN quantity ELSE 0 END) opening_qty, SUM(CASE WHEN kind='sale' AND sale_id IS NOT NULL AND EXISTS(SELECT 1 FROM sale_invoices v WHERE v.id=stock_movements.sale_id AND v.status='posted') THEN ABS(quantity) ELSE 0 END) sale_qty FROM stock_movements WHERE branch_id=? GROUP BY product_id",
        [id],
      );
      final cats = await sql.query('product_categories', orderBy: 'name');
      final brands = await sql.query('product_brands', orderBy: 'name');
      if (!mounted || request != _loadRequest) return;
      setState(() {
        branches = branchRows;
        selectedBranchId = id;
        products = rows;
        stockCategories = cats;
        stockBrands = brands;
        stockMetrics = {for (final m in metrics) m['product_id']: m};
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        loading = false;
        error = tr(
          'Could not load stock. Do not clear app data. Check that branch code PZD exists for the first upgrade.',
          'လက်ကျန်စာရင်း မဖတ်နိုင်ပါ။ App Data မဖျက်ပါနှင့်။ ပထမအဆင့်မြှင့်ချိန်တွင် PZD ဆိုင်ခွဲကုဒ် ရှိရန်လိုပါသည်။',
        );
      });
    }
  }

  Future<void> showAddProduct({Map<String, Object?>? product}) async {
    final branchId = selectedBranchId;
    if (branchId == null || loading) return;
    List<Map<String, Object?>> categoryChoices;
    var categoryId = product?['category_id'] as int? ?? 1;
    try {
      final categories = await AppDatabase.instance.getProductCategories(
        includeInactive: true,
      );
      categoryChoices = categories
          .where((c) => c['active'] == 1 || c['id'] == categoryId)
          .toList();
      if (!categoryChoices.any((c) => c['id'] == categoryId)) {
        categoryId = 1;
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Could not load categories. Retry.',
                'အမျိုးအစားများ မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final formKey = GlobalKey<FormState>();
    final editing = product != null;

    final nameController = TextEditingController(
      text: product?['name'] as String? ?? '',
    );
    final itemCodeController = TextEditingController(
      text: product?['item_code'] as String? ?? '',
    );
    final barcodeController = TextEditingController(
      text: product?['barcode'] as String? ?? '',
    );
    final priceController = TextEditingController(
      text: product == null || product['price'] == 0
          ? ''
          : AppCurrency.input(product['price'] as int),
    );
    final stockController = TextEditingController(
      text: product?['stock']?.toString() ?? '',
    );

    bool saving = false;
    String? saveError;
    Uint8List? newPhoto = recoveredProductId == (product?['id'] as int? ?? 0)
        ? recoveredPhoto
        : null;
    bool removePhoto = false;

    try {
      final added = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return PopScope(
                canPop: !saving,
                child: DesktopDialog(
                  title: Text(
                    editing
                        ? tr(
                            'Edit Product (all branches)',
                            'ပစ္စည်းပြင်ရန် (ဆိုင်ခွဲအားလုံး)',
                          )
                        : '${tr('Add Product', 'ပစ္စည်းအသစ်')} - $branchLabel',
                  ),
                  content: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              if (newPhoto != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    newPhoto!,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else if (editing && !removePhoto)
                                ProductPhoto(
                                  productId: product['id'] as int,
                                  hasImage: product['has_image'] == 1,
                                  size: 64,
                                )
                              else
                                const SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: Icon(Icons.inventory_2_outlined),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.add_a_photo_outlined,
                                      ),
                                      label: Text(
                                        tr('Choose photo', 'ပုံရွေးရန်'),
                                      ),
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final source =
                                                  await showDesktopSheet<
                                                    ImageSource
                                                  >(
                                                    context: dialogContext,
                                                    builder: (sheetContext) => SafeArea(
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (AppCapabilities
                                                              .camera)
                                                            DesktopListTile(
                                                              leading: const Icon(
                                                                Icons
                                                                    .camera_alt_outlined,
                                                              ),
                                                              title: Text(
                                                                tr(
                                                                  'Camera',
                                                                  'ကင်မရာ',
                                                                ),
                                                              ),
                                                              onTap: () =>
                                                                  Navigator.pop(
                                                                    sheetContext,
                                                                    ImageSource
                                                                        .camera,
                                                                  ),
                                                            ),
                                                          DesktopListTile(
                                                            leading: const Icon(
                                                              Icons
                                                                  .photo_library_outlined,
                                                            ),
                                                            title: Text(
                                                              tr(
                                                                'Gallery',
                                                                'ဓာတ်ပုံများ',
                                                              ),
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  sheetContext,
                                                                  ImageSource
                                                                      .gallery,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                              if (source == null ||
                                                  !dialogContext.mounted) {
                                                return;
                                              }
                                              try {
                                                final prefs =
                                                    SharedPreferencesAsync();
                                                await prefs.setInt(
                                                  'product_photo_picker_target_v1',
                                                  product?['id'] as int? ?? 0,
                                                );
                                                final picked =
                                                    await ImagePicker()
                                                        .pickImage(
                                                          source: source,
                                                          maxWidth: 1024,
                                                          maxHeight: 1024,
                                                          imageQuality: 75,
                                                          requestFullMetadata:
                                                              false,
                                                        );
                                                if (picked == null ||
                                                    !dialogContext.mounted) {
                                                  return;
                                                }
                                                if (await picked.length() >
                                                    10000000) {
                                                  throw const FormatException(
                                                    'Photo exceeds 10 MB',
                                                  );
                                                }
                                                final normalized =
                                                    await prepareProductPhoto(
                                                      await picked
                                                          .readAsBytes(),
                                                    );
                                                if (!dialogContext.mounted) {
                                                  return;
                                                }
                                                setDialogState(() {
                                                  newPhoto = normalized;
                                                  removePhoto = false;
                                                  saveError = null;
                                                });
                                              } catch (_) {
                                                if (dialogContext.mounted) {
                                                  setDialogState(() {
                                                    saveError = tr(
                                                      'Could not open photo. Try a JPG or PNG under 10 MB.',
                                                      'ပုံဖွင့်မရပါ။ 10 MB အောက် JPG/PNG ပုံဖြင့် ပြန်စမ်းပါ။',
                                                    );
                                                  });
                                                }
                                              } finally {
                                                try {
                                                  await SharedPreferencesAsync()
                                                      .remove(
                                                        'product_photo_picker_target_v1',
                                                      );
                                                } catch (_) {
                                                  // The next recovery check can clear this stale target.
                                                }
                                              }
                                            },
                                    ),
                                    if (newPhoto != null ||
                                        (editing &&
                                            product['has_image'] == 1 &&
                                            !removePhoto))
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete_outline),
                                        label: Text(
                                          tr('Remove photo', 'ပုံဖယ်ရန်'),
                                        ),
                                        onPressed: saving
                                            ? null
                                            : () => setDialogState(() {
                                                newPhoto = null;
                                                removePhoto = true;
                                              }),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Text(
                            tr(
                              'One photo per product; shared by all branches. Not printed on vouchers.',
                              'ပစ္စည်းတစ်မျိုးလျှင် ပုံတစ်ပုံ၊ ဆိုင်ခွဲအားလုံးတွင် တူညီသည်။ ဘောင်ချာတွင် မပုံနှိပ်ပါ။',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: nameController,
                            enabled: !saving,
                            decoration: const InputDecoration(
                              labelText: 'Product name',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter a product name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: categoryId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: tr('Category', 'ပစ္စည်းအမျိုးအစား'),
                            ),
                            items: categoryChoices
                                .map(
                                  (c) => DropdownMenuItem<int>(
                                    value: c['id'] as int,
                                    child: Text(
                                      '${c['name']}${c['active'] == 1 ? '' : ' (${tr('archived', 'ပိတ်ထားသည်')})'}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (id) {
                                    if (id != null) {
                                      setDialogState(() => categoryId = id);
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: itemCodeController,
                            enabled: !saving,
                            maxLength: 32,
                            decoration: InputDecoration(
                              labelText: tr(
                                'Item code (optional)',
                                'ပစ္စည်းကုဒ် (မဖြစ်မနေမလို)',
                              ),
                              helperText: tr(
                                'Blank = automatic ITEM number. If the barcode also changes, reprint old labels. Past invoices stay unchanged.',
                                'အလွတ်ထားလျှင် ITEM နံပါတ်အလိုအလျောက်။ Barcode ပါပြောင်းလျှင် Label အသစ်ထုတ်ပါ။ ဘောင်ချာဟောင်း မပြောင်းပါ။',
                              ),
                              helperMaxLines: 3,
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return null;
                              if (!BarcodeRules.validItemCode(value)) {
                                return tr(
                                  'Use 1–32 English letters, numbers, - or _, no spaces.',
                                  'အင်္ဂလိပ်စာ၊ ဂဏန်း၊ - သို့ _ စာလုံး ၁–၃၂ လုံး၊ Space မပါရ.',
                                );
                              }
                              if (RegExp(
                                    r'^ITEM-[0-9]{6,}$',
                                    caseSensitive: false,
                                  ).hasMatch(value) &&
                                  (product == null ||
                                      value.toUpperCase() !=
                                          BarcodeRules.itemCode(
                                            product['id'] as int,
                                          ))) {
                                return tr(
                                  'Automatic ITEM numbers are reserved. Use another code.',
                                  'အလိုအလျောက် ITEM နံပါတ်များကို အခြားပစ္စည်းအတွက် သုံးမရပါ။',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: barcodeController,
                            enabled: !saving,
                            maxLength: 32,
                            decoration: InputDecoration(
                              labelText: tr(
                                'Barcode (optional)',
                                'Barcode (မဖြစ်မနေမလို)',
                              ),
                              helperText: tr(
                                'Leave blank to use the item code. Barcode is shared across branches.',
                                'မဖြည့်လျှင် Item Code သုံးမည်။ ဆိုင်ခွဲအားလုံးအတွက် တူညီသည်။',
                              ),
                              helperMaxLines: 3,
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                tooltip: tr(
                                  'Scan existing barcode',
                                  'ရှိပြီးသား Barcode ဖတ်ရန်',
                                ),
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final value =
                                            await Navigator.push<String>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const BarcodeScanPage(),
                                              ),
                                            );
                                        if (dialogContext.mounted &&
                                            value != null) {
                                          barcodeController.text = value;
                                        }
                                      },
                              ),
                            ),
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return null;
                              if (!BarcodeRules.valid(value)) {
                                return tr(
                                  'Use 1–32 English letters, numbers or symbols, without spaces.',
                                  'အင်္ဂလိပ်အက္ခရာ၊ ဂဏန်း၊ သင်္ကေတ ၁–၃၂ လုံးသာ၊ Space မပါဘဲ ထည့်ပါ။',
                                );
                              }
                              if (value.toUpperCase().startsWith('ITEM-') &&
                                  value != itemCodeController.text.trim() &&
                                  (product == null ||
                                      value !=
                                          BarcodeRules.itemCode(
                                            product['id'] as int,
                                          ))) {
                                return tr(
                                  'ITEM- codes are reserved. Leave blank for automatic code.',
                                  'ITEM- ကုဒ်များကို စနစ်က သတ်မှတ်သည်။ အလိုအလျောက်သုံးရန် အလွတ်ထားပါ။',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: priceController,
                            enabled: !saving,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Selling price (${AppCurrency.displayCode})',
                              helperText: tr(
                                'Blank = 0 for now. Edit later when the price is known.',
                                'အလွတ်ထားလျှင် ယာယီ ၀။ ဈေးသိမှ ပြန်ပြင်နိုင်သည်။',
                              ),
                            ),
                            validator: (value) {
                              final number = AppCurrency.tryParse(
                                value?.trim() ?? '',
                              );
                              if ((value?.trim().isEmpty ?? true)) return null;
                              if (number == null ||
                                  number < 0 ||
                                  number > 2147483647) {
                                return 'Enter a valid price (maximum ${AppCurrency.format(2147483647)}).';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: stockController,
                            enabled: !saving && !editing,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Opening stock',
                            ),
                            validator: (value) {
                              final number = int.tryParse(value?.trim() ?? '');
                              if ((value?.trim().isEmpty ?? true)) return null;
                              if (number == null ||
                                  number < 0 ||
                                  number > 2147483647) {
                                return 'Enter 0 to 2147483647';
                              }
                              return null;
                            },
                          ),
                          if (saveError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              saveError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;

                              setDialogState(() {
                                saving = true;
                                saveError = null;
                              });

                              try {
                                if (editing) {
                                  await AppDatabase.instance.updateProduct(
                                    id: product['id'] as int,
                                    name: nameController.text,
                                    price: priceController.text.trim().isEmpty
                                        ? 0
                                        : AppCurrency.parse(
                                            priceController.text.trim(),
                                          ),
                                    barcode: barcodeController.text,
                                    itemCode: itemCodeController.text,
                                    categoryId: categoryId,
                                    imageBytes: newPhoto,
                                    removeImage: removePhoto,
                                  );
                                } else {
                                  await AppDatabase.instance.addProduct(
                                    branchId: branchId,
                                    name: nameController.text,
                                    price: priceController.text.trim().isEmpty
                                        ? 0
                                        : AppCurrency.parse(
                                            priceController.text.trim(),
                                          ),
                                    barcode: barcodeController.text,
                                    itemCode: itemCodeController.text,
                                    categoryId: categoryId,
                                    stock: stockController.text.trim().isEmpty
                                        ? 0
                                        : int.parse(
                                            stockController.text.trim(),
                                          ),
                                    imageBytes: newPhoto,
                                  );
                                }

                                if (!dialogContext.mounted) return;
                                Navigator.pop(dialogContext, true);
                              } catch (_) {
                                if (!dialogContext.mounted) return;

                                setDialogState(() {
                                  saving = false;
                                  saveError = tr(
                                    'Could not save. Check whether this item code or barcode already belongs to another product.',
                                    'မသိမ်းနိုင်ပါ။ ဤ Item Code သို့မဟုတ် Barcode ကို အခြားပစ္စည်းတွင် သုံးထားပြီးသား ရှိ/မရှိ စစ်ပါ။',
                                  );
                                });
                              }
                            },
                      child: Text(saving ? 'Saving...' : 'Save'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (added == true && mounted) {
        recoveredPhoto = null;
        recoveredProductId = null;
        await loadProducts();
      }
    } finally {
      // Wait for the closing dialog animation before disposing its fields.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      nameController.dispose();
      itemCodeController.dispose();
      barcodeController.dispose();
      priceController.dispose();
      stockController.dispose();
    }
  }

  Future<void> showStockIn(Map<String, Object?> product) async {
    final branchId = selectedBranchId;
    if (branchId == null || loading) return;
    final currentBranch = branchLabel;
    final formKey = GlobalKey<FormState>();
    int quantity = 0;
    String note = '';
    bool saving = false;
    String? saveError;

    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !saving,
              child: DesktopDialog(
                title: Text(
                  "${tr('Stock In', 'ပစ္စည်းအဝင်')}: ${product['name']}\n$currentBranch",
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          enabled: !saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity to add',
                          ),
                          validator: (value) {
                            final number = int.tryParse(value?.trim() ?? '');

                            if (number == null ||
                                number <= 0 ||
                                number > 2147483647) {
                              return 'Enter 1 to 2147483647';
                            }

                            return null;
                          },
                          onSaved: (value) {
                            quantity = int.parse(value!.trim());
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          enabled: !saving,
                          maxLength: 200,
                          decoration: const InputDecoration(
                            labelText: 'Note (optional)',
                          ),
                          onSaved: (value) {
                            note = value?.trim() ?? '';
                          },
                        ),
                        if (saveError != null)
                          Text(
                            saveError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            formKey.currentState!.save();

                            setDialogState(() {
                              saving = true;
                              saveError = null;
                            });

                            try {
                              await AppDatabase.instance.addStock(
                                branchId: branchId,
                                productId: product['id'] as int,
                                quantity: quantity,
                                note: note,
                              );

                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext, true);
                            } catch (_) {
                              if (!dialogContext.mounted) return;

                              setDialogState(() {
                                saving = false;
                                saveError =
                                    'Could not add stock. Please retry.';
                              });
                            }
                          },
                    child: Text(saving ? 'Saving...' : 'Add Stock'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (added == true && mounted) {
      await loadProducts();
    }
  }

  Future<void> showStockHistory(Map<String, Object?> product) async {
    final branchId = selectedBranchId;
    if (branchId == null || loading) return;
    final currentBranch = branchLabel;
    try {
      final rows = await AppDatabase.instance.getStockMovements(
        product['id'] as int,
        branchId: branchId,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return DesktopDialog(
            title: Text(
              "${tr('Stock History', 'လက်ကျန်မှတ်တမ်း')}: ${product['name']}\n$currentBranch",
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 350,
              child: rows.isEmpty
                  ? const Center(child: Text('No stock-in records yet.'))
                  : DesktopListView.separated(
                      desktopColumns: const [
                        "Date",
                        "Movement",
                        "Quantity",
                        "Note",
                      ],
                      desktopCells: (context, index) {
                        final r = rows[index];
                        return [
                          desktopDate(r['created_at']),
                          desktopCellText(r['kind']),
                          desktopCellText(r['quantity']),
                          desktopCellText(r['note']),
                        ];
                      },

                      itemCount: rows.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final dateText = AppDateTime.format(row['created_at']);

                        final note = row['note'] as String;
                        final transferMovement = note.toLowerCase().contains(
                          'transfer #',
                        );
                        final movementLabel = transferMovement
                            ? tr('(Transfer)', '(ဆိုင်ခွဲလွှဲ)')
                            : row['kind'] == 'opening'
                            ? tr('(Opening)', '(အဖွင့်လက်ကျန်)')
                            : row['kind'] == 'sale'
                            ? tr('(Sale)', '(အရောင်း)')
                            : '';

                        return DesktopListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            row['kind'] == 'sale'
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                          ),
                          title: Text(
                            "${row['kind'] == 'sale' ? '-' : '+'}${row['quantity']} $movementLabel",
                          ),
                          subtitle: Text(
                            note.isEmpty ? dateText : '$dateText\n$note',
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load stock history. Please retry.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppCapabilities.windows) return stockDesktop();
    return mobileStock();
  }
}
