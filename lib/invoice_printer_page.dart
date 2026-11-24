import 'voucher_pdf_preview.dart';
import 'print_template.dart';
import 'print_template_editor.dart';
import 'desktop_ui.dart';
import 'desktop_commands.dart';
import 'a4_layout_settings.dart';
import 'a4_layout_editor.dart';
import 'stationery_editor.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import 'app_database.dart';
import 'activity_repository.dart';
import 'app_language.dart';
import 'invoice_pdf.dart';
import 'invoice_print_settings.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

Future<void> showInvoicePrintPopup(
  BuildContext context,
  int id, {
  bool purchase = false,
}) async {
  final sale = purchase
      ? await purchasePrintSnapshot(id)
      : await AppDatabase.instance.getConfirmedSale(id);
  if (!context.mounted) return;
  await showVoucherPrintPopup(context, sale, filename: '${purchase ? 'PUR' : 'INV'}-$id.pdf');
}

Future<void> showVoucherPrintPopup(
  BuildContext context,
  Map<String, Object?> sale, {
  required String filename,
}) async {
  final settings = await InvoicePrintSettings.load();
  final pdf = await buildInvoicePdf(
    sale: sale,
    settings: settings,
    myanmar:
        settings.language == 'my' ||
        (settings.language == 'app' && AppLanguage.current.value == 'my'),
  );
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialog) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 1100,
        height: MediaQuery.sizeOf(dialog).height - 60,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_t('Print voucher', 'ဘောင်ချာ Print ထုတ်ရန်')),
                  ),
                  IconButton(
                    tooltip: _t('Close', 'ပိတ်ရန်'),
                    onPressed: () => Navigator.pop(dialog),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: VoucherPdfPreview(
                bytes: pdf.bytes,
                format: pdf.format,
                name: filename,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class InvoicePrinterSettingsPage extends StatefulWidget {
  const InvoicePrinterSettingsPage({super.key});
  @override
  State<InvoicePrinterSettingsPage> createState() =>
      _InvoicePrinterSettingsPageState();
}

class _InvoicePrinterSettingsPageState
    extends State<InvoicePrinterSettingsPage> {
  InvoicePrintSettings? settings;
  bool busy = false, settingsLoaded = false;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await InvoicePrintSettings.load();
      if (mounted) {
        setState(() {
          settings = value;
          settingsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          settings = const InvoicePrintSettings();
          message = _t(
            'Could not read saved print settings. Defaults are shown; Save to replace them.',
            'သိမ်းထားသော Print ဆက်တင်မဖတ်နိုင်ပါ။ Default ကို ပြထားပါသည်။ သိမ်းမည်ကို နှိပ်ပြီး ပြန်သတ်မှတ်နိုင်သည်။',
          );
        });
      }
    }
  }

  Future<void> save(InvoicePrintSettings value) async {
    if (busy) {
      return;
    }
    final before = settingsLoaded && settings != null
        ? jsonEncode(settings!.toJson())
        : 'Previous settings not readable';
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await value.save();
      settings = value;
      settingsLoaded = true;
      try {
        await ActivityRepository.preference(
          'invoice_print_defaults',
          before,
          jsonEncode(value.toJson()),
        );
      } catch (_) {
        if (mounted) {
          setState(
            () => message = _t(
              'Print settings saved, but activity could not be recorded.',
              'Print setting သိမ်းပြီးသော်လည်း Activity မမှတ်နိုင်ပါ။',
            ),
          );
        }
        return;
      }
      if (mounted) {
        setState(
          () => message = _t(
            'Default print settings saved on this device.',
            'ဤစက်အတွက် Default Print ဆက်တင် သိမ်းပြီးပါပြီ။',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = _t(
            'Could not save print settings. Retry.',
            'Print ဆက်တင် မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => settings == null
      ? const Center(child: CircularProgressIndicator())
      : _InvoiceOptionsForm(
          initial: settings!,
          busy: busy,
          message: message,
          actionLabel: _t('Save default settings', 'Default ဆက်တင် သိမ်းမည်'),
          onSubmit: save,
        );
}

class InvoicePrintPage extends StatefulWidget {
  const InvoicePrintPage({
    super.key,
    required this.saleId,
    this.purchase = false,
    this.expense = false,
  }) : sharedSnapshot = null;
  const InvoicePrintPage.shared({
    super.key,
    required Map<String, Object?> snapshot,
  }) : sharedSnapshot = snapshot, saleId = 0, purchase = false, expense = false;

  final Map<String, Object?>? sharedSnapshot;
  final int saleId;
  final bool purchase, expense;
  @override
  State<InvoicePrintPage> createState() => _InvoicePrintPageState();
}

class _InvoicePrintPageState extends State<InvoicePrintPage> {
  final optionsKey = GlobalKey<_InvoiceOptionsFormState>();
  InvoicePrintSettings? settings;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await InvoicePrintSettings.load();
      if (mounted) {
        setState(() => settings = value);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          settings = const InvoicePrintSettings();
          error = _t(
            'Could not load defaults. You can choose print settings below.',
            'Default မဖတ်နိုင်ပါ။ အောက်တွင် Print ဆက်တင်ရွေးနိုင်ပါသည်။',
          );
        });
      }
    }
  }

  Future<Map<String, Object?>> snapshot() async {
    if (widget.sharedSnapshot case final shared?) return shared;
    if (widget.expense) return expensePrintSnapshot(widget.saleId);
    if (widget.purchase) return purchasePrintSnapshot(widget.saleId);
    return AppDatabase.instance.getConfirmedSale(widget.saleId);
  }

  Future<void> preview(InvoicePrintSettings value) async {
    if (busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // This read obtains current debt/receipt status in a transaction. Printing
      // never confirms a sale, deducts stock or writes money entries.
      final sale = await snapshot();
      final myanmar =
          value.language == 'my' ||
          (value.language == 'app' && AppLanguage.current.value == 'my');
      final pdf = await buildInvoicePdf(
        sale: sale,
        settings: value,
        myanmar: myanmar,
      );
      await value.save();
      settings = value;
      if (!mounted) {
        return;
      }
      final number = (widget.sharedSnapshot?['document_number'] as String?) ??
          '${widget.expense
              ? 'EXP'
              : widget.purchase
              ? 'PUR'
              : 'INV'}-${widget.saleId.toString().padLeft(6, '0')}';
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(title: Text('$number · PDF')),
            body: VoucherPdfPreview(
              bytes: pdf.bytes,
              format: pdf.format,
              name: '$number.pdf',
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = _t(
            'Could not create invoice PDF. Try larger paper or turn off photos, then retry.',
            'Invoice PDF မဖန်တီးနိုင်ပါ။ စာရွက်ပိုကြီးရွေးပါ သို့မဟုတ် ပုံများပိတ်ပြီး ပြန်စမ်းပါ။',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: !busy && settings != null,
    commands: {
      DesktopCommand.print: () async {
        await optionsKey.currentState?.submit();
      },
    },
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(_t('Invoice Print / PDF', 'Invoice Print / PDF')),
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : _InvoiceOptionsForm(
              key: optionsKey,
              documentLoader: snapshot,
              initial: settings!,
              busy: busy,
              message: error,
              actionLabel: _t(
                'Preview / Print / PDF',
                'နမူနာကြည့် / Print / PDF',
              ),
              onSubmit: preview,
            ),
    ),
  );
}

Future<Map<String, Object?>> expensePrintSnapshot(int id) async {
  final db = await AppDatabase.instance.database;
  final rows = await db.query('expenses', where: 'id=?', whereArgs: [id]);
  if (rows.isEmpty) throw StateError('Expense not found');
  final e = rows.single;
  final businesses = await db.query('business_profile', where: 'id=1');
  final branches = await db.query(
    'branches',
    where: 'id=?',
    whereArgs: [e['branch_id']],
  );
  final branch = branches.isEmpty ? <String, Object?>{} : branches.single;
  return {
    ...e,
    'document_prefix': 'EXP',
    'document_title': _t('EXPENSE VOUCHER', 'အသုံးစရိတ်ဘောင်ချာ'),
    'business_name': businesses.isEmpty ? '' : businesses.single['name'],
    'branch_name_snapshot': branch['name'] ?? '',
    'branch_code_snapshot': branch['code'] ?? '',
    'branch_phone_snapshot': branch['phone'] ?? '',
    'branch_address_snapshot': branch['address'] ?? '',
    'invoice_date': e['expense_date'],
    'confirmed_at': e['posted_at'],
    'customer_name': '',
    'customer_phone': '',
    'customer_address': '',
    'customer_company': '',
    'employee_name': '',
    'subtotal': e['amount'],
    'discount_amount': 0,
    'total': e['amount'],
    'paid': e['amount'],
    'balance_due': 0,
    'items': [
      {
        'item_code': '',
        'item_name': '${e['category']} · ${e['note']}',
        'qty': 1,
        'price': e['amount'],
        'amount': e['amount'],
        'tracking_json': '[]',
      },
    ],
  };
}

Future<Map<String, Object?>> purchasePrintSnapshot(int id) async {
  final p = await AppDatabase.instance.getPurchase(id);
  final db = await AppDatabase.instance.database;
  final businesses = await db.query('business_profile', where: 'id=1');
  final branches = await db.query(
    'branches',
    where: 'id=?',
    whereArgs: [p['branch_id']],
  );
  final branch = branches.isEmpty ? <String, Object?>{} : branches.single;
  return {
    ...p,
    'business_name': businesses.isEmpty ? '' : businesses.single['name'],
    'branch_name_snapshot': branch['name'] ?? '',
    'branch_code_snapshot': branch['code'] ?? '',
    'branch_phone_snapshot': branch['phone'] ?? '',
    'branch_address_snapshot': branch['address'] ?? '',
    'document_prefix': 'PUR',
    'document_title': _t('PURCHASE INVOICE', 'အဝယ်ဘောင်ချာ'),
    'customer_name': p['supplier_name'],
    'customer_phone': p['supplier_phone'],
    'customer_address': p['supplier_address'],
    'customer_company': '',
    'subtotal': p['total'],
    'discount_amount': 0,
    'employee_name': '',
    'items': [
      for (final raw in p['items'] as List)
        {
          ...Map<String, Object?>.from(raw as Map),
          'price': raw['purchase_price'],
        },
    ],
  };
}

class _InvoiceOptionsForm extends StatefulWidget {
  const _InvoiceOptionsForm({
    super.key,
    this.documentLoader,
    required this.initial,
    required this.busy,
    required this.actionLabel,
    required this.onSubmit,
    this.message,
  });
  final InvoicePrintSettings initial;
  final Future<Map<String, Object?>> Function()? documentLoader;
  final bool busy;
  final String actionLabel;
  final String? message;
  final Future<void> Function(InvoicePrintSettings) onSubmit;
  @override
  State<_InvoiceOptionsForm> createState() => _InvoiceOptionsFormState();
}

class _InvoiceOptionsFormState extends State<_InvoiceOptionsForm> {
  final form = GlobalKey<FormState>();
  late String paper, language;
  late A4LayoutSettings a4;
  PrintTemplate? template;
  late bool payments, salePerson;
  late final TextEditingController width, height, footer;
  bool logo = true,
      photos = false,
      customer = true,
      branch = true,
      date = true,
      itemCode = true,
      prices = true,
      discount = true;
  String layout = 'auto';
  int resets = 0;
  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    a4 = s.a4;
    template = s.template;
    logo = s.showLogo;
    photos = s.showItemPhotos;
    customer = s.showCustomer;
    branch = s.showBranch;
    date = s.showDate;
    itemCode = s.showItemCode;
    prices = s.showPrices;
    discount = s.showDiscount;
    layout = s.layout;
    paper = s.paper;
    language = s.language;
    payments = s.showPayments;
    salePerson = s.showSalePerson;
    width = TextEditingController(text: s.customWidthMm.toString());
    height = TextEditingController(text: s.customHeightMm.toString());
    footer = TextEditingController(text: s.footer);
  }

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    footer.dispose();
    super.dispose();
  }

  String? dimension(String? text, double min, double max) {
    final value = double.tryParse(text?.trim() ?? '');
    return value == null || !value.isFinite || value < min || value > max
        ? _t('Enter $min–$max mm.', '$min–$max mm အတွင်း ထည့်ပါ။')
        : null;
  }

  Future<void> submit() async {
    if (widget.busy || !form.currentState!.validate()) {
      return;
    }
    await widget.onSubmit(currentSettings());
  }

  InvoicePrintSettings currentSettings() {
    return InvoicePrintSettings(
      paper: paper,
      language: language,
      customWidthMm: paper == 'custom'
          ? double.parse(width.text.trim())
          : widget.initial.customWidthMm,
      customHeightMm: paper == 'custom'
          ? double.parse(height.text.trim())
          : widget.initial.customHeightMm,
      showPayments: payments,
      showSalePerson: salePerson,
      footer: footer.text.trim(),
      showLogo: logo,
      showItemPhotos: photos,
      showCustomer: customer,
      showBranch: branch,
      showDate: date,
      showItemCode: itemCode,
      showPrices: prices,
      showDiscount: discount,
      layout: layout,
      a4: a4,
      template: template,
    );
  }

  Future<void> useOriginalMobileLayout() async {
    if (widget.busy || !form.currentState!.validate()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          _t(
            'Use original mobile print layout?',
            'မူလ Mobile ဘောင်ချာပုံစံကို သုံးမလား။',
          ),
        ),
        content: Text(
          _t(
            'Use the original mobile renderer for the selected paper size. Your custom template, business logo, branch details and appearance settings are kept.',
            'ရွေးထားသော စာရွက်အရွယ်အလိုက် မူလ Mobile ပုံစံကို သုံးမည်။ Custom template၊ ဆိုင် Logo၊ ဆိုင်ခွဲအချက်အလက်နှင့် ချိန်ညှိချက်များကို ဆက်ထိန်းထားမည်။',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(_t('Use original layout', 'မူလပုံစံသုံးမည်')),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      final next = InvoicePrintSettings.fromJson({
        ...currentSettings().toJson(),
        'layout': 'auto',
      });
      await next.save();
      if (!mounted) return;
      setState(() {
        layout = 'auto';
        template = next.template;
        resets++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Original mobile layout saved.',
              'မူလ Mobile ပုံစံကို သိမ်းပြီးပါပြီ။',
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not save layout. Retry.',
                'Layout မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> design() async {
    if (widget.busy || !form.currentState!.validate()) return;
    final current = currentSettings();
    final doc = await widget.documentLoader?.call();
    if (!mounted) return;
    final initial =
        template ??
        (current.pageFormat.width / PdfPageFormat.mm <= 100
            ? PrintTemplate.receipt(
                width: current.pageFormat.width / PdfPageFormat.mm,
                height: current.pageFormat.height / PdfPageFormat.mm,
              )
            : PrintTemplate.invoice().resized(
                current.pageFormat.width / PdfPageFormat.mm,
                current.pageFormat.height / PdfPageFormat.mm,
              ));
    await Navigator.push<PrintTemplate>(
      context,
      MaterialPageRoute(
        builder: (_) => PrintTemplateEditorPage(
          initial: initial,
          document: doc,
          options: current.toJson(),
          onSave: (selected) async {
            if (!mounted) throw StateError('Print settings page closed');
            setState(() {
              template = selected;
              layout = 'designer';
              resets++;
            });
            await currentSettings().save();
          },
        ),
      ),
    );
  }

  Future<void> editStationery() async {
    if (widget.busy || !form.currentState!.validate()) return;
    try {
      final initial = currentSettings();
      var document = await widget.documentLoader?.call();
      if (document == null) {
        final db = await AppDatabase.instance.database;
        final saved = await db.query(
          'sale_invoices',
          columns: ['id'],
          where: "status='posted'",
          orderBy: 'id DESC',
          limit: 1,
        );
        if (saved.isNotEmpty) {
          document = await AppDatabase.instance.getConfirmedSale(
            saved.single['id'] as int,
          );
        }
        if (document == null) {
          final business = (await db.query(
            'business_profile',
            where: 'id=1',
          )).firstOrNull;
          final branches = await AppDatabase.instance.getBranches();
          document = {
            'id': 0,
            'status': 'draft',
            'business_name': '${business?['name'] ?? ''}'.trim().isEmpty
                ? 'Business name'
                : business!['name'],
            'branch_id': branches.firstOrNull?['id'],
            'invoice_date': DateTime.now().toIso8601String().substring(0, 10),
            'customer_name': 'Sample customer',
            'customer_phone': '',
            'customer_address': '',
            'employee_name': 'Sample salesperson',
            'currency_code': business?['currency_code'] ?? 'MMK',
            'currency_digits': business?['currency_digits'] ?? 0,
            'subtotal': 1000,
            'discount_amount': 0,
            'total': 1000,
            'paid': 1000,
            'balance_due': 0,
            'remark': 'Sample voucher',
            'items': [
              {
                'item_name': 'Sample item',
                'item_code': 'SAMPLE',
                'qty': 1,
                'price': 1000,
                'amount': 1000,
              },
            ],
          };
        }
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StationeryEditor(
            initial: initial,
            document: document!,
            onSave: (next) async {
              final saved = InvoicePrintSettings.fromJson({
                ...initial.toJson(),
                'paper': 'a4',
                'layout': 'auto',
                'a4': next.toJson(),
              });
              await saved.save();
              if (mounted) {
                setState(() {
                  a4 = next;
                  layout = 'auto';
                  resets++;
                });
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget option(String en, String my, bool value, void Function(bool) change) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_t(en, my)),
        value: value,
        onChanged: widget.busy ? null : (v) => setState(() => change(v)),
      );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.busy,
    child: Form(
      key: form,
      child: DesktopListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _t('Paper and invoice layout', 'စာရွက်နှင့် Invoice ပုံစံ'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('paper:$resets'),
            initialValue: paper,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('Paper size', 'စာရွက်အရွယ်အစား'),
            ),
            items: InvoicePrintSettings.papers.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: widget.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => paper = value);
                    }
                  },
          ),
          if (paper == 'custom')
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: width,
                    enabled: !widget.busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('Width (mm)', 'အကျယ် (mm)'),
                    ),
                    validator: (s) => dimension(s, 58, 216),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: height,
                    enabled: !widget.busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('Height (mm)', 'အမြင့် (mm)'),
                    ),
                    validator: (s) => dimension(s, 100, 1000),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('language:$resets'),
            initialValue: language,
            decoration: InputDecoration(
              labelText: _t('Invoice language', 'Invoice ဘာသာစကား'),
            ),
            items: [
              DropdownMenuItem(
                value: 'app',
                child: Text(_t('Same as app', 'App နှင့်တူညီမည်')),
              ),
              const DropdownMenuItem(value: 'en', child: Text('English')),
              const DropdownMenuItem(value: 'my', child: Text('မြန်မာ')),
            ],
            onChanged: widget.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => language = value);
                    }
                  },
          ),
          if (paper == 'a4')
            OutlinedButton.icon(
              key: const ValueKey('open-stationery-editor'),
              onPressed: widget.busy ? null : editStationery,
              icon: const Icon(Icons.tune),
              label: Text(
                _t('Edit header & footer', 'ခေါင်းစီးနှင့် အောက်ခြေ ပြင်ရန်'),
              ),
            ),
          OutlinedButton.icon(
            key: const ValueKey('open-print-designer'),
            onPressed: widget.busy ? null : design,
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: Text(
              _t(
                'Visual layout designer',
                'ပုံစံကို လွတ်လပ်စွာ ဒီဇိုင်းပြင်ရန်',
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('restore-original-mobile-voucher'),
            onPressed: widget.busy ? null : useOriginalMobileLayout,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
              _t(
                'Use original mobile print layout',
                'မူလ Mobile ဘောင်ချာပုံစံသုံးရန်',
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('layout:$resets'),
            initialValue: layout,
            decoration: InputDecoration(labelText: _t('Layout', 'ပုံစံ')),
            items: [
              if (template != null)
                DropdownMenuItem(
                  value: 'designer',
                  child: Text(
                    _t(
                      'Custom visual template',
                      'စိတ်ကြိုက် ဒီဇိုင်း Template',
                    ),
                  ),
                ),
              DropdownMenuItem(
                value: 'auto',
                child: Text(
                  _t(
                    'Original mobile print layout',
                    'မူလ Mobile ဘောင်ချာပုံစံ',
                  ),
                ),
              ),
              DropdownMenuItem(
                value: 'compact',
                child: Text(_t('Compact', 'ကျစ်လျစ်ပုံစံ')),
              ),
            ],
            onChanged: widget.busy
                ? null
                : (v) {
                    if (v != null) setState(() => layout = v);
                  },
          ),
          if ((paper == 'a4' && layout == 'auto') ||
              paper == 'receipt80' ||
              paper == 'receipt58')
            A4LayoutEditor(
              key: ValueKey('appearance:$paper:$resets'),
              receipt: paper != 'a4',
              value: a4,
              enabled: !widget.busy,
              onChanged: (v) => setState(() => a4 = v),
              onReset: () => setState(() {
                a4 = const A4LayoutSettings();
                resets++;
              }),
            ),
          option(
            'Show business logo',
            'လုပ်ငန်း Logo ပြမည်',
            logo,
            (v) => logo = v,
          ),
          option(
            'Show item photos',
            'ပစ္စည်းပုံ ပြမည်',
            photos,
            (v) => photos = v,
          ),
          option(
            'Show customer information',
            'ဝယ်သူအချက်အလက် ပြမည်',
            customer,
            (v) => customer = v,
          ),
          option(
            'Show branch information',
            'ဆိုင်ခွဲအချက်အလက် ပြမည်',
            branch,
            (v) => branch = v,
          ),
          option(
            'Show invoice date',
            'ဘောင်ချာရက် ပြမည်',
            date,
            (v) => date = v,
          ),
          option(
            'Show item code',
            'ပစ္စည်းကုဒ် ပြမည်',
            itemCode,
            (v) => itemCode = v,
          ),
          option(
            'Show unit price',
            'တစ်ခုဈေး ပြမည်',
            prices,
            (v) => prices = v,
          ),
          option(
            'Show discount',
            'လျှော့ဈေး ပြမည်',
            discount,
            (v) => discount = v,
          ),
          TextButton.icon(
            onPressed: widget.busy
                ? null
                : () => setState(() {
                    paper = 'receipt80';
                    language = 'app';
                    layout = 'auto';
                    logo = true;
                    photos = false;
                    customer = true;
                    branch = true;
                    date = true;
                    itemCode = true;
                    prices = true;
                    discount = true;
                    salePerson = true;
                    payments = true;
                    width.text = '80';
                    height.text = '200';
                    footer.clear();
                    a4 = const A4LayoutSettings();
                    resets++;
                  }),
            icon: const Icon(Icons.restart_alt),
            label: Text(
              _t(
                'Reset to default · then Save / Preview',
                'မူလအတိုင်းပြန်ထားရန် · ပြီးလျှင် Save / Preview နှိပ်ပါ',
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: salePerson,
            title: Text(_t('Show sale person', 'အရောင်းဝန်ထမ်းအမည် ဖော်ပြမည်')),
            onChanged: widget.busy
                ? null
                : (value) => setState(() => salePerson = value),
          ),
          TextFormField(
            controller: footer,
            enabled: !widget.busy,
            maxLength: 300,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: _t(
                'Footer / Thank-you note (optional)',
                'အောက်ခြေစာသား / ကျေးဇူးတင်စာ (မဖြစ်မနေမလို)',
              ),
            ),
            validator: (s) => (s?.trim().length ?? 0) > 300
                ? _t('Maximum 300 characters.', 'စာလုံး 300 အထိသာ ထည့်ပါ။')
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Stock quantities are never printed on customer invoices. Paid / credit due reflect the status when Preview is opened.',
              'Customer Invoice တွင် Stock လက်ကျန် မပါပါ။ Paid / Credit Due သည် နမူနာကြည့်ချိန် ငွေရှင်းအခြေအနေ ဖြစ်ပါသည်။',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'Receipt height adjusts automatically; very long receipts split into pages. Use Actual Size / 100% and match the printer paper. Uses system Print / Share; direct Bluetooth pairing is not included.',
              'Receipt အမြင့်ကို အလိုအလျောက်ချိန်မည်။ ရှည်လွန်းလျှင် စာမျက်နှာခွဲမည်။ Actual Size / 100% နှင့် စာရွက်အရွယ် တူအောင်ထားပါ။ System Print / Share သုံးမည်။ Bluetooth တိုက်ရိုက်ချိတ်ခြင်း မပါသေးပါ။',
            ),
          ),
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(widget.message!),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.busy ? null : submit,
            icon: const Icon(Icons.print_outlined),
            label: Text(
              widget.busy
                  ? _t('Please wait...', 'ခဏစောင့်ပါ…')
                  : widget.actionLabel,
            ),
          ),
        ],
      ),
    ),
  );
}
