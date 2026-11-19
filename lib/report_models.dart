import 'dart:typed_data';

class ReportTable {
  const ReportTable(
    this.title,
    this.columns,
    this.rows, {
    this.moneyColumns = const {},
  });
  final String title;
  final List<String> columns;
  final List<List<Object?>> rows;
  final Set<int> moneyColumns;
}

class ReportAttachment {
  const ReportAttachment(this.path, this.bytes);
  final String path;
  final Uint8List bytes;
}

class ReportBook {
  ReportBook({
    required this.title,
    required this.business,
    required this.filters,
    required this.tables,
    this.attachments = const [],
    this.rawData,
  });
  final String title, business, filters;
  final List<ReportTable> tables;
  final List<ReportAttachment> attachments;
  final Map<String, Object?>? rawData;
  final generatedAt = DateTime.now().toUtc();
}
