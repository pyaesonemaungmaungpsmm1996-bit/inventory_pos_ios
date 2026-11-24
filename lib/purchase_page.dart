import 'product_tracking.dart';
import 'history_date_filter.dart';
import 'split_payment_dialog.dart';
import 'desktop_ui.dart';
import 'desktop_commands.dart';
import 'app_capabilities.dart';
import 'invoice_printer_page.dart';
import 'voucher_permissions.dart';

import 'package:image_picker/image_picker.dart';

import 'product_photo.dart';
import 'barcode_scan_page.dart';
import 'pos_ui.dart';
import 'product_details_form.dart';
import 'amount_input.dart';

import 'dart:async';
import 'shared_pos_page.dart';
import 'shared_pos_session.dart';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'categories_page.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'invoice_void_dialog.dart';
import 'barcode_rules.dart';
import 'contacts_page.dart';

part 'desktop_purchase.dart';
part 'desktop_purchase_history.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _money(int amount) => AppCurrency.format(amount);
String _no(int id) => 'PUR-${id.toString().padLeft(6, '0')}';

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage>
    with WidgetsBindingObserver {
  final db = AppDatabase.instance;
  final payments = <int, TextEditingController>{};
  final purchaseSearch = TextEditingController();
  final purchaseSearchFocus = FocusNode();
  final purchaseCellNodes = <String, FocusNode>{};
  bool choosingPurchaseItem = false, lineDialogOpen = false;
  String? purchaseLookupError;
  final supplierFocus = FocusNode(),
      paidFocus = FocusNode(),
      rowsFocus = FocusNode();
  int selectedLine = 0;
  final keyboardScroll = ScrollController();
  final lines = <Map<String, Object?>>[];
  String requestKey = _newRequestKey();
  static String _newRequestKey() =>
      'purchase-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Timer? _saveTimer;
  Future<void> _lastWrite = Future<void>.value();
  bool restored = false,
      posted = false,
      ready = false,
      dirty = false,
      saveFailed = false;
  List<Map<String, Object?>> branches = [],
      suppliers = [],
      products = [],
      categories = [],
      accounts = [];
  int? branchId, supplierId;
  DateTime purchaseDate = AppDateTime.today();
  bool loading = true, posting = false;
  String? error;
  int ticket = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initialize();
  }

  @override
  void dispose() {
    for (final node in purchaseCellNodes.values) {
      node.dispose();
    }
    purchaseSearch.dispose();
    purchaseSearchFocus.dispose();
    keyboardScroll.dispose();
    supplierFocus.dispose();
    paidFocus.dispose();
    rowsFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    if (ready && dirty && !posted && !posting) {
      unawaited(_saveNow());
    }
    for (final c in payments.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveTimer?.cancel();
      if (ready && dirty && !posted && !posting) {
        unawaited(_saveNow());
      }
    }
  }

  late final SharedPosSession? _sharedPurchase = SharedPosSession.current;
  final _cloudProductIds = <String, int>{};
  final _cloudAccountIds = <String, int>{};

  Future<void> initialize() async {
    if (_sharedPurchase != null) {
      await load();
      if (mounted) ready = error == null;
      return;
    }
    Map<String, Object?>? saved;
    try {
      final json = await db.getPurchaseWork();
      if (json != null) {
        saved = Map<String, Object?>.from(jsonDecode(json) as Map);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t(
            'Could not read unfinished purchase. Retry before editing.',
            'ရေးလက်စ အဝယ်ကို ဖတ်မရပါ။ မပြင်ခင် ပြန်စမ်းပါ။',
          );
        });
      }
      return;
    }
    if (!mounted) return;
    branchId = saved?['branch_id'] as int? ?? widget.initialBranchId;
    await load();
    if (!mounted || error != null) return;
    final snapshot = saved;
    if (snapshot != null) {
      final savedDate = DateTime.tryParse(
        snapshot['purchase_date'] as String? ?? '',
      );
      final savedLines = snapshot['lines'] as List?;
      final savedPayments = snapshot['payments'] as Map?;
      setState(() {
        if (savedDate != null) purchaseDate = savedDate;
        final selected = snapshot['supplier_id'] as int?;
        supplierId = suppliers.any((row) => row['id'] == selected)
            ? selected
            : null;
        lines.clear();
        if (savedLines != null) {
          for (final raw in savedLines) {
            if (raw is Map) {
              lines.add({
                ...Map<String, Object?>.from(raw),
                'purchase_price': raw['purchase_price'] ?? 0,
              });
            }
          }
        }
        if (savedPayments != null) {
          for (final account in accounts) {
            final key = (account['id'] as int).toString();
            payments[account['id']]?.text = savedPayments[key] as String? ?? '';
          }
        }
        requestKey = snapshot['request_key'] as String? ?? requestKey;
        restored = true;
        dirty = true;
      });
    }
    ready = true;
  }

  Map<String, Object?> _snapshot() => {
    'request_key': requestKey,
    'branch_id': branchId,
    'supplier_id': supplierId,
    'purchase_date': _date(purchaseDate),
    'lines': lines,
    'payments': {
      for (final e in payments.entries) e.key.toString(): e.value.text,
    },
  };

  Future<void> _saveNow() async {
    if (_sharedPurchase != null || !ready || !dirty || posted || posting) return;
    final payload = jsonEncode(_snapshot());
    _lastWrite = _lastWrite
        .catchError((Object _) {})
        .then((_) => db.putPurchaseWork(payload));
    try {
      await _lastWrite;
      if (mounted && saveFailed) setState(() => saveFailed = false);
    } catch (_) {
      if (mounted) setState(() => saveFailed = true);
    }
  }

  void _touch() {
    if (!ready || posted || posting) return;
    dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveNow());
    });
  }

  Future<void> discardWork() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DesktopDialog(
        title: Text(
          _t('Discard unfinished purchase?', 'ရေးလက်စအဝယ်ကို ဖျက်မလား?'),
        ),
        content: Text(
          _t(
            'Unsaved purchase details on this device will be removed.',
            'ဤစက်ရှိ ရေးလက်စအချက်အလက်များကို ဖျက်မည်။',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('Keep editing', 'ဆက်ရေးမည်')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('Discard', 'ဖျက်မည်')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _saveTimer?.cancel();
    try {
      await _lastWrite;
      if (_sharedPurchase == null) await db.deletePurchaseWork();
      if (!mounted) return;
      setState(() {
        lines.clear();
        supplierId = null;
        purchaseDate = AppDateTime.today();
        for (final c in payments.values) {
          c.clear();
        }
        requestKey = _newRequestKey();
        restored = false;
        dirty = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not discard the saved purchase.',
                'သိမ်းထားသော အဝယ်ကို မဖျက်နိုင်ပါ။',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> load({bool resetBranch = false}) async {
    final current = ++ticket;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      if (_sharedPurchase case final session?) {
        final data = await session.load();
        final code = session.connection.branchCode;
        final cloudCategories = await db.getProductCategories();
        final cloudSuppliers = await db.getContacts(kind: 'supplier', activeOnly: true);
        if (!mounted || current != ticket) return;
        final serials = data['serials'] as Map;
        setState(() {
          branchId = 0;
          branches = [{'id': 0, 'name': code, 'code': code}];
          categories = cloudCategories;
          suppliers = cloudSuppliers;
          products = [
            for (final row in (data['stock'] as List).cast<Map>())
              {
                'id': _cloudProductIds.putIfAbsent(row['id'] as String, () => _cloudProductIds.length + 1),
                'cloud_id': row['id'],
                'name': row['name'],
                'item_code': row['code'],
                'barcode': row['code'],
                'price': row['price'],
                'stock': row['on_hand'],
                'tracking': serials.containsKey(row['id']) ? 'serial' : 'none',
                'category_id': cloudCategories.firstOrNull?['id'],
              },
          ];
          accounts = [
            for (final row in (data['accounts'] as List).cast<Map>())
              {
                'id': _cloudAccountIds.putIfAbsent(row['id'] as String, () => _cloudAccountIds.length + 1),
                'cloud_id': row['id'],
                'name': row['name'],
                'type': row['kind'],
                'balance': row['balance'],
              },
          ];
          for (final account in accounts) {
            payments.putIfAbsent(account['id'] as int, TextEditingController.new);
          }
          loading = false;
        });
        return;
      }
      final rows = await db.getBranches();
      final preferred = resetBranch ? null : branchId;
      final fallback = await db.getDefaultBranchId();
      final chosen = rows.any((b) => b['id'] == preferred)
          ? preferred
          : rows.any((b) => b['id'] == fallback)
          ? fallback
          : (rows.isEmpty ? null : rows.first['id'] as int);
      final newSuppliers = await db.getContacts(
        kind: 'supplier',
        activeOnly: true,
      );
      final newProducts = chosen == null
          ? <Map<String, Object?>>[]
          : await db.getProducts(branchId: chosen);
      final newCategories = await db.getProductCategories();
      final newAccounts = chosen == null
          ? <Map<String, Object?>>[]
          : await db.getMoneyAccounts(branchId: chosen);
      if (!mounted || current != ticket) return;
      setState(() {
        branches = rows;
        branchId = chosen;
        suppliers = newSuppliers;
        products = newProducts;
        categories = newCategories;
        accounts = newAccounts;
        loading = false;
        if (!suppliers.any((s) => s['id'] == supplierId)) supplierId = null;
        for (final account in accounts) {
          payments.putIfAbsent(
            account['id'] as int,
            () => TextEditingController(),
          );
        }
      });
    } catch (_) {
      if (mounted && current == ticket) {
        setState(() {
          loading = false;
          error = _t(
            'Could not load purchase choices.',
            'အဝယ်စာရင်းအတွက် ရွေးချယ်စရာများ မဖတ်နိုင်ပါ။',
          );
        });
      }
    }
  }

  Future<void> selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: purchaseDate,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (picked != null && mounted) {
      setState(() => purchaseDate = picked);
      _touch();
    }
  }

  Future<void> openPurchaseManager(String title, Widget page) async {
    if (!AppCapabilities.windows) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(title: Text(title)),
            body: page,
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) {
        final screen = MediaQuery.sizeOf(dialog);
        return Dialog(
          key: const ValueKey('purchase-manager-window'),
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: min(screen.width - 48, 1180),
            height: screen.height * .86,
            child: Column(
              children: [
                Container(
                  color: const Color(0xff192f50),
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _t('Close window', 'Window ပိတ်ရန်'),
                        onPressed: () => Navigator.pop(dialog),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) =>
                        MaterialPageRoute<void>(builder: (_) => page),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> manageSuppliers() async {
    await openPurchaseManager(
      _t('Suppliers', 'ပစ္စည်းပေးသွင်းသူများ'),
      const ContactsPage(kind: 'supplier'),
    );
    if (mounted) {
      await load();
      _touch();
    }
  }

  Future<void> manageCategories() async {
    if (posting || loading) return;
    _saveTimer?.cancel();
    await _saveNow();
    if (!mounted || saveFailed) return;
    await openPurchaseManager(
      _t('Categories', 'အမျိုးအစားများ'),
      const CategoriesPage(initialKind: 'product'),
    );
    if (mounted) await load();
  }

  Future<void> addLine([
    int? index,
    bool focusBarcode = false,
    bool focusQuantity = false,
    Map<String, Object?>? initialProduct,
  ]) async {
    if (loading || posting || categories.isEmpty) return;
    if (AppCapabilities.windows && lineDialogOpen) return;
    final selectedProduct = initialProduct;
    final old = index == null
        ? (selectedProduct == null
              ? null
              : <String, Object?>{
                  'product_id': selectedProduct['id'],
                  'name': selectedProduct['name'],
                  'item_code': selectedProduct['item_code'],
                  'barcode': selectedProduct['barcode'],
                  'category_id':
                      categories.any(
                        (c) => c['id'] == selectedProduct['category_id'],
                      )
                      ? selectedProduct['category_id']
                      : categories.first['id'],
                  'sale_price': selectedProduct['price'],
                  'tracking': selectedProduct['tracking'],
                  'qty': 1,
                })
        : lines[index];
    final catalogIdentity = products
        .where((r) => r['id'] == old?['product_id'])
        .firstOrNull;
    if (old != null && catalogIdentity != null) {
      old['item_code'] = catalogIdentity['item_code'];
      old['barcode'] = catalogIdentity['barcode'];
    }
    int productId = old?['product_id'] as int? ?? 0;
    int categoryId =
        old?['category_id'] as int? ?? categories.first['id'] as int;
    final name = TextEditingController(text: old?['name'] as String? ?? '');
    final itemCode = TextEditingController(
      text: old?['item_code'] as String? ?? '',
    );
    final barcode = TextEditingController(
      text: old?['barcode'] as String? ?? '',
    );
    String? photo = old?['photo_base64'] as String?;
    final purchasePrice = TextEditingController(
      text: old == null
          ? ''
          : (old['purchase_price'] == null
                ? ''
                : AmountInputFormatter.group(
                    AppCurrency.input(old['purchase_price'] as int),
                  )),
    );
    final salePrice = TextEditingController(
      text: old == null
          ? ''
          : (old['sale_price'] == null
                ? ''
                : AmountInputFormatter.group(
                    AppCurrency.input(old['sale_price'] as int),
                  )),
    );
    final qty = TextEditingController(text: old?['qty']?.toString() ?? '1');
    final form = GlobalKey<FormState>();
    try {
      if (AppCapabilities.windows) {
        lineDialogOpen = true;
        final catalog = products.where((p) => p['id'] == productId).firstOrNull;
        Map<String, Object?> entry() => {
          'product_id': productId == 0 ? null : productId,
          'name': name.text.trim(),
          'item_code': itemCode.text.trim(),
          'barcode': barcode.text.trim(),
          'photo_base64': ?photo,
          'category_id': categoryId,
          'purchase_price': purchasePrice.text.trim().isEmpty
              ? 0
              : AppCurrency.parse(purchasePrice.text.trim()),
          'sale_price': salePrice.text.trim().isEmpty
              ? null
              : AppCurrency.parse(salePrice.text.trim()),
          'qty': int.parse(qty.text.trim()),
        };
        qty.selection = TextSelection(
          baseOffset: 0,
          extentOffset: qty.text.length,
        );
        final unified = await purchaseProductDetails(
          context,
          {
            'product_id': productId == 0 ? null : productId,
            'category_id': categoryId,
            'qty': int.tryParse(qty.text) ?? 1,
          },
          previous: old,
          product: catalog,
          title: index == null
              ? _t('Add Purchase Item', 'အဝယ်ပစ္စည်းထည့်ရန်')
              : _t('Edit Purchase Item', 'အဝယ်ပစ္စည်းပြင်ရန်'),
          actionLabel: index == null
              ? _t('Add to invoice', 'ဘောင်ချာထဲထည့်ရန်')
              : _t('Update item', 'ပစ္စည်းပြင်ရန်'),
          readEntry: entry,
          validateEntry: () => form.currentState?.validate() ?? false,
          entryBuilder: (dialog, update, changeCategory) => Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (productId != 0)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(dialog).colorScheme.primaryContainer
                          .withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.text,
                          style: Theme.of(dialog).textTheme.titleMedium,
                        ),
                        Text(
                          _t('Item code: ', 'ပစ္စည်းကုဒ်: ') + itemCode.text,
                        ),
                        Text('Barcode: ${barcode.text}'),
                        Text(
                          _t(
                                'Current branch stock: ',
                                'လက်ရှိဆိုင်ခွဲ လက်ကျန်: ',
                              ) +
                              (catalog?['stock'] ?? 0).toString(),
                        ),
                      ],
                    ),
                  ),
                if (productId == 0)
                  TextFormField(
                    key: const ValueKey('purchase-popup-name'),
                    controller: name,
                    autofocus: true,
                    maxLength: 150,
                    decoration: InputDecoration(
                      labelText: _t('Item name', 'ပစ္စည်းအမည်'),
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? _t('Enter item name', 'ပစ္စည်းအမည် ဖြည့်ပါ')
                        : null,
                  ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (_, box) {
                    final w = box.maxWidth >= 650
                        ? (box.maxWidth - 24) / 3
                        : box.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: w,
                          child: TextFormField(
                            key: const ValueKey('purchase-popup-qty'),
                            controller: qty,
                            autofocus: productId != 0,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: _t('Quantity', 'အရေအတွက်'),
                            ),
                            validator: (v) {
                              final n = int.tryParse(v?.trim() ?? '');
                              return n != null && n > 0 && n <= 2147483647
                                  ? null
                                  : _t(
                                      'Enter valid quantity',
                                      'အရေအတွက် မှန်ကန်စွာထည့်ပါ',
                                    );
                            },
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: TextFormField(
                            key: const ValueKey('purchase-popup-buy'),
                            controller: purchasePrice,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: _t(
                                'Purchase price · optional',
                                'အဝယ်ဈေး · မဖြည့်လည်းရ',
                              ),
                              hintText: '0',
                              helperText: _t(
                                'Leave blank = 0 Ks',
                                'မဖြည့်လျှင် 0 Ks',
                              ),
                            ),
                            validator: (v) => _validPrice(v)
                                ? null
                                : _t('Invalid price', 'ဈေးနှုန်းမမှန်ပါ'),
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: TextFormField(
                            key: const ValueKey('purchase-popup-sale'),
                            controller: salePrice,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: _t(
                                'Selling price · optional',
                                'အရောင်းဈေး · နောက်မှဖြည့်နိုင်',
                              ),
                            ),
                            validator: (v) => _validPrice(v)
                                ? null
                                : _t('Invalid price', 'ဈေးနှုန်းမမှန်ပါ'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  key: ValueKey('popup-category-$categoryId'),
                  initialValue: categories.any((c) => c['id'] == categoryId)
                      ? categoryId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('Category', 'အမျိုးအစား'),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c['id'] as int,
                        child: Text(c['name'].toString()),
                      ),
                  ],
                  validator: (v) => v == null
                      ? _t('Choose category', 'အမျိုးအစား ရွေးပါ')
                      : null,
                  onChanged: (id) async {
                    if (id != null &&
                        await changeCategory(id) &&
                        dialog.mounted) {
                      update(() => categoryId = id);
                    }
                  },
                ),
                if (productId == 0) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: itemCode,
                    maxLength: 32,
                    decoration: InputDecoration(
                      labelText: _t(
                        'Item code · blank = automatic',
                        'ပစ္စည်းကုဒ် · အလွတ်ထားလျှင် အလိုအလျောက်',
                      ),
                    ),
                    validator: (v) {
                      final code = v?.trim() ?? '';
                      return code.isEmpty ||
                              (BarcodeRules.validItemCode(code) &&
                                  !RegExp(
                                    r'^ITEM-[0-9]{6,}$',
                                    caseSensitive: false,
                                  ).hasMatch(code))
                          ? null
                          : _t('Invalid or reserved code', 'ကုဒ်မမှန်ပါ');
                    },
                  ),
                  TextFormField(
                    controller: barcode,
                    maxLength: 32,
                    decoration: InputDecoration(
                      labelText: _t(
                        'Barcode · optional',
                        'Barcode · နောက်မှဖြည့်နိုင်',
                      ),
                    ),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ||
                            BarcodeRules.valid(v!.trim())
                        ? null
                        : _t('Invalid barcode', 'Barcode မမှန်ပါ'),
                  ),
                ],
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 960,
                        maxHeight: 960,
                        imageQuality: 80,
                      );
                      if (file == null) return;
                      final image = await prepareProductPhoto(
                        await file.readAsBytes(),
                      );
                      if (dialog.mounted) {
                        update(() => photo = base64Encode(image));
                      }
                    } catch (_) {
                      if (dialog.mounted) {
                        ScaffoldMessenger.of(dialog).showSnackBar(
                          SnackBar(
                            content: Text(
                              _t('Could not load photo', 'ပုံဖတ်မရပါ'),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 17),
                  label: Text(_t('Photo · optional', 'ပုံ · နောက်မှထည့်နိုင်')),
                ),
                if (photo != null)
                  Row(
                    children: [
                      Image.memory(
                        base64Decode(photo!),
                        width: 60,
                        height: 60,
                        fit: BoxFit.contain,
                      ),
                      TextButton(
                        onPressed: () => update(() => photo = null),
                        child: Text(_t('Remove photo', 'ပုံဖယ်ရန်')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
        if (unified != null && mounted) acceptPurchaseLine(unified, old, index);
        return;
      }
      final result = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, update) => DesktopDialog(
            title: Text(
              index == null
                  ? _t('Add Purchase Item', 'အဝယ်ပစ္စည်းထည့်ရန်')
                  : _t('Edit Purchase Item', 'အဝယ်ပစ္စည်းပြင်ရန်'),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButton<int>(
                      value: productId,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(
                            _t(
                              'New product (automatic item code)',
                              'ပစ္စည်းအသစ် (ကုဒ်အလိုအလျောက်)',
                            ),
                          ),
                        ),
                        ...products.map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as int,
                            child: Text(
                              '${p['name']} · ${p['item_code']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        update(() {
                          productId = id;
                          final selected = products
                              .where((p) => p['id'] == id)
                              .toList();
                          if (selected.isNotEmpty) {
                            name.text = selected.single['name'] as String;
                            itemCode.text =
                                selected.single['item_code'] as String;
                            barcode.text =
                                '${selected.single['barcode'] ?? ''}';
                            photo = null;
                            salePrice.text = AppCurrency.input(
                              selected.single['price'] as int,
                            );
                          } else {
                            name.clear();
                            itemCode.clear();
                            barcode.clear();
                            photo = null;
                            salePrice.clear();
                          }
                        });
                      },
                    ),
                    TextFormField(
                      controller: name,
                      enabled: productId == 0,
                      maxLength: 150,
                      decoration: InputDecoration(
                        labelText: _t('Item name', 'ပစ္စည်းအမည်'),
                      ),
                      validator: (v) =>
                          productId == 0 && (v?.trim().isEmpty ?? true)
                          ? _t('Enter item name', 'ပစ္စည်းအမည်ဖြည့်ပါ')
                          : null,
                    ),
                    TextFormField(
                      controller: itemCode,
                      enabled: productId == 0,
                      maxLength: 32,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Item code (optional)',
                          'ပစ္စည်းကုဒ် (မဖြစ်မနေမလို)',
                        ),
                        helperText: _t(
                          'Blank = automatic ITEM number. The barcode label uses this code by default.',
                          'အလွတ်ထားလျှင် ITEM နံပါတ်အလိုအလျောက်။ Barcode Label တွင် ဤကုဒ်ကို သုံးမည်။',
                        ),
                      ),
                      validator: (value) {
                        final code = value?.trim() ?? '';
                        if (productId != 0 || code.isEmpty) return null;
                        if (!BarcodeRules.validItemCode(code) ||
                            RegExp(
                              r'^ITEM-[0-9]{6,}$',
                              caseSensitive: false,
                            ).hasMatch(code)) {
                          return _t(
                            'Use 1–32 letters/digits/-/_; automatic ITEM numbers are reserved.',
                            'အင်္ဂလိပ်စာ/ဂဏန်း/-/_ ၁–၃၂ လုံးသုံးပါ။ ITEM နံပါတ်အလိုအလျောက်ကို မသုံးရ။',
                          );
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      autofocus: AppCapabilities.windows && focusBarcode,
                      controller: barcode,
                      enabled: productId == 0,
                      maxLength: 32,
                      decoration: InputDecoration(
                        labelText: _t(
                          'Barcode (optional)',
                          'Barcode (မဖြစ်မနေမလို)',
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: productId != 0
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
                          v == null ||
                              v.trim().isEmpty ||
                              BarcodeRules.valid(v.trim())
                          ? null
                          : _t('Invalid barcode', 'Barcode မမှန်ပါ'),
                    ),
                    if (photo != null)
                      Image.memory(
                        base64Decode(photo!),
                        height: 90,
                        fit: BoxFit.contain,
                      ),
                    Wrap(
                      children: [
                        for (final source in [
                          ImageSource.gallery,
                          if (AppCapabilities.camera) ImageSource.camera,
                        ])
                          TextButton.icon(
                            onPressed: () async {
                              try {
                                final file = await ImagePicker().pickImage(
                                  source: source,
                                  maxWidth: 960,
                                  maxHeight: 960,
                                  imageQuality: 80,
                                );
                                if (file == null) return;
                                final bytes = await prepareProductPhoto(
                                  await file.readAsBytes(),
                                );
                                if (context.mounted) {
                                  update(() => photo = base64Encode(bytes));
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _t(
                                          'Could not load photo',
                                          'ပုံမဖတ်နိုင်ပါ',
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: Icon(
                              source == ImageSource.gallery
                                  ? Icons.photo_library_outlined
                                  : Icons.camera_alt_outlined,
                            ),
                            label: Text(
                              source == ImageSource.gallery
                                  ? _t('Photo (optional)', 'ပုံ (မဖြစ်မနေမလို)')
                                  : _t('Camera', 'ကင်မရာ'),
                            ),
                          ),
                        if (photo != null)
                          TextButton(
                            onPressed: () => update(() => photo = null),
                            child: Text(_t('Remove photo', 'ပုံဖယ်ရန်')),
                          ),
                      ],
                    ),
                    DropdownButton<int>(
                      value: categoryId,
                      isExpanded: true,
                      items: categories
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['id'] as int,
                              child: Text(c['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (id) {
                        if (id != null) update(() => categoryId = id);
                      },
                    ),
                    TextFormField(
                      autofocus:
                          AppCapabilities.windows &&
                          initialProduct != null &&
                          !focusQuantity,
                      controller: purchasePrice,
                      inputFormatters: const [AmountInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${_t('Purchase price', 'အဝယ်ဈေး')} (${AppCurrency.displayCode})',
                        helperText: _t(
                          'Optional. Leave blank to receive stock at zero cost.',
                          'မဖြည့်လျှင် အဝယ်တန်ဖိုး သုညဖြင့် Stock ထည့်မည်။',
                        ),
                      ),
                      validator: (v) => _validPrice(v)
                          ? null
                          : _t(
                              'Enter a valid purchase price',
                              'အဝယ်ဈေးမှန်ကန်စွာထည့်ပါ',
                            ),
                    ),
                    TextFormField(
                      controller: salePrice,
                      inputFormatters: const [AmountInputFormatter()],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${_t('Selling price', 'အရောင်းဈေး')} (${AppCurrency.displayCode})',
                        helperText: _t(
                          'Leave blank to set later in Stock & Products.',
                          'Stock & Products တွင် နောက်မှ သတ်မှတ်နိုင်သည်။',
                        ),
                      ),
                      validator: (v) => _validPrice(v)
                          ? null
                          : _t(
                              'Enter a valid selling price',
                              'အရောင်းဈေးမှန်ကန်စွာထည့်ပါ',
                            ),
                    ),
                    TextFormField(
                      autofocus: AppCapabilities.windows && focusQuantity,
                      controller: qty,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _t('Quantity', 'အရေအတွက်'),
                      ),
                      validator: (v) {
                        final count = int.tryParse(v?.trim() ?? '');
                        return count != null && count > 0 && count <= 2147483647
                            ? null
                            : _t(
                                'Enter valid quantity',
                                'အရေအတွက်မှန်ကန်စွာထည့်ပါ',
                              );
                      },
                    ),
                    if (productId != 0)
                      Text(
                        _t(
                          'Selling price and category will update the product in all branches after posting.',
                          'Confirm ပြီးလျှင် အရောင်းဈေးနှင့် အမျိုးအစားသည် ဆိုင်ခွဲအားလုံးအတွက် ပြောင်းမည်။',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
              ),
              FilledButton(
                onPressed: () {
                  if (!form.currentState!.validate()) return;
                  Navigator.pop(ctx, <String, Object?>{
                    'product_id': productId == 0 ? null : productId,
                    'name': name.text.trim(),
                    'item_code': itemCode.text.trim(),
                    'barcode': barcode.text.trim(),
                    'photo_base64': ?photo,
                    'category_id': categoryId,
                    'purchase_price': purchasePrice.text.trim().isEmpty
                        ? 0
                        : AppCurrency.parse(purchasePrice.text.trim()),
                    'sale_price': salePrice.text.trim().isEmpty
                        ? null
                        : AppCurrency.parse(salePrice.text.trim()),
                    'qty': int.parse(qty.text.trim()),
                  });
                },
                child: Text(_t('Add', 'ထည့်မည်')),
              ),
            ],
          ),
        ),
      );
      if (result == null || !mounted) return;
      final selectedProducts = products
          .where((p) => p['id'] == result['product_id'])
          .toList();
      final details = await purchaseProductDetails(
        context,
        result,
        previous: old,
        product: selectedProducts.isEmpty ? null : selectedProducts.single,
      );
      if (details == null || !mounted) return;
      result.addAll(details);
      acceptPurchaseLine(result, old, index);
    } finally {
      lineDialogOpen = false;
      if (!AppCapabilities.windows) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      name.dispose();
      itemCode.dispose();
      barcode.dispose();
      purchasePrice.dispose();
      salePrice.dispose();
      qty.dispose();
    }
  }

  void acceptPurchaseLine(
    Map<String, Object?> result,
    Map<String, Object?>? old,
    int? index,
  ) {
    result['purchase_price'] ??= 0;
    final selectedProducts = products
        .where((p) => p['id'] == result['product_id'])
        .toList();
    if (result['create_separate_sku'] == true) {
      result['product_id'] = null;
      result['item_code'] = '';
      result['barcode'] = '';
      final source = selectedProducts.single;
      final oldVariant = [
        source['color'] ?? '',
        source['size'] ?? '',
      ].where((s) => '$s'.isNotEmpty).join(' / ');
      var baseName = '${result['name']}';
      if (oldVariant.isNotEmpty && baseName.endsWith(' · $oldVariant')) {
        baseName = baseName.substring(
          0,
          baseName.length - oldVariant.length - 3,
        );
      }
      final mode = result['tracking'];
      result['name'] = mode == 'none'
          ? baseName
          : '$baseName · ${mode == 'both' ? 'Serial + IMEI' : mode.toString().toUpperCase()}';
    }
    if (result['product_id'] == null) {
      final suffix = [
        result['color'],
        result['size'],
      ].where((s) => '$s'.isNotEmpty).join(' / ');
      final previousSuffix = [
        old?['color'] ?? '',
        old?['size'] ?? '',
      ].where((s) => '$s'.isNotEmpty).join(' / ');
      var cleanName = '${result['name']}';
      if (previousSuffix.isNotEmpty &&
          cleanName.endsWith(' · $previousSuffix')) {
        cleanName = cleanName.substring(
          0,
          cleanName.length - previousSuffix.length - 3,
        );
      }
      result['name'] = suffix.isEmpty ? cleanName : '$cleanName · $suffix';
    }
    final newCode = result['item_code'] as String? ?? '';
    if (result['product_id'] == null &&
        newCode.isNotEmpty &&
        products.any(
          (p) =>
              (p['item_code'] as String).toLowerCase() == newCode.toLowerCase(),
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Item code already belongs to another product.',
              'Item Code ကို အခြားပစ္စည်းတွင် သုံးထားပြီးသား ဖြစ်သည်။',
            ),
          ),
        ),
      );
      return;
    }
    if (result['product_id'] != null &&
        lines.asMap().entries.any(
          (e) =>
              e.key != index && e.value['product_id'] == result['product_id'],
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'This item is already on the purchase. Edit its quantity instead.',
              'ဤပစ္စည်းရှိပြီးသားဖြစ်သည်။ အရေအတွက်ကို ပြင်ပါ။',
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      if (index == null) {
        lines.add(result);
      } else {
        lines[index] = result;
      }
    });
    _touch();
  }

  bool _validPrice(String? raw) {
    if (raw == null || raw.trim().isEmpty) return true;
    final value = AppCurrency.tryParse(raw.trim());
    return value != null && value >= 0 && value <= 2147483647;
  }

  int get total => lines.fold<int>(
    0,
    (sum, l) => sum + (l['purchase_price'] as int? ?? 0) * (l['qty'] as int),
  );
  int get paid => accounts.fold<int>(
    0,
    (sum, a) =>
        sum + (AppCurrency.tryParse(payments[a['id']]?.text.trim() ?? '') ?? 0),
  );

  Future<void> focusPaid() => desktopFocusInScroll(paidFocus, keyboardScroll);

  Future<void> saveWork() async {
    if (_sharedPurchase != null) return;
    await _saveNow();
    if (saveFailed) throw StateError('Draft save failed');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Purchase draft saved locally',
              'အဝယ် Draft ကို စက်တွင်သိမ်းပြီးပါပြီ။',
            ),
          ),
        ),
      );
    }
  }

  Future<void> leaveByKeyboard() async {
    await _saveNow();
    if (saveFailed || !mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> keyboardPost() async {
    if (!validPurchaseNumbers()) return;
    await post();
  }

  void selectLine(int delta) {
    if (lines.isNotEmpty) {
      setState(
        () => selectedLine = (selectedLine + delta).clamp(0, lines.length - 1),
      );
    }
  }

  Future<void> removeSelected() async {
    if (lines.isEmpty) return;
    selectedLine = selectedLine.clamp(0, lines.length - 1);
    if (!await desktopAsk(
          context,
          _t('Remove draft item?', 'Draft ပစ္စည်းဖယ်မလား။'),
          '${lines[selectedLine]['name']}',
        ) ||
        !mounted) {
      return;
    }
    setState(() => lines.removeAt(selectedLine));
    _touch();
  }

  bool validPurchaseNumbers() {
    if (lines.any((line) {
      final qty = line['qty'];
      final buy = line['purchase_price'];
      final sale = line['sale_price'];
      return qty is! int ||
          qty < 1 ||
          qty > 2147483647 ||
          buy is! int ||
          buy < 0 ||
          buy > 2147483647 ||
          (sale != null && (sale is! int || sale < 0 || sale > 2147483647));
    })) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Enter a valid quantity and purchase price for every item. Selling price may be blank.',
              'ပစ္စည်းတိုင်းအတွက် အရေအတွက်နှင့် အဝယ်ဈေး မှန်ကန်စွာ ဖြည့်ပါ။ အရောင်းဈေး အလွတ်ထားနိုင်သည်။',
            ),
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> post() async {
    if (posting || loading) return;
    if (!validPurchaseNumbers()) return;
    if (branchId == null || supplierId == null || lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Choose branch, supplier and at least one item.',
              'ဆိုင်ခွဲ၊ Supplier နှင့် ပစ္စည်းတစ်ခုအနည်းဆုံး ရွေးပါ။',
            ),
          ),
        ),
      );
      return;
    }
    final allocation = await showSplitPaymentDialog(
      context,
      total: total,
      accounts: accounts,
      purchase: true,
      initial: [
        for (final a in accounts)
          if ((AppCurrency.tryParse(payments[a['id']]!.text) ?? 0) > 0)
            {
              'account_id': a['id'] as int,
              'amount': AppCurrency.tryParse(payments[a['id']]!.text)!,
            },
      ],
    );
    if (allocation == null || !mounted) return;
    setState(() {
      for (final c in payments.values) {
        c.clear();
      }
      for (final p in allocation) {
        payments[p['account_id']]!.text = AmountInputFormatter.group(
          AppCurrency.input(p['amount']!),
        );
      }
    });
    final split = <Map<String, int>>[];
    for (final account in accounts) {
      final input = payments[account['id']]!.text.trim();
      if (input.isEmpty) continue;
      final amount = AppCurrency.tryParse(input);
      if (amount == null || amount < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Invalid payment amount', 'ငွေပမာဏမှားနေသည်')),
          ),
        );
        return;
      }
      if (amount > 0) {
        split.add({'account_id': account['id'] as int, 'amount': amount});
      }
    }
    if (total < 0 || total > 9000000000000 || paid > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Payments cannot exceed the purchase total. Unpaid amount becomes supplier credit.',
              'ပေးချေငွေသည် အဝယ်စုစုပေါင်းထက် မကျော်ရ။ ကျန်ငွေကို Supplier အကြွေးအဖြစ် မှတ်မည်။',
            ),
          ),
        ),
      );
      return;
    }
    final itemsToPost = lines.map((line) {
      final productId = line['product_id'] as int?;
      final selected = products.where((p) => p['id'] == productId).toList();
      final existingPrice = selected.isEmpty
          ? 0
          : selected.first['price'] as int;
      return <String, Object?>{
        ...line,
        'purchase_price': line['purchase_price'] ?? 0,
        'sale_price': line['sale_price'] ?? existingPrice,
      };
    }).toList();
    _saveTimer?.cancel();
    setState(() => posting = true);
    try {
      await _lastWrite;
      if (_sharedPurchase case final session?) {
        if (await session.hasPending()) {
          if (!mounted) return;
          final retry = await desktopAsk(
            context,
            _t('Retry pending transaction?', 'စောင့်နေသောစာရင်း ပြန်ပို့မလား?'),
            _t('The previous transaction will be retried before another purchase is posted.', 'အဝယ်အသစ် မတင်မီ ယခင်စာရင်းကို ပြန်ပို့ပါမည်။'),
          );
          if (!retry || !mounted) return;
          await session.retry();
        } else {
          final sharedLines = <SharedPosLine>[];
          for (final line in itemsToPost) {
            final item = products.where((p) => p['id'] == line['product_id']).firstOrNull;
            if (item == null ||
                line['tracking'] != item['tracking'] ||
                line['sale_price'] != item['price']) {
              throw StateError(_t(
                'Select an existing shared item and keep its selling price and tracking mode.',
                'Cloud ပစ္စည်းရှိပြီးသားကို ရွေးပြီး ရောင်းဈေးနှင့် tracking ကို မူလအတိုင်းထားပါ။',
              ));
            }
            sharedLines.add((
              product: item['cloud_id'] as String,
              label: item['name'] as String,
              quantity: line['qty'] as int,
              unitPrice: line['purchase_price'] as int,
              serials: item['tracking'] == 'serial'
                  ? [
                      for (final lot in ProductTracking.decode(line['lots']))
                        lot['serial'] as String,
                    ]
                  : null,
            ));
          }
          await session.post(
            kind: 'purchase',
            lines: sharedLines,
            payments: {
              for (final payment in split)
                accounts.singleWhere((a) => a['id'] == payment['account_id'])['cloud_id'] as String:
                    payment['amount']!,
            },
            counterparty: suppliers.singleWhere((r) => r['id'] == supplierId)['name'] as String,
          );
        }
        posted = true;
        if (mounted) Navigator.pop(context);
        return;
      }
      final id = await db.postPurchase(
        requestKey: requestKey,
        branchId: branchId!,
        supplierId: supplierId!,
        invoiceDate: _date(purchaseDate),
        items: itemsToPost,
        payments: split,
      );
      posted = true;
      if (!mounted) return;
      try {
        await showInvoicePrintPopup(context, id, purchase: true);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  'Purchase saved. Print could not open; use Purchase History to retry.',
                  'အဝယ်သိမ်းပြီးပါပြီ။ Print မဖွင့်နိုင်ပါ။ Purchase History မှ ပြန်ထုတ်နိုင်သည်။',
                ),
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        final detail = e is StateError
            ? e.message
            : e is ArgumentError
            ? '${e.message}'
            : '${e.runtimeType}: ${e.toString().split(' sql ').first.split(' sql:').first.split(' args ').first}';
        await showDialog<void>(
          context: context,
          builder: (c) => DesktopDialog(
            title: Text(_t('Could not confirm purchase', 'အဝယ်အတည်ပြုမရပါ')),
            content: SingleChildScrollView(
              child: SelectableText(
                '${_t('No partial purchase was posted. Your draft is kept.', 'တစ်စိတ်တစ်ပိုင်း မသိမ်းထားပါ။ Draft ကို ဆက်သိမ်းထားပါသည်။')}\n\n$detail',
              ),
            ),
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
      if (mounted) setState(() => posting = false);
      if (!posted) _touch();
    }
  }

  void desktopUpdate(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: ready && !loading && !posting,
    onEscape: leaveByKeyboard,
    commands: {
      DesktopCommand.newVoucher: discardWork,
      DesktopCommand.saveDraft: saveWork,
      DesktopCommand.search: () => purchaseSearchFocus.requestFocus(),
      DesktopCommand.addItem: () =>
          AppCapabilities.windows ? choosePurchaseItem() : addLine(),
      DesktopCommand.barcode: () => AppCapabilities.windows
          ? purchaseSearchFocus.requestFocus()
          : addLine(null, true),
      DesktopCommand.contact: () => supplierFocus.requestFocus(),
      DesktopCommand.paid: focusPaid,
      DesktopCommand.confirm: keyboardPost,
      DesktopCommand.focusRows: () =>
          desktopFocusInScroll(rowsFocus, keyboardScroll),
      DesktopCommand.previousRow: () => selectLine(-1),
      DesktopCommand.nextRow: () => selectLine(1),
      DesktopCommand.quantity: () => lines.isEmpty
          ? Future<void>.value()
          : addLine(selectedLine.clamp(0, lines.length - 1), false, true),
      DesktopCommand.editRow: () => lines.isEmpty
          ? Future<void>.value()
          : addLine(selectedLine.clamp(0, lines.length - 1)),
      DesktopCommand.removeItem: removeSelected,
    },
    child: AppCapabilities.windows && !loading && error == null
        ? desktopPurchaseEditor()
        : DesktopScaffold(
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: TextButton(
                      onPressed: initialize,
                      child: Text('$error · ${_t('Retry', 'ပြန်စမ်းရန်')}'),
                    ),
                  )
                : DesktopListView(
                    controller: keyboardScroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 105),
                    children: [
                      if (saveFailed)
                        Text(
                          _t(
                            'Purchase auto-save failed. Keep this screen open and retry.',
                            'အဝယ်အလိုအလျောက်သိမ်းခြင်း မအောင်မြင်ပါ။ ဤစာမျက်နှာကို မပိတ်ဘဲ ပြန်စမ်းပါ။',
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (saveFailed)
                        TextButton(
                          onPressed: () {
                            unawaited(_saveNow());
                          },
                          child: Text(
                            _t(
                              'Retry auto-save',
                              'အလိုအလျောက်သိမ်းခြင်း ပြန်စမ်းရန်',
                            ),
                          ),
                        ),
                      if (restored)
                        Text(
                          _t(
                            'Unfinished purchase restored from this device.',
                            'ဤစက်ရှိ ရေးလက်စအဝယ်ကို ပြန်ဖွင့်ထားသည်။',
                          ),
                        ),
                      TextButton.icon(
                        onPressed: posting ? null : discardWork,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(
                          _t(
                            'Discard purchase draft',
                            'အဝယ်ရေးလက်စကို ဖျက်မည်',
                          ),
                        ),
                      ),
                      DropdownButton<int>(
                        value: branchId,
                        isExpanded: true,
                        hint: Text(_t('Select branch', 'ဆိုင်ခွဲရွေးရန်')),
                        items: branches
                            .map(
                              (b) => DropdownMenuItem(
                                value: b['id'] as int,
                                child: Text('${b['name']} (${b['code']})'),
                              ),
                            )
                            .toList(),
                        onChanged: posting || lines.isNotEmpty || paid != 0
                            ? null
                            : (id) async {
                                if (id == null || id == branchId) return;
                                for (final c in payments.values) {
                                  c.dispose();
                                }
                                payments.clear();
                                setState(() {
                                  branchId = id;
                                  accounts = [];
                                });
                                await load();
                                _touch();
                              },
                      ),
                      DesktopListTile(
                        title: Text(
                          '${_t('Purchase date', 'အဝယ်ရက်')}: ${_date(purchaseDate)}',
                        ),
                        subtitle: Text(
                          _t(
                            'Backdate is allowed. Actual confirmation time is recorded separately.',
                            'နောက်ကြောင်းရက်ရွေးနိုင်သည်။ အတည်ပြုချိန်ကို သီးခြားမှတ်သည်။',
                          ),
                        ),
                        trailing: const Icon(Icons.calendar_month_outlined),
                        onTap: posting ? null : selectDate,
                      ),
                      DropdownButton<int>(
                        focusNode: supplierFocus,
                        value: suppliers.any((s) => s['id'] == supplierId)
                            ? supplierId
                            : null,
                        isExpanded: true,
                        hint: Text(_t('Choose supplier', 'Supplier ရွေးပါ')),
                        items: suppliers
                            .map(
                              (s) => DropdownMenuItem(
                                value: s['id'] as int,
                                child: Text(
                                  '${s['name']} · ${s['phone']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: posting
                            ? null
                            : (id) {
                                setState(() => supplierId = id);
                                _touch();
                              },
                      ),
                      TextButton.icon(
                        onPressed: posting ? null : manageSuppliers,
                        icon: const Icon(Icons.people_outline),
                        label: Text(
                          _t('Add/Edit Suppliers', 'Supplier ထည့်/ပြင်ရန်'),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _t('Purchase items', 'အဝယ်ပစ္စည်းများ'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: posting ? null : manageCategories,
                            child: Text(_t('Categories', 'အမျိုးအစားများ')),
                          ),
                        ],
                      ),
                      if (AppCapabilities.windows)
                        TextButton(
                          onPressed: () => rowsFocus.requestFocus(),
                          child: Text(
                            _t(
                              'Items · F5 / ↑ ↓ / Enter',
                              'ပစ္စည်းများ · F5 / ↑ ↓ / Enter',
                            ),
                          ),
                        ),
                      Focus(
                        focusNode: rowsFocus,
                        child: Column(
                          children: [
                            for (int i = 0; i < lines.length; i++)
                              Card(
                                color:
                                    AppCapabilities.windows && selectedLine == i
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                                child: DesktopListTile(
                                  title: Text(
                                    '${(lines[i]['item_code'] as String).isEmpty ? _t('Auto code', 'အလိုအလျောက်ကုဒ်') : lines[i]['item_code']} · ${lines[i]['name']}\n${lines[i]['qty']} × ${lines[i]['purchase_price'] == null ? _t('Price pending', 'ဈေးမသတ်မှတ်ရသေး') : _money(lines[i]['purchase_price'] as int)}',
                                  ),
                                  subtitle: Text(
                                    '${_t('Amount', 'ကျသင့်ငွေ')}: ${lines[i]['purchase_price'] == null ? _t('Pending', 'မသတ်မှတ်ရသေး') : _money((lines[i]['qty'] as int) * (lines[i]['purchase_price'] as int))} · '
                                    '${_t('Selling price', 'အရောင်းဈေး')}: ${lines[i]['sale_price'] == null ? _t('Set later', 'နောက်မှသတ်မှတ်မည်') : _money(lines[i]['sale_price'] as int)}',
                                  ),
                                  onTap: posting
                                      ? null
                                      : () async {
                                          selectedLine = i;
                                          await addLine(i);
                                        },
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: posting
                                        ? null
                                        : () {
                                            setState(() => lines.removeAt(i));
                                            _touch();
                                          },
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: posting ? null : () => addLine(),
                        icon: const Icon(Icons.add),
                        label: Text(
                          desktopHint(
                            _t('Add Item', 'ပစ္စည်းထည့်ရန်'),
                            DesktopCommand.addItem,
                          ),
                        ),
                      ),
                      const Divider(),
                      AmountSummary(
                        label: _t('Total', 'စုစုပေါင်း'),
                        amount: total,
                      ),
                      Text(
                        _t(
                          'Pay now from branch accounts, or leave blank for supplier credit. This is not an Expense.',
                          'ဆိုင်ခွဲအကောင့်မှ ပေးနိုင်သည်။ Supplier အကြွေးထားရန် အလွတ်ထားနိုင်သည်။ Expense မဟုတ်ပါ။',
                        ),
                      ),
                      for (final account in accounts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: TextField(
                            focusNode: account['id'] == accounts.first['id']
                                ? paidFocus
                                : null,
                            controller: payments[account['id']],
                            enabled: !posting,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _touch();
                            },
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText:
                                  '${account['name']} (${account['type']})',
                              helperText:
                                  '${_t('Available', 'လက်ကျန်')}: ${_money(account['balance'] as int)}',
                            ),
                          ),
                        ),
                      Text(
                        '${_t('Payment total', 'ပေးချေမှုစုစုပေါင်း')}: ${_money(paid)}',
                      ),
                      Text(
                        '${_t('Supplier credit due', 'Supplier အကြွေးကျန်')}: ${_money(total - paid)}',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: posting
                            ? null
                            : AppCapabilities.windows
                            ? keyboardPost
                            : post,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          posting
                              ? _t('Posting...', 'သိမ်းနေသည်…')
                              : desktopHint(
                                  _t('Confirm Purchase', 'အဝယ်အတည်ပြုရန်'),
                                  DesktopCommand.confirm,
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
  );
}

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({
    super.key,
    this.initialPurchaseId,
    this.initialBranchId,
    this.allowDraftEditing = true,
  });
  final int? initialPurchaseId;
  final int? initialBranchId;
  final bool allowDraftEditing;
  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  void updateHistory(VoidCallback change) => setState(change);
  String historySearch = '', historyStatus = 'all';
  int? historySupplier;
  DateTime? historyFrom, historyTo;
  List<Map<String, Object?>> branches = [],
      purchases = [],
      supplierBalances = [];
  int? branchId;
  SharedPosSession? _sharedHistory;
  Timer? _sharedHistoryRefresh;
  int _historyRequest = 0;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    branchId = widget.initialBranchId;
    _sharedHistory = SharedPosSession.current;
    if (_sharedHistory != null) {
      _sharedHistoryRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!loading) unawaited(load(background: true));
      });
    }
    start();
  }

  @override
  void dispose() {
    _sharedHistoryRefresh?.cancel();
    super.dispose();
  }

  String purchaseReference(Map<String, Object?> row) =>
      row['reference'] as String? ?? _no(row['id'] as int);

  Future<void> start() async {
    await load();
    if (mounted && error == null && widget.initialPurchaseId != null) {
      await detail(widget.initialPurchaseId!);
    }
  }

  Future<void> load({bool background = false}) async {
    final request = ++_historyRequest;
    if (mounted) {
      setState(() {
        if (!background) loading = true;
        error = null;
      });
    }
    try {
      if (_sharedHistory case final session?) {
        final view = await session.load();
        if (!mounted || request != _historyRequest) return;
        final history = (view['vouchers'] as List).cast<Map>()
            .where((row) => row['kind'] == 'purchase').toList()
          ..sort((a, b) => '${b['occurred_at']}'.compareTo('${a['occurred_at']}'));
        final balances = <String, ({int count, int amount})>{};
        final mapped = <Map<String, Object?>>[];
        for (final row in history) {
          final supplier = row['counterparty'] as String? ?? '—';
          final due = row['due'] as int? ?? 0;
          if (due > 0 && row['status'] != 'void') {
            final old = balances[supplier];
            balances[supplier] = (
              count: (old?.count ?? 0) + 1,
              amount: (old?.amount ?? 0) + due,
            );
          }
          mapped.add({
            'id': mapped.length,
            'reference': row['number'],
            'branch_id': 0,
            'supplier_name': supplier,
            'invoice_date': row['invoice_date'] ??
                (row['occurred_at'] as String).split('T').first,
            'confirmed_at': row['occurred_at'],
            'total': row['total'],
            'balance_due': due,
            'status': row['status'],
          });
        }
        setState(() {
          branchId = 0;
          branches = [
            {'id': 0, 'name': session.connection.branchCode, 'code': session.connection.branchCode},
          ];
          purchases = mapped;
          supplierBalances = [
            for (final entry in balances.entries)
              {'name': entry.key, 'purchase_count': entry.value.count, 'balance_due': entry.value.amount},
          ];
          loading = false;
        });
        return;
      }
      final db = AppDatabase.instance;
      final rows = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final id = rows.any((b) => b['id'] == preferred)
          ? preferred
          : (rows.isEmpty ? null : rows.first['id'] as int);
      final history = id == null
          ? <Map<String, Object?>>[]
          : await db.getPurchases(branchId: id);
      final balances = id == null
          ? <Map<String, Object?>>[]
          : await db.getSupplierBalances(branchId: id);
      if (mounted) {
        setState(() {
          branches = rows;
          branchId = id;
          purchases = history;
          supplierBalances = balances;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _t('Could not load purchase history', 'အဝယ်မှတ်တမ်း ဖတ်မရပါ');
        });
      }
    }
  }

  Future<void> create() async {
    if (!widget.allowDraftEditing) return;
    if (_sharedHistory case final session?) {
      await _openSharedHistory(session, SharedPosPageKind.purchase);
      return;
    }
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopScaffold(
          appBar: AppBar(title: Text(_t('Purchase', 'ပစ္စည်းအဝယ်'))),
          body: const PurchasePage(),
        ),
      ),
    );
    if (id != null && mounted) {
      await load();
      if (mounted) await detail(id);
    }
  }

  Future<bool> settle(
    int purchaseId,
    int branch,
    int due, {
    Map<int, int> initial = const {},
    int? correctionId,
  }) async {
    List<Map<String, Object?>> accounts;
    try {
      accounts = await AppDatabase.instance.getMoneyAccounts(branchId: branch);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not load branch accounts',
                'ဆိုင်ခွဲအကောင့်များ ဖတ်မရပါ',
              ),
            ),
          ),
        );
      }
      return false;
    }
    if (!mounted) return false;
    final inputs = <int, TextEditingController>{
      for (final account in accounts)
        (account['id'] as int): TextEditingController(
          text: initial[account['id']] == null
              ? ''
              : AppCurrency.input(initial[account['id']]!),
        ),
    };
    final key =
        '${correctionId == null ? 'supplier' : 'supplier-correction-$correctionId'}-${DateTime.now().toUtc().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    var busy = false;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, refresh) => DesktopDialog(
                title: Text(
                  _t('Pay supplier credit', 'Supplier အကြွေးရှင်းရန်'),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_no(purchaseId)} · ${_t('Due', 'ကျန်ငွေ')}: ${_money(due)}',
                      ),
                      for (final account in accounts)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextField(
                            controller: inputs[account['id']],
                            enabled: !busy,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              labelText:
                                  '${account['name']} (${account['type']})',
                              helperText:
                                  '${_t('Available', 'လက်ကျန်')}: ${_money(account['balance'] as int)}',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.pop(dialogContext, false),
                    child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
                  ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final splits = <Map<String, int>>[];
                            var sum = 0;
                            for (final account in accounts) {
                              final raw = inputs[account['id']]!.text.trim();
                              if (raw.isEmpty) continue;
                              final amount = AppCurrency.tryParse(raw);
                              if (amount == null || amount < 0) {
                                ScaffoldMessenger.of(dialogContext)
                                    .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _t(
                                            'Invalid payment amount',
                                            'ပေးချေငွေမှားနေသည်',
                                          ),
                                        ),
                                      ),
                                    );
                                return;
                              }
                              if (amount > 0) {
                                splits.add({
                                  'account_id': account['id'] as int,
                                  'amount': amount,
                                });
                                sum += amount;
                              }
                            }
                            if (sum <= 0 || sum > due) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _t(
                                      'Pay more than zero and no more than the outstanding balance.',
                                      'သုညထက်ပိုပြီး ကျန်ငွေထက်မကျော်အောင် ပေးပါ။',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }
                            refresh(() => busy = true);
                            try {
                              await AppDatabase.instance.settleSupplierPurchase(
                                requestKey: key,
                                purchaseId: purchaseId,
                                paymentDate: _date(AppDateTime.today()),
                                payments: splits,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext, true);
                              }
                            } catch (e) {
                              if (dialogContext.mounted) {
                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${_t('Payment not posted', 'ငွေပေးချေမှု မသိမ်းရပါ')}: $e',
                                    ),
                                  ),
                                );
                                refresh(() => busy = false);
                              }
                            }
                          },
                    child: Text(_t('Pay', 'ပေးချေရန်')),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final controller in inputs.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _openSharedHistory(
    SharedPosSession session,
    SharedPosPageKind kind, {
    String? reference,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(_t('Purchase', 'ပစ္စည်းအဝယ်'))),
          body: kind == SharedPosPageKind.purchase
              ? const PurchasePage()
              : SharedPosPage(session: session, kind: kind, voucherReference: reference),
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> detail(int id) async {
    if (_sharedHistory case final session?) {
      final row = purchases.where((row) => row['id'] == id).firstOrNull;
      if (row != null) {
        await _openSharedHistory(
          session,
          SharedPosPageKind.purchases,
          reference: row['reference'] as String?,
        );
      }
      return;
    }
    try {
      final purchase = await AppDatabase.instance.getPurchase(id);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(
              title: Text(_no(id)),
              actions: [
                if (purchase['status'] == 'posted')
                  IconButton(
                    tooltip: _t('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
                    icon: const Icon(Icons.lock_outline),
                    onPressed: () async {
                      try {
                        await AppDatabase.instance.createPurchaseCorrectionWork(
                          id: id,
                        );
                        if (!mounted || !context.mounted) return;
                        Navigator.pop(context);
                        await create();
                        if (mounted) await load();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
              ],
            ),
            body: DesktopListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_t('Print / PDF', 'Print / PDF')),
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          InvoicePrintPage(saleId: id, purchase: true),
                    ),
                  ),
                ),
                if (purchase['status'] == 'void')
                  Text(
                    'VOID · ${purchase['void_reason']}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    _t(
                      'Delete purchase permanently',
                      'အဝယ်ဘောင်ချာ အပြီးတိုင်ဖျက်ရန်',
                    ),
                  ),
                  onPressed: () async {
                    final ok = await deleteVoucherWithPrompt(
                      context,
                      kind: 'purchase',
                      id: id,
                      number: _no(id),
                    );
                    if (ok && mounted && context.mounted) {
                      Navigator.pop(context);
                      if (mounted) await load();
                    }
                  },
                ),
                if (purchase['replacement_id'] != null)
                  Text(
                    '${_t('Corrected by', 'ပြင်ဆင်ပြီးဘောင်ချာ')}: '
                    '${_no(purchase['replacement_id'] as int)}',
                  ),
                Text(
                  '${_t('Purchase date', 'အဝယ်ရက်')}: ${purchase['invoice_date']}',
                ),
                Text(
                  '${_t('Confirmed at', 'အတည်ပြုချိန်')}: ${AppDateTime.format(purchase['confirmed_at'])}',
                ),
                Text(
                  '${_t('Supplier', 'ပစ္စည်းပေးသွင်းသူ')}: ${purchase['supplier_name']}',
                ),
                Text(
                  '${purchase['supplier_phone']}\n${purchase['supplier_address']}',
                ),
                const Divider(),
                for (final item in purchase['items'] as List)
                  DesktopListTile(
                    onTap: () =>
                        showProductTracking(context, item['tracking_json']),
                    title: Text('${item['item_code']} · ${item['item_name']}'),
                    subtitle: Text(
                      '${item['category_name']} · ${item['qty']} × ${_money(item['purchase_price'] as int)}\n${_t('Selling price', 'အရောင်းဈေး')}: ${_money(item['sale_price'] as int)}',
                    ),
                    trailing: MoneyText(item['amount'] as int),
                  ),
                const Divider(),
                AmountSummary(
                  label: _t('Total', 'စုစုပေါင်း'),
                  amount: purchase['total'] as int,
                ),
                Text(
                  '${_t('Paid', 'ပေးပြီး')}: ${_money(purchase['paid'] as int)}',
                ),
                Text(
                  '${_t('Supplier credit due', 'Supplier အကြွေးကျန်')}: ${_money(purchase['balance_due'] as int)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final payment in purchase['payments'] as List)
                  Text(
                    '${payment['account_name']}: ${_money(payment['amount'] as int)} · ${AppDateTime.format(payment['created_at'])}',
                  ),
                for (final payment in purchase['settlement_payments'] as List)
                  Text(
                    '${payment['status'] == 'void' ? 'VOID · ' : ''}${_t('Credit payment', 'အကြွေးရှင်း')} · ${payment['account_name']}: ${_money(payment['amount'] as int)} · ${AppDateTime.format(payment['created_at'])}',
                  ),
                for (final settlement in purchase['settlements'] as List)
                  if (settlement['replacement_id'] != null)
                    Text(
                      '${_t('Corrected supplier payment', 'ပြင်ဆင်ပြီး Supplier ငွေပေးချေမှု')}: '
                      '#${settlement['id']} → #${settlement['replacement_id']}',
                    ),
                for (final settlement in purchase['settlements'] as List)
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text(
                      '${_t('Delete supplier payment permanently', 'Supplier ငွေပေးချေမှု အပြီးတိုင်ဖျက်ရန်')} #${settlement['id']}',
                    ),
                    onPressed: () async {
                      final ok = await deleteVoucherWithPrompt(
                        context,
                        kind: 'settlement',
                        id: settlement['id'] as int,
                        number: 'SET-${settlement['id']}',
                      );
                      if (ok && mounted && context.mounted) {
                        Navigator.pop(context);
                        if (mounted) await load();
                        if (mounted) await detail(id);
                      }
                    },
                  ),
                for (final settlement in purchase['settlements'] as List)
                  if (settlement['status'] == 'posted')
                    TextButton.icon(
                      icon: const Icon(Icons.undo_outlined),
                      label: Text(
                        '${_t('Void supplier payment', 'Supplier ငွေပေးချေမှု ပယ်ဖျက်ရန်')} #${settlement['id']}',
                      ),
                      onPressed: () async {
                        final reason = await askInvoiceVoidReason(
                          context,
                          _t(
                            'Void supplier payment?',
                            'Supplier ငွေပေးချေမှု ပယ်ဖျက်မလား?',
                          ),
                        );
                        if (reason == null) return;
                        try {
                          await AppDatabase.instance.voidSupplierSettlement(
                            id: settlement['id'] as int,
                            reason: reason,
                          );
                          if (!mounted || !context.mounted) return;
                          Navigator.pop(context);
                          await load();
                          if (mounted) await detail(id);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                    ),
                for (final settlement in purchase['settlements'] as List)
                  if (settlement['status'] == 'posted')
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        '${_t('Correct supplier payment', 'Supplier ငွေပေးချေမှု ပြန်ပြင်ရန်')} #${settlement['id']}',
                      ),
                      onPressed: () async {
                        final oldPayments = <int, int>{
                          for (final p
                              in purchase['settlement_payments'] as List)
                            if (p['settlement_id'] == settlement['id'])
                              p['account_id'] as int: p['amount'] as int,
                        };
                        try {
                          await VoucherPermissions.requireEditable();
                          if (!mounted || !context.mounted) return;
                          Navigator.pop(context);
                          await load();
                          final due =
                              (purchase['balance_due'] as int) +
                              (settlement['amount'] as int);
                          await settle(
                            id,
                            purchase['branch_id'] as int,
                            due,
                            initial: oldPayments,
                            correctionId: settlement['id'] as int,
                          );
                          if (mounted) {
                            await load();
                            await detail(id);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                    ),
                if (widget.allowDraftEditing && purchase['status'] == 'posted')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      _t('Void purchase invoice', 'အဝယ်ဘောင်ချာ ပယ်ဖျက်ရန်'),
                    ),
                    onPressed: () async {
                      final reason = await askInvoiceVoidReason(
                        context,
                        _t(
                          'Void purchase invoice?',
                          'အဝယ်ဘောင်ချာ ပယ်ဖျက်မလား?',
                        ),
                      );
                      if (reason == null) return;
                      try {
                        await AppDatabase.instance.voidPurchaseInvoice(
                          id: id,
                          reason: reason,
                        );
                        if (!mounted || !context.mounted) return;
                        Navigator.pop(context);
                        await load();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                if (purchase['status'] == 'posted')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(
                      _t(
                        'Correct purchase invoice',
                        'အဝယ်ဘောင်ချာ ပြန်ပြင်ရန်',
                      ),
                    ),
                    onPressed: () async {
                      const reason = 'Edited using voucher unlock';
                      try {
                        await AppDatabase.instance.createPurchaseCorrectionWork(
                          id: id,
                          reason: reason,
                        );
                        if (!mounted || !context.mounted) return;
                        Navigator.pop(context);
                        await create();
                        if (mounted) await load();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                  ),
                if (purchase['status'] == 'posted' &&
                    (purchase['balance_due'] as int) > 0)
                  FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(_t('Pay remaining balance', 'ကျန်ငွေရှင်းရန်')),
                    onPressed: () async {
                      final ok = await settle(
                        id,
                        purchase['branch_id'] as int,
                        purchase['balance_due'] as int,
                      );
                      if (ok && mounted) {
                        Navigator.pop(context);
                        await load();
                        if (mounted) await detail(id);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Could not open purchase', 'အဝယ်မှတ်တမ်း ဖွင့်မရပါ'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = purchases
        .where(
          (p) =>
              HistoryDates.includes(p['invoice_date'], historyFrom, historyTo),
        )
        .toList();
    return AppCapabilities.windows
        ? desktopHistory()
        : DesktopCommandScope(
            enabled: !loading,
            commands: {DesktopCommand.newVoucher: create},
            child: DesktopScaffold(
              body: Column(
                children: [
                  DropdownButton<int>(
                    value: branchId,
                    isExpanded: true,
                    hint: Text(_t('Select branch', 'ဆိုင်ခွဲရွေးရန်')),
                    items: branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text('${b['name']} (${b['code']})'),
                          ),
                        )
                        .toList(),
                    onChanged: loading
                        ? null
                        : (id) {
                            if (id != null) {
                              setState(() => branchId = id);
                              load();
                            }
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: HistoryDateFilter(
                      from: historyFrom,
                      to: historyTo,
                      onChanged: (from, to) => setState(() {
                        historyFrom = from;
                        historyTo = to;
                      }),
                    ),
                  ),
                  if (!loading && supplierBalances.isNotEmpty)
                    DesktopSection(
                      title: Text(
                        '${_t('Supplier credit due', 'Supplier အကြွေးကျန်')}: '
                        '${_money(supplierBalances.fold<int>(0, (sum, row) => sum + (row['balance_due'] as int)))}',
                      ),
                      children: [
                        for (final row in supplierBalances)
                          DesktopListTile(
                            title: Text(row['name'] as String),
                            trailing: MoneyText(row['balance_due'] as int),
                            subtitle: Text(
                              '${row['purchase_count']} ${_t('purchases', 'အဝယ်')}',
                            ),
                          ),
                      ],
                    ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(
                            child: TextButton(
                              onPressed: load,
                              child: Text('$error · Retry'),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: load,
                            child: DesktopListView.builder(
                              desktopColumns: const [
                                "Invoice No.",
                                "Date",
                                "Supplier",
                                "Total",
                                "Outstanding",
                                "Status",
                              ],
                              desktopCells: (context, index) {
                                final r = visible[index];
                                return [
                                  desktopCellText(purchaseReference(r)),
                                  desktopCellText(r['invoice_date']),
                                  desktopCellText(r['supplier_name']),
                                  desktopMoney(r['total']),
                                  desktopMoney(r['balance_due']),
                                  desktopCellText(r['status']),
                                ];
                              },

                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final p = visible[index];
                                return DesktopListTile(
                                  title: Text(
                                    '${purchaseReference(p)} · ${p['supplier_name']}',
                                  ),
                                  subtitle: Text(
                                    '${p['status'] == 'void' ? 'VOID · ' : ''}${p['invoice_date']} · ${AppDateTime.format(p['confirmed_at'])}',
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      MoneyText(p['total'] as int),
                                      if ((p['balance_due'] as int) > 0)
                                        Text(
                                          '${_t('Due', 'ကျန်')}: ${_money(p['balance_due'] as int)}',
                                        ),
                                    ],
                                  ),
                                  onTap: () => detail(p['id'] as int),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
              floatingActionButton: widget.allowDraftEditing
                  ? FloatingActionButton(
                      onPressed: loading ? null : create,
                      child: const Icon(Icons.add),
                    )
                  : null,
            ),
          );
  }
}
