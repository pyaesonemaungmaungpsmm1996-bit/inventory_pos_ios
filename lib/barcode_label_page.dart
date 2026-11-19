import 'voucher_pdf_preview.dart';
import 'print_template.dart';
import 'print_template_editor.dart';
import 'template_bindings.dart';
import 'template_pdf.dart';
import 'desktop_ui.dart';

import 'dart:convert';

import 'portable_preferences.dart';

import 'pos_ui.dart';

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_currency.dart';
import 'app_language.dart';
import 'barcode_rules.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _itemCode(Map<String, Object?> product) =>
    product['item_code'] as String? ??
    BarcodeRules.itemCode(product['id'] as int);

class BarcodeLabelSelection {
  const BarcodeLabelSelection({required this.product, required this.count});
  final Map<String, Object?> product;
  final int count;
  static int validate(List<BarcodeLabelSelection> values) {
    if (values.isEmpty) throw ArgumentError('Select at least one item');
    var total = 0;
    final ids = <Object?>{};
    for (final row in values) {
      if (row.count < 1 || row.count > 10000 || !ids.add(row.product['id'])) {
        throw ArgumentError('Check label quantities and duplicate items');
      }
      total += row.count;
    }
    if (total > 10000) {
      throw ArgumentError(
        'Split more than 10000 labels into separate print jobs',
      );
    }
    return total;
  }
}

class BarcodeLabelPage extends StatefulWidget {
  const BarcodeLabelPage({super.key, required this.product, this.batch});
  final Map<String, Object?> product;
  final List<BarcodeLabelSelection>? batch;
  @override
  State<BarcodeLabelPage> createState() => _BarcodeLabelPageState();
}

class _BarcodeLabelPageState extends State<BarcodeLabelPage> {
  final form = GlobalKey<FormState>();
  final width = TextEditingController(text: '50');
  final height = TextEditingController(text: '30');
  final count = TextEditingController(text: '1');
  String size = '50x30', paper = 'roll';
  int labelsAcross = 1;
  final labelGap = TextEditingController(text: '2'),
      labelMargin = TextEditingController(text: '0');
  PrintTemplate? template;
  String nameAlign = 'center', barcodeAlign = 'center', bottomAlign = 'center';
  double offsetX = 0, offsetY = 0;
  String savedAlign(Object? value) =>
      ['left', 'center', 'right'].contains(value) ? value as String : 'center';
  double savedOffset(Object? value) {
    final n = value is num ? value.toDouble() : 0.0;
    return n.isFinite ? n.clamp(-1.0, 1.0).toDouble() : 0.0;
  }

  Widget alignmentOption(
    String label,
    String value,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$resets:$value'),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: 'left', child: Text(_t('Left', 'ဘယ်'))),
      DropdownMenuItem(value: 'center', child: Text(_t('Center', 'အလယ်'))),
      DropdownMenuItem(value: 'right', child: Text(_t('Right', 'ညာ'))),
    ],
    onChanged: busy
        ? null
        : (v) {
            if (v != null) setState(() => change(v));
          },
  );
  Widget offsetOption(
    String label,
    double value,
    ValueChanged<double> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ${value.toStringAsFixed(1)} mm'),
      Slider(
        value: value,
        min: -1,
        max: 1,
        divisions: 20,
        label: '${value.toStringAsFixed(1)} mm',
        onChanged: busy || template != null
            ? null
            : (v) => setState(() => change(v)),
      ),
    ],
  );
  bool showPrice = true,
      busy = false,
      showName = true,
      showCode = true,
      showNumber = true,
      showVariant = true,
      qr = false;
  int resets = 0;
  @override
  void initState() {
    super.initState();
    loadDefaults();
  }

  Future<void> loadDefaults() async {
    try {
      final raw = await PortablePreferences.read('label_options_v2');
      if (raw == null || !mounted) return;
      final v = jsonDecode(raw) as Map;
      final w = double.tryParse('${v['width']}'),
          h = double.tryParse('${v['height']}');
      if (w == null ||
          h == null ||
          !w.isFinite ||
          !h.isFinite ||
          w < (v['template'] is Map ? 5 : 25) ||
          w > (v['template'] is Map ? 1000 : 120) ||
          h < (v['template'] is Map ? 5 : 15) ||
          h > (v['template'] is Map ? 1000 : 80) ||
          !['roll', 'a4'].contains(v['paper']) ||
          [
            'price',
            'name',
            'code',
            'number',
            'variant',
            'qr',
          ].any((k) => v[k] is! bool)) {
        return;
      }
      setState(() {
        if (v['template'] is Map) {
          final restored = PrintTemplate.fromJson(v['template'] as Map);
          restored.validate();
          template = restored;
        }
        size = 'custom';
        width.text = '$w';
        height.text = '$h';
        paper = v['paper'] as String;
        showPrice = v['price'] as bool;
        showName = v['name'] as bool;
        showCode = v['code'] as bool;
        showNumber = v['number'] as bool;
        labelsAcross = v['across'] == 2 ? 2 : 1;
        labelGap.text = (v['gap'] ?? 2).toString();
        labelMargin.text = (v['margin'] ?? 0).toString();
        showVariant = v['variant'] as bool;
        qr = v['qr'] as bool;
        nameAlign = savedAlign(v['nameAlign']);
        barcodeAlign = savedAlign(v['barcodeAlign']);
        bottomAlign = savedAlign(v['bottomAlign']);
        offsetX = savedOffset(v['offsetX']);
        offsetY = savedOffset(v['offsetY']);
        resets++;
      });
    } catch (_) {
      /* Invalid preferences leave defaults usable. */
    }
  }

  Future<void> saveDefaults() async {
    if (!form.currentState!.validate()) return;
    await PortablePreferences.write(
      'label_options_v2',
      jsonEncode({
        if (template != null) 'template': template!.toJson(),
        'width': width.text,
        'height': height.text,
        'paper': paper,
        'across': labelsAcross,
        'gap': labelGap.text,
        'margin': labelMargin.text,
        'price': showPrice,
        'name': showName,
        'code': showCode,
        'number': showNumber,
        'variant': showVariant,
        'qr': qr,
        'nameAlign': nameAlign,
        'barcodeAlign': barcodeAlign,
        'bottomAlign': bottomAlign,
        'offsetX': offsetX,
        'offsetY': offsetY,
      }),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('Label settings saved', 'Label ဆက်တင် သိမ်းပြီး')),
        ),
      );
    }
  }

  Widget option(String title, bool value, void Function(bool) change) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        value: value,
        onChanged: busy ? null : (v) => setState(() => change(v)),
      );
  String? error;
  @override
  void dispose() {
    labelGap.dispose();
    labelMargin.dispose();
    width.dispose();
    height.dispose();
    count.dispose();
    super.dispose();
  }

  Future<void> design() async {
    if (busy || !form.currentState!.validate()) return;
    final initial =
        template ??
        PrintTemplate.barcodeLabel().resized(
          double.parse(width.text),
          double.parse(height.text),
        );
    await Navigator.push<PrintTemplate>(
      context,
      MaterialPageRoute(
        builder: (_) => PrintTemplateEditorPage(
          initial: initial,
          labelProduct: widget.product,
          onSave: (selected) async {
            if (!mounted) throw StateError('Label settings page closed');
            setState(() {
              template = selected;
              size = 'custom';
              width.text = selected.width.toString();
              height.text = selected.height.toString();
              resets++;
            });
            await saveDefaults();
          },
        ),
      ),
    );
  }

  Future<void> preview() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final w = double.parse(width.text.trim());
      final h = double.parse(height.text.trim());
      final n = int.parse(count.text.trim());
      final barcode =
          widget.product['barcode'] as String? ?? _itemCode(widget.product);
      final minimum = BarcodeRules.minimumLabelWidthMm(barcode);
      if (template == null && !qr && w < minimum) {
        setState(
          () => error = _t(
            'This barcode needs a label at least ${minimum.ceil()} mm wide. Choose a wider label.',
            'ဤ Barcode အတွက် Label အကျယ် အနည်းဆုံး ${minimum.ceil()} mm လိုပါသည်။ ပိုကျယ်သော Label ရွေးပါ။',
          ),
        );
        return;
      }
      final bytes = await buildBarcodeLabels(
        product: widget.product,
        batch: widget.batch,
        template: template,
        widthMm: w,
        heightMm: h,
        count: n,
        showPrice: showPrice,
        a4: paper == 'a4',
        labelsAcross: labelsAcross,
        gapMm: double.tryParse(labelGap.text) ?? 2,
        marginMm: double.tryParse(labelMargin.text) ?? 0,
        showName: showName,
        showCode: showCode,
        showNumber: showNumber,
        showVariant: showVariant,
        qr: qr,
        nameAlign: nameAlign,
        barcodeAlign: barcodeAlign,
        bottomAlign: bottomAlign,
        offsetXmm: offsetX,
        offsetYmm: offsetY,
      );
      await saveDefaults();
      if (!mounted) return;
      final format = paper == 'a4'
          ? PdfPageFormat.a4
          : PdfPageFormat(
              (w * labelsAcross +
                      (double.tryParse(labelGap.text) ?? 2) *
                          (labelsAcross - 1) +
                      2 * (double.tryParse(labelMargin.text) ?? 0)) *
                  PdfPageFormat.mm,
              (h + 2 * (double.tryParse(labelMargin.text) ?? 0)) *
                  PdfPageFormat.mm,
            );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(
              title: Text(_t('Barcode Label Preview', 'Barcode Label နမူနာ')),
            ),
            body: VoucherPdfPreview(
              bytes: bytes,
              format: format,
              name: widget.batch == null ? 'labels.pdf' : 'batch-labels.pdf',
            ),
          ),
        ),
      );
    } catch (cause) {
      if (mounted) {
        setState(
          () => error = _t(
            'Could not create labels. Hide optional text or choose a larger size, then retry. $cause',
            'Label မဖန်တီးနိုင်ပါ။ စာသားအချို့ဖျောက်ပါ သို့မဟုတ် ပိုကြီးသော Label ရွေးပြီး ပြန်စမ်းပါ။ $cause',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  String? dimension(String? text, double min, double max) {
    final value = double.tryParse(text?.trim() ?? '');
    return value == null || !value.isFinite || value < min || value > max
        ? _t('Enter $min–$max mm.', '$min–$max mm အတွင်း ထည့်ပါ။')
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: DesktopScaffold(
      appBar: AppBar(
        title: Text(_t('Print Barcode Labels', 'Barcode Label ထုတ်ရန်')),
      ),
      body: Form(
        key: form,
        child: DesktopListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.batch == null
                  ? widget.product['name'] as String
                  : _t('Selected items: ', 'ရွေးထားသောပစ္စည်း: ') +
                        widget.batch!.length.toString(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(_itemCode(widget.product)),
            SelectableText(
              widget.product['barcode'] as String? ?? _itemCode(widget.product),
            ),
            MoneyText(widget.product['price'] as int),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('open-label-designer'),
              onPressed: busy ? null : design,
              icon: const Icon(Icons.design_services_outlined),
              label: Text(_t('Design label layout', 'Label ပုံစံပြင်ရန်')),
            ),
            if (template != null)
              Text(
                _t(
                  'Custom template controls text, barcode type and alignment. Edit them in the designer.',
                  'စိတ်ကြိုက် Template သုံးထားသည်။ စာသား၊ Barcode အမျိုးအစားနှင့် Alignment ကို Designer ထဲတွင် ပြင်ပါ။',
                ),
              ),
            if (template != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() => template = null);
                      },
                child: Text(_t('Use standard layout', 'ပုံမှန်ပုံစံသုံးမည်')),
              ),
            DropdownButtonFormField<int>(
              initialValue: labelsAcross,
              decoration: const InputDecoration(
                labelText: 'Labels per row / တစ်တန်းအရေအတွက်',
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 2, child: Text('2')),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => labelsAcross = v ?? 1),
            ),
            TextFormField(
              controller: labelGap,
              decoration: const InputDecoration(labelText: 'Gap (mm)'),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null || !n.isFinite || n < 0 || n > 20
                    ? '0–20 mm'
                    : null;
              },
            ),
            TextFormField(
              controller: labelMargin,
              decoration: const InputDecoration(labelText: 'Margin (mm)'),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                return n == null || !n.isFinite || n < 0 || n > 20
                    ? '0–20 mm'
                    : null;
              },
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('size:$resets'),
              initialValue: size,
              decoration: InputDecoration(
                labelText: _t('Label size', 'Label အရွယ်အစား'),
              ),
              items:
                  [
                        '30x20',
                        '40x20',
                        '40x30',
                        '50x25',
                        '50x30',
                        '60x40',
                        '80x40',
                        'custom',
                      ]
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s == 'custom'
                                ? _t('Custom', 'စိတ်ကြိုက်')
                                : '$s mm',
                          ),
                        ),
                      )
                      .toList(),
              onChanged: busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        size = value;
                        if (value != 'custom') {
                          final dimensions = value.split('x');
                          width.text = dimensions[0];
                          height.text = dimensions[1];
                        }
                      });
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: width,
                    readOnly: size != 'custom',
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('Width (mm)', 'အကျယ် (mm)'),
                    ),
                    validator: (s) => dimension(
                      s,
                      template == null ? 25 : 5,
                      template == null ? 120 : 1000,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: height,
                    readOnly: size != 'custom',
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('Height (mm)', 'အမြင့် (mm)'),
                    ),
                    validator: (s) => dimension(
                      s,
                      template == null ? 15 : 5,
                      template == null ? 80 : 1000,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('paper:$resets'),
              initialValue: paper,
              decoration: InputDecoration(
                labelText: _t('Paper layout', 'စာရွက်ပုံစံ'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'roll',
                  child: Text(
                    _t(
                      'Sticker roll (one or two across)',
                      'တစ်မျက်နှာလျှင် Label တစ်ခု / Roll',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'a4',
                  child: Text(
                    _t(
                      'A4 sheet — 8mm margins, 2mm gaps',
                      'A4 — ဘေးလွတ် 8mm၊ ကြားလွတ် 2mm',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              isExpanded: true,
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => paper = value);
                    },
            ),
            const SizedBox(height: 12),
            if (widget.batch == null)
              TextFormField(
                controller: count,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _t('Number of labels', 'Label အရေအတွက်'),
                ),
                validator: (s) {
                  final n = int.tryParse(s?.trim() ?? '');
                  return n == null || n < 1 || n > 200
                      ? _t('Enter 1–200.', '၁–၂၀၀ အတွင်း ထည့်ပါ။')
                      : null;
                },
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: showPrice,
              title: Text(_t('Show price', 'ဈေးနှုန်းဖော်ပြမည်')),
              onChanged: busy
                  ? null
                  : (value) => setState(() => showPrice = value),
            ),
            option(
              _t(
                'QR Code (off = Barcode Code 128)',
                'QR Code (ပိတ်လျှင် Barcode Code 128)',
              ),
              qr,
              (v) => qr = v,
            ),
            option(
              _t('Show item name', 'ပစ္စည်းအမည် ပြမည်'),
              showName,
              (v) => showName = v,
            ),
            option(
              _t('Show item code', 'Item Code ပြမည်'),
              showCode,
              (v) => showCode = v,
            ),
            option(
              _t('Show barcode number', 'Barcode နံပါတ် ပြမည်'),
              showNumber,
              (v) => showNumber = v,
            ),
            option(
              _t('Show color / size', 'Color / Size ပြမည်'),
              showVariant,
              (v) => showVariant = v,
            ),
            Text(
              _t(
                'Print at Actual Size / 100%. For small labels hide optional text or choose QR. Scan uses the saved barcode or item code; it never encodes the selling price.',
                'Actual Size / 100% ဖြင့်ထုတ်ပါ။ Label သေးလျှင် စာသားဖျောက် သို့မဟုတ် QR ရွေးပါ။ Scan က သိမ်းထားသော Barcode/Item Code ကိုသုံးပြီး ဈေးနှုန်းကို ကုဒ်မလုပ်ပါ။',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _t('Label alignment', 'Label နေရာချိန်ရန်'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            alignmentOption(
              _t('Top text', 'အပေါ်စာသား'),
              nameAlign,
              (v) => nameAlign = v,
            ),
            const SizedBox(height: 12),
            alignmentOption(
              'Barcode / QR',
              barcodeAlign,
              (v) => barcodeAlign = v,
            ),
            const SizedBox(height: 12),
            alignmentOption(
              _t('Number & price', 'နံပါတ်နှင့် ဈေးနှုန်း'),
              bottomAlign,
              (v) => bottomAlign = v,
            ),
            const SizedBox(height: 12),
            offsetOption(
              _t('Horizontal offset (+ right)', 'ဘယ်/ညာ ရွှေ့ရန် (+ ညာ)'),
              offsetX,
              (v) => offsetX = v,
            ),
            offsetOption(
              _t('Vertical offset (+ down)', 'အပေါ်/အောက် ရွှေ့ရန် (+ အောက်)'),
              offsetY,
              (v) => offsetY = v,
            ),
            Text(
              _t(
                'Offsets move all label content. Print at 100% and use a test label to calibrate the printer.',
                'စာနှင့် Barcode အားလုံးကို ရွှေ့ပေးမည်။ 100% ဖြင့် စမ်းထုတ်ပြီး Printer နှင့် ကိုက်ညီအောင် ချိန်ပါ။',
              ),
            ),
            OutlinedButton(
              onPressed: busy ? null : saveDefaults,
              child: Text(_t('Save label settings', 'Label ဆက်တင် သိမ်းရန်')),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await PortablePreferences.remove('label_options_v2');
                      if (mounted) {
                        setState(() {
                          size = '50x30';
                          paper = 'roll';
                          labelsAcross = 1;
                          labelGap.text = '2';
                          labelMargin.text = '0';
                          width.text = '50';
                          height.text = '30';
                          count.text = '1';
                          showPrice = true;
                          showName = true;
                          showCode = true;
                          showNumber = true;
                          showVariant = true;
                          qr = false;
                          nameAlign = 'center';
                          barcodeAlign = 'center';
                          bottomAlign = 'center';
                          offsetX = 0;
                          offsetY = 0;
                          resets++;
                        });
                      }
                    },
              child: Text(_t('Reset to default', 'မူလဆက်တင် ပြန်ထားရန်')),
            ),
            const SizedBox(height: 12),
            Text(
              _t(
                'Uses the phone/system Print or Share service. Direct Bluetooth printer pairing is not included.',
                'ဖုန်း၏ Print / Share Service ကိုသုံးမည်။ Bluetooth Printer တိုက်ရိုက်ချိတ်ခြင်း မပါသေးပါ။',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : preview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(
                busy
                    ? _t('Creating...', 'ဖန်တီးနေသည်…')
                    : _t('Preview / Print / PDF', 'နမူနာကြည့် / Print / PDF'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Render text with Flutter so Myanmar and other installed script fonts use
/// the same glyph shaping as the app. Barcode bars remain vector PDF content.
Future<Uint8List> _labelText(
  String text,
  double width,
  double height,
  double size, {
  bool bold = false,
  int maxLines = 1,
  String alignment = 'center',
}) async {
  const scale = 4.0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        height: 1.1,
        color: Colors.black,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: alignment == 'left'
        ? TextAlign.left
        : alignment == 'right'
        ? TextAlign.right
        : TextAlign.center,
    maxLines: maxLines,
    ellipsis: '…',
  );
  painter.layout(minWidth: width, maxWidth: width);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = Colors.white,
  );
  painter.paint(
    canvas,
    Offset(0, math.max(0.0, (height - painter.height) / 2)),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * scale).ceil(),
    (height * scale).ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  painter.dispose();
  if (data == null) throw StateError('Could not render label text');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> buildBarcodeLabels({
  required Map<String, Object?> product,
  List<BarcodeLabelSelection>? batch,
  PrintTemplate? template,
  required double widthMm,
  required double heightMm,
  required int count,
  required bool showPrice,
  required bool a4,
  bool showName = true,
  bool showCode = true,
  bool showNumber = true,
  bool showVariant = true,
  bool qr = false,
  String nameAlign = 'center',
  String barcodeAlign = 'center',
  String bottomAlign = 'center',
  int labelsAcross = 1,
  double gapMm = 2,
  marginMm = 0,
  double offsetXmm = 0,
  double offsetYmm = 0,
}) async {
  if (![1, 2].contains(labelsAcross) ||
      !gapMm.isFinite ||
      gapMm < 0 ||
      gapMm > 20 ||
      !marginMm.isFinite ||
      marginMm < 0 ||
      marginMm > 20) {
    throw ArgumentError('Invalid sticker layout');
  }
  if (batch != null) BarcodeLabelSelection.validate(batch);
  const mm = PdfPageFormat.mm;
  final w = widthMm * mm, h = heightMm * mm;
  if (count < 1 || count > 10000) throw ArgumentError('Invalid label count');
  final templateCache = TemplateRasterCache();
  if (template != null) {
    template.validate();
    if (!template.label) throw ArgumentError('Choose a label template');
  }
  Future<pw.Widget Function()> makeLabel(Map<String, Object?> product) async {
    if (template != null) {
      final selected = template.resized(widthMm, heightMm);
      selected.validate();
      final content = await renderTemplateWidget(
        template: selected,
        fields: TemplateBindings.item({
          ...product,
          'item_code': _itemCode(product),
          'barcode': product['barcode'] ?? _itemCode(product),
        }),
        rows: const [],
        cache: templateCache,
      );
      return () => content;
    }
    final code = product['barcode'] as String? ?? _itemCode(product);
    if (!widthMm.isFinite ||
        !heightMm.isFinite ||
        widthMm < 25 ||
        widthMm > 120 ||
        heightMm < 15 ||
        heightMm > 80 ||
        count < 1 ||
        count > 200 ||
        (!qr && widthMm < BarcodeRules.minimumLabelWidthMm(code))) {
      throw ArgumentError('Invalid label size or count');
    }
    if ([
          nameAlign,
          barcodeAlign,
          bottomAlign,
        ].any((v) => !['left', 'center', 'right'].contains(v)) ||
        !offsetXmm.isFinite ||
        !offsetYmm.isFinite ||
        offsetXmm.abs() > 1 ||
        offsetYmm.abs() > 1) {
      throw ArgumentError('Invalid label alignment or offset');
    }
    pw.Alignment pdfAlignment(String value) => value == 'left'
        ? pw.Alignment.centerLeft
        : value == 'right'
        ? pw.Alignment.centerRight
        : pw.Alignment.center;
    const mm = PdfPageFormat.mm;
    final w = widthMm * mm, h = heightMm * mm;
    final contentWidth = w - 3 * mm;
    final ratio = BarcodeRules.narrowBarRatio(code);
    // Reserve ten modules of white space on each side even when aligning left
    // or right. Only use spare width for alignment; never shrink below .25 mm.
    final minimumBarsWidth = .25 * mm / ratio;
    final preferredWidth =
        contentWidth - (barcodeAlign == 'center' ? 0 : 4 * mm);
    final barsWidth = math.max(
      minimumBarsWidth,
      preferredWidth / (1 + 20 * ratio),
    );
    final quietZone = 10 * ratio * barsWidth;
    final nameText = [
      if (showCode) _itemCode(product),
      if (showName) '${product['name']}',
      if (showVariant)
        '${product['color'] ?? ''} ${product['size'] ?? ''}'.trim(),
    ].where((v) => v.isNotEmpty).join(' · ');
    final nameHeight = nameText.isEmpty ? 0.0 : 6 * mm;
    final numberHeight = showNumber ? 3 * mm : 0.0;
    final name = pw.MemoryImage(
      await _labelText(
        nameText,
        contentWidth,
        6 * mm,
        7,
        maxLines: 2,
        alignment: nameAlign,
      ),
    );
    final number = pw.MemoryImage(
      await _labelText(code, contentWidth, 3 * mm, 6, alignment: bottomAlign),
    );
    final price = showPrice
        ? pw.MemoryImage(
            await _labelText(
              AppCurrency.format(product['price'] as int),
              contentWidth,
              3 * mm,
              8,
              bold: true,
              alignment: bottomAlign,
            ),
          )
        : null;
    final barcodeHeight =
        h -
        3 * mm -
        nameHeight -
        numberHeight -
        (showPrice ? 3 * mm : 0) -
        1 * mm;
    if (barcodeHeight < 7 * mm) {
      throw ArgumentError(
        'Label is too small for the selected fields. Hide text or choose a larger size.',
      );
    }
    pw.Widget label() => pw.Container(
      width: w,
      height: h,
      color: PdfColors.white,
      padding: const pw.EdgeInsets.all(1.5 * mm),
      child: pw.Transform.translate(
        offset: PdfPoint(offsetXmm * mm, offsetYmm * mm),
        child: pw.Column(
          children: [
            if (nameHeight > 0)
              pw.Image(name, width: contentWidth, height: nameHeight),
            pw.SizedBox(height: 0.5 * mm),
            pw.Align(
              alignment: pdfAlignment(barcodeAlign),
              child: pw.Padding(
                padding: pw.EdgeInsets.symmetric(
                  horizontal: qr ? 0 : quietZone,
                ),
                child: pw.BarcodeWidget(
                  data: code,
                  barcode: qr ? bc.Barcode.qrCode() : bc.Barcode.code128(),
                  drawText: false,
                  width: qr ? math.min(contentWidth, barcodeHeight) : barsWidth,
                  height: barcodeHeight,
                ),
              ),
            ),
            pw.SizedBox(height: 0.5 * mm),
            if (showNumber)
              pw.Image(number, width: contentWidth, height: 3 * mm),
            if (price != null)
              pw.Image(price, width: contentWidth, height: 3 * mm),
          ],
        ),
      ),
    );

    return label;
  }

  final factories = <pw.Widget Function()>[];
  for (final selection
      in batch ?? [BarcodeLabelSelection(product: product, count: count)]) {
    final factory = await makeLabel(selection.product);
    factories.addAll(List.filled(selection.count, factory));
  }
  final total = factories.length;
  final doc = pw.Document();
  if (!a4) {
    final gap = gapMm * mm, margin = marginMm * mm;
    for (int i = 0; i < total; i += labelsAcross) {
      final rowStart = i;
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            w * labelsAcross + gap * (labelsAcross - 1) + 2 * margin,
            h + 2 * margin,
          ),
          margin: pw.EdgeInsets.all(margin),
          build: (_) => pw.Row(
            children: [
              for (var col = 0; col < labelsAcross; col++) ...[
                if (col > 0) pw.SizedBox(width: gap),
                pw.SizedBox(
                  width: w,
                  height: h,
                  child: rowStart + col < total
                      ? factories[rowStart + col]()
                      : null,
                ),
              ],
            ],
          ),
        ),
      );
    }
  } else {
    final gap = gapMm * mm;
    final margin = marginMm * mm;
    final aw = PdfPageFormat.a4.width - 2 * margin,
        ah = PdfPageFormat.a4.height - 2 * margin;
    final columns = labelsAcross;
    if (columns * w + (columns - 1) * gap > aw) {
      throw ArgumentError('Labels do not fit paper width');
    }
    final rows = ((ah + gap) / (h + gap)).floor();
    if (columns < 1 || rows < 1) throw ArgumentError('Label does not fit A4');
    final capacity = columns * rows;
    for (int start = 0; start < total; start += capacity) {
      final used = math.min(capacity, total - start);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(margin),
          build: (_) => pw.SizedBox(
            width: aw,
            height: ah,
            child: pw.Stack(
              children: [
                for (int i = 0; i < used; i++)
                  pw.Positioned(
                    left: (i % columns) * (w + gap),
                    top: (i ~/ columns) * (h + gap),
                    child: factories[start + i](),
                  ),
              ],
            ),
          ),
        ),
      );
    }
  }
  return doc.save();
}
