import 'dart:math' as math;
part 'reference_invoice_template.dart';

class PrintColumn {
  const PrintColumn({
    required this.title,
    required this.expression,
    this.weight = 1,
    this.align = 'left',
  });
  final String title, expression, align;
  final double weight;
  Map<String, Object> toJson() => {
    'title': title,
    'expression': expression,
    'weight': weight,
    'align': align,
  };
  factory PrintColumn.fromJson(Map json) => PrintColumn(
    title: json['title'] as String,
    expression: json['expression'] as String,
    weight: (json['weight'] as num).toDouble(),
    align: json['align'] as String? ?? 'left',
  );
}

class PrintElement {
  const PrintElement({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text = '',
    this.fontSize = 10,
    this.fontFamily = '',
    this.bold = false,
    this.italic = false,
    this.align = 'left',
    this.color = 0xff000000,
    this.fill = 0x00ffffff,
    this.border = 0,
    this.borderColor = 0xff000000,
    this.lastPageOnly = false,
    this.locked = false,
    this.qr = false,
    this.imageBase64 = '',
    this.rowHeight = 8,
    this.headerHeight = 7,
    this.columns = const [],
    this.fitText = true,
  });
  final String id, kind, text, fontFamily, align, imageBase64;
  final double x, y, width, height, fontSize, border, rowHeight, headerHeight;
  final int color, fill, borderColor;
  final bool bold, italic, lastPageOnly, locked, qr, fitText;
  final List<PrintColumn> columns;
  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'text': text,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'bold': bold,
    'italic': italic,
    'align': align,
    'color': color,
    'fill': fill,
    'border': border,
    'borderColor': borderColor,
    'lastPageOnly': lastPageOnly,
    'locked': locked,
    'qr': qr,
    'imageBase64': imageBase64,
    'rowHeight': rowHeight,
    'headerHeight': headerHeight,
    'columns': columns.map((c) => c.toJson()).toList(),
    'fitText': fitText,
  };
  factory PrintElement.fromJson(Map json) {
    double n(String key, double fallback) =>
        (json[key] as num? ?? fallback).toDouble();
    return PrintElement(
      id: json['id'] as String,
      kind: json['kind'] as String,
      x: n('x', 0),
      y: n('y', 0),
      width: n('width', 10),
      height: n('height', 10),
      text: json['text'] as String? ?? '',
      fontSize: n('fontSize', 10),
      fontFamily: json['fontFamily'] as String? ?? '',
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      align: json['align'] as String? ?? 'left',
      color: json['color'] as int? ?? 0xff000000,
      fill: json['fill'] as int? ?? 0x00ffffff,
      border: n('border', 0),
      borderColor: json['borderColor'] as int? ?? 0xff000000,
      lastPageOnly: json['lastPageOnly'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      qr: json['qr'] as bool? ?? false,
      imageBase64: json['imageBase64'] as String? ?? '',
      rowHeight: n('rowHeight', 8),
      headerHeight: n('headerHeight', 7),
      columns: (json['columns'] as List? ?? [])
          .map((c) => PrintColumn.fromJson(c as Map))
          .toList(),
      fitText: json['fitText'] as bool? ?? true,
    );
  }
  PrintElement withValues(Map<String, Object?> values) =>
      PrintElement.fromJson({...toJson(), ...values});
}

class PrintTemplate {
  const PrintTemplate({
    this.name = 'Custom layout',
    this.width = 210,
    this.height = 297,
    this.elements = const [],
    this.label = false,
  });
  final String name;
  final double width, height;
  final List<PrintElement> elements;
  final bool label;
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${math.Random.secure().nextInt(1 << 30).toRadixString(36)}';
  Map<String, Object> toJson() => {
    'version': 1,
    'name': name,
    'width': width,
    'height': height,
    'label': label,
    'elements': elements.map((e) => e.toJson()).toList(),
  };
  factory PrintTemplate.fromJson(Map json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported template version');
    }
    final value = PrintTemplate(
      name: json['name'] as String,
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      label: json['label'] as bool? ?? false,
      elements: (json['elements'] as List)
          .map((e) => PrintElement.fromJson(e as Map))
          .toList(),
    );
    value.validate();
    return value;
  }
  PrintTemplate copyWith({
    String? name,
    double? width,
    double? height,
    List<PrintElement>? elements,
  }) => PrintTemplate(
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    elements: elements ?? this.elements,
    label: label,
  );
  PrintTemplate resized(double w, double h) {
    final sx = w / width, sy = h / height, scale = math.min(sx, sy);
    final value = copyWith(
      width: w,
      height: h,
      elements: [
        for (final e in elements)
          e.withValues({
            'x': e.x * sx,
            'y': e.y * sy,
            'width': e.width * sx,
            'height': e.height * sy,
            'fontSize': math.max(1, e.fontSize * scale),
            'rowHeight': e.rowHeight * sy,
            'headerHeight': e.headerHeight * sy,
          }),
      ],
    );
    value.validate();
    return value;
  }

  void validate() {
    bool finite(double v) => v.isFinite;
    if (!finite(width) ||
        !finite(height) ||
        width <= 0 ||
        height <= 0 ||
        width > 5000 ||
        height > 5000 ||
        name.length > 200 ||
        elements.length > 1000) {
      throw const FormatException('Invalid template page');
    }
    final ids = <String>{};
    for (final e in elements) {
      if (e.id.isEmpty ||
          !ids.add(e.id) ||
          ![
            'text',
            'image',
            'line',
            'box',
            'barcode',
            'table',
          ].contains(e.kind) ||
          ![
            e.x,
            e.y,
            e.width,
            e.height,
            e.fontSize,
            e.border,
            e.rowHeight,
            e.headerHeight,
          ].every(finite) ||
          e.x < 0 ||
          e.y < 0 ||
          e.width <= 0 ||
          e.height <= 0 ||
          e.x + e.width > width + .001 ||
          e.y + e.height > height + .001 ||
          e.fontSize < 1 ||
          e.fontSize > 500 ||
          e.border < 0 ||
          e.border > 50 ||
          !['left', 'center', 'right'].contains(e.align) ||
          e.text.length > 20000 ||
          e.imageBase64.length > 6 * 1024 * 1024) {
        throw const FormatException(
          'An element is invalid or outside the paper',
        );
      }
      for (final value in [e.color, e.fill, e.borderColor]) {
        if (value < 0 || value > 0xffffffff) {
          throw const FormatException('Invalid element color');
        }
      }
      if (e.kind == 'table') {
        if (e.columns.isEmpty ||
            e.rowHeight <= 0 ||
            e.headerHeight < 0 ||
            e.height < e.headerHeight + e.rowHeight) {
          throw const FormatException(
            'The item table needs room for a header and at least one row',
          );
        }
        for (final c in e.columns) {
          if (c.title.length > 300 ||
              c.expression.length > 1000 ||
              !c.weight.isFinite ||
              c.weight <= 0 ||
              !['left', 'center', 'right'].contains(c.align)) {
            throw const FormatException('Invalid item-table column');
          }
        }
      }
    }
  }

  int rowsPerPage() {
    final tables = elements.where((e) => e.kind == 'table');
    if (tables.isEmpty) return 0;
    return tables
        .map((e) => ((e.height - e.headerHeight) / e.rowHeight).floor())
        .reduce(math.min);
  }

  List<(int, int)> pageRanges(int count) {
    validate();
    if (count < 0) throw ArgumentError('Invalid row count');
    final capacity = rowsPerPage();
    if (capacity == 0 || count == 0) return [(0, count)];
    return [
      for (var start = 0; start < count; start += capacity)
        (start, math.min(count, start + capacity)),
    ];
  }

  factory PrintTemplate.invoice({PrintTemplate? previous}) =>
      originalMobileInvoiceTemplate(previous: previous);
  factory PrintTemplate.legacyInvoice() {
    return const PrintTemplate(
      elements: [
        PrintElement(
          id: 'logo',
          kind: 'image',
          x: 10,
          y: 10,
          width: 28,
          height: 25,
        ),
        PrintElement(
          id: 'business',
          kind: 'text',
          x: 44,
          y: 10,
          width: 156,
          height: 12,
          text: '{business.name}',
          fontSize: 22,
          bold: true,
          align: 'center',
        ),
        PrintElement(
          id: 'branches',
          kind: 'text',
          x: 44,
          y: 24,
          width: 156,
          height: 24,
          text: '{branch.info}',
          fontSize: 9,
          align: 'center',
        ),
        PrintElement(
          id: 'title',
          kind: 'text',
          x: 10,
          y: 51,
          width: 190,
          height: 9,
          text: '{invoice.title} · {invoice.number}',
          fontSize: 15,
          bold: true,
          align: 'center',
        ),
        PrintElement(
          id: 'customer',
          kind: 'text',
          x: 10,
          y: 65,
          width: 118,
          height: 23,
          text: 'Customer: {customer.name}\nPhone: {customer.phone}\n{customer.company}\n{customer.address}',
          fontSize: 9,
        ),
        PrintElement(
          id: 'date',
          kind: 'text',
          x: 135,
          y: 65,
          width: 65,
          height: 20,
          text: 'Date: {invoice.date}\nSalesperson: {employee.name}\n{customer.id}',
          fontSize: 9,
        ),
        PrintElement(
          id: 'items',
          kind: 'table',
          x: 10,
          y: 92,
          width: 190,
          height: 139,
          border: .2,
          fontSize: 9,
          columns: [
            PrintColumn(
              title: 'Item',
              expression: '{item.code} · {item.name}',
              weight: 5,
            ),
            PrintColumn(title: 'Qty', expression: '{item.qty}', align: 'right'),
            PrintColumn(
              title: 'Price',
              expression: '{item.unit_price}',
              weight: 2,
              align: 'right',
            ),
            PrintColumn(
              title: 'Discount',
              expression: '{item.discount}',
              weight: 2,
              align: 'right',
            ),
            PrintColumn(
              title: 'Amount',
              expression: '{item.amount}',
              weight: 2,
              align: 'right',
            ),
          ],
        ),
        PrintElement(
          id: 'remark',
          kind: 'text',
          x: 10,
          y: 238,
          width: 108,
          height: 30,
          text: 'Remark: {invoice.remark}',
          fontSize: 9,
          lastPageOnly: true,
        ),
        PrintElement(
          id: 'totals',
          kind: 'text',
          x: 124,
          y: 238,
          width: 76,
          height: 32,
          text: 'Subtotal: {totals.subtotal}\nDiscount: {totals.discount}\nTotal: {totals.total}\nPaid: {totals.paid}\nBalance: {totals.balance}',
          fontSize: 10,
          bold: true,
          lastPageOnly: true,
        ),
        PrintElement(
          id: 'footer',
          kind: 'text',
          x: 10,
          y: 277,
          width: 155,
          height: 10,
          text: '{footer}',
          fontSize: 8,
        ),
        PrintElement(
          id: 'pages',
          kind: 'text',
          x: 170,
          y: 277,
          width: 30,
          height: 10,
          text: '{page.number} / {page.count}',
          fontSize: 8,
          align: 'right',
        ),
      ],
    );
  }
  factory PrintTemplate.receipt({double width = 80, double height = 200}) =>
      const PrintTemplate(
        name: 'Custom receipt',
        width: 80,
        height: 200,
        elements: [
          PrintElement(
            id: 'logo',
            kind: 'image',
            x: 3,
            y: 3,
            width: 16,
            height: 16,
          ),
          PrintElement(
            id: 'business',
            kind: 'text',
            x: 22,
            y: 3,
            width: 55,
            height: 15,
            text: '{business.name}',
            fontSize: 14,
            bold: true,
            align: 'center',
          ),
          PrintElement(
            id: 'branch',
            kind: 'text',
            x: 3,
            y: 21,
            width: 74,
            height: 20,
            text: '{branch.info}',
            fontSize: 8,
            align: 'center',
          ),
          PrintElement(
            id: 'number',
            kind: 'text',
            x: 3,
            y: 43,
            width: 74,
            height: 8,
            text: '{invoice.number} · {invoice.date}',
            fontSize: 8,
            bold: true,
          ),
          PrintElement(
            id: 'customer',
            kind: 'text',
            x: 3,
            y: 52,
            width: 74,
            height: 12,
            text: '{customer.name} · {customer.phone}',
            fontSize: 8,
          ),
          PrintElement(
            id: 'items',
            kind: 'table',
            x: 3,
            y: 66,
            width: 74,
            height: 76,
            fontSize: 8,
            border: .15,
            rowHeight: 8,
            headerHeight: 6,
            columns: [
              PrintColumn(title: 'Item', expression: '{item.name}', weight: 4),
              PrintColumn(
                title: 'Qty',
                expression: '{item.qty}',
                align: 'right',
              ),
              PrintColumn(
                title: 'Amount',
                expression: '{item.amount}',
                weight: 2,
                align: 'right',
              ),
            ],
          ),
          PrintElement(
            id: 'totals',
            kind: 'text',
            x: 3,
            y: 146,
            width: 48,
            height: 26,
            text: 'Total: {totals.total}\nPaid: {totals.paid}\nBalance: {totals.balance}',
            fontSize: 10,
            bold: true,
            lastPageOnly: true,
          ),
          PrintElement(
            id: 'voucher-qr',
            kind: 'barcode',
            x: 54,
            y: 146,
            width: 23,
            height: 23,
            qr: true,
            text: '{invoice.qr}',
            lastPageOnly: true,
          ),
          PrintElement(
            id: 'footer',
            kind: 'text',
            x: 3,
            y: 176,
            width: 74,
            height: 14,
            text: '{invoice.remark}\n{footer}',
            fontSize: 8,
            lastPageOnly: true,
          ),
          PrintElement(
            id: 'page',
            kind: 'text',
            x: 3,
            y: 193,
            width: 74,
            height: 4,
            text: '{page.number} / {page.count}',
            fontSize: 6,
            align: 'right',
          ),
        ],
      ).resized(width, height);
  factory PrintTemplate.barcodeLabel({double width = 50, double height = 30}) =>
      const PrintTemplate(
        name: 'Custom label',
        width: 50,
        height: 30,
        label: true,
        elements: [
          PrintElement(
            id: 'name',
            kind: 'text',
            x: 2,
            y: 1,
            width: 46,
            height: 6,
            text: '{item.name}',
            fontSize: 8,
            bold: true,
            align: 'center',
          ),
          PrintElement(
            id: 'barcode',
            kind: 'barcode',
            x: 3,
            y: 8,
            width: 44,
            height: 13,
            text: '{item.barcode}',
          ),
          PrintElement(
            id: 'code',
            kind: 'text',
            x: 2,
            y: 22,
            width: 46,
            height: 3,
            text: '{item.code}',
            fontSize: 6,
            align: 'center',
          ),
          PrintElement(
            id: 'price',
            kind: 'text',
            x: 2,
            y: 26,
            width: 46,
            height: 3,
            text: '{item.unit_price}',
            fontSize: 8,
            bold: true,
            align: 'center',
          ),
        ],
      ).resized(width, height);
}
