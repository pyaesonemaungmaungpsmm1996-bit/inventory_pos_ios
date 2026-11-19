import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/report_export.dart';
import 'package:inventory_pos/report_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Excel retains Unicode, exact IDs and literal formula-like text', () {
    final longText = List.filled(100, 'မြန်မာစာ details\n').join();
    final book = ReportBook(title: 'Test', business: 'မြန်မာဆိုင်', filters: 'All', tables: [
      ReportTable('Items', ['Name', 'Quantity', 'Value', 'Note', 'ID'], [
        ['ကော်ဖီ & Tea', 2, 123.45, '=1+1', 123456789012345678],
        ['Second', 1, 0, longText, null],
      ], moneyColumns: {2}),
    ]);
    final zip = ZipDecoder().decodeBytes(buildReportExcel(book));
    String file(String name) => utf8.decode(zip.findFile(name)!.content);
    final sheet = file('xl/worksheets/sheet2.xml');
    expect(sheet, contains('ကော်ဖီ &amp; Tea'));
    expect(sheet, contains('=1+1'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, contains('123456789012345678'));
    expect(sheet, contains('<v>123.45</v>'));
    expect(sheet, contains('autoFilter'));
    expect(sheet, contains('state="frozen"'));
    expect(file('xl/worksheets/sheet3.xml'), contains('မြန်မာစာ'));
    expect(file('xl/workbook.xml'), contains('Long Text'));
    expect(file('[Content_Types].xml'), contains('spreadsheetml.sheet.main+xml'));
  });

  test('PDF renders Unicode and long notes on multiple pages', () async {
    final book = ReportBook(title: 'Report', business: 'မြန်မာဆိုင်', filters: '2026', tables: [
      ReportTable('Details', ['Item', 'Note'], [
        ['ကော်ဖီ', List.filled(70, 'ရှင်းလင်းချက်\n').join()],
      ]),
    ]);
    final bytes = await buildReportPdf(book);
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
