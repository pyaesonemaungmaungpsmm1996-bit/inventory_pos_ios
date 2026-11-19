import 'app_database.dart';
import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_datetime.dart';
import 'app_language.dart';
import 'activity_repository.dart';
import 'report_viewer_page.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _origin(String value) => switch (value) {
  'tracked' => _t('Tracked event', 'အသစ်မှတ်ထားသော ဖြစ်ရပ်'),
  'saved_history' => _t('Earlier saved history', 'အရင်သိမ်းထားသော History'),
  'timestamp_only' => _t('Earlier timestamp only', 'အရင်အချိန်အချက်အလက်သာရှိ'),
  _ => _t('System note', 'စနစ်မှတ်ချက်'),
};
IconData _icon(String action) => switch (action) {
  'delete' || 'remove_attachment' => Icons.delete_outline,
  'void' => Icons.undo,
  'create' || 'record_created' => Icons.add_circle_outline,
  'archive' => Icons.archive_outlined,
  'restore' => Icons.unarchive_outlined,
  'receive' || 'apply' => Icons.check_circle_outline,
  'export_prepared' => Icons.file_download_outlined,
  _ => Icons.history,
};

class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key});
  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  List<Map<String, Object?>> branches = [],
      modules = [],
      actions = [],
      rows = [];
  int? branch;
  String? module, action, origin;
  bool technical = false,
      global = true,
      loading = true,
      moreBusy = false,
      hasMore = false;
  int total = 0, request = 0;
  String? error;
  ActivityFilter? loaded;
  late DateTime from = DateTime(
    AppDateTime.today().year,
    AppDateTime.today().month,
  );
  late DateTime to = AppDateTime.today();
  final search = TextEditingController();
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
    if (mounted) await load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  ActivityFilter filter() => ActivityFilter(
    from: _date(from),
    to: _date(to),
    branch: branch,
    module: module,
    action: action,
    origin: origin,
    technical: technical,
    includeGlobal: global,
    search: search.text,
  );
  Future<void> load() async {
    final token = ++request;
    final selected = filter();
    setState(() {
      loading = true;
      error = null;
      moreBusy = false;
    });
    try {
      final options = await ActivityRepository.options();
      final result = await ActivityRepository.page(selected);
      if (!mounted || token != request) return;
      setState(() {
        branches = options['branches']!;
        modules = options['modules']!;
        actions = options['actions']!;
        rows = result.rows;
        total = result.total;
        hasMore = result.rows.length == 80;
        loaded = selected;
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

  Future<void> more() async {
    if (moreBusy || loading || loaded == null || rows.isEmpty) return;
    final token = request, selected = loaded!, cursor = rows.last;
    setState(() {
      moreBusy = true;
      error = null;
    });
    try {
      final result = await ActivityRepository.page(
        selected,
        beforeTime: cursor['event_ms'] as int,
        beforeId: cursor['id'] as int,
      );
      if (!mounted || token != request) return;
      setState(() {
        rows.addAll(result.rows);
        total = result.total;
        hasMore = result.rows.length == 80;
        moreBusy = false;
      });
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          error = '$e';
          moreBusy = false;
        });
      }
    }
  }

  Future<void> date(bool first) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: AppDateTime.today(),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (first) {
        from = selected;
        if (to.isBefore(from)) to = from;
      } else {
        to = selected;
        if (from.isAfter(to)) from = to;
      }
    });
    await load();
  }

  String branchLabel(Object? id) {
    if (id == null) return _t('Global / not recorded', 'အားလုံး / မမှတ်ထား');
    final matches = branches.where((b) => b['id'] == id);
    return matches.isEmpty
        ? 'Branch #$id'
        : '${matches.first['name']} (${matches.first['code']})';
  }

  void export() {
    final selected = loaded;
    if (selected == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Activity History',
          load: () => ActivityRepository.report(
            selected,
            '${selected.from} to ${selected.to} | Module: ${selected.module ?? 'All'} | Action: ${selected.action ?? 'All'} | '
            'Branch: ${branchLabel(selected.branch)} | Origin: ${selected.origin ?? 'All'} | Technical: ${selected.technical} | Search: ${selected.search}',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    body: RefreshIndicator(
      onRefresh: load,
      child: DesktopListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 70),
        children: [
          Text(
            _t(
              'New database changes are tracked from v39. Earlier rows show only history/timestamps that actually existed. Actor names are Not recorded until authenticated user identity is available.',
              'v39 မှစပြီး database ပြောင်းလဲမှုများကို မှတ်ပါသည်။ အဟောင်းများတွင် တကယ်ရှိခဲ့သော history/အချိန်ကိုသာ ပြပါသည်။ Login user identity မရှိသေးသဖြင့် လုပ်ဆောင်သူအမည်ကို Not recorded ဟု ပြပါသည်။',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => date(true),
                  child: Text(_date(from)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => date(false),
                  child: Text(_date(to)),
                ),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: module ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('Module', 'စာရင်းအပိုင်း'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(_t('All modules', 'စာရင်းအပိုင်းအားလုံး')),
              ),
              for (final m in modules)
                DropdownMenuItem(
                  value: m['value'] as String,
                  child: Text(m['value'] as String),
                ),
            ],
            onChanged: (v) {
              setState(() => module = v == '' ? null : v);
              load();
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: action ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('Action', 'လုပ်ဆောင်မှု'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(_t('All actions', 'လုပ်ဆောင်မှုအားလုံး')),
              ),
              for (final a in actions)
                DropdownMenuItem(
                  value: a['value'] as String,
                  child: Text(a['value'] as String),
                ),
            ],
            onChanged: (v) {
              setState(() => action = v == '' ? null : v);
              load();
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: branch ?? -1,
            isExpanded: true,
            decoration: InputDecoration(labelText: _t('Branch', 'ဆိုင်ခွဲ')),
            items: [
              DropdownMenuItem(
                value: -1,
                child: Text(_t('All branches', 'ဆိုင်ခွဲအားလုံး')),
              ),
              for (final b in branches)
                DropdownMenuItem(
                  value: b['id'] as int,
                  child: Text('${b['name']} (${b['code']})'),
                ),
            ],
            onChanged: (v) {
              setState(() => branch = v == -1 ? null : v);
              load();
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: origin ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: _t('Evidence source', 'မှတ်တမ်းအထောက်အထား'),
            ),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(_t('All evidence sources', 'အထောက်အထားအားလုံး')),
              ),
              for (final s in [
                'tracked',
                'saved_history',
                'timestamp_only',
                'system',
              ])
                DropdownMenuItem(value: s, child: Text(_origin(s))),
            ],
            onChanged: (v) {
              setState(() => origin = v == '' ? null : v);
              load();
            },
          ),
          if (branch != null)
            SwitchListTile(
              title: Text(
                _t(
                  'Include global / unrecorded branch events',
                  'ဆိုင်ခွဲမမှတ်ထား / အားလုံးဆိုင်ရာ ဖြစ်ရပ်ပါပြရန်',
                ),
              ),
              value: global,
              onChanged: (v) {
                setState(() => global = v);
                load();
              },
            ),
          SwitchListTile(
            title: Text(
              _t(
                'Include movement / line details',
                'ငွေ/stock အရွေ့နှင့် item လိုင်းများပါပြရန်',
              ),
            ),
            subtitle: Text(
              _t(
                'More than one database event can belong to one voucher.',
                'ဘောင်ချာတစ်ခုတွင် database ဖြစ်ရပ် အများအပြား ပါနိုင်ပါသည်။',
              ),
            ),
            value: technical,
            onChanged: (v) {
              setState(() => technical = v);
              load();
            },
          ),
          TextField(
            controller: search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: _t(
                'Search reference / name / changed field',
                'ဘောင်ချာအညွှန်း / အမည် / ပြောင်းထားသည့် field ရှာရန်',
              ),
              suffixIcon: IconButton(
                onPressed: load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: loading || loaded == null ? null : export,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Excel / PDF / Print'),
          ),
          if (loading || moreBusy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: load, child: Text('Retry: $error')),
          if (!loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${rows.length} / $total ${_t('events', 'ဖြစ်ရပ်')} · ${AppDateTime.current.value}',
              ),
            ),
          if (!loading && rows.isEmpty && error == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _t(
                  'No matching activity. Widen dates or change the filters.',
                  'ကိုက်ညီသောဖြစ်ရပ် မရှိပါ။ ရက်အပိုင်းအခြား သို့မဟုတ် filter ပြောင်းပါ။',
                ),
              ),
            ),
          if (!loading)
            DesktopInlineTable(
              columns: const [
                "Reference",
                "Action",
                "Date",
                "Module",
                "Branch",
                "Actor",
                "Evidence",
              ],
              rows: [
                for (final row in rows)
                  Card(
                    child: DesktopListTile(
                      leading: Icon(_icon(row['action'] as String)),
                      title: Text('${row['reference']} · ${row['action']}'),
                      subtitle: Text(
                        '${activityLocalTime(row['event_at'])}\n${row['module']} · ${_origin(row['origin'] as String)}\n'
                        '${branchLabel(row['branch_id'])}${row['peer_branch_id'] == null ? '' : ' → ${branchLabel(row['peer_branch_id'])}'}\n'
                        '${_t('Actor', 'လုပ်ဆောင်သူ')}: ${row['actor_name']}',
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ActivityDetail(id: row['id'] as int),
                        ),
                      ),
                    ),
                  ),
              ],
              cells: [
                for (final row in rows)
                  [
                    desktopCellText(row['reference']),
                    desktopCellText(row['action']),
                    desktopCellText(activityLocalTime(row['event_at'])),
                    desktopCellText(row['module']),
                    desktopCellText(branchLabel(row['branch_id'])),
                    desktopCellText(row['actor_name']),
                    desktopCellText(_origin(row['origin'] as String)),
                  ],
              ],
            ),
          if (!loading && !hasMore && rows.length < total)
            OutlinedButton(
              onPressed: load,
              child: Text(
                _t('Refresh newer activity', 'ဖြစ်ရပ်အသစ်များ ပြန်ဖတ်ရန်'),
              ),
            ),
          if (!loading && hasMore)
            OutlinedButton(
              onPressed: moreBusy ? null : more,
              child: Text(_t('Load more', 'ထပ်ကြည့်ရန်')),
            ),
        ],
      ),
    ),
  );
}

class _ActivityDetail extends StatefulWidget {
  const _ActivityDetail({required this.id});
  final int id;
  @override
  State<_ActivityDetail> createState() => _ActivityDetailState();
}

class _ActivityDetailState extends State<_ActivityDetail> {
  Map<String, Object?>? record;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await ActivityRepository.get(widget.id);
      if (mounted) {
        setState(() {
          record = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void export() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportViewerPage(
          title: 'Activity #${widget.id}',
          load: () => ActivityRepository.reportOne(widget.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text('Activity #${widget.id}')),
    body: record == null
        ? Center(
            child: error == null
                ? const CircularProgressIndicator()
                : TextButton(onPressed: load, child: Text('Retry: $error')),
          )
        : DesktopListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${record!['reference']} · ${record!['action']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(activityLocalTime(record!['event_at'])),
              Text('UTC: ${record!['event_at']}'),
              Text('${_t('Module', 'စာရင်းအပိုင်း')}: ${record!['module']}'),
              Text('${_t('Actor', 'လုပ်ဆောင်သူ')}: ${record!['actor_name']}'),
              Text(
                '${_t('Source', 'မူရင်း')}: ${record!['source_table']} / ${record!['record_id']}',
              ),
              Text(
                '${_t('Evidence', 'အထောက်အထား')}: ${_origin(record!['origin'] as String)}',
              ),
              Text(
                'Branch ID: ${record!['branch_id'] ?? 'Global / not recorded'} · Other branch: ${record!['peer_branch_id'] ?? '—'}',
              ),
              const Divider(),
              Text(
                _t('Changed fields', 'ပြောင်းထားသည့် field များ'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SelectableText('${record!['changed_fields']}'),
              DesktopSection(
                initiallyExpanded: true,
                title: Text(_t('Before', 'မပြင်မီ')),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText('${record!['before_summary']}'),
                  ),
                ],
              ),
              DesktopSection(
                initiallyExpanded: true,
                title: Text(_t('After', 'ပြင်ပြီး')),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText('${record!['after_summary']}'),
                  ),
                ],
              ),
              Text(
                _t(
                  'Field summaries retain stored units. Full report money columns show recorded currency units. Activity summaries can remain after original voucher deletion.',
                  'Field အကျဉ်းသည် database တွင် သိမ်းထားသော ယူနစ်ဖြစ်သည်။ Report ငွေကော်လံများတွင် မူရင်းငွေကြေးယူနစ်ဖြင့် ပြပါသည်။ ဘောင်ချာဖျက်ပြီးနောက် ဖြစ်ရပ်အကျဉ်း ဆက်ကျန်နိုင်ပါသည်။',
                ),
              ),
              OutlinedButton.icon(
                onPressed: export,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Excel / PDF / Print'),
              ),
            ],
          ),
  );
}
