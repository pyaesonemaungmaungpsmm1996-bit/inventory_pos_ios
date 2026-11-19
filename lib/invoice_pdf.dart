import 'app_capabilities.dart';
import 'template_pdf.dart';
import 'template_bindings.dart';
import 'invoice_branch_header.dart';
import 'a4_layout_settings.dart';
import 'voucher_code.dart';
import 'sale_return_print_snapshot.dart';
import 'business_logo_page.dart';
import 'product_tracking.dart';

import 'package:barcode/barcode.dart' as bc;

import 'app_database.dart';

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_print_model.dart';
import 'invoice_print_settings.dart';
import 'app_currency.dart';
import 'app_datetime.dart';

part 'invoice_a4.dart';
part 'invoice_receipt.dart';

class GeneratedInvoicePdf {
  const GeneratedInvoicePdf(
    this.bytes,
    this.format, {
    this.headerRegions = const {},
  });
  final Uint8List bytes;
  final PdfPageFormat format;

  /// Draggable header regions in PDF points from the page's top-left corner.
  final Map<String, Rect> headerRegions;
}

class _RowImage {
  const _RowImage(this.bytes, this.height);
  final Uint8List bytes;
  final double height;
}

/// Rasterize shaped text, not stock data or live UI. Flutter's font fallback and
/// Myanmar shaping are preserved offline; row images paginate without clipping.
Future<_RowImage> _renderInvoiceRow(
  InvoicePrintRow row,
  double width,
  bool narrow, {
  double? fontSizeOverride,
  Color background = Colors.white,
  List<double>? columnFractions,
}) async {
  if (row.picture != null) return _RowImage(row.picture!, narrow ? 40 : 56);
  const scale = 4.0;
  final fontSize =
      fontSizeOverride ??
      (row.large ? (narrow ? 10.5 : 13.0) : (narrow ? 8.5 : 9.2));
  final count = row.cells.length;
  final fractions =
      columnFractions ??
      (count == 4
          ? const [0.44, 0.10, 0.22, 0.24]
          : count == 2
          ? const [0.55, 0.45]
          : const [1.0]);
  const gap = 4.0;
  final available = width - (count - 1) * gap;
  final painters = <TextPainter>[];
  final widths = <double>[];
  for (int i = 0; i < count; i++) {
    final cellWidth = available * fractions[i];
    final align = row.center
        ? TextAlign.center
        : row.right || (row.columns && i > 0)
        ? TextAlign.right
        : TextAlign.left;
    final painter = TextPainter(
      text: TextSpan(
        text: row.cells[i],
        style: TextStyle(
          fontFamily: AppCapabilities.windows ? 'Segoe UI' : null,
          fontFamilyFallback: const ['Myanmar Text', 'Noto Sans Myanmar'],
          fontSize: fontSize,
          height: 1.2,
          color: Colors.black,
          fontWeight: row.bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    );
    painter.layout(minWidth: cellWidth, maxWidth: cellWidth);
    painters.add(painter);
    widths.add(cellWidth);
  }
  final height = painters.fold<double>(0, (h, p) => math.max(h, p.height)) + 4;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = background,
  );
  double x = 0;
  for (int i = 0; i < count; i++) {
    painters[i].paint(canvas, Offset(x, 2));
    x += widths[i] + gap;
  }
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Could not render invoice text');
    }
    return _RowImage(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      height,
    );
  } finally {
    image?.dispose();
    picture.dispose();
    for (final painter in painters) {
      painter.dispose();
    }
  }
}

bool _usesSalesA4Header(String kind) => kind == 'INV' || kind == 'RET';

Future<GeneratedInvoicePdf> buildInvoicePdf({
  required Map<String, Object?> sale,
  required InvoicePrintSettings settings,
  required bool myanmar,
  Future<Uint8List?> Function()? loadLogo,
  Future<List<Map<String, Object?>>> Function()? loadBranches,
}) async {
  settings.validate();
  final photoMap = <int, Uint8List>{};
  if (settings.showItemPhotos) {
    for (final item in sale['items'] as List) {
      final rawId = (item as Map)['product_id'];
      if (rawId is! int) continue;
      final id = rawId;
      final bytes = await AppDatabase.instance.getProductImage(id);
      if (bytes != null) photoMap[id] = bytes;
    }
  }
  // There is no POS-brand fallback: this is the user's saved business logo.
  final logo = settings.showLogo
      ? await (loadLogo ?? BusinessLogoStore.read)()
      : null;
  final branchRows = <Map<String, Object?>>[];
  if (settings.showBranch &&
      ['auto', 'one', 'two'].contains(settings.a4.branchMode) &&
      (sale['branch_id'] is int ||
          settings.a4.primaryBranchId != null ||
          loadBranches != null)) {
    branchRows.addAll(
      await (loadBranches ?? AppDatabase.instance.getBranches)(),
    );
  }
  final printSale = <String, Object?>{
    ...sale,
    'document_number': VoucherCode.displayNumber(sale),
    if (settings.paper == 'a4' &&
        !settings.narrow &&
        _usesSalesA4Header(VoucherCode.kindOf(sale)))
      'print_a4_branch_blocks': InvoiceBranchHeader.resolve(
        sale,
        settings.a4,
        branchRows,
        includeThird: true,
      ),
    'print_branch_blocks': InvoiceBranchHeader.resolve(
      sale,
      settings.a4,
      branchRows,
    ),
  };
  if (settings.layout == 'designer' && settings.template != null) {
    final result = await renderTemplatePdf(
      template: settings.template!,
      fields: TemplateBindings.invoice(printSale, {
        ...settings.toJson(),
        'language': myanmar ? 'my' : 'en',
      }),
      rows: [
        for (final row in sale['items'] as List)
          TemplateBindings.item(
            row as Map,
            currency: sale['currency_code'] as String? ?? 'MMK',
            digits: sale['currency_digits'] as int? ?? 0,
            prices: settings.showPrices,
            discounts: settings.showDiscount,
            codes: settings.showItemCode,
          ),
      ],
      logo: logo,
    );
    return GeneratedInvoicePdf(result.bytes, result.format);
  }
  if (settings.paper == 'a4' && !settings.narrow) {
    return _buildA4Invoice(
      sale: printSale,
      settings: settings,
      myanmar: myanmar,
      logo: logo,
      photos: photoMap,
    );
  }
  if (settings.autoHeight) {
    return _buildSlipInvoice(
      sale: printSale,
      settings: settings,
      myanmar: myanmar,
      logo: logo,
      photos: photoMap,
    );
  }
  final rows = invoicePrintRows(
    {...sale, 'business_logo': logo, 'item_images': photoMap},
    settings,
    myanmar: myanmar,
  );
  final margin = settings.marginMm * PdfPageFormat.mm;
  var format = settings.pageFormat;
  final width = format.width - 2 * margin;
  final images = <_RowImage?>[];
  double totalHeight = 0;
  for (final row in rows) {
    final image = row.rule
        ? null
        : await _renderInvoiceRow(row, width, settings.narrow);
    images.add(image);
    totalHeight += image?.height ?? 8;
  }
  const footerHeight = 14.0;
  if (settings.autoHeight) {
    // Ordinary receipts get one naturally sized page; very long receipts split.
    final height = (totalHeight + 2 * margin + footerHeight + 6)
        .clamp(60 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm)
        .toDouble();
    format = PdfPageFormat(format.width, height);
  }
  final usableHeight = format.height - 2 * margin - footerHeight;
  if (images.any((row) => row != null && row.height > usableHeight)) {
    throw StateError(
      'A row is too tall. Choose a taller custom paper or a larger page.',
    );
  }
  final widgets = <pw.Widget>[];
  for (final image in images) {
    if (image == null) {
      widgets.add(
        pw.SizedBox(
          height: 8,
          child: pw.Center(
            child: pw.Container(
              height: 0.5,
              width: width,
              color: PdfColors.black,
            ),
          ),
        ),
      );
    } else {
      widgets.add(
        pw.Image(
          pw.MemoryImage(image.bytes),
          width: width,
          height: image.height,
        ),
      );
    }
  }
  final number =
      '${sale['document_prefix'] ?? 'INV'}-${(sale['id'] as int).toString().padLeft(6, '0')}';
  final doc = pw.Document(
    title: number,
    author: sale['business_name'] as String? ?? '',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(margin),
      maxPages: 100,
      footer: (context) => pw.SizedBox(
        height: footerHeight,
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '$number  ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: settings.narrow ? 6 : 8),
          ),
        ),
      ),
      build: (_) => widgets,
    ),
  );
  return GeneratedInvoicePdf(await doc.save(), format);
}

/// Render the saved return snapshot with the same Flutter text shaping as sales.
Future<GeneratedInvoicePdf> buildSaleReturnPdf({
  required Map<String, Object?> returned,
  required InvoicePrintSettings settings,
  required bool myanmar,
  Future<Uint8List?> Function()? loadLogo,
  Future<List<Map<String, Object?>>> Function()? loadBranches,
}) async {
  settings.validate();
  if (settings.layout == 'designer' ||
      (settings.paper == 'a4' && !settings.narrow) ||
      settings.autoHeight) {
    return buildInvoicePdf(
      sale: saleReturnPrintSnapshot(returned),
      settings: settings,
      myanmar: myanmar,
      loadLogo: loadLogo,
      loadBranches: loadBranches,
    );
  }

  String t(String en, String my) => myanmar ? my : en;
  final code = returned['currency_code'] as String? ?? 'MMK';
  final digits = returned['currency_digits'] as int? ?? 0;
  String money(Object? n) =>
      AppCurrency.format(n as int, currency: code, decimalPlaces: digits);
  final id = returned['id'] as int;
  final number = 'RET-${id.toString().padLeft(6, '0')}';
  final saleNumber =
      'INV-${(returned['sale_id'] as int).toString().padLeft(6, '0')}';
  final rows = <InvoicePrintRow>[];
  void line(
    String s, {
    bool bold = false,
    bool right = false,
    bool center = false,
  }) =>
      rows.add(InvoicePrintRow([s], bold: bold, right: right, center: center));
  void rule() => rows.add(const InvoicePrintRow([], rule: true));
  final logo = settings.showLogo ? await BusinessLogoStore.read() : null;
  if (logo != null) rows.add(InvoicePrintRow(const [], picture: logo));
  line(returned['business_name'] as String? ?? '', bold: true, center: true);
  line(
    t('SALE RETURN INVOICE', 'အရောင်းပြန်အပ် ဘောင်ချာ'),
    bold: true,
    center: true,
  );
  line(number, bold: true, center: true);
  if (returned['status'] == 'void') {
    line('VOID · ${returned['void_reason']}', bold: true, center: true);
  }
  if (returned['replacement_id'] != null) {
    line(
      '${t('Corrected by', 'ပြင်ဆင်ပြီးဘောင်ချာ')}: '
      'RET-${(returned['replacement_id'] as int).toString().padLeft(6, '0')}',
    );
  }
  line('${t('Original invoice', 'မူရင်းဘောင်ချာ')}: $saleNumber');
  if (settings.showDate) {
    line(
      '${t('Return date', 'ပြန်အပ်သည့်ရက်')}: ${AppDateTime.format(returned['created_at'])}',
    );
  }
  if (settings.showSalePerson) {
    line(
      '${t('Sale person', 'အရောင်းဝန်ထမ်း')}: '
      '${(returned['employee_name'] as String? ?? '').isEmpty ? '—' : returned['employee_name']}',
    );
  }
  if (settings.showBranch) {
    line(
      '${t('Branch', 'ဆိုင်ခွဲ')}: ${returned['branch_name_snapshot']} (${returned['branch_code_snapshot']})',
    );
  }
  if (settings.showCustomer) {
    line('${t('Customer', 'ဝယ်သူ')}: ${returned['customer_name']}');
  }
  line('${t('Reason', 'အကြောင်းရင်း')}: ${returned['reason']}');
  rule();
  for (final raw in returned['items'] as List) {
    final item = raw as Map;
    if (settings.showItemPhotos && item['product_id'] is int) {
      final bytes = await AppDatabase.instance.getProductImage(
        item['product_id'] as int,
      );
      if (bytes != null) rows.add(InvoicePrintRow(const [], picture: bytes));
    }
    line(
      '${settings.showItemCode ? '${item['item_code']} · ' : ''}${item['item_name']}',
      bold: true,
    );
    for (final lot in ProductTracking.decode(item['tracking_json'])) {
      if (lot['serial'] != null) line('Serial: ${lot['serial']}');
      if (lot['imei'] != null) line('IMEI: ${lot['imei']}');
    }
    rows.add(
      InvoicePrintRow([
        '${t('Quantity returned', 'ပြန်ယူအရေအတွက်')}: ${item['qty']}',
        money(item['refund_amount']),
      ], columns: true),
    );
  }
  rule();
  line(
    '${t('Total refunded', 'ပြန်အမ်းငွေစုစုပေါင်း')}: ${money(returned['total'])}',
    bold: true,
    right: true,
  );
  line(settings.footer, center: true);
  final margin = settings.marginMm * PdfPageFormat.mm;
  var format = settings.pageFormat;
  final width = format.width - margin * 2;
  final images = <_RowImage?>[];
  var totalHeight = 0.0;
  for (final row in rows) {
    final rendered = row.rule
        ? null
        : await _renderInvoiceRow(row, width, settings.narrow);
    images.add(rendered);
    totalHeight += rendered?.height ?? 8;
  }
  const footerHeight = 14.0;
  if (settings.autoHeight) {
    format = PdfPageFormat(
      format.width,
      (totalHeight + margin * 2 + footerHeight + 6)
          .clamp(60 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm)
          .toDouble(),
    );
  }
  final usable = format.height - margin * 2 - footerHeight;
  if (images.any((r) => r != null && r.height > usable)) {
    throw StateError('Choose a taller page for the return invoice');
  }
  final widgets = <pw.Widget>[];
  for (final rendered in images) {
    widgets.add(
      rendered == null
          ? pw.SizedBox(
              height: 8,
              child: pw.Center(
                child: pw.Container(
                  height: 0.5,
                  width: width,
                  color: PdfColors.black,
                ),
              ),
            )
          : pw.Image(
              pw.MemoryImage(rendered.bytes),
              width: width,
              height: rendered.height,
            ),
    );
  }
  final doc = pw.Document(
    title: number,
    author: returned['business_name'] as String? ?? '',
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(margin),
      maxPages: 100,
      footer: (context) => pw.SizedBox(
        height: footerHeight,
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '$number  ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: settings.narrow ? 6 : 8),
          ),
        ),
      ),
      build: (_) => widgets,
    ),
  );
  return GeneratedInvoicePdf(await doc.save(), format);
}
