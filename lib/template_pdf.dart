import 'app_capabilities.dart';

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart' as bc;

import 'print_template.dart';
import 'template_bindings.dart';
import 'barcode_rules.dart';

class TemplatePdf {
  const TemplatePdf(this.bytes, this.format);
  final Uint8List bytes;
  final PdfPageFormat format;
}

class TemplateRasterCache {
  final images = <String, pw.MemoryImage>{};
  Future<pw.MemoryImage> text(PrintElement e, String value) async {
    final key = jsonEncode([
      e.width,
      e.height,
      e.fontSize,
      e.fontFamily,
      e.color,
      e.bold,
      e.italic,
      e.align,
      e.fitText,
      value,
    ]);
    final existing = images[key];
    if (existing != null) return existing;
    final w = e.width * PdfPageFormat.mm, h = e.height * PdfPageFormat.mm;
    final scale = [
      3.0,
      4096 / w,
      4096 / h,
      math.sqrt(12000000 / (w * h)),
    ].reduce(math.min);
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: e.fontFamily.isEmpty
              ? (AppCapabilities.windows ? 'Segoe UI' : null)
              : e.fontFamily,
          fontFamilyFallback: const [
            'Myanmar Text',
            'Noto Sans Myanmar',
            'Segoe UI',
          ],
          fontSize: e.fontSize,
          fontWeight: e.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: e.italic ? FontStyle.italic : FontStyle.normal,
          color: Color(e.color),
          height: 1.15,
        ),
      ),
      textAlign: e.align == 'right'
          ? TextAlign.right
          : e.align == 'center'
          ? TextAlign.center
          : TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: w, maxWidth: w);
    final fit = e.fitText && painter.height > h ? h / painter.height : 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..clipRect(Rect.fromLTWH(0, 0, w, h));
    if (fit < 1) {
      canvas.translate(
        e.align == 'right'
            ? w * (1 - fit)
            : e.align == 'center'
            ? w * (1 - fit) / 2
            : 0,
        0,
      );
      canvas.scale(fit);
    }
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      math.max(1, (w * scale).ceil()),
      math.max(1, (h * scale).ceil()),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    painter.dispose();
    if (bytes == null) throw StateError('Could not rasterize template text');
    final result = pw.MemoryImage(bytes.buffer.asUint8List());
    images[key] = result;
    return result;
  }
}

Future<pw.Widget> renderTemplateWidget({
  required PrintTemplate template,
  required Map<String, String> fields,
  List<Map<String, String>> rows = const [],
  Uint8List? logo,
  TemplateRasterCache? cache,
}) async {
  template.validate();
  final raster = cache ?? TemplateRasterCache();
  const mm = PdfPageFormat.mm;
  final layers = <pw.Widget>[];
  Future<pw.Widget> cell(PrintElement style, String text) => raster
      .text(style, text)
      .then(
        (image) =>
            pw.Image(image, width: style.width * mm, height: style.height * mm),
      );
  for (final e in template.elements) {
    if (e.lastPageOnly &&
        e.kind != 'table' &&
        fields['page.number'] != fields['page.count']) {
      continue;
    }
    pw.Widget child = pw.SizedBox();
    final value = TemplateBindings.resolve(e.text, fields);
    if (e.kind == 'text') {
      child = await cell(e, value);
    } else if (e.kind == 'image') {
      final bytes = e.imageBase64.isNotEmpty
          ? base64Decode(e.imageBase64)
          : logo;
      if (bytes != null && bytes.isNotEmpty) {
        child = pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain);
      }
    } else if (e.kind == 'barcode' &&
        e.text == '{invoice.qr}' &&
        value.isEmpty) {
      child = await cell(
        e.withValues({'fontSize': 7.0, 'align': 'center'}),
        'QR after confirmation',
      );
    } else if (e.kind == 'barcode' && value.isNotEmpty) {
      if (e.qr) {
        child = pw.Center(
          child: pw.BarcodeWidget(
            barcode: bc.Barcode.qrCode(),
            data: value,
            drawText: false,
            width: math.min(e.width, e.height) * mm,
            height: math.min(e.width, e.height) * mm,
          ),
        );
      } else {
        if (e.width < BarcodeRules.minimumLabelWidthMm(value)) {
          throw StateError('Barcode $value needs a wider element or QR mode');
        }
        final ratio = BarcodeRules.narrowBarRatio(value),
            bars = (e.width - 3) * mm / (1 + 20 * ratio);
        final quiet = 10 * ratio * bars;
        child = pw.Center(
          child: pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: quiet),
            child: pw.BarcodeWidget(
              barcode: bc.Barcode.code128(),
              data: value,
              drawText: false,
              width: bars,
              height: e.height * mm,
            ),
          ),
        );
      }
    } else if (e.kind == 'line') {
      child = pw.Container(color: PdfColor.fromInt(e.color));
    } else if (e.kind == 'table') {
      final weights = e.columns.fold<double>(0, (n, c) => n + c.weight);
      Future<pw.Widget> tableRow(Map<String, String> row, bool heading) async {
        final cells = <pw.Widget>[];
        for (final c in e.columns) {
          final width = e.width * c.weight / weights;
          final h = heading ? e.headerHeight : e.rowHeight;
          final style = e.withValues({
            'kind': 'text',
            'width': width,
            'height': h,
            'align': c.align,
            'bold': heading || e.bold,
          });
          final image = await cell(
            style,
            heading
                ? c.title
                : TemplateBindings.resolve(c.expression, {...fields, ...row}),
          );
          cells.add(
            pw.Container(
              width: width * mm,
              height: h * mm,
              decoration: pw.BoxDecoration(
                color: heading ? const PdfColor.fromInt(0xffedf2f7) : null,
                border: pw.Border.all(
                  color: PdfColor.fromInt(e.borderColor),
                  width: e.border * mm,
                ),
              ),
              child: image,
            ),
          );
        }
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: cells,
        );
      }

      final lines = <pw.Widget>[];
      if (e.headerHeight > 0) lines.add(await tableRow({}, true));
      for (final row in rows) {
        lines.add(await tableRow(row, false));
      }
      child = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: lines,
      );
    }
    layers.add(
      pw.Positioned(
        left: e.x * mm,
        top: e.y * mm,
        child: pw.Container(
          width: e.width * mm,
          height: e.height * mm,
          decoration: pw.BoxDecoration(
            color: (e.fill >> 24) == 0 ? null : PdfColor.fromInt(e.fill),
            border: e.border > 0 && e.kind != 'table'
                ? pw.Border.all(
                    color: PdfColor.fromInt(e.borderColor),
                    width: e.border * mm,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
  return pw.SizedBox(
    width: template.width * mm,
    height: template.height * mm,
    child: pw.Stack(children: layers),
  );
}

Future<TemplatePdf> renderTemplatePdf({
  required PrintTemplate template,
  required Map<String, String> fields,
  List<Map<String, String>> rows = const [],
  Uint8List? logo,
}) async {
  template.validate();
  final format = PdfPageFormat(
    template.width * PdfPageFormat.mm,
    template.height * PdfPageFormat.mm,
  );
  final ranges = template.pageRanges(rows.length);
  final doc = pw.Document(title: fields['invoice.number'] ?? template.name);
  final cache = TemplateRasterCache();
  for (var page = 0; page < ranges.length; page++) {
    final range = ranges[page];
    final values = {
      ...fields,
      'page.number': (page + 1).toString(),
      'page.count': ranges.length.toString(),
    };
    final content = await renderTemplateWidget(
      template: template,
      fields: values,
      rows: [
        for (var i = range.$1; i < range.$2; i++)
          {...rows[i], 'item.no': (i + 1).toString()},
      ],
      logo: logo,
      cache: cache,
    );
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => content,
      ),
    );
  }
  return TemplatePdf(await doc.save(), format);
}
