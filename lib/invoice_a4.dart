part of 'invoice_pdf.dart';

/// A4 stationery layout. Receipt rendering stays on its existing code path.
Future<GeneratedInvoicePdf> _buildA4Invoice({
  required Map<String, Object?> sale,
  required InvoicePrintSettings settings,
  required bool myanmar,
  required Uint8List? logo,
  required Map<int, Uint8List> photos,
}) async {
  final a4 = settings.a4;
  final kind = VoucherCode.kindOf(sale);
  final isReturn = kind == 'RET';
  final format = PdfPageFormat.a4;
  final margin = 10 * PdfPageFormat.mm;
  final width = format.width - margin * 2;
  // Paint transforms leave all flow measurements untouched: item/Remark/totals
  // and pagination retain the original mobile geometry.
  pw.Widget positioned(String id, pw.Widget child) => pw.Transform.translate(
    offset: PdfPoint(
      a4.placement(id, 'x') * PdfPageFormat.mm,
      -a4.placement(id, 'y') * PdfPageFormat.mm,
    ),
    child: pw.Transform.scale(scale: a4.placement(id, 'scale'), child: child),
  );
  String text(Object? value) => value?.toString().trim() ?? '';
  String t(String en, String my) => myanmar ? my : en;
  final currency = sale['currency_code'] as String? ?? 'MMK';
  final digits = sale['currency_digits'] as int? ?? 0;
  String money(Object? value) => AppCurrency.format(
    value as int,
    currency: currency,
    decimalPlaces: digits,
  );
  final originalNumber =
      sale['document_number'] as String? ??
      '${sale['document_prefix'] ?? 'INV'}-${(sale['id'] as int).toString().padLeft(6, '0')}';

  final savedCode = text(sale['branch_code_snapshot']);
  final branchId = sale['branch_id'];
  final prefix = savedCode.isNotEmpty
      ? savedCode
      : branchId is int && branchId > 0
      ? 'BR${branchId.toString().padLeft(2, '0')}'
      : 'BR00';
  final suffix =
      RegExp(r'[0-9]+$').stringMatch(originalNumber) ??
      (sale['id'] as int).toString();
  final number = kind == 'INV'
      ? '$prefix-${suffix.padLeft(6, '0')}'
      : originalNumber;

  Future<pw.Image> shaped(
    String value,
    double cellWidth, {
    bool bold = false,
    bool center = false,
    bool right = false,
    bool large = false,
    double? fontSize,
    bool shaded = false,
  }) async {
    final image = await _renderInvoiceRow(
      InvoicePrintRow(
        [value],
        bold: bold,
        center: center,
        right: right,
        large: large,
      ),
      cellWidth,
      false,
      fontSizeOverride: fontSize,
      background: shaded ? const Color(0xffeeeeee) : Colors.white,
    );
    return pw.Image(
      pw.MemoryImage(image.bytes),
      width: cellWidth,
      height: image.height,
    );
  }

  final logoWidth = a4.logoWidthMm * PdfPageFormat.mm;
  final inset = logo == null ? 0.0 : logoWidth + 10;
  final headingWidth = width - 2 * inset;
  final business = await shaped(
    a4.heading.trim().isEmpty ? text(sale['business_name']) : a4.heading.trim(),
    headingWidth,
    bold: true,
    center: true,
    fontSize: a4.headingSize,
  );
  final subtitle = a4.subtitle.trim().isEmpty
      ? null
      : await shaped(
          a4.subtitle.trim(),
          headingWidth,
          bold: true,
          center: true,
          fontSize: a4.subtitleSize,
        );
  final blocks = List<String>.from(
    sale['print_branch_blocks'] as List? ?? const [],
  );
  final branchAreaWidth = width - inset;
  final branchWidth = blocks.length > 1
      ? (branchAreaWidth - 12) / 2
      : headingWidth;
  final branchLeft = settings.showBranch && blocks.isNotEmpty
      ? await shaped(
          blocks.first,
          branchWidth,
          center: a4.leftBranchAlign == 'center',
          right: a4.leftBranchAlign == 'right',
          fontSize: 8.5,
        )
      : null;
  final branchRight = settings.showBranch && blocks.length > 1
      ? await shaped(
          blocks[1],
          branchWidth,
          center: a4.rightBranchAlign == 'center',
          right: a4.rightBranchAlign == 'right',
          fontSize: 8.5,
        )
      : null;
  pw.Widget legacyHeader() => pw.Column(
    children: [
      pw.Container(
        constraints: pw.BoxConstraints(
          minHeight: logo == null ? 0 : logoWidth * .82,
        ),
        child: pw.Stack(
          children: [
            pw.Column(
              children: [
                pw.Center(
                  child: pw.SizedBox(
                    width: headingWidth,
                    child: pw.Column(
                      children: [
                        positioned('heading', business),
                        if (subtitle != null) positioned('subtitle', subtitle),
                      ],
                    ),
                  ),
                ),
                if (branchLeft != null) ...[
                  pw.SizedBox(height: 10),
                  if (branchRight == null)
                    pw.Center(child: positioned('branch-left', branchLeft))
                  else
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logo != null) pw.SizedBox(width: inset),
                        positioned('branch-left', branchLeft),
                        ...[
                          pw.SizedBox(width: 5.5),
                          positioned(
                            'branch-divider',
                            pw.Container(
                              width: .5,
                              height: 58,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          positioned('branch-right', branchRight),
                        ],
                      ],
                    ),
                ],
              ],
            ),
            if (logo != null)
              pw.Positioned(
                left: 0,
                top: 0,
                child: pw.SizedBox(
                  width: logoWidth,
                  height: logoWidth * .82,
                  child: positioned(
                    'logo',
                    pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Divider(thickness: .7),
    ],
  );

  // Keep the legacy header's flow height for this invoice. The editable blocks
  // occupy only that space, so changing their positions cannot reflow the body.
  final headerHeight = math.max(
    logo == null ? 0.0 : logoWidth * .82,
    business.height! +
        (subtitle?.height ?? 0) +
        (branchLeft == null
            ? 0.0
            : 10 +
                  (branchRight == null
                      ? branchLeft.height!
                      : math.max(
                          58.0,
                          math.max(branchLeft.height!, branchRight.height!),
                        ))),
  );
  final regions = <String, Rect>{};
  final elements = <pw.Widget>[];
  if (kind == 'INV') {
    final addresses = List<String>.from(
      sale['print_a4_branch_blocks'] as List? ?? blocks,
    );
    final hasAddresses = settings.showBranch && addresses.isNotEmpty;
    final top = hasAddresses ? headerHeight * .55 : headerHeight;
    void add(String id, Rect base, pw.Widget child) {
      final scale = a4.placement(id, 'scale');
      final w = math.min(width, base.width * scale);
      final h = math.min(headerHeight, base.height * scale);
      final x = (base.left + a4.placement(id, 'x') * PdfPageFormat.mm).clamp(
        0.0,
        width - w,
      );
      final y = (base.top + a4.placement(id, 'y') * PdfPageFormat.mm).clamp(
        0.0,
        headerHeight - h,
      );
      regions[id] = Rect.fromLTWH(margin + x, margin + y, w, h);
      elements.add(
        pw.Positioned(
          left: x,
          top: y,
          child: pw.SizedBox(
            width: w,
            height: h,
            child: pw.FittedBox(
              fit: pw.BoxFit.contain,
              alignment: pw.Alignment.topLeft,
              child: child,
            ),
          ),
        ),
      );
    }

    if (logo != null) {
      add(
        'a4-logo',
        Rect.fromLTWH(0, 0, logoWidth, top),
        pw.Image(
          pw.MemoryImage(logo),
          width: logoWidth,
          height: top,
          fit: pw.BoxFit.contain,
        ),
      );
    }
    final titleWidth = width - inset;
    final title = await shaped(
      a4.heading.trim().isEmpty
          ? text(sale['business_name'])
          : a4.heading.trim(),
      titleWidth,
      bold: true,
      fontSize: a4.headingSize,
    );
    final second = a4.subtitle.trim().isEmpty
        ? null
        : await shaped(
            a4.subtitle.trim(),
            titleWidth,
            bold: true,
            fontSize: a4.subtitleSize,
          );
    add(
      'a4-heading',
      Rect.fromLTWH(inset, 0, titleWidth, top),
      pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [title, ?second]),
    );
    if (hasAddresses) {
      final addressWidth = (width - 16) / 3;
      final y = top + 3;
      for (var i = 0; i < math.min(addresses.length, 3); i++) {
        final align = i == 0
            ? a4.leftBranchAlign
            : i == 1
            ? a4.rightBranchAlign
            : 'left';
        final id = A4LayoutSettings.editableHeader[i + 2];
        final cellWidth = addressWidth * a4.placement(id, 'scale');
        add(
          id,
          Rect.fromLTWH(
            i * (addressWidth + 8),
            y,
            addressWidth,
            headerHeight - y,
          ),
          await shaped(
            addresses[i],
            cellWidth,
            fontSize: 8.5,
            center: align == 'center',
            right: align == 'right',
          ),
        );
      }
    }
  }
  pw.Widget header() => kind != 'INV'
      ? legacyHeader()
      : pw.Column(
          children: [
            pw.SizedBox(
              width: width,
              height: headerHeight,
              child: pw.ClipRect(child: pw.Stack(children: elements)),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: .7),
          ],
        );

  final infoWidth = (width - 76) / 2;
  Future<pw.Widget> detail(
    String label,
    String value, {
    bool bold = false,
  }) async => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      await shaped(label, a4.labelWidth, bold: true, fontSize: a4.infoSize),
      await shaped(':', 8, fontSize: a4.infoSize),
      await shaped(
        value,
        infoWidth - a4.labelWidth - 8,
        bold: bold,
        fontSize: a4.infoSize,
      ),
    ],
  );
  final customer = <pw.Widget>[];
  if (settings.showCustomer && sale['document_prefix'] != 'EXP') {
    final supplier = sale['document_prefix'] == 'PUR';
    customer.add(
      await detail(
        supplier ? t('Supplier', 'ကုန်ပေးသွင်းသူ') : t('Customer', 'ဝယ်သူ'),
        text(sale['customer_name']).isEmpty
            ? 'Walk-in'
            : text(sale['customer_name']),
      ),
    );
    customer.add(
      await detail(t('Address', 'လိပ်စာ'), text(sale['customer_address'])),
    );
    customer.add(
      await detail(t('Phone', 'ဖုန်း'), text(sale['customer_phone'])),
    );
    if (text(sale['customer_company']).isNotEmpty) {
      customer.add(
        await detail(t('Company', 'ကုမ္ပဏီ'), text(sale['customer_company'])),
      );
    }
  }
  final metadata = <pw.Widget>[
    await detail('Invoice No.', number),
    if (settings.showSalePerson)
      await detail(
        isReturn
            ? t('Processed by', 'ဆောင်ရွက်သူ')
            : kind == 'PUR'
            ? t('Purchased by', 'ဝယ်ယူသူ')
            : t('Sale person', 'အရောင်းဝန်ထမ်း'),
        text(sale['employee_name']),
      ),
  ];
  final documentTitle = switch (kind) {
    'RET' => t('Sale Return Invoice', 'အရောင်းပြန်အမ်းဘောင်ချာ'),
    'PUR' => t('Purchase Invoice', 'အဝယ်ဘောင်ချာ'),
    'EXP' => t('Expense Voucher', 'အသုံးစရိတ်ဘောင်ချာ'),
    _ => t('Sale Invoice', 'အရောင်းဘောင်ချာ'),
  };
  final title = await shaped(
    sale['status'] == 'draft' ? '$documentTitle - DRAFT' : documentTitle,
    width * .55,
    bold: true,
    large: true,
    shaded: true,
  );
  final date = settings.showDate
      ? await shaped(
          'Date : ${text(sale['invoice_date'])}',
          width * .45,
          right: true,
          shaded: true,
        )
      : pw.SizedBox();
  final notice = <pw.Widget>[];
  if (sale['status'] == 'void') {
    notice.add(
      await shaped('VOID : ${text(sale['void_reason'])}', width, bold: true),
    );
  }
  if (sale['replacement_id'] != null) {
    notice.add(await shaped('Corrected by : ${sale['replacement_id']}', width));
  }

  if (isReturn) {
    notice.add(
      await shaped(
        'Original invoice: INV-${(sale['sale_id'] as int).toString().padLeft(6, '0')}',
        width,
      ),
    );
    notice.add(
      await shaped(
        '${t('Reason', 'အကြောင်းပြချက်')}: ${text(sale['reason'])}',
        width,
      ),
    );
  }
  // Keep currency amounts in their original invoice snapshot currency.
  final totalsFraction = a4.totalsPercent / 100;
  final fractions = <double>[
    .045,
    1 - totalsFraction - .045,
    settings.showPrices ? .065 : totalsFraction / 2,
    if (settings.showPrices) totalsFraction / 2 - .065,
    totalsFraction / 2,
  ];
  final fractionTotal = fractions.fold<double>(0, (a, b) => a + b);
  final cellWidths = fractions
      .map((f) => width * f / fractionTotal - 8)
      .toList();
  Future<pw.TableRow> tableRow(
    List<String> cells, {
    bool heading = false,
    Uint8List? photo,
  }) async {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < cells.length; i++) {
      final value = await shaped(
        cells[i],
        cellWidths[i],
        bold: heading,
        center: i == 0 || i == 2,
        right: i >= 3,
        fontSize: a4.tableSize,
        shaded: heading,
      );
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.all(4),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              value,
              if (i == 1 && photo != null)
                pw.SizedBox(
                  width: 46,
                  height: 40,
                  child: pw.Image(
                    pw.MemoryImage(photo),
                    fit: pw.BoxFit.contain,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return pw.TableRow(
      repeat: heading,
      decoration: heading
          ? pw.BoxDecoration(color: PdfColor.fromHex('#eeeeee'))
          : null,
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: widgets,
    );
  }

  final tableRows = <pw.TableRow>[
    await tableRow([
      'No.',
      t('Item name', 'ပစ္စည်းအမည်'),
      t('Qty', 'အရေအတွက်'),
      if (settings.showPrices) t('Price', 'ဈေးနှုန်း'),
      t('Amount', 'ကျသင့်ငွေ'),
    ], heading: true),
  ];
  var index = 0;
  for (final raw in sale['items'] as List) {
    final item = Map<String, Object?>.from(raw as Map);
    final description = <String>[
      '${settings.showItemCode && text(item['item_code']).isNotEmpty ? '${text(item['item_code'])} - ' : ''}${text(item['item_name'])}',
      if ('${item['color_snapshot'] ?? ''}${item['size_snapshot'] ?? ''}'
          .isNotEmpty)
        '${t('Color / Size', 'အရောင် / အရွယ်')}: ${item['color_snapshot'] ?? ''} / ${item['size_snapshot'] ?? ''}',
      if (settings.showDiscount && (item['item_discount'] as int? ?? 0) > 0)
        '${t('Item discount', 'ပစ္စည်းလျှော့ဈေး')}: ${money(item['item_discount'])}',
      for (final lot in ProductTracking.decode(item['tracking_json'])) ...[
        if (lot['serial'] != null) 'Serial: ${lot['serial']}',
        if (lot['imei'] != null) 'IMEI: ${lot['imei']}',
        if (lot['expires_on'] != null) 'Expiry: ${lot['expires_on']}',
        if (lot['warranty_until'] != null)
          'Warranty until: ${lot['warranty_until']}',
      ],
    ].join('\n');
    // Bound each physical table row so large serial lists can cross pages.
    final pieces = <String>[];
    for (var start = 0; start < description.length; start += 500) {
      pieces.add(
        description.substring(start, math.min(start + 500, description.length)),
      );
    }
    if (pieces.isEmpty) pieces.add('');
    index++;
    for (var part = 0; part < pieces.length; part++) {
      tableRows.add(
        await tableRow([
          part == 0 ? '$index' : '',
          pieces[part],
          part == 0 ? '${item['qty']}' : '',
          if (settings.showPrices)
            part == 0 && item['price'] != null ? money(item['price']) : '',
          part == 0
              ? money(
                  (item['amount'] as int) -
                      (item['item_discount'] as int? ?? 0),
                )
              : '',
        ], photo: part == 0 ? photos[item['product_id']] : null),
      );
    }
  }

  final totalsWidth = width * totalsFraction;
  final remarkWidth = width - totalsWidth;
  final summary = <(pw.Widget, pw.Widget, double)>[];
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
          ? t('Total refunded', 'ပြန်အမ်းငွေစုစုပေါင်း')
          : t('Total amount', 'ကျသင့်ငွေစုစုပေါင်း'),
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
    final label = await _renderInvoiceRow(
      InvoicePrintRow([entry.$1], bold: entry.$3),
      totalsWidth / 2 - 8,
      false,
      fontSizeOverride: a4.infoSize,
      background: const Color(0xffeeeeee),
    );
    final amount = await _renderInvoiceRow(
      InvoicePrintRow([money(entry.$2)], bold: entry.$3, right: true),
      totalsWidth / 2 - 8,
      false,
      fontSizeOverride: a4.infoSize,
    );
    summary.add((
      pw.Image(
        pw.MemoryImage(label.bytes),
        width: totalsWidth / 2 - 8,
        height: label.height,
      ),
      pw.Image(
        pw.MemoryImage(amount.bytes),
        width: totalsWidth / 2 - 8,
        height: amount.height,
      ),
      math.max(label.height, amount.height) + 8,
    ));
  }
  final remarkImage = await _renderInvoiceRow(
    InvoicePrintRow([
      '${a4.remarkLabel} : ${text(sale['remark'])}',
    ], bold: true),
    remarkWidth - 12,
    false,
    fontSizeOverride: a4.infoSize,
  );
  // The Remark box ends at Discount; later totals continue on the right.
  final totalBandCount = settings.showDiscount
      ? summary.length - 3
      : summary.length - 2;
  final bandHeight = summary
      .take(totalBandCount)
      .fold<double>(0, (h, row) => h + row.$3);
  final commonHeight = math.max(bandHeight, remarkImage.height + 12);
  final rowExtra = (commonHeight - bandHeight) / totalBandCount;
  final bottomGrid = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Container(
        width: remarkWidth,
        height: commonHeight,
        padding: const pw.EdgeInsets.all(6),
        alignment: pw.Alignment.topLeft,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: .5)),
        child: pw.Image(
          pw.MemoryImage(remarkImage.bytes),
          width: remarkWidth - 12,
          height: remarkImage.height,
        ),
      ),
      pw.SizedBox(
        width: totalsWidth,
        child: pw.Table(
          border: pw.TableBorder.all(width: .5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            for (final (index, row) in summary.indexed)
              pw.TableRow(
                children: [
                  pw.Container(
                    height: row.$3 + (index < totalBandCount ? rowExtra : 0),
                    color: PdfColor.fromHex('#eeeeee'),
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.centerLeft,
                    child: row.$1,
                  ),
                  pw.Container(
                    height: row.$3 + (index < totalBandCount ? rowExtra : 0),
                    padding: const pw.EdgeInsets.all(4),
                    alignment: pw.Alignment.centerRight,
                    child: row.$2,
                  ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
  final signatureWidth = (width - 36) / 3;
  final signatures = <pw.Widget>[];
  for (final (signatureIndex, label) in [
    kind == 'PUR' &&
            a4.customerSignature == const A4LayoutSettings().customerSignature
        ? "Supplier's Signature"
        : a4.customerSignature,
    a4.cashierSignature,
    a4.authorizedSignature,
  ].indexed) {
    signatures.add(
      pw.SizedBox(
        width: signatureWidth,
        child: positioned(
          [
            'signature-left',
            'signature-middle',
            'signature-right',
          ][signatureIndex],
          pw.Column(
            children: [
              pw.Divider(thickness: .5),
              await shaped(label, signatureWidth, center: true),
            ],
          ),
        ),
      ),
    );
  }
  final footerText = settings.footer.trim().isEmpty
      ? null
      : await shaped(settings.footer.trim(), width, center: true);
  final printedAt = AppDateTime.format(
    DateTime.now().toUtc().toIso8601String(),
  );
  final doc = pw.Document(title: number, author: text(sale['business_name']));
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(margin),
      maxPages: 100,
      header: (_) => header(),
      footer: (context) => pw.SizedBox(
        height: 88,
        child: pw.Column(
          children: [
            pw.Spacer(),
            if (context.pageNumber == context.pagesCount) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: signatures,
              ),
              pw.SizedBox(height: 8),
              if (footerText != null) positioned('footer', footerText),
            ],
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                positioned(
                  'print-date',
                  pw.Text(
                    'Print Date : $printedAt',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
                positioned(
                  'page-number',
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      build: (_) => [
        pw.Container(
          color: PdfColor.fromHex('#eeeeee'),
          child: pw.Row(
            children: [
              positioned('invoice-title', title),
              positioned('invoice-date', date),
            ],
          ),
        ),
        ...notice,
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              width: infoWidth * 2,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: infoWidth,
                    child: positioned(
                      'customer-block',
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: customer,
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: infoWidth,
                    child: positioned(
                      'invoice-info',
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: metadata,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            if (sale['status'] == 'draft')
              pw.SizedBox(width: 64, height: 64)
            else
              positioned(
                'voucher-qr',
                pw.BarcodeWidget(
                  barcode: bc.Barcode.qrCode(),
                  data: VoucherCode.encode(sale),
                  width: 64,
                  height: 64,
                  drawText: false,
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(width: .5),
          columnWidths: {
            for (var i = 0; i < fractions.length; i++)
              i: pw.FlexColumnWidth(fractions[i]),
          },
          children: tableRows,
        ),
        bottomGrid,
      ],
    ),
  );
  return GeneratedInvoicePdf(await doc.save(), format, headerRegions: regions);
}
