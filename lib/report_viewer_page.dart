import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'report_models.dart';
import 'report_export.dart';
import 'report_table_preview.dart';

class ReportViewerPage extends StatefulWidget {
  const ReportViewerPage({super.key, required this.title, required this.load});
  final String title;
  final Future<ReportBook> Function() load;
  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage> {
  ReportBook? report;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.load();
      if (mounted) {
        setState(() {
          report = value;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> export(String kind) async {
    if (busy || report == null) return;
    final snapshot = report!;
    setState(() => busy = true);
    try {
      if (kind == 'excel') {
        await shareReportExcel(snapshot);
      } else if (kind == 'zip') {
        await shareCompleteReport(snapshot);
      } else {
        await previewReport(context, snapshot);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text(report?.title ?? widget.title)),
    body: report == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : TextButton(onPressed: load, child: Text('Retry: $error')),
          )
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null) Text(error!),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => export('excel'),
                    child: const Text('Excel'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => export('pdf'),
                    child: const Text('PDF / Print'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => export('zip'),
                    child: const Text('Complete ZIP'),
                  ),
                ],
              ),
              for (final table in report!.tables)
                Card(
                  child: DesktopSection(
                    initiallyExpanded: true,
                    title: Text('${table.title} (${table.rows.length})'),
                    children: [ReportTablePreview(table: table)],
                  ),
                ),
            ],
          ),
  );
}
