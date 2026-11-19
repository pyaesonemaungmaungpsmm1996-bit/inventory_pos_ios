import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'report_models.dart';

class ReportTablePreview extends StatefulWidget {
  const ReportTablePreview({super.key, required this.table, this.onOpen});
  final ReportTable table;
  final ValueChanged<List<Object?>>? onOpen;
  @override
  State<ReportTablePreview> createState() => _ReportTablePreviewState();
}

class _ReportTablePreviewState extends State<ReportTablePreview> {
  late _ReportRows source;
  int pageSize = 10;
  @override
  void initState() {
    super.initState();
    source = _ReportRows(widget.table, detail);
  }

  @override
  void didUpdateWidget(covariant ReportTablePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) {
      source.dispose();
      source = _ReportRows(widget.table, detail);
    }
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  void detail(List<Object?> row) {
    if (widget.onOpen != null) {
      widget.onOpen!(row);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(widget.table.title),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.table.columns.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.table.columns[i],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SelectableText('${row[i] ?? ''}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(
              (AppLanguage.current.value == 'my' ? 'ပိတ်ရန်' : 'Close'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PaginatedDataTable(
    key: ValueKey(widget.table),
    showFirstLastButtons: true,
    rowsPerPage: pageSize,
    availableRowsPerPage: const [10, 25, 50],
    onRowsPerPageChanged: (value) {
      if (value != null) setState(() => pageSize = value);
    },
    columns: widget.table.columns
        .map((c) => DataColumn(label: Text(c)))
        .toList(),
    source: source,
  );
}

class _ReportRows extends DataTableSource {
  _ReportRows(this.table, this.onOpen);
  final ReportTable table;
  final ValueChanged<List<Object?>> onOpen;
  @override
  DataRow? getRow(int index) {
    if (index >= table.rows.length) return null;
    final row = table.rows[index];
    return DataRow.byIndex(
      index: index,
      onSelectChanged: (_) => onOpen(row),
      cells: [
        for (final cell in row)
          DataCell(
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                '${cell ?? ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  @override
  int get rowCount => table.rows.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}
