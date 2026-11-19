part of 'invoice_pdf.dart';

/// Thermal receipt layout: fixed physical width, naturally sized length.
Future<GeneratedInvoicePdf> _buildSlipInvoice({
  required Map<String, Object?> sale,
  required InvoicePrintSettings settings,
  required bool myanmar,
  required Uint8List? logo,
  required Map<int, Uint8List> photos,
}) async {
  final margin = settings.marginMm * PdfPageFormat.mm;
  final width = settings.pageFormat.width - margin * 2;
  final narrow = settings.paper == 'receipt58';
  final font = settings.a4.tableSize * (narrow ? .86 : 1);
  final infoFont = settings.a4.infoSize * (narrow ? .86 : 1);
  final kind = VoucherCode.kindOf(sale),
      isReturn = VoucherCode.kindOf(sale) == 'RET';
  final code = sale['currency_code'] as String? ?? 'MMK';
  final digits = sale['currency_digits'] as int? ?? 0;
  String t(String en, String my) => myanmar ? my : en;
  String text(Object? v) => v?.toString().trim() ?? '';
  String money(Object? n) =>
      AppCurrency.format(n as int, currency: code, decimalPlaces: digits);
  String numeric(Object? n) {
    final v = money(n);
    return v.substring(0, v.length - AppCurrency.display(code).length - 1);
  }

  final number =
      sale['document_number'] as String? ??
      '$kind-${(sale['id'] as int).toString().padLeft(6, '0')}';
  final blocks = <(pw.Widget, double)>[];
  void gap(double h) => blocks.add((pw.SizedBox(height: h), h));
  void rule({bool dotted = false}) => blocks.add((
    pw.Divider(
      height: 5,
      thickness: dotted ? .3 : .8,
      borderStyle: dotted ? pw.BorderStyle.dotted : pw.BorderStyle.solid,
    ),
    5,
  ));
  Future<void> line(
    List<String> cells, {
    bool bold = false,
    bool center = false,
    double? size,
    bool shaded = false,
    bool valuesLeft = false,
    List<double>? fractions,
  }) async {
    final image = await _renderInvoiceRow(
      InvoicePrintRow(
        cells,
        bold: bold,
        center: center,
        columns: cells.length > 1 && !valuesLeft,
      ),
      width,
      true,
      fontSizeOverride: size ?? font,
      columnFractions: fractions,
      background: shaded ? const Color(0xffdddddd) : Colors.white,
    );
    blocks.add((
      pw.Image(pw.MemoryImage(image.bytes), width: width, height: image.height),
      image.height,
    ));
  }

  Future<void> detail(String label, String value) async => line(
    [label, ': $value'],
    size: infoFont,
    valuesLeft: true,
    fractions: const [.35, .65],
  );
  if (logo != null) {
    blocks.add((
      pw.Center(
        child: pw.Image(
          pw.MemoryImage(logo),
          width: 52,
          height: 44,
          fit: pw.BoxFit.contain,
        ),
      ),
      44,
    ));
    gap(4);
  }
  await line(
    [
      settings.a4.heading.trim().isEmpty
          ? text(sale['business_name'])
          : settings.a4.heading.trim(),
    ],
    center: true,
    bold: true,
    size: narrow ? 12 : 14,
  );
  if (settings.a4.subtitle.trim().isNotEmpty) {
    await line([settings.a4.subtitle.trim()], center: true, size: infoFont + 1);
  }
  if (settings.showBranch) {
    final branch = List<String>.from(
      sale['print_branch_blocks'] as List? ?? const [],
    ).join('\n');
    if (branch.isNotEmpty) await line([branch], center: true, size: infoFont);
  }
  rule();
  final title = switch (kind) {
    'RET' => t('Sale Return Invoice', 'အရောင်းပြန်အမ်းဘောင်ချာ'),
    'PUR' => t('Purchase Invoice', 'အဝယ်ဘောင်ချာ'),
    'EXP' => t('Expense Voucher', 'အသုံးစရိတ်ဘောင်ချာ'),
    _ => t('Sale Invoice', 'အရောင်းဘောင်ချာ'),
  };
  await line(
    [sale['status'] == 'draft' ? '$title - DRAFT' : title],
    bold: true,
    center: true,
    size: infoFont,
  );
  if (sale['status'] == 'void') {
    await line(
      ['VOID: ${text(sale['void_reason'])}'],
      bold: true,
      center: true,
    );
  }
  if (sale['replacement_id'] != null) {
    await line(['Corrected by: ${sale['replacement_id']}']);
  }
  gap(6);
  if (settings.showDate) {
    await detail(t('Date', 'ရက်စွဲ'), text(sale['invoice_date']));
  }
  await detail(t('Invoice No.', 'ဘောင်ချာအမှတ်'), number);
  if (settings.showCustomer && kind != 'EXP') {
    await detail(
      kind == 'PUR' ? t('Supplier', 'ကုန်ပေးသွင်းသူ') : t('Customer', 'ဝယ်သူ'),
      text(sale['customer_name']).isEmpty
          ? 'Walk-in'
          : text(sale['customer_name']),
    );
    if (text(sale['customer_phone']).isNotEmpty) {
      await detail(t('Phone', 'ဖုန်း'), text(sale['customer_phone']));
    }
    if (text(sale['customer_address']).isNotEmpty) {
      await detail(t('Address', 'လိပ်စာ'), text(sale['customer_address']));
    }
    if (text(sale['customer_company']).isNotEmpty) {
      await detail(t('Company', 'ကုမ္ပဏီ'), text(sale['customer_company']));
    }
    await detail(t('City', 'မြို့'), text(sale['customer_city']));
  }
  await detail(settings.a4.remarkLabel, text(sale['remark']));
  if (settings.showSalePerson) {
    await detail(
      isReturn
          ? t('Processed by', 'ဆောင်ရွက်သူ')
          : t('Sale person', 'အရောင်းဝန်ထမ်း'),
      text(sale['employee_name']),
    );
  }
  if (isReturn) {
    await detail(
      t('Original invoice', 'မူရင်းဘောင်ချာ'),
      'INV-${(sale['sale_id'] as int).toString().padLeft(6, '0')}',
    );
    await detail(t('Reason', 'အကြောင်းပြချက်'), text(sale['reason']));
  }
  gap(10);
  await line([
    '${t('Currency', 'ငွေကြေး')}: ${AppCurrency.display(code)}',
  ], size: font - 1);
  final fractions = settings.showPrices
      ? const [.42, .08, .24, .26]
      : const [.60, .10, .30];
  await line(
    [
      t('Item name', 'ပစ္စည်းအမည်'),
      t('Qty', 'အရေအတွက်'),
      if (settings.showPrices) t('Price', 'ဈေးနှုန်း'),
      t('Amount', 'ကျသင့်ငွေ'),
    ],
    bold: true,
    shaded: true,
    fractions: fractions,
  );
  var totalQty = 0;
  for (final raw in sale['items'] as List) {
    final item = Map<String, Object?>.from(raw as Map);
    totalQty += item['qty'] as int;
    if (settings.showItemPhotos && photos[item['product_id']] != null) {
      blocks.add((
        pw.Image(
          pw.MemoryImage(photos[item['product_id']]!),
          width: 36,
          height: 32,
          fit: pw.BoxFit.contain,
        ),
        32,
      ));
    }
    final description = [
      '${settings.showItemCode && text(item['item_code']).isNotEmpty ? '${text(item['item_code'])} - ' : ''}${text(item['item_name'])}',
      if ('${item['color_snapshot'] ?? ''}${item['size_snapshot'] ?? ''}'
          .isNotEmpty)
        '${t('Color / Size', 'အရောင် / အရွယ်')}: ${item['color_snapshot'] ?? ''} / ${item['size_snapshot'] ?? ''}',
      if (settings.showDiscount && (item['item_discount'] as int? ?? 0) > 0)
        '${t('Item discount', 'ပစ္စည်းလျှော့ဈေး')}: ${numeric(item['item_discount'])}',
      for (final lot in ProductTracking.decode(item['tracking_json'])) ...[
        if (lot['serial'] != null) 'Serial: ${lot['serial']}',
        if (lot['imei'] != null) 'IMEI: ${lot['imei']}',
        if (lot['expires_on'] != null) 'Expiry: ${lot['expires_on']}',
        if (lot['warranty_until'] != null) 'Warranty: ${lot['warranty_until']}',
      ],
    ].join('\n');
    for (var start = 0; start < math.max(1, description.length); start += 250) {
      final first = start == 0;
      await line([
        description.substring(start, math.min(start + 250, description.length)),
        first ? '${item['qty']}' : '',
        if (settings.showPrices)
          first && item['price'] != null ? numeric(item['price']) : '',
        first
            ? numeric(
                (item['amount'] as int) - (item['item_discount'] as int? ?? 0),
              )
            : '',
      ], fractions: fractions);
    }
    rule(dotted: true);
  }
  await detail(t('Total qty', 'စုစုပေါင်းအရေအတွက်'), '$totalQty');
  for (final entry in <(String, Object?, bool)>[
    (t('Subtotal', 'စုစုပေါင်း'), sale['subtotal'], false),
    if (settings.showDiscount &&
        ((sale['items'] as List).fold<int>(
              0,
              (sum, raw) => sum + ((raw as Map)['item_discount'] as int? ?? 0),
            )) >
            0) ...[
      (
        t('Item discounts', 'ပစ္စည်းလျှော့ဈေးများ'),
        (sale['items'] as List).fold<int>(
          0,
          (sum, raw) => sum + ((raw as Map)['item_discount'] as int? ?? 0),
        ),
        false,
      ),
      (
        t('Voucher discount', 'ဘောင်ချာလျှော့ဈေး'),
        sale['voucher_discount_amount'] ?? 0,
        false,
      ),
    ] else if (settings.showDiscount)
      (t('Discount', 'လျှော့ဈေး'), sale['discount_amount'], false),
    (
      isReturn
          ? t('Total refunded', 'ပြန်အမ်းငွေ')
          : t('Total amount', 'ကျသင့်ငွေ'),
      sale['total'],
      true,
    ),
    (
      isReturn
          ? t('Refund paid', 'ပြန်အမ်းပြီးငွေ')
          : t('Paid', 'ပေးချေပြီးငွေ'),
      sale['paid'],
      false,
    ),
    (t('Balance', 'ကျန်ငွေ'), sale['balance_due'], true),
  ]) {
    await line(
      [entry.$1, money(entry.$2)],
      bold: entry.$3,
      fractions: const [.51, .49],
    );
  }
  if (settings.footer.trim().isNotEmpty) {
    gap(5);
    await line([settings.footer.trim()], center: true);
  }
  gap(12);
  final qrSize = math.min(width * .70, 46 * PdfPageFormat.mm);
  blocks.add((
    pw.Center(
      child: sale['status'] == 'draft'
          ? pw.SizedBox(width: qrSize, height: qrSize)
          : pw.BarcodeWidget(
              barcode: bc.Barcode.qrCode(),
              data: VoucherCode.encode(sale),
              width: qrSize,
              height: qrSize,
              drawText: false,
            ),
    ),
    qrSize,
  ));
  gap(6);
  await line([number], center: true, size: 7);
  final totalHeight = blocks.fold<double>(0, (h, b) => h + b.$2);
  final format = PdfPageFormat(
    settings.pageFormat.width,
    (totalHeight + 2 * margin + 14)
        .clamp(60 * PdfPageFormat.mm, 1000 * PdfPageFormat.mm)
        .toDouble(),
  );
  final doc = pw.Document(title: number, author: text(sale['business_name']));
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(margin),
      maxPages: 100,
      footer: (context) => pw.SizedBox(
        height: 8,
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 6),
          ),
        ),
      ),
      build: (_) => [for (final block in blocks) block.$1],
    ),
  );
  return GeneratedInvoicePdf(await doc.save(), format);
}
