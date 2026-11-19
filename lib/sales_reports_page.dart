import 'app_database.dart';
import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_datetime.dart';
import 'app_language.dart';
import 'report_export.dart';
import 'report_models.dart';
import 'report_repository.dart';
import 'report_table_preview.dart';

String _label(String en, String my) =>
    AppLanguage.current.value == 'my' ? my : en;
String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class SalesReportsPage extends StatefulWidget {
  const SalesReportsPage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<SalesReportsPage> createState() => _SalesReportsPageState();
}

class _SalesReportsPageState extends State<SalesReportsPage> {
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  late int year = AppDateTime.today().year, month = AppDateTime.today().month;
  String period = 'month';
  int? branch, employee, product, category, customer;
  bool includeVoid = false, loading = true, exporting = false;
  String? error;
  int request = 0;
  Map<String, List<Map<String, Object?>>> choices = {};
  ReportBook? report;

  @override
  void initState() {
    super.initState();
    branch = widget.initialBranchId;
    initializeDefaultBranch();
  }

  Future<void> initializeDefaultBranch() async {
    try {
      branch ??= await AppDatabase.instance.getDefaultBranchId();
    } catch (_) {
      /* The normal load shows any storage error. */
    }
    if (mounted) await initialize();
  }

  Future<void> initialize() async {
    try {
      final options = await ReportRepository.options();
      if (!mounted) return;
      setState(() => choices = options);
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  String selectedName(String key, int? id) {
    if (id == null) return 'All';
    final rows = (choices[key] ?? []).where((r) => r['id'] == id);
    return rows.isEmpty ? '#$id' : '${rows.first['name']} (#$id)';
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    if (period != 'custom') {
      from = DateTime(year, period == 'year' ? 1 : month);
      to = period == 'year'
          ? DateTime(year + 1, 1, 0)
          : DateTime(year, month + 1, 0);
    }
    final filters = SalesReportFilter(
      from: _iso(from),
      to: _iso(to),
      branch: branch,
      employee: employee,
      product: product,
      category: category,
      customer: customer,
      includeVoid: includeVoid,
    );
    final labels =
        '${_iso(from)} to ${_iso(to)} | Branch: ${selectedName('branches', branch)} | '
        'Seller: ${selectedName('employees', employee)} | Item: ${selectedName('products', product)} | '
        'Category: ${selectedName('categories', category)} | Customer: ${selectedName('customers', customer)} | Include VOID details: $includeVoid';
    try {
      final result = await ReportRepository.sales(filters, labels);
      if (!mounted || token != request) return;
      setState(() {
        report = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted || token != request) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> date(bool start) async {
    final value = await showDatePicker(
      context: context,
      initialDate: start ? from : to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        from = value;
        if (to.isBefore(from)) to = from;
      } else {
        to = value;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> select(
    String key,
    String title,
    int? current,
    ValueChanged<int?> onSelect,
  ) async {
    String search = '';
    final result = await showDialog<int>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) {
          final rows = (choices[key] ?? [])
              .where(
                (r) => '${r['name']} ${r['item_code'] ?? ''} ${r['id']}'
                    .toLowerCase()
                    .contains(search.toLowerCase()),
              )
              .toList();
          return DesktopDialog(
            title: Text(title),
            content: SizedBox(
              width: 480,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: _label(
                        'Search name / code',
                        'အမည် / ကုဒ် ရှာရန်',
                      ),
                    ),
                    onChanged: (value) => update(() => search = value),
                  ),
                  Expanded(
                    child: DesktopListView(
                      children: [
                        DesktopListTile(
                          title: Text(_label('All', 'အားလုံး')),
                          selected: current == null,
                          onTap: () => Navigator.pop(dialog, -1),
                        ),
                        for (final row in rows)
                          DesktopListTile(
                            selected: row['id'] == current,
                            title: Text(
                              '${row['item_code'] == null ? '' : '${row['item_code']} · '}${row['name']}',
                            ),
                            subtitle: Text(
                              '#${row['id']}${row['branch_id'] == null ? '' : ' · Branch #${row['branch_id']}'}',
                            ),
                            onTap: () =>
                                Navigator.pop(dialog, row['id'] as int),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(_label('Cancel', 'မလုပ်တော့')),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() => onSelect(result == -1 ? null : result));
    await load();
  }

  Future<void> export(String kind) async {
    if (exporting || loading || report == null) return;
    final snapshot = report!;
    setState(() => exporting = true);
    try {
      if (kind == 'excel') {
        await shareReportExcel(snapshot);
      } else if (kind == 'zip') {
        await shareCompleteReport(snapshot);
      } else {
        await previewReport(context, snapshot);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Widget filterTile(
    String title,
    String key,
    int? value,
    ValueChanged<int?> onSelect,
  ) => DesktopListTile(
    dense: true,
    title: Text(title),
    subtitle: Text(selectedName(key, value)),
    trailing: const Icon(Icons.filter_list),
    onTap: exporting ? null : () => select(key, title, value, onSelect),
  );

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    body: RefreshIndicator(
      onRefresh: initialize,
      child: DesktopListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          DropdownButtonFormField<String>(
            initialValue: period,
            decoration: InputDecoration(labelText: _label('Period', 'ကာလ')),
            items: [
              DropdownMenuItem(
                value: 'month',
                child: Text(_label('Month', 'လအလိုက်')),
              ),
              DropdownMenuItem(
                value: 'year',
                child: Text(_label('Year', 'နှစ်အလိုက်')),
              ),
              DropdownMenuItem(
                value: 'custom',
                child: Text(_label('Custom date range', 'ရက်အပိုင်းအခြား')),
              ),
            ],
            onChanged: exporting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => period = value);
                      load();
                    }
                  },
          ),
          if (period != 'custom')
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: year,
                    decoration: InputDecoration(
                      labelText: _label('Year', 'နှစ်'),
                    ),
                    items: [
                      for (var n = 2000; n <= 2100; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: exporting
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => year = value);
                              load();
                            }
                          },
                  ),
                ),
                if (period == 'month') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: month,
                      decoration: InputDecoration(
                        labelText: _label('Month', 'လ'),
                      ),
                      items: [
                        for (var n = 1; n <= 12; n++)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: exporting
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => month = value);
                                load();
                              }
                            },
                    ),
                  ),
                ],
              ],
            ),
          if (period == 'custom')
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: exporting ? null : () => date(true),
                    child: Text(_iso(from)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: exporting ? null : () => date(false),
                    child: Text(_iso(to)),
                  ),
                ),
              ],
            ),
          filterTile(
            _label('Branch', 'ဆိုင်ခွဲ'),
            'branches',
            branch,
            (v) => branch = v,
          ),
          filterTile(
            _label('Original salesperson', 'မူရင်းရောင်းသူ'),
            'employees',
            employee,
            (v) => employee = v,
          ),
          filterTile(
            _label('Item', 'ပစ္စည်း'),
            'products',
            product,
            (v) => product = v,
          ),
          filterTile(
            _label('Customer', 'ဝယ်သူ'),
            'customers',
            customer,
            (v) => customer = v,
          ),
          filterTile(
            _label('Category', 'ပစ္စည်းအမျိုးအစား'),
            'categories',
            category,
            (v) => category = v,
          ),
          SwitchListTile(
            title: Text(_label('Include VOID details', 'VOID အသေးစိတ်ပါပြရန်')),
            subtitle: Text(
              _label(
                'Summary always excludes VOID',
                'စာရင်းချုပ်တွင် VOID မထည့်တွက်ပါ',
              ),
            ),
            value: includeVoid,
            onChanged: exporting
                ? null
                : (v) {
                    setState(() => includeVoid = v);
                    load();
                  },
          ),
          if (loading || exporting) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: initialize, child: Text('Retry: $error')),
          if (!loading && error == null && report != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: exporting ? null : () => export('excel'),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: exporting ? null : () => export('pdf'),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('PDF / Print'),
                ),
                OutlinedButton.icon(
                  onPressed: exporting ? null : () => export('zip'),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('Complete ZIP'),
                ),
              ],
            ),
            for (final table in report!.tables)
              Card(
                child: DesktopSection(
                  initiallyExpanded: table.title == 'Summary',
                  title: Text('${table.title} (${table.rows.length})'),
                  children: [
                    if (table.rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('No records'),
                      )
                    else
                      ReportTablePreview(table: table),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
