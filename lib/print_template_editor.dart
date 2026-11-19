import 'voucher_pdf_preview.dart';
import 'app_capabilities.dart';
import 'live_pdf_preview.dart';
import 'invoice_pdf.dart';
import 'invoice_branch_header.dart';
import 'a4_layout_settings.dart';

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode/barcode.dart' as bc;

import 'app_database.dart';
import 'app_language.dart';
import 'business_logo_page.dart';
import 'desktop_ui.dart';
import 'print_template.dart';
import 'template_bindings.dart';
import 'template_pdf.dart';

class PrintTemplateEditorPage extends StatefulWidget {
  const PrintTemplateEditorPage({
    super.key,
    required this.initial,
    this.document,
    this.labelProduct,
    this.options = const {},
    this.onSave,
    this.logoBytes,
  });
  final PrintTemplate initial;
  final Map<String, Object?>? document, labelProduct;
  final Map<String, Object?> options;
  final Future<void> Function(PrintTemplate)? onSave;
  final Uint8List? logoBytes;
  @override
  State<PrintTemplateEditorPage> createState() =>
      _PrintTemplateEditorPageState();
}

class _PrintTemplateEditorPageState extends State<PrintTemplateEditorPage> {
  late PrintTemplate value;
  String? selected;
  double zoom = .7;
  bool grid = true, busy = false, showSidePreview = false, lockLogoRatio = true;
  String? error;
  Uint8List? logo;
  final undo = <PrintTemplate>[], redo = <PrintTemplate>[];
  final controllers = <String, TextEditingController>{};
  int bindingReset = 0;
  Map<String, Object?> document = {};
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  PrintElement? get element =>
      value.elements.where((e) => e.id == selected).firstOrNull;
  @override
  void initState() {
    super.initState();
    value = widget.initial;
    if (value.elements.isNotEmpty) selected = value.elements.first.id;
    syncFields();
    load();
  }

  Future<void> load() async {
    try {
      if (widget.document != null && widget.logoBytes != null) {
        setState(() {
          document = widget.document!;
          logo = widget.logoBytes;
        });
        return;
      }
      final db = await AppDatabase.instance.database;
      final business = await db.query('business_profile', where: 'id=1');
      final image = await BusinessLogoStore.read();
      final branchRows = await AppDatabase.instance.getBranches();
      if (!mounted) return;
      setState(() {
        logo = image;
        document =
            widget.document ??
            {
              'id': 1,
              'business_name': business.isEmpty
                  ? 'Business name'
                  : business.single['name'],
              'invoice_date': DateTime.now().toIso8601String().substring(0, 10),
              'customer_name': 'Sample customer',
              'customer_phone': '09 123 456 789',
              'customer_address': 'Sample address',
              'employee_name': 'Sample salesperson',
              'subtotal': 3000,
              'discount_amount': 0,
              'total': 3000,
              'paid': 3000,
              'balance_due': 0,
              'remark': 'Sample data — edit the layout, not invoice values.',
              'items': [
                {
                  'id': 1,
                  'item_code': 'SAMPLE-01',
                  'item_name': 'Sample item',
                  'qty': 2,
                  'price': 1000,
                  'amount': 2000,
                },
                {
                  'id': 2,
                  'item_code': 'SAMPLE-02',
                  'item_name': 'Another sample item',
                  'qty': 1,
                  'price': 1000,
                  'amount': 1000,
                },
              ],
            };
        document = Map<String, Object?>.from(document);
        document['print_branch_blocks'] = InvoiceBranchHeader.resolve(
          document,
          A4LayoutSettings.fromJson(
            Map<String, dynamic>.from(widget.options['a4'] as Map? ?? {}),
          ),
          branchRows,
        );
      });
    } catch (_) {
      if (mounted) setState(() => document = widget.document ?? {});
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get fields => {
    ...widget.initial.label
        ? TemplateBindings.item(
            widget.labelProduct ??
                {
                  'id': 1,
                  'item_code': 'SAMPLE-01',
                  'name': 'Sample item',
                  'barcode': 'SAMPLE-01',
                  'price': 1000,
                },
          )
        : TemplateBindings.invoice(document, widget.options),
    'page.number': '1',
    'page.count': '1',
  };
  List<Map<String, String>> get rows => [
    for (final row in document['items'] as List? ?? [])
      TemplateBindings.item(row as Map),
  ];
  void syncFields() {
    final e = element;
    if (e == null) return;
    for (final entry in <String, Object>{
      'text': e.text,
      'x': e.x,
      'y': e.y,
      'width': e.width,
      'height': e.height,
      'fontSize': e.fontSize,
      'fontFamily': e.fontFamily,
      'color': e.color.toRadixString(16).padLeft(8, '0'),
      'fill': e.fill.toRadixString(16).padLeft(8, '0'),
      'border': e.border,
      'rowHeight': e.rowHeight,
      'headerHeight': e.headerHeight,
    }.entries) {
      controllers.putIfAbsent(entry.key, () => TextEditingController()).text =
          entry.value.toString();
    }
  }

  void commit(PrintTemplate next, {bool history = true, bool sync = false}) {
    try {
      next.validate();
      if (history) {
        undo.add(value);
        if (undo.length > 40) undo.removeAt(0);
        redo.clear();
      }
      setState(() {
        value = next;
        error = null;
      });
      if (sync) syncFields();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  void change(
    Map<String, Object?> values, {
    bool history = true,
    bool sync = false,
  }) {
    final e = element;
    if (e == null) return;
    commit(
      value.copyWith(
        elements: [
          for (final old in value.elements)
            old.id == e.id ? old.withValues(values) : old,
        ],
      ),
      history: history,
      sync: sync,
    );
  }

  void choose(String id) {
    setState(() => selected = id);
    syncFields();
  }

  void add(String kind) {
    final margin = math.min(5.0, value.width / 20);
    final width = math.min(
      kind == 'table' ? 150.0 : 60.0,
      value.width - 2 * margin,
    );
    final height = math.min(
      kind == 'table'
          ? 80.0
          : kind == 'image' || kind == 'barcode'
          ? 25.0
          : kind == 'line'
          ? 0.5
          : 12.0,
      value.height - 2 * margin,
    );
    final e = PrintElement(
      id: PrintTemplate.newId(),
      kind: kind,
      x: margin,
      y: margin,
      width: width,
      height: height,
      text: kind == 'text'
          ? 'Text'
          : kind == 'barcode'
          ? (value.label ? '{item.barcode}' : '{invoice.number}')
          : '',
      border: kind == 'box' || kind == 'table' ? .2 : 0,
      rowHeight: math.min(8, height / 3),
      headerHeight: math.min(6, height / 3),
      columns: kind == 'table'
          ? const [
              PrintColumn(title: 'Item', expression: '{item.name}', weight: 3),
              PrintColumn(title: 'Qty', expression: '{item.qty}'),
              PrintColumn(
                title: 'Amount',
                expression: '{item.amount}',
                weight: 2,
              ),
            ]
          : const [],
    );
    selected = e.id;
    commit(value.copyWith(elements: [...value.elements, e]), sync: true);
  }

  void remove() {
    final id = selected;
    if (id == null) return;
    commit(
      value.copyWith(
        elements: value.elements.where((e) => e.id != id).toList(),
      ),
    );
    setState(() => selected = value.elements.firstOrNull?.id);
    syncFields();
  }

  void duplicate() {
    final e = element;
    if (e == null) return;
    final copy = e.withValues({
      'id': PrintTemplate.newId(),
      'x': math.min(e.x + 2, value.width - e.width),
      'y': math.min(e.y + 2, value.height - e.height),
    });
    selected = copy.id;
    commit(value.copyWith(elements: [...value.elements, copy]), sync: true);
  }

  void moveLayer(int delta) {
    final index = value.elements.indexWhere((e) => e.id == selected),
        target = value.elements.indexWhere((e) => e.id == selected) + delta;
    if (index < 0 || target < 0 || target >= value.elements.length) return;
    final layers = List<PrintElement>.from(value.elements);
    final e = layers.removeAt(index);
    layers.insert(target, e);
    commit(value.copyWith(elements: layers));
  }

  Future<void> pageSize() async {
    final w = TextEditingController(text: value.width.toString()),
        h = TextEditingController(text: value.height.toString()),
        name = TextEditingController(text: value.name);
    final form = GlobalKey<FormState>();
    final selected = await showDialog<bool>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(t('Paper and template', 'စာရွက်နှင့် Template')),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: InputDecoration(
                  labelText: t('Template name', 'Template အမည်'),
                ),
              ),
              for (final pair in [
                (w, t('Width (mm)', 'အကျယ် (mm)')),
                (h, t('Height (mm)', 'အမြင့် (mm)')),
              ])
                TextFormField(
                  controller: pair.$1,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: pair.$2),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    return n != null && n.isFinite && n > 0 && n <= 5000
                        ? null
                        : t(
                            'Enter a positive paper dimension',
                            'စာရွက်အရွယ်အစားအမှန် ထည့်ပါ',
                          );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialog, true);
            },
            child: Text(t('Apply', 'သတ်မှတ်ရန်')),
          ),
        ],
      ),
    );
    if (selected == true && mounted) {
      commit(
        value
            .resized(double.parse(w.text), double.parse(h.text))
            .copyWith(name: name.text.trim()),
        sync: true,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    w.dispose();
    h.dispose();
    name.dispose();
  }

  Future<void> image() async {
    if (element?.kind != 'image') return;
    final id = selected;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        throw StateError('Choose an image smaller than 20 MB');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        1200 / math.max(descriptor.width, descriptor.height),
      );
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      if (data == null) throw StateError('Could not read image');
      if (mounted && selected == id) {
        change({'imageBase64': base64Encode(data.buffer.asUint8List())});
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error =
              t('Could not load image: ', 'ပုံဖတ်မရပါ: ') + e.toString(),
        );
      }
    }
  }

  Future<void> columns() async {
    final e = element;
    if (e == null || e.kind != 'table') return;
    var entries = [for (final c in e.columns) (PrintTemplate.newId(), c)];
    final result = await showDialog<List<PrintColumn>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DesktopDialog(
          title: Text(t('Item table columns', 'ပစ္စည်းဇယား Column များ')),
          content: SizedBox(
            width: 800,
            height: 450,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final pair = entries[index];
                      void set(PrintColumn c) =>
                          update(() => entries[index] = (pair.$1, c));
                      final c = pair.$2;
                      return Card(
                        key: ValueKey(pair.$1),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: c.title,
                                      decoration: InputDecoration(
                                        labelText: t('Heading', 'ခေါင်းစဉ်'),
                                      ),
                                      onChanged: (v) => set(
                                        PrintColumn(
                                          title: v,
                                          expression: c.expression,
                                          weight: c.weight,
                                          align: c.align,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: index == 0
                                        ? null
                                        : () => update(() {
                                            final row = entries.removeAt(index);
                                            entries.insert(index - 1, row);
                                          }),
                                    icon: const Icon(
                                      Icons.arrow_upward,
                                      size: 16,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: entries.length < 2
                                        ? null
                                        : () => update(
                                            () => entries.removeAt(index),
                                          ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                              TextFormField(
                                initialValue: c.expression,
                                decoration: InputDecoration(
                                  labelText: t(
                                    'Value / binding, e.g. {item.name}',
                                    'တန်ဖိုး / Field ဥပမာ {item.name}',
                                  ),
                                ),
                                onChanged: (v) => set(
                                  PrintColumn(
                                    title: c.title,
                                    expression: v,
                                    weight: c.weight,
                                    align: c.align,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      initialValue: c.weight.toString(),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: t(
                                          'Relative width',
                                          'အကျယ်အချိုး',
                                        ),
                                      ),
                                      onChanged: (v) {
                                        final n = double.tryParse(v);
                                        if (n != null && n > 0) {
                                          set(
                                            PrintColumn(
                                              title: c.title,
                                              expression: c.expression,
                                              weight: n,
                                              align: c.align,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: c.align,
                                      items: [
                                        for (final v in [
                                          'left',
                                          'center',
                                          'right',
                                        ])
                                          DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          set(
                                            PrintColumn(
                                              title: c.title,
                                              expression: c.expression,
                                              weight: c.weight,
                                              align: v,
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                TextButton.icon(
                  onPressed: () => update(
                    () => entries.add((
                      PrintTemplate.newId(),
                      const PrintColumn(
                        title: 'Column',
                        expression: '{item.name}',
                      ),
                    )),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(t('Add column', 'Column ထည့်ရန်')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialog, entries.map((r) => r.$2).toList()),
              child: Text(t('Apply columns', 'Column များသတ်မှတ်ရန်')),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted && selected == e.id) {
      change({'columns': result.map((c) => c.toJson()).toList()});
    }
  }

  void addVoucherQr() {
    add('barcode');
    change({'text': '{invoice.qr}', 'qr': true}, sync: true);
  }

  Future<void> resetLayout() async {
    if (busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(
          t('Reset layout to default?', 'Layout ကို မူလပုံစံ ပြန်ထားမလား။'),
        ),
        content: Text(
          t(
            'This replaces the current design. Save the layout to use it for future prints. Undo is available before saving.',
            'လက်ရှိဒီဇိုင်းကို အစားထိုးမည်။ နောက်တစ်ခါ Print အတွက် Layout ကို သိမ်းပါ။ မသိမ်းမီ Undo ပြန်လုပ်နိုင်သည်။',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t('Reset layout', 'မူလပုံစံ ပြန်ယူရန်')),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final defaults = value.label
        ? PrintTemplate.barcodeLabel(width: value.width, height: value.height)
        : value.width <= 100
        ? PrintTemplate.receipt(width: value.width, height: value.height)
        : PrintTemplate.invoice(previous: value)
              .resized(value.width, value.height);
    selected = defaults.elements.firstOrNull?.id;
    commit(defaults, sync: true);
  }

  void addressColumns(bool two) {
    if (value.label) return;
    final old = value.elements
        .where(
          (e) => [
            'branches',
            'branch',
            'address-left',
            'address-right',
          ].contains(e.id),
        )
        .firstOrNull;
    final x = old?.x ?? 10.0, y = old?.y ?? 24.0;
    final w = old?.width ?? (value.width - 20), h = old?.height ?? 24.0;
    final address = PrintElement(
      id: 'address-left',
      kind: 'text',
      x: x,
      y: y,
      width: two ? (w - 4) / 2 : w,
      height: h,
      text: two ? '{branch.left}' : '{branch.info}',
      fontSize: old?.fontSize ?? 9,
    );
    selected = address.id;
    commit(
      value.copyWith(
        elements: [
          for (final e in value.elements)
            if (![
              'branches',
              'branch',
              'address-left',
              'address-right',
            ].contains(e.id))
              e,
          address,
          if (two)
            PrintElement(
              id: 'address-right',
              kind: 'text',
              x: x + (w + 4) / 2,
              y: y,
              width: (w - 4) / 2,
              height: h,
              text: '{branch.right}',
              fontSize: old?.fontSize ?? 9,
            ),
        ],
      ),
      sync: true,
    );
  }

  Widget sidePreview() {
    final template = value, data = fields, items = rows, image = logo;
    return LivePdfPreview(
      title: t('Print preview', 'Print Preview'),
      revision: jsonEncode([template.toJson(), data, items]),
      onClose: () => setState(() => showSidePreview = false),
      generate: () async {
        final result = await renderTemplatePdf(
          template: template,
          fields: data,
          rows: items,
          logo: image,
        );
        return GeneratedInvoicePdf(result.bytes, result.format);
      },
    );
  }

  Future<void> preview() async {
    setState(() => busy = true);
    try {
      final result = await renderTemplatePdf(
        template: value,
        fields: fields,
        rows: value.label ? [] : rows,
        logo: logo,
      );
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(
              title: Text(t('Actual PDF preview', 'တကယ့် PDF နမူနာ')),
            ),
            body: VoucherPdfPreview(
              bytes: result.bytes,
              format: result.format,
              name: 'template-preview.pdf',
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void validatePendingProperties() {
    final selectedElement = element;
    if (selectedElement == null) return;
    final values = <String, Object?>{};
    for (final key in [
      'x',
      'y',
      'width',
      'height',
      'fontSize',
      'border',
      'rowHeight',
      'headerHeight',
    ]) {
      final number = double.tryParse(controllers[key]?.text ?? '');
      if (number == null || !number.isFinite) {
        throw FormatException('Enter a valid number for $key');
      }
      values[key] = number;
    }
    for (final key in ['color', 'fill']) {
      final color = int.tryParse(
        (controllers[key]?.text ?? '').replaceAll('#', ''),
        radix: 16,
      );
      if (color == null) {
        throw FormatException('Enter a valid hexadecimal color for $key');
      }
      values[key] = (controllers[key]!.text.replaceAll('#', '').length <= 6)
          ? 0xff000000 | color
          : color;
    }
    values['text'] = controllers['text']?.text ?? selectedElement.text;
    values['fontFamily'] =
        controllers['fontFamily']?.text ?? selectedElement.fontFamily;
    final next = value.copyWith(
      elements: [
        for (final e in value.elements)
          e.id == selectedElement.id ? e.withValues(values) : e,
      ],
    );
    next.validate();
    value = next;
  }

  bool leaving = false;
  bool get changed =>
      jsonEncode(value.toJson()) != jsonEncode(widget.initial.toJson());
  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      validatePendingProperties();
      value.validate();
      await widget.onSave?.call(value);
      if (!mounted) return;
      setState(() => leaving = true);
      Navigator.pop(context, value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    if (busy) return;
    final answer = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t('Save layout changes?', 'ပုံစံပြင်ဆင်မှုကို သိမ်းမလား။')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'keep'),
            child: Text(t('Keep editing', 'ဆက်ပြင်မည်')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'discard'),
            child: Text(t('Discard', 'မသိမ်းပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, 'save'),
            child: Text(t('Save', 'သိမ်းမည်')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (answer == 'save') {
      await save();
      return;
    }
    if (answer == 'discard') {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  Widget palette() => ListView(
    padding: const EdgeInsets.all(10),
    children: [
      if (!value.label)
        OutlinedButton.icon(
          onPressed: busy ? null : addVoucherQr,
          icon: const Icon(Icons.qr_code_2),
          label: Text(t('Voucher QR', 'ဘောင်ချာ QR')),
        ),
      Text(
        t('Add element', 'အပိုင်းထည့်ရန်'),
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final pair in [
        (
          'text',
          Icons.text_fields,
          t('Text / Data field', 'စာသား / Data Field'),
        ),
        ('image', Icons.image_outlined, t('Logo / Image', 'Logo / ပုံ')),
        ('line', Icons.horizontal_rule, t('Line', 'မျဉ်း')),
        ('box', Icons.crop_square, t('Box', 'အကွက်')),
        ('barcode', Icons.qr_code_2, t('Barcode / QR', 'Barcode / QR')),
        if (!value.label)
          ('table', Icons.table_chart_outlined, t('Item table', 'ပစ္စည်းဇယား')),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => add(pair.$1),
            icon: Icon(pair.$2, size: 17),
            label: Text(pair.$3),
          ),
        ),
      const Divider(),
      Text(t('Layers', 'အလွှာများ')),
      for (final e in value.elements)
        ListTile(
          dense: true,
          selected: e.id == selected,
          title: Text(
            '${e.kind} · ${e.text.isEmpty ? e.id : e.text}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Icon(
            e.locked ? Icons.lock_outline : Icons.layers_outlined,
            size: 16,
          ),
          onTap: () => choose(e.id),
        ),
    ],
  );
  Widget properties() {
    final e = element;
    if (e == null) {
      return Center(child: Text(t('Select an element', 'အပိုင်းတစ်ခုရွေးပါ')));
    }
    Widget field(
      String key,
      String label, {
      bool numeric = false,
      int lines = 1,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        key: ValueKey('template-property-$key'),
        controller: controllers[key],
        enabled: !busy,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.multiline,
        maxLines: lines,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          if (numeric) {
            final n = double.tryParse(v);
            if (n != null) {
              change({
                key: n,
                if (e.kind == 'image' && lockLogoRatio && key == 'width')
                  'height': n * e.height / e.width,
                if (e.kind == 'image' && lockLogoRatio && key == 'height')
                  'width': n * e.width / e.height,
              });
              if (e.kind == 'image' &&
                  lockLogoRatio &&
                  ['width', 'height'].contains(key)) {
                final other = key == 'width' ? 'height' : 'width';
                controllers[other]?.text =
                    (other == 'width' ? element!.width : element!.height)
                        .toString();
              }
            }
          } else if (['color', 'fill'].contains(key)) {
            final color = int.tryParse(v.replaceAll('#', ''), radix: 16);
            if (color != null) {
              change({
                key: v.replaceAll('#', '').length <= 6
                    ? 0xff000000 | color
                    : color,
              });
            }
          } else {
            change({key: v});
          }
        },
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          t('Selected: ', 'ရွေးထားသည်: ') + e.kind,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: t('Duplicate', 'ပွားရန်'),
              onPressed: busy ? null : duplicate,
              icon: const Icon(Icons.copy, size: 18),
            ),
            IconButton(
              tooltip: t('Delete', 'ဖယ်ရန်'),
              onPressed: busy ? null : remove,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
            IconButton(
              tooltip: t('Layer up', 'အပေါ်အလွှာ'),
              onPressed: busy ? null : () => moveLayer(1),
              icon: const Icon(Icons.flip_to_front, size: 18),
            ),
            IconButton(
              tooltip: t('Layer down', 'အောက်အလွှာ'),
              onPressed: busy ? null : () => moveLayer(-1),
              icon: const Icon(Icons.flip_to_back, size: 18),
            ),
          ],
        ),
        if (e.kind == 'image')
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('Lock aspect ratio', 'အချိုးအစား မပြောင်းရန်')),
            value: lockLogoRatio,
            onChanged: busy
                ? null
                : (v) => setState(() => lockLogoRatio = v ?? true),
          ),
        for (final p in [
          ('x', 'X (mm)'),
          ('y', 'Y (mm)'),
          ('width', t('Width (mm)', 'အကျယ် (mm)')),
          ('height', t('Height (mm)', 'အမြင့် (mm)')),
        ])
          field(p.$1, p.$2, numeric: true),
        if (e.kind == 'text' || e.kind == 'barcode') ...[
          field(
            'text',
            t('Text and bindings', 'စာသားနှင့် Field များ'),
            lines: 3,
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${e.id}-binding-$bindingReset'),
            decoration: InputDecoration(
              labelText: t('Insert data field', 'Data Field ထည့်ရန်'),
            ),
            items: [
              for (final key
                  in value.label
                      ? TemplateBindings.itemFields
                      : [
                          ...TemplateBindings.invoiceFields,
                          ...TemplateBindings.itemFields,
                        ])
                DropdownMenuItem(
                  value: key,
                  child: Text(key, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (binding) {
              if (binding == null) return;
              final c = controllers['text']!;
              final offset = c.selection.isValid
                  ? c.selection.start
                  : c.text.length;
              final text =
                  '${c.text.substring(0, offset)}{$binding}${c.text.substring(offset)}';
              c.text = text;
              change({'text': text});
              setState(() => bindingReset++);
            },
          ),
        ],
        if (e.kind == 'text' || e.kind == 'table') ...[
          field(
            'fontSize',
            t('Font size (pt)', 'စာလုံးအရွယ် (pt)'),
            numeric: true,
          ),
          field(
            'fontFamily',
            t('Font family · blank = system', 'Font အမည် · အလွတ်ဆို System'),
          ),
          Row(
            children: [
              Checkbox(
                value: e.bold,
                onChanged: busy ? null : (v) => change({'bold': v ?? false}),
              ),
              Text(t('Bold', 'စာလုံးထူ')),
              Checkbox(
                value: e.italic,
                onChanged: busy ? null : (v) => change({'italic': v ?? false}),
              ),
              Text(t('Italic', 'စာလုံးစောင်း')),
            ],
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${e.id}-${e.align}'),
            initialValue: e.align,
            decoration: InputDecoration(
              labelText: t('Alignment', 'စာသားညှိရန်'),
            ),
            items: [
              for (final v in ['left', 'center', 'right'])
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) {
              if (v != null) change({'align': v});
            },
          ),
          Row(
            children: [
              Checkbox(
                value: e.fitText,
                onChanged: (v) => change({'fitText': v ?? true}),
              ),
              Expanded(
                child: Text(
                  t(
                    'Fit text inside element',
                    'စာသားကို အကွက်အတွင်း ဆံ့အောင်ညှိရန်',
                  ),
                ),
              ),
            ],
          ),
        ],
        field(
          'color',
          t('Text / line color · ARGB hex', 'စာသား/မျဉ်းအရောင် · ARGB hex'),
        ),
        field('fill', t('Background · ARGB hex', 'နောက်ခံအရောင် · ARGB hex')),
        field('border', t('Border (mm)', 'ဘောင်အထူ (mm)'), numeric: true),
        if (e.kind == 'image') ...[
          OutlinedButton.icon(
            onPressed: busy ? null : image,
            icon: const Icon(Icons.upload_file),
            label: Text(t('Choose image', 'ပုံရွေးရန်')),
          ),
          TextButton(
            onPressed: () => change({'imageBase64': ''}),
            child: Text(t('Use business logo', 'လုပ်ငန်း Logo သုံးရန်')),
          ),
        ],
        if (e.kind == 'barcode')
          Row(
            children: [
              Checkbox(
                value: e.qr,
                onChanged: (v) => change({'qr': v ?? false}),
              ),
              Text(t('QR mode', 'QR ပုံစံ')),
            ],
          ),
        if (e.kind == 'table') ...[
          field(
            'rowHeight',
            t('Row height (mm)', 'အကြောင်းအမြင့် (mm)'),
            numeric: true,
          ),
          field(
            'headerHeight',
            t('Header height (mm)', 'ခေါင်းစဉ်အမြင့် (mm)'),
            numeric: true,
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : columns,
            icon: const Icon(Icons.view_column_outlined),
            label: Text(t('Edit columns', 'Column များပြင်ရန်')),
          ),
        ],
        if (e.kind != 'table')
          Row(
            children: [
              Checkbox(
                value: e.lastPageOnly,
                onChanged: (v) => change({'lastPageOnly': v ?? false}),
              ),
              Expanded(
                child: Text(t('Last page only', 'နောက်ဆုံးစာမျက်နှာတွင်သာ')),
              ),
            ],
          ),
        Row(
          children: [
            Checkbox(
              value: e.locked,
              onChanged: (v) => change({'locked': v ?? false}),
            ),
            Text(t('Lock position', 'နေရာမရွှေ့ရန်')),
          ],
        ),
      ],
    );
  }

  Widget elementView(PrintElement e, double scale) {
    final fs = fields;
    final color = Color(e.color);
    if (e.kind == 'text') {
      return CustomPaint(
        painter: _TemplateTextPainter(
          e,
          TemplateBindings.resolve(e.text, fs),
          scale,
        ),
      );
    }
    if (e.kind == 'image') {
      try {
        final data = e.imageBase64.isEmpty ? logo : base64Decode(e.imageBase64);
        return data == null || data.isEmpty
            ? const Center(child: Icon(Icons.image_outlined))
            : Image.memory(
                data,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) =>
                    const Icon(Icons.broken_image_outlined),
              );
      } catch (_) {
        return const Icon(Icons.broken_image_outlined);
      }
    }
    if (e.kind == 'barcode') {
      if (e.text == '{invoice.qr}' &&
          TemplateBindings.resolve(e.text, fs).isEmpty) {
        return const Center(
          child: Text(
            'QR after confirmation',
            style: TextStyle(fontSize: 9, color: Colors.black),
          ),
        );
      }
      return CustomPaint(
        painter: _TemplateBarcodePainter(
          TemplateBindings.resolve(e.text, fs),
          e.qr,
        ),
      );
    }
    if (e.kind == 'line') return ColoredBox(color: color);
    if (e.kind == 'table') {
      final total = e.columns.fold<double>(0, (n, c) => n + c.weight);
      final capacity = ((e.height - e.headerHeight) / e.rowHeight).floor();
      final values = rows.take(capacity).toList();
      Widget row(Map<String, String> data, bool header, int index) => SizedBox(
        height: (header ? e.headerHeight : e.rowHeight) * scale,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in e.columns)
              SizedBox(
                width: e.width * scale * c.weight / total,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: header
                        ? const Color(0xffedf2f7)
                        : Colors.transparent,
                    border: Border.all(
                      color: Color(e.borderColor),
                      width: math.max(.2, e.border * scale),
                    ),
                  ),
                  child: CustomPaint(
                    painter: _TemplateTextPainter(
                      e.withValues({
                        'width': e.width * c.weight / total,
                        'height': header ? e.headerHeight : e.rowHeight,
                        'align': c.align,
                        'bold': header || e.bold,
                      }),
                      header
                          ? c.title
                          : TemplateBindings.resolve(c.expression, {
                              ...fields,
                              ...data,
                              'item.no': (index + 1).toString(),
                            }),
                      scale,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      return Column(
        children: [
          if (e.headerHeight > 0) row({}, true, 0),
          for (var i = 0; i < values.length; i++) row(values[i], false, i),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget canvas() => LayoutBuilder(
    builder: (context, box) {
      final scale = 3.0 * zoom;
      Widget layer(PrintElement e) => Positioned(
        left: e.x * scale,
        top: e.y * scale,
        width: e.width * scale,
        height: e.height * scale,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => choose(e.id),
          onPanStart: busy || e.locked
              ? null
              : (_) {
                  choose(e.id);
                  undo.add(value);
                  if (undo.length > 40) undo.removeAt(0);
                  redo.clear();
                },
          onPanUpdate: busy || e.locked
              ? null
              : (details) {
                  final current = element;
                  if (current == null) return;
                  double snap(double v) => grid ? (v * 2).round() / 2 : v;
                  final x = snap(
                        (current.x + details.delta.dx / scale).clamp(
                          0.0,
                          value.width - current.width,
                        ),
                      ),
                      y = snap(
                        (current.y + details.delta.dy / scale).clamp(
                          0.0,
                          value.height - current.height,
                        ),
                      );
                  change({
                    'x': x.clamp(0.0, value.width - current.width),
                    'y': y.clamp(0.0, value.height - current.height),
                  }, history: false);
                },
          onPanEnd: (_) => syncFields(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(e.fill),
              border: Border.all(
                color: e.id == selected
                    ? Colors.blue
                    : Color(e.borderColor)
                          .withValues(alpha: e.border > 0 ? 1 : 0),
                width: e.id == selected ? 1.5 : e.border * scale,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: elementView(e, scale)),
                if (e.id == selected && !e.locked)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: GestureDetector(
                        key: ValueKey('template-resize-${e.id}'),
                        behavior: HitTestBehavior.opaque,
                        onPanStart: busy
                            ? null
                            : (_) {
                                undo.add(value);
                                redo.clear();
                              },
                        onPanUpdate: busy
                            ? null
                            : (d) {
                                final current = element;
                                if (current == null) return;
                                var w = (current.width + d.delta.dx / scale)
                                    .clamp(1.0, value.width - current.x);
                                var h = (current.height + d.delta.dy / scale)
                                    .clamp(1.0, value.height - current.y);
                                if (current.kind == 'image' && lockLogoRatio) {
                                  final ratio = current.height / current.width;
                                  w = w.clamp(
                                    1.0,
                                    math.min(
                                      value.width - current.x,
                                      (value.height - current.y) / ratio,
                                    ),
                                  );
                                  h = w * ratio;
                                }
                                change({
                                  'width': w,
                                  'height': h,
                                }, history: false);
                              },
                        onPanEnd: (_) => syncFields(),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            border: Border.all(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final paper = SizedBox(
        width: value.width * scale,
        height: value.height * scale,
        child: ColoredBox(
          color: Colors.white,
          child: Stack(
            children: [
              if (grid)
                Positioned.fill(
                  child: CustomPaint(painter: _TemplateGrid(scale)),
                ),
              for (final e in value.elements) layer(e),
            ],
          ),
        ),
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(24), child: paper),
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final desktop = box.maxWidth >= 1000;
      final toolbar = Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : pageSize,
            icon: const Icon(Icons.description_outlined, size: 17),
            label: Text(
              '${value.width.toStringAsFixed(1)} × ${value.height.toStringAsFixed(1)} mm',
            ),
          ),
          IconButton(
            tooltip: t('Undo', 'နောက်တစ်ဆင့်ပြန်ရန်'),
            onPressed: busy || undo.isEmpty
                ? null
                : () {
                    redo.add(value);
                    setState(() => value = undo.removeLast());
                    syncFields();
                  },
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: t('Redo', 'ပြန်လုပ်ရန်'),
            onPressed: busy || redo.isEmpty
                ? null
                : () {
                    undo.add(value);
                    setState(() => value = redo.removeLast());
                    syncFields();
                  },
            icon: const Icon(Icons.redo),
          ),
          SizedBox(
            width: 150,
            child: Slider(
              value: zoom,
              min: .2,
              max: 2,
              onChanged: (v) => setState(() => zoom = v),
            ),
          ),
          Text('${(zoom * 100).round()}%'),
          Checkbox(
            value: grid,
            onChanged: (v) => setState(() => grid = v ?? false),
          ),
          Text(t('Grid', 'Grid')),
          OutlinedButton.icon(
            key: const ValueKey('template-reset'),
            onPressed: busy ? null : resetLayout,
            icon: const Icon(Icons.restart_alt, size: 17),
            label: Text(t('Reset to Default', 'မူလပုံစံ ပြန်ယူရန်')),
          ),
          if (!value.label)
            PopupMenuButton<bool>(
              tooltip: t('Address layout', 'လိပ်စာပုံစံ'),
              onSelected: addressColumns,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: false,
                  child: Text(t('One-column address', 'လိပ်စာ တစ်ကော်လံ')),
                ),
                PopupMenuItem(
                  value: true,
                  child: Text(t('Two-column address', 'လိပ်စာ နှစ်ကော်လံ')),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t('Address layout', 'လိပ်စာပုံစံ')),
                    const Icon(Icons.arrow_drop_down, size: 17),
                  ],
                ),
              ),
            ),
          if (desktop)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t('Print preview', 'Print Preview')),
                Switch(
                  key: const ValueKey('template-preview-toggle'),
                  value: showSidePreview,
                  onChanged: (v) => setState(() => showSidePreview = v),
                ),
              ],
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : preview,
            icon: const Icon(Icons.picture_as_pdf, size: 17),
            label: Text(t('PDF preview', 'PDF နမူနာ')),
          ),
          FilledButton.icon(
            onPressed: busy ? null : save,
            icon: const Icon(Icons.save_outlined, size: 17),
            label: Text(
              value.label
                  ? t('Save template', 'Template သိမ်းရန်')
                  : t('Save Layout', 'Layout သိမ်းရန်'),
            ),
          ),
        ],
      );
      final body = Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer
                  .withValues(alpha: .3),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: toolbar,
          ),
          if (widget.document == null && widget.labelProduct == null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                t(
                  'Design preview uses sample items. PDF preview shows the exact print layout.',
                  'နမူနာပစ္စည်းများဖြင့် ပုံစံပြထားသည်။ PDF preview တွင် တကယ်ထုတ်မည့် Layout ကိုကြည့်ပါ။',
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: desktop
                ? Row(
                    children: [
                      SizedBox(width: 170, child: palette()),
                      const VerticalDivider(width: 1),
                      Expanded(child: canvas()),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 285,
                        child: showSidePreview && box.maxWidth < 1300
                            ? Column(
                                children: [
                                  Expanded(child: properties()),
                                  SizedBox(
                                    height: box.maxHeight * .35,
                                    child: sidePreview(),
                                  ),
                                ],
                              )
                            : properties(),
                      ),
                      if (showSidePreview && box.maxWidth >= 1300)
                        SizedBox(
                          width: 300,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: sidePreview(),
                          ),
                        ),
                    ],
                  )
                : TabBarView(children: [canvas(), palette(), properties()]),
          ),
        ],
      );
      return PopScope(
        canPop: leaving || (!busy && !changed),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) leave();
        },
        child: DefaultTabController(
          length: 3,
          child: DesktopScaffold(
            appBar: AppBar(
              title: Text(
                value.label
                    ? t('Label layout designer', 'Label ပုံစံဒီဇိုင်း')
                    : t('Print Layout Editor', 'Print Layout ပြင်ရန်'),
              ),
              bottom: desktop
                  ? null
                  : TabBar(
                      tabs: [
                        Tab(text: t('Design', 'ဒီဇိုင်း')),
                        Tab(text: t('Elements', 'အပိုင်းများ')),
                        Tab(text: t('Properties', 'ပြင်ဆင်ရန်')),
                      ],
                    ),
            ),
            body: body,
          ),
        ),
      );
    },
  );
}

class _TemplateGrid extends CustomPainter {
  const _TemplateGrid(this.scale);
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xffe7ecf1)
      ..strokeWidth = .5;
    for (double x = 0; x < size.width; x += 5 * scale) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 5 * scale) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_TemplateGrid old) => old.scale != scale;
}

class _TemplateTextPainter extends CustomPainter {
  const _TemplateTextPainter(this.element, this.text, this.scale);
  final PrintElement element;
  final String text;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    final e = element;
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: e.fontFamily.isEmpty
              ? (AppCapabilities.windows ? 'Segoe UI' : null)
              : e.fontFamily,
          fontFamilyFallback: const [
            'Myanmar Text',
            'Noto Sans Myanmar',
            'Segoe UI',
          ],
          fontSize: e.fontSize * scale / PdfPageFormat.mm,
          height: 1.15,
          color: Color(e.color),
          fontWeight: e.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: e.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: e.align == 'right'
          ? TextAlign.right
          : e.align == 'center'
          ? TextAlign.center
          : TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: size.width, maxWidth: size.width);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (e.fitText && p.height > size.height) {
      final fit = size.height / p.height;
      canvas.translate(
        e.align == 'right'
            ? size.width * (1 - fit)
            : e.align == 'center'
            ? size.width * (1 - fit) / 2
            : 0,
        0,
      );
      canvas.scale(fit);
    }
    p.paint(canvas, Offset.zero);
    canvas.restore();
    p.dispose();
  }

  @override
  bool shouldRepaint(_TemplateTextPainter old) => true;
}

class _TemplateBarcodePainter extends CustomPainter {
  const _TemplateBarcodePainter(this.value, this.qr);
  final String value;
  final bool qr;
  @override
  void paint(Canvas canvas, Size size) {
    try {
      final code = qr ? bc.Barcode.qrCode() : bc.Barcode.code128();
      final paint = Paint()..color = Colors.black;
      final quiet = qr ? 0.0 : size.width * .07;
      for (final part in code.make(
        value,
        width: size.width - quiet * 2,
        height: size.height,
        drawText: false,
      )) {
        if (part is bc.BarcodeBar && part.black) {
          canvas.drawRect(
            Rect.fromLTWH(part.left + quiet, part.top, part.width, part.height),
            paint,
          );
        }
      }
    } catch (_) {
      final p = TextPainter(
        text: const TextSpan(
          text: 'Barcode / QR',
          style: TextStyle(color: Colors.red, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      p.paint(canvas, Offset.zero);
      p.dispose();
    }
  }

  @override
  bool shouldRepaint(_TemplateBarcodePainter old) =>
      old.value != value || old.qr != qr;
}
