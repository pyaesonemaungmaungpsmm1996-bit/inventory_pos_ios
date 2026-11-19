import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'report_export.dart';
import 'report_repository.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key});
  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  List<String> datasets = [];
  final selected = <String>{};
  String search = '', message = '';
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = await ReportRepository.datasets();
      if (!mounted) return;
      setState(() {
        datasets = rows.map((r) => r['name'] as String).toList();
        selected.addAll(datasets);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          message = '$e';
        });
      }
    }
  }

  Future<void> export(String kind) async {
    if (busy || selected.isEmpty) return;
    final names = Set<String>.of(selected);
    setState(() {
      busy = true;
      message = _t('Preparing records…', 'စာရင်းများ ပြင်ဆင်နေပါသည်…');
    });
    try {
      final book = await ReportRepository.allData(names);
      if (!mounted) return;
      if (kind == 'excel') {
        await shareReportExcel(book);
      } else if (kind == 'zip') {
        await shareCompleteReport(book);
      } else {
        await previewReport(context, book);
      }
      if (mounted) {
        setState(
          () => message = _t(
            'Export prepared. Use the share/save or print options.',
            'Export ပြင်ဆင်ပြီးပါပြီ။ Share / Save သို့မဟုတ် Print မှ သိမ်းပါ။',
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    body: DesktopListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Text(
          _t(
            'Export any stored dataset',
            'သိမ်းထားသော စာရင်းများ Export ထုတ်ရန်',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'Excel: all columns and records in separate sheets. PDF: all fields with repeated headings and photo pages. Complete ZIP: Excel + full JSON + original attachments. Select fewer datasets for a shorter PDF.',
            'Excel တွင် column နှင့် record အားလုံး sheet ခွဲပါမည်။ PDF တွင် အချက်အလက်အားလုံးနှင့် ပုံများပါမည်။ Complete ZIP တွင် Excel၊ JSON နှင့် မူရင်းပုံဖိုင်များပါမည်။ PDF တိုစေရန် လိုသည့်စာရင်းများသာ ရွေးပါ။',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: busy || selected.isEmpty
                  ? null
                  : () => export('excel'),
              icon: const Icon(Icons.table_view),
              label: const Text('Excel .xlsx'),
            ),
            OutlinedButton.icon(
              onPressed: busy || selected.isEmpty ? null : () => export('pdf'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('PDF / Print'),
            ),
            OutlinedButton.icon(
              onPressed: busy || selected.isEmpty ? null : () => export('zip'),
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Complete ZIP'),
            ),
          ],
        ),
        if (loading || busy) const LinearProgressIndicator(),
        if (message.isNotEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(message)),
        TextField(
          enabled: !busy,
          decoration: InputDecoration(
            labelText: _t('Search dataset', 'စာရင်းအမျိုးအစားရှာရန်'),
          ),
          onChanged: (v) => setState(() => search = v.toLowerCase()),
        ),
        Row(
          children: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => selected.addAll(datasets)),
              child: Text(_t('Select all', 'အားလုံးရွေး')),
            ),
            TextButton(
              onPressed: busy ? null : () => setState(selected.clear),
              child: Text(_t('Clear', 'ရွေးထားသည်များဖြုတ်')),
            ),
            Text('${selected.length} / ${datasets.length}'),
          ],
        ),
        for (final name in datasets.where((n) => n.contains(search)))
          CheckboxListTile(
            title: Text(reportHeading(name)),
            subtitle: Text(name),
            value: selected.contains(name),
            onChanged: busy
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      selected.add(name);
                    } else {
                      selected.remove(name);
                    }
                  }),
          ),
      ],
    ),
  );
}
