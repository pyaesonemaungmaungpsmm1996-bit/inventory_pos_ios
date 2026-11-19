import 'app_database.dart';
import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_datetime.dart';
import 'app_language.dart';
import 'money_ledger_repository.dart';
import 'report_export.dart';
import 'report_models.dart';
import 'report_table_preview.dart';
import 'report_viewer_page.dart';
import 'supplier_ledger_repository.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SupplierLedgerPage extends StatefulWidget {
  const SupplierLedgerPage({super.key});
  @override
  State<SupplierLedgerPage> createState() => _SupplierLedgerPageState();
}

class _SupplierLedgerPageState extends State<SupplierLedgerPage> {
  List<Map<String, Object?>> branches = [], suppliers = [];
  int? branch, supplier;
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  final search = TextEditingController();
  ReportBook? report;
  bool loading = true, busy = false;
  String? error;
  int request = 0, optionRequest = 0;
  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> initialize() async {
    final token = ++optionRequest;
    try {
      final options = await SupplierLedgerRepository.options();
      if (!mounted || token != optionRequest) return;
      setState(() {
        branches = options['branches']!;
        suppliers = options['suppliers']!;
      });
      await load();
    } catch (e) {
      if (mounted && token == optionRequest) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  String selected(List<Map<String, Object?>> rows, int? id) {
    if (id == null) return 'All';
    final matches = rows.where((r) => r['id'] == id);
    return matches.isEmpty ? '#$id' : '${matches.first['name']} (#$id)';
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    final labels =
        '${_date(from)} to ${_date(to)} | Branch: ${selected(branches, branch)} | '
        'Supplier: ${selected(suppliers, supplier)} | Search: ${search.text.trim()}';
    try {
      final value = await SupplierLedgerRepository.load(
        from: _date(from),
        to: _date(to),
        branch: branch,
        supplier: supplier,
        search: search.text,
        labels: labels,
      );
      if (!mounted || token != request) return;
      setState(() {
        report = value;
        loading = false;
      });
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> date(bool first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (first) {
        from = picked;
        if (to.isBefore(from)) to = from;
      } else {
        to = picked;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> chooseSupplier() async {
    var query = '';
    final picked = await showDialog<int>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DesktopDialog(
          title: Text(_t('Supplier', 'ပစ္စည်းပေးသွင်းသူ')),
          content: SizedBox(
            width: 480,
            height: 360,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: _t(
                      'Search name / phone / company',
                      'အမည် / ဖုန်း / ကုမ္ပဏီ ရှာရန်',
                    ),
                  ),
                  onChanged: (v) => update(() => query = v.toLowerCase()),
                ),
                Expanded(
                  child: DesktopListView(
                    children: [
                      DesktopListTile(
                        title: Text(_t('All suppliers', 'Supplier အားလုံး')),
                        onTap: () => Navigator.pop(dialog, -1),
                      ),
                      for (final row in suppliers.where(
                        (r) => '${r['name']} ${r['phone']} ${r['company']}'
                            .toLowerCase()
                            .contains(query),
                      ))
                        DesktopListTile(
                          title: Text('${row['name']}'),
                          subtitle: Text('${row['phone']} · #${row['id']}'),
                          onTap: () => Navigator.pop(dialog, row['id'] as int),
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
              child: Text(_t('Cancel', 'မလုပ်တော့')),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => supplier = picked == -1 ? null : picked);
    await load();
  }

  Future<void> export(String kind) async {
    if (busy || loading || report == null) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openPurchase(Object? id) {
    if (id is! int) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Purchase #$id',
          load: () => SupplierLedgerRepository.purchase(id),
        ),
      ),
    );
  }

  void openEvent(List<Object?> row) {
    if (row[14] is int) {
      final id = row[14] as int;
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReportViewerPage(
            title: 'Money entry #$id',
            load: () => MoneyLedgerRepository.voucher(id),
          ),
        ),
      );
    } else {
      openPurchase(row[15]);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    body: RefreshIndicator(
      onRefresh: initialize,
      child: DesktopListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey(branch),
            initialValue: branch ?? -1,
            isExpanded: true,
            decoration: InputDecoration(labelText: _t('Branch', 'ဆိုင်ခွဲ')),
            items: [
              DropdownMenuItem(
                value: -1,
                child: Text(_t('All branches', 'ဆိုင်ခွဲအားလုံး')),
              ),
              for (final r in branches)
                DropdownMenuItem(
                  value: r['id'] as int,
                  child: Text('${r['name']} (${r['code']})'),
                ),
            ],
            onChanged: busy
                ? null
                : (v) {
                    setState(() => branch = v == -1 ? null : v);
                    load();
                  },
          ),
          DesktopListTile(
            title: Text(_t('Supplier', 'ပစ္စည်းပေးသွင်းသူ')),
            subtitle: Text(selected(suppliers, supplier)),
            trailing: const Icon(Icons.search),
            onTap: busy ? null : chooseSupplier,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => date(true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_date(from)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => date(false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_date(to)),
                ),
              ),
            ],
          ),
          TextField(
            controller: search,
            enabled: !busy,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: _t(
                'Find voucher / note / account',
                'ဘောင်ချာ / မှတ်ချက် / အကောင့် ရှာရန်',
              ),
              suffixIcon: IconButton(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _t(
                'Positive balance = payable to supplier. Negative balance = credit. Search filters transactions only; balances include all entries. Tap a purchase or transaction for full voucher details.',
                'လက်ကျန်အပေါင်းသည် Supplier ကိုပေးရန်ဖြစ်ပြီး အနုတ်သည် ကိုယ့်ဘက်က Credit ဖြစ်သည်။ ရှာဖွေခြင်းက transaction များကိုသာ စစ်ပြပါသည်။ ဘောင်ချာအသေးစိတ်ကြည့်ရန် အဝယ် သို့မဟုတ် transaction အကြောင်းကို နှိပ်ပါ။',
              ),
            ),
          ),
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: initialize, child: Text('Retry: $error')),
          if (!loading && error == null && report != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => export('excel'),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => export('pdf'),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('PDF / Print'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => export('zip'),
                  icon: const Icon(Icons.folder_zip_outlined),
                  label: const Text('Complete ZIP'),
                ),
              ],
            ),
            for (final table in report!.tables)
              Card(
                child: DesktopSection(
                  initiallyExpanded: true,
                  title: Text('${table.title} (${table.rows.length})'),
                  children: [
                    if (table.rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_t('No records', 'စာရင်းမရှိပါ')),
                      )
                    else
                      ReportTablePreview(
                        table: table,
                        onOpen: table.title == 'Supplier Transactions'
                            ? openEvent
                            : table.title == 'Purchase Balances at Cutoff' ||
                                  table.title == 'Purchased Item Details'
                            ? (row) => openPurchase(row.first)
                            : null,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
