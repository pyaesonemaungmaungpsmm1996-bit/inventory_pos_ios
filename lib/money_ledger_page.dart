import 'app_database.dart';
import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'money_ledger_repository.dart';
import 'report_export.dart';
import 'report_models.dart';
import 'report_table_preview.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class MoneyLedgerPage extends StatefulWidget {
  const MoneyLedgerPage({super.key});
  @override
  State<MoneyLedgerPage> createState() => _MoneyLedgerPageState();
}

class _MoneyLedgerPageState extends State<MoneyLedgerPage> {
  List<Map<String, Object?>> branches = [], accounts = [];
  int? branch, account;
  String type = 'all';
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
      final options = await MoneyLedgerRepository.options();
      if (!mounted || token != optionRequest) return;
      setState(() {
        branches = options['branches']!;
        accounts = options['accounts']!;
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

  String branchLabel() {
    if (branch == null) return 'All';
    final rows = branches.where((row) => row['id'] == branch);
    return rows.isEmpty
        ? '#$branch'
        : '${rows.first['name']} (${rows.first['code']})';
  }

  String accountLabel() {
    if (account == null) return 'All';
    final rows = accounts.where((row) => row['id'] == account);
    return rows.isEmpty ? '#$account' : '${rows.first['name']} (#$account)';
  }

  Future<void> load() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    final labels =
        '${_date(from)} to ${_date(to)} | Branch: ${branchLabel()} | '
        'Type: $type | Account: ${accountLabel()} | Search: ${search.text.trim()}';
    try {
      final value = await MoneyLedgerRepository.load(
        from: _date(from),
        to: _date(to),
        branch: branch,
        account: account,
        type: type == 'all' ? null : type,
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
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> date(bool first) async {
    final value = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (first) {
        from = value;
        if (to.isBefore(from)) to = from;
      } else {
        to = value;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  Future<void> chooseAccount() async {
    var query = '';
    final available = accounts
        .where(
          (row) =>
              (branch == null || row['branch_id'] == branch) &&
              (type == 'all' || row['type'] == type),
        )
        .toList();
    final picked = await showDialog<int>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DesktopDialog(
          title: Text(_t('Account', 'ငွေအကောင့်')),
          content: SizedBox(
            width: 480,
            height: 360,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: _t(
                      'Search account / branch',
                      'အကောင့် / ဆိုင်ခွဲ ရှာရန်',
                    ),
                  ),
                  onChanged: (v) => update(() => query = v.toLowerCase()),
                ),
                Expanded(
                  child: DesktopListView(
                    children: [
                      DesktopListTile(
                        title: Text(_t('All accounts', 'အကောင့်အားလုံး')),
                        onTap: () => Navigator.pop(dialog, -1),
                      ),
                      for (final row in available.where(
                        (r) => '${r['name']} ${r['branch_name']}'
                            .toLowerCase()
                            .contains(query),
                      ))
                        DesktopListTile(
                          title: Text('${row['name']} · ${row['type']}'),
                          subtitle: Text(
                            '${row['branch_name']} (${row['branch_code']})',
                          ),
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
    setState(() => account = picked == -1 ? null : picked);
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
              for (final row in branches)
                DropdownMenuItem(
                  value: row['id'] as int,
                  child: Text('${row['name']} (${row['code']})'),
                ),
            ],
            onChanged: busy
                ? null
                : (v) {
                    setState(() {
                      branch = v == -1 ? null : v;
                      account = null;
                    });
                    load();
                  },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: InputDecoration(
              labelText: _t('Account type', 'အကောင့်အမျိုးအစား'),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(
                  _t('Cash + Bank + Wallet', 'ငွေသား + ဘဏ် + Wallet'),
                ),
              ),
              const DropdownMenuItem(value: 'cash', child: Text('Cash')),
              const DropdownMenuItem(value: 'bank', child: Text('Bank')),
              const DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) {
                      setState(() {
                        type = v;
                        account = null;
                      });
                      load();
                    }
                  },
          ),
          DesktopListTile(
            title: Text(_t('Account', 'ငွေအကောင့်')),
            subtitle: Text(accountLabel()),
            trailing: const Icon(Icons.search),
            onTap: busy ? null : chooseAccount,
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
                'Find voucher / note / amount',
                'ဘောင်ချာ / မှတ်ချက် / ငွေပမာဏ ရှာရန်',
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
                'Search narrows transaction rows only. Opening, closing and running balances include all entries in the selected accounts. VOID reversals remain visible.',
                'ရှာဖွေခြင်းက transaction အကြောင်းများကိုသာ စစ်ပြပါသည်။ အဖွင့်၊ အပိတ်နှင့် လက်ကျန်များသည် ရွေးထားသောအကောင့်၏ entry အားလုံးကို ထည့်တွက်ပါသည်။ VOID ပြန်ညှိ entries လည်း ပါပါသည်။',
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
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${_t('Currency', 'ငွေကြေး')}: ${AppCurrency.code}'),
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
                        child: Text(_t('No entries', 'စာရင်းမရှိပါ')),
                      )
                    else
                      ReportTablePreview(
                        table: table,
                        onOpen: table.title == 'Transaction Details'
                            ? (row) => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReportViewerPage(
                                    title: 'Entry #${row.first}',
                                    load: () => MoneyLedgerRepository.voucher(
                                      row.first as int,
                                    ),
                                  ),
                                ),
                              )
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
