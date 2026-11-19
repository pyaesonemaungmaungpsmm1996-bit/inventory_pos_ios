import 'desktop_ui.dart';
import 'pos_ui.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_datetime.dart';
import 'app_language.dart';

String _label(String en, String my) =>
    AppLanguage.current.value == 'my' ? my : en;
String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ExpenseSummaryPage extends StatefulWidget {
  const ExpenseSummaryPage({super.key});

  @override
  State<ExpenseSummaryPage> createState() => _ExpenseSummaryPageState();
}

class _ExpenseSummaryPageState extends State<ExpenseSummaryPage> {
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  List<Map<String, Object?>> branches = [];
  int? branchId;
  Map<String, Object?>? summary;
  bool loading = true;
  String? error;
  int requestId = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final request = ++requestId;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = AppDatabase.instance;
      final all = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final selected = all.any((row) => row['id'] == preferred)
          ? preferred
          : (all.isEmpty ? null : all.first['id'] as int);
      final result = selected == null
          ? null
          : await db.getExpenseSummary(
              branchId: selected,
              fromDate: _iso(from),
              toDate: _iso(to),
            );
      if (!mounted || request != requestId) return;
      setState(() {
        branches = all;
        branchId = selected;
        summary = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted || request != requestId) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> chooseDate(bool start) async {
    final initial = start ? from : to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        from = picked;
        if (to.isBefore(from)) to = from;
      } else {
        to = picked;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        (summary?['categories'] as Map<String, Map<String, int>>?) ?? {};
    final days = (summary?['days'] as Map<String, Map<String, int>>?) ?? {};
    final categoryRows = categories.entries.toList()
      ..sort((a, b) => b.value['amount']!.compareTo(a.value['amount']!));
    return DesktopScaffold(
      body: RefreshIndicator(
        onRefresh: load,
        child: DesktopListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            if (branches.isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey(branchId),
                initialValue: branchId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _label('Branch', 'ဆိုင်ခွဲ'),
                ),
                items: branches
                    .map(
                      (row) => DropdownMenuItem<int>(
                        value: row['id'] as int,
                        child: Text('${row['name']} (${row['code']})'),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  setState(() => branchId = id);
                  load();
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => chooseDate(true),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_iso(from)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => chooseDate(false),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_iso(to)),
                  ),
                ),
              ],
            ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              TextButton(
                onPressed: load,
                child: Text(
                  '${_label('Could not load. Retry', 'ဖတ်မရပါ။ ပြန်စမ်းရန်')}: $error',
                ),
              ),
            if (!loading && error == null && summary != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label('Total expenses', 'စုစုပေါင်း အသုံးစရိတ်'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      MoneyText(summary!['total'] as int, size: 20),
                      Text(
                        '${summary!['count']} ${_label('expenses', 'ကြိမ်')}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _label('By category', 'Category အလိုက်'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final entry in categoryRows)
                DesktopListTile(
                  title: Text(entry.key),
                  subtitle: Text(
                    '${entry.value['count']} ${_label('expenses', 'ကြိမ်')}',
                  ),
                  trailing: MoneyText(entry.value['amount']!),
                ),
              if (categoryRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _label(
                      'No expenses in this date range',
                      'ဤရက်အတွင်း အသုံးစရိတ်မရှိပါ',
                    ),
                  ),
                ),
              const Divider(),
              Text(
                _label('By day', 'နေ့စဉ်အသုံးစရိတ်'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              DesktopInlineTable(
                columns: const ["Date", "Expenses", "Amount"],
                rows: [
                  for (final entry in days.entries)
                    DesktopListTile(
                      title: Text(entry.key),
                      subtitle: Text(
                        '${entry.value['count']} ${_label('expenses', 'ကြိမ်')}',
                      ),
                      trailing: MoneyText(entry.value['amount']!),
                    ),
                ],
                cells: [
                  for (final entry in days.entries)
                    [
                      desktopCellText(entry.key),
                      desktopCellText(entry.value['count']),
                      desktopMoney(entry.value['amount']),
                    ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
