import 'desktop_ui.dart';

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'app_currency.dart';
import 'activity_repository.dart';
import 'report_models.dart';

String _xml(Object? value) => '${value ?? ''}'
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String _column(int value) {
  var n = value + 1, result = '';
  while (n > 0) {
    n--;
    result = String.fromCharCode(65 + n % 26) + result;
    n ~/= 26;
  }
  return result;
}

List<String> _chunks(String text, int size) {
  final units = text.runes.toList();
  if (units.isEmpty) return [''];
  final result = <String>[];
  var start = 0, lines = 0;
  for (var i = 0; i < units.length; i++) {
    if (units[i] == 10) lines++;
    if (i - start + 1 >= size || lines >= 10) {
      result.add(String.fromCharCodes(units.sublist(start, i + 1)));
      start = i + 1;
      lines = 0;
    }
  }
  if (start < units.length) {
    result.add(String.fromCharCodes(units.sublist(start)));
  }
  return result;
}

void _zipText(Archive archive, String name, String text) {
  final bytes = utf8.encode(text);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

Uint8List buildReportExcel(ReportBook book) {
  final archive = Archive();
  final longText = <List<Object?>>[];
  final tables = [
    ReportTable(
      'Report Info',
      ['Field', 'Value'],
      [
        ['Business', book.business],
        ['Report', book.title],
        ['Filters', book.filters],
        ['Generated UTC', book.generatedAt.toIso8601String()],
        ['Currency', AppCurrency.code],
        [
          'Amounts',
          'Sales report amounts are currency units. Complete Data Export retains database minor units.',
        ],
        [
          'Attachments',
          'Attachment cells are references. Use Complete ZIP to include original files.',
        ],
        ['Nulls', 'An empty cell is null. Empty text cells retain text type.'],
        ['Tables', book.tables.length],
      ],
    ),
    ...book.tables,
  ];
  // Split overlong text into a dedicated continuation sheet, never silently truncate.
  final prepared = <ReportTable>[];
  for (final table in tables) {
    final rows = <List<Object?>>[];
    for (var i = 0; i < table.rows.length; i++) {
      rows.add([
        for (var j = 0; j < table.columns.length; j++)
          (() {
            final value = table.rows[i][j];
            if (value is String &&
                (value.length > 350 || '\n'.allMatches(value).length > 10)) {
              final parts = _chunks(value, 350);
              for (var k = 0; k < parts.length; k++) {
                longText.add([
                  table.title,
                  i + 1,
                  table.columns[j],
                  k + 1,
                  parts[k],
                ]);
              }
              return 'See Long Text: ${table.title}, data row ${i + 1}, ${table.columns[j]}';
            }
            return value;
          })(),
      ]);
    }
    // Excel supports 1,048,576 rows. Reserve report/title/header space.
    for (var offset = 0; offset < math.max(1, rows.length); offset += 1000000) {
      prepared.add(
        ReportTable(
          offset == 0 ? table.title : '${table.title} ${offset ~/ 1000000 + 1}',
          table.columns,
          rows.skip(offset).take(1000000).toList(),
          moneyColumns: table.moneyColumns,
        ),
      );
    }
  }
  if (longText.isNotEmpty) {
    prepared.add(
      ReportTable('Long Text', [
        'Sheet',
        'Data row',
        'Column',
        'Part',
        'Text',
      ], longText),
    );
  }
  final names = <String>[], used = <String>{};
  for (var i = 0; i < prepared.length; i++) {
    var base = prepared[i].title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ');
    base = base.substring(0, math.min(25, base.length));
    var name = base, suffix = 1;
    while (!used.add(name.toLowerCase())) {
      name = '$base ${suffix++}';
    }
    names.add(name);
  }
  final amountFormat = AppCurrency.digits == 0
      ? '#,##0;[Red]-#,##0'
      : '#,##0.00;[Red]-#,##0.00';
  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  _zipText(
    archive,
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${List.generate(prepared.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}'
        '</Types>',
  );
  _zipText(
    archive,
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  _zipText(
    archive,
    'xl/workbook.xml',
    '<workbook xmlns="$ns" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${List.generate(names.length, (i) => '<sheet name="${_xml(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}'
        '</sheets><definedNames>${List.generate(names.length, (i) => '<definedName name="_xlnm.Print_Titles" localSheetId="$i">&apos;${_xml(names[i].replaceAll("'", "''"))}&apos;!\$1:\$4</definedName>').join()}</definedNames></workbook>',
  );
  _zipText(
    archive,
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${List.generate(names.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}'
        '<Relationship Id="rId${names.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  );
  _zipText(
    archive,
    'xl/styles.xml',
    '''<styleSheet xmlns="$ns">
    <numFmts count="1"><numFmt numFmtId="164" formatCode="$amountFormat"/></numFmts>
    <fonts count="3"><font><sz val="11"/><name val="Myanmar Text"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Myanmar Text"/></font><font><b/><sz val="16"/><color rgb="FF00695C"/><name val="Myanmar Text"/></font></fonts>
    <fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF00695C"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF0F7F6"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="2"><border/><border><left style="thin"><color rgb="FFD5E4E1"/></left><right style="thin"><color rgb="FFD5E4E1"/></right><top style="thin"><color rgb="FFD5E4E1"/></top><bottom style="thin"><color rgb="FFD5E4E1"/></bottom></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1"><alignment vertical="top" horizontal="right"/></xf><xf numFmtId="164" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1"><alignment vertical="top" horizontal="right"/></xf></cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>''',
  );
  for (var index = 0; index < prepared.length; index++) {
    final table = prepared[index];
    final last = _column(table.columns.length - 1);
    String cell(Object? value, int col, int row, int style) {
      final address = '${_column(col)}$row';
      if (value == null) return '<c r="$address" s="$style"/>';
      if (value is num && (value is! int || value.abs() < 1000000000000000)) {
        return '<c r="$address" s="$style"><v>$value</v></c>';
      }
      return '<c r="$address" s="$style" t="inlineStr"><is><t xml:space="preserve">${_xml(value)}</t></is></c>';
    }

    final rows = StringBuffer();
    rows.write(
      '<row r="1" ht="32" customHeight="1">${cell('${book.business} · ${book.title} · ${table.title}', 0, 1, 2)}</row>',
    );
    final filterHeight = math.min(
      409,
      math.max(
        64,
        (book.filters.length / (table.columns.length * 25)).ceil() * 16 + 20,
      ),
    );
    rows.write(
      '<row r="2" ht="$filterHeight" customHeight="1">${cell(book.filters, 0, 2, 0)}</row>',
    );
    rows.write(
      '<row r="3">${cell('Generated UTC: ${book.generatedAt.toIso8601String()} | ${table.rows.length} rows', 0, 3, 0)}</row>',
    );
    rows.write(
      '<row r="4" ht="38" customHeight="1">${List.generate(table.columns.length, (j) => cell(table.columns[j], j, 4, 1)).join()}</row>',
    );
    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      final lines = row.fold<int>(
        1,
        (n, v) => math.max(
          n,
          '${v ?? ''}'
              .split('\n')
              .fold<int>(
                0,
                (sum, line) =>
                    sum + math.max(1, (line.runes.length / 24).ceil()),
              ),
        ),
      );
      final height = math.min(409, math.max(30, (lines + 1) * 16));
      rows.write(
        '<row r="${i + 5}" ht="$height" customHeight="1">${List.generate(table.columns.length, (j) => cell(row[j], j, i + 5, table.moneyColumns.contains(j) ? (i.isEven ? 5 : 6) : (i.isEven ? 3 : 4))).join()}</row>',
      );
    }
    _zipText(
      archive,
      'xl/worksheets/sheet${index + 1}.xml',
      '<worksheet xmlns="$ns">'
          '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><sheetViews><sheetView workbookViewId="0"><pane ySplit="4" topLeftCell="A5" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
          '<cols>${List.generate(table.columns.length, (j) => '<col min="${j + 1}" max="${j + 1}" width="${table.moneyColumns.contains(j) ? 20 : 28}" customWidth="1"/>').join()}</cols>'
          '<sheetData>$rows</sheetData><autoFilter ref="A4:$last${math.max(4, table.rows.length + 4)}"/>'
          '${table.columns.length > 1 ? '<mergeCells count="3"><mergeCell ref="A1:${last}1"/><mergeCell ref="A2:${last}2"/><mergeCell ref="A3:${last}3"/></mergeCells>' : ''}'
          '<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/>'
          '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
          '<headerFooter><oddFooter>&amp;CPage &amp;P of &amp;N</oddFooter></headerFooter></worksheet>',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _PdfRow {
  const _PdfRow(this.bytes, this.height);
  final Uint8List bytes;
  final double height;
}

Future<_PdfRow> _paintRow(
  List<String> cells,
  double width, {
  bool header = false,
  bool stripe = false,
  bool title = false,
}) async {
  const scale = 2.0;
  final painters = <TextPainter>[];
  final cellWidth = width / cells.length;
  for (final text in cells) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: title ? 13 : 8.5,
          height: 1.3,
          fontWeight: header || title ? FontWeight.bold : FontWeight.normal,
          color: header ? Colors.white : const Color(0xff172c29),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: cellWidth - 12);
    painters.add(painter);
  }
  final height = painters.fold<double>(0, (h, p) => math.max(h, p.height)) + 14;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(scale);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()
      ..color = header
          ? const Color(0xff00695c)
          : stripe
          ? const Color(0xffeff6f5)
          : Colors.white,
  );
  for (var i = 0; i < painters.length; i++) {
    painters[i].paint(canvas, Offset(i * cellWidth + 6, 7));
    canvas.drawLine(
      Offset(i * cellWidth, height),
      Offset((i + 1) * cellWidth, height),
      Paint()
        ..color = const Color(0xffd5e4e1)
        ..strokeWidth = .5,
    );
  }
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(
      (width * scale).ceil(),
      (height * scale).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not render report text');
    return _PdfRow(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      height,
    );
  } finally {
    image?.dispose();
    picture.dispose();
    for (final p in painters) {
      p.dispose();
    }
  }
}

Future<Uint8List> buildReportPdf(ReportBook book) async {
  final document = pw.Document();
  final format = PdfPageFormat.a4.landscape;
  const margin = 24.0;
  final width = format.width - margin * 2;
  final title = await _paintRow(
    ['${book.business} · ${book.title}'],
    width,
    title: true,
  );
  final filterRows = <_PdfRow>[];
  for (final text in _chunks(
    '${book.filters}\nGenerated UTC: ${book.generatedAt.toIso8601String()}',
    550,
  )) {
    filterRows.add(await _paintRow([text], width));
  }
  pw.Widget rowWidget(_PdfRow row) =>
      pw.Image(pw.MemoryImage(row.bytes), width: width, height: row.height);
  var pageNumber = 0;
  // At most five data columns per band; each repeats row number for exact joins.
  for (final table in book.tables) {
    for (var start = 0; start < table.columns.length; start += 5) {
      final end = math.min(start + 5, table.columns.length);
      final heading = await _paintRow(
        [
          '${table.title} · Columns ${start + 1}–$end / ${table.columns.length} · ${table.rows.length} records',
        ],
        width,
        title: true,
      );
      final header = await _paintRow(
        ['Row', ...table.columns.sublist(start, end)],
        width,
        header: true,
      );
      final fixedHeight =
          title.height +
          filterRows.fold<double>(0, (h, r) => h + r.height) +
          heading.height +
          header.height;
      final capacity = format.height - margin * 2 - 20 - fixedHeight;
      if (capacity < 100) throw StateError('Report heading is too tall');
      var pending = <_PdfRow>[], height = 0.0;
      void addPage() {
        final rows = List<_PdfRow>.of(pending);
        final number = ++pageNumber;
        document.addPage(
          pw.Page(
            pageFormat: format,
            margin: const pw.EdgeInsets.all(margin),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                rowWidget(title),
                ...filterRows.map(rowWidget),
                rowWidget(heading),
                rowWidget(header),
                ...rows.map(rowWidget),
                pw.Spacer(),
                pw.Text(
                  'Page $number | ${book.generatedAt.toIso8601String()} | Row numbers join column bands',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        );
        pending = [];
        height = 0;
      }

      for (var i = 0; i < table.rows.length; i++) {
        // Long cells continue on extra lines/rows rather than disappearing off the page.
        final pieces = [
          for (var j = start; j < end; j++)
            _chunks('${table.rows[i][j] ?? ''}', 120),
        ];
        final count = pieces.fold<int>(1, (n, p) => math.max(n, p.length));
        for (var part = 0; part < count; part++) {
          final row = await _paintRow(
            [
              '${i + 1}${part == 0 ? '' : ' cont.${part + 1}'}',
              for (final p in pieces) part < p.length ? p[part] : '',
            ],
            width,
            stripe: i.isOdd,
          );
          if (row.height > capacity) {
            throw StateError('A report row exceeds page size');
          }
          if (height + row.height > capacity && pending.isNotEmpty) addPage();
          pending.add(row);
          height += row.height;
        }
        if (i % 30 == 0) await Future<void>.delayed(Duration.zero);
      }
      if (pending.isNotEmpty || table.rows.isEmpty) addPage();
    }
  }
  for (final attachment in book.attachments) {
    if (!(attachment.path.endsWith('.png') ||
        attachment.path.endsWith('.jpg'))) {
      continue;
    }
    final caption = await _paintRow([attachment.path], width, title: true);
    final number = ++pageNumber;
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Column(
          children: [
            rowWidget(title),
            rowWidget(caption),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(
                  pw.MemoryImage(attachment.bytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
            pw.Text('Page $number', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ),
    );
  }
  return document.save();
}

Future<void> _recordReportPrepared(ReportBook book, String format) async {
  try {
    await ActivityRepository.exportPrepared(book, format);
  } catch (error) {
    // Export must remain usable for recovery even if the database cannot append an audit row.
    debugPrint('Report prepared; activity could not be recorded: $error');
  }
}

Future<void> shareReportExcel(ReportBook book) async {
  final bytes = buildReportExcel(book);
  await _recordReportPrepared(book, 'Excel');
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      fileNameOverrides: [
        'report_${book.generatedAt.millisecondsSinceEpoch}.xlsx',
      ],
    ),
  );
}

Future<void> shareCompleteReport(ReportBook book) async {
  final archive = Archive();
  final excel = buildReportExcel(book);
  archive.addFile(ArchiveFile('report.xlsx', excel.length, excel));
  _zipText(
    archive,
    'manifest.json',
    const JsonEncoder.withIndent('  ').convert({
      'title': book.title,
      'business': book.business,
      'filters': book.filters,
      'generated_utc': book.generatedAt.toIso8601String(),
      'currency': AppCurrency.code,
      'currency_digits': AppCurrency.digits,
      'tables': [
        for (final t in book.tables)
          {'title': t.title, 'columns': t.columns, 'rows': t.rows},
      ],
      'raw_data': book.rawData,
      'attachments': [
        for (final a in book.attachments)
          {'path': a.path, 'bytes': a.bytes.length},
      ],
    }),
  );
  for (final a in book.attachments) {
    archive.addFile(ArchiveFile(a.path, a.bytes.length, a.bytes));
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  await _recordReportPrepared(book, 'Complete ZIP');
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/zip')],
      fileNameOverrides: [
        'complete_report_${book.generatedAt.millisecondsSinceEpoch}.zip',
      ],
    ),
  );
}

Future<void> previewReport(BuildContext context, ReportBook book) async {
  final bytes = await buildReportPdf(book);
  await _recordReportPrepared(book, 'PDF / print preview');
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => DesktopScaffold(
        appBar: AppBar(title: Text(book.title)),
        body: PdfPreview(
          build: (_) async => bytes,
          initialPageFormat: PdfPageFormat.a4.landscape,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: 'report_${book.generatedAt.millisecondsSinceEpoch}.pdf',
        ),
      ),
    ),
  );
}
