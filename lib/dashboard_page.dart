import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'dashboard_repository.dart';
import 'live_sale_sync.dart';
import 'live_purchase_sync.dart';
import 'voucher_code.dart';
import 'sale_invoice_history_page.dart';
import 'online_account_service.dart';
import 'pos_ui.dart';
import 'subscription_runtime.dart';
part 'desktop_dashboard.dart';

const dashboardActions = [
  'purchase',
  'stock',
  'customers',
  'reports',
  'collections',
  'account',
  'transfer',
  'expenses',
];
const defaultDashboardActions = [
  'purchase',
  'stock',
  'customers',
  'reports',
  'collections',
  'account',
];
String dashboardLabel(String key) => switch (key) {
  'purchase' => AppLanguage.text('Purchase'),
  'stock' => AppLanguage.text('Balance Stock'),
  'customers' => AppLanguage.text('Customers'),
  'reports' => AppLanguage.text('Sales Reports'),
  'collections' => AppLanguage.text('Customer Payments'),
  'account' => AppLanguage.text('Account'),
  'transfer' => AppLanguage.text('Stock Transfer'),
  'expenses' => AppLanguage.text('Expense'),
  _ => key,
};
IconData dashboardIcon(String key) => switch (key) {
  'purchase' => Icons.shopping_bag_outlined,
  'stock' => Icons.inventory_2_outlined,
  'customers' => Icons.people_outline,
  'reports' => Icons.bar_chart_outlined,
  'collections' => Icons.payments_outlined,
  'account' => Icons.manage_accounts_outlined,
  'transfer' => Icons.swap_horiz,
  'expenses' => Icons.receipt_long_outlined,
  _ => Icons.history,
};

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onAction,
    required this.onRecent,
    required this.onBranch,
  });
  final Future<void> Function(String action, int branch) onAction;
  final Future<void> Function(Map<String, Object?> row, int branch) onRecent;
  final void Function(int? branch) onBranch;
  @override
  State<DashboardPage> createState() => DashboardPageState();
}

class DashboardPageState extends State<DashboardPage> {
  final prefs = SharedPreferencesAsync();
  List<Map<String, Object?>> branches = [];
  List<String> shortcuts = [...defaultDashboardActions];
  int? branch;
  bool today = false, loading = true;
  int request = 0;
  Map<String, Object?>? data;
  String? error, preferenceKey;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    SubscriptionRuntime.changed.addListener(licenseChanged);
    LiveSaleSync.feed.addListener(_liveSalesChanged);
    LivePurchaseSync.rows.addListener(_liveSalesChanged);
    reload();
  }

  @override
  void dispose() {
    SubscriptionRuntime.changed.removeListener(licenseChanged);
    LiveSaleSync.feed.removeListener(_liveSalesChanged);
    LivePurchaseSync.rows.removeListener(_liveSalesChanged);
    super.dispose();
  }

  void _liveSalesChanged() {
    if (mounted) setState(() {});
  }

  List<Map<String, Object?>> _recentWithSyncedSales(
    List<Map<String, Object?>> local,
    Map<String, Object?>? overview,
  ) {
    if (branch == null || overview == null) return local;
    final updates = LiveSaleSync.feed.value;
    final identities =
        (overview['sale_identities'] as List?)?.cast<Map<String, Object?>>() ??
        [];
    final remote = SaleInvoiceHistoryRepository.mergeSales(identities, branches)
        .where(
          (sale) =>
              sale['live_voucher'] != null &&
              sale['branch_id'] == branch &&
              sale['status'] == 'posted' &&
              sale['total'] is int,
        )
        .map(
          (sale) => <String, Object?>{
            'kind': 'sale',
            'branch_id': branch,
            'live_voucher': sale['live_voucher'],
            'live_number': sale['live_number'],
            'live_account': updates.account,
            'amount': sale['total'],
            'status': sale['status'],
            'recorded_at': sale['updated_at'],
          },
        );
    final selected = branches.where((b) => b['id'] == branch).firstOrNull;
    final purchaseIdentities =
        (overview['purchase_identities'] as List?)
            ?.cast<Map<String, Object?>>() ??
        [];
    final syncedPurchases = selected == null
        ? <Map<String, Object?>>[]
        : LivePurchaseSync.forBranch(purchaseIdentities, selected);
    final combined = [...local, ...remote, ...syncedPurchases]
      ..sort((a, b) {
        final first = b['recorded_at']?.toString() ?? '';
        final second = a['recorded_at']?.toString() ?? '';
        return first.compareTo(second);
      });
    return VoucherCode.markReferenceCollisions(
      combined,
      dashboardReference,
    ).take(5).toList();
  }

  void licenseChanged() {
    if (mounted) reload();
  }

  Future<void> reload() async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
      data = null;
    });
    try {
      final policy = SubscriptionRuntime.effective(
        await SubscriptionRuntime.read(),
        DateTime.now(),
      );
      final all = await AppDatabase.instance.getBranches();
      // Preserve existing local read access, including read-only retained branches.
      // Financial writes still go through the existing branch/license guards.
      final allowed = all;
      String user = 'local';
      try {
        user = OnlineAccounts.client.auth.currentUser?.id ?? 'local';
      } catch (_) {}
      final key = 'dashboard_ui_v1:${policy['business_id'] ?? 'local'}:$user';
      var selected = branch;
      var actions = shortcuts;
      if (key != preferenceKey) {
        selected = await prefs.getInt('$key:branch');
        final raw = await prefs.getString('$key:actions');
        actions = [...defaultDashboardActions];
        if (raw != null) {
          try {
            final parsed = jsonDecode(raw);
            if (parsed is List) {
              actions = parsed
                  .whereType<String>()
                  .where(dashboardActions.contains)
                  .toSet()
                  .toList();
            }
          } catch (_) {}
        }
      }
      selected = allowed.any((b) => b['id'] == selected)
          ? selected
          : await AppDatabase.instance.getDefaultBranchId();
      if (!allowed.any((b) => b['id'] == selected)) {
        selected = allowed.isEmpty ? null : allowed.first['id'] as int;
      }
      final result = selected == null
          ? null
          : await DashboardRepository.overview(selected, today: today);
      if (!mounted || token != request) return;
      setState(() {
        branches = allowed;
        branch = selected;
        data = result;
        shortcuts = actions;
        preferenceKey = key;
        loading = false;
      });
      widget.onBranch(selected);
    } catch (e) {
      if (mounted && token == request) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> selectBranch(int? id) async {
    if (id == null || id == branch) return;
    setState(() => branch = id);
    widget.onBranch(id);
    if (preferenceKey != null) {
      try {
        await prefs.setInt('$preferenceKey:branch', id);
      } catch (_) {}
    }
    await reload();
  }

  Future<void> editActions() async {
    final storageKey = preferenceKey;
    if (storageKey == null) return;
    var selected = [...shortcuts];
    final order = [
      ...selected,
      ...dashboardActions.where((a) => !selected.contains(a)),
    ];
    String? saveError;
    bool saving = false;
    final result = await showDesktopSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .78,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('Edit quick actions', 'အမြန်ဝင်ရန်များ ပြင်မည်'),
                          style: Theme.of(c).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(c),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    t(
                      'Choose shortcuts, then drag to reorder.',
                      'ထည့်လိုသည်ကို ရွေးပြီး အစီအစဉ်ရွှေ့ပါ။',
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: order.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (saving) return;
                        update(() {
                          final key = order.removeAt(oldIndex);
                          order.insert(newIndex, key);
                        });
                      },
                      itemBuilder: (c, index) {
                        final key = order[index];
                        return DesktopListTile(
                          key: ValueKey(key),
                          leading: Checkbox(
                            value: selected.contains(key),
                            onChanged: saving
                                ? null
                                : (checked) => update(() {
                                    if (checked == true) {
                                      selected.add(key);
                                    } else {
                                      selected.remove(key);
                                    }
                                  }),
                          ),
                          title: Text(dashboardLabel(key)),
                          subtitle: null,
                          trailing: ReorderableDragStartListener(
                            index: index,
                            enabled: !saving,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (saveError != null)
                    Text(
                      saveError!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  Wrap(
                    spacing: 10,
                    children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(c),
                        child: Text(t('Cancel', 'မလုပ်တော့')),
                      ),
                      OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => update(() {
                                selected = [...defaultDashboardActions];
                                order
                                  ..clear()
                                  ..addAll(dashboardActions);
                              }),
                        child: Text(t('Reset', 'မူလအတိုင်း')),
                      ),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                update(() => saving = true);
                                final values = order
                                    .where(selected.contains)
                                    .toList();
                                try {
                                  await prefs.setString(
                                    '$storageKey:actions',
                                    jsonEncode(values),
                                  );
                                  if (c.mounted) Navigator.pop(c, values);
                                } catch (_) {
                                  if (c.mounted) {
                                    update(() {
                                      saving = false;
                                      saveError = t(
                                        'Could not save. Retry.',
                                        'သိမ်းမရပါ။ ပြန်စမ်းပါ။',
                                      );
                                    });
                                  }
                                }
                              },
                        child: Text(t('Save', 'သိမ်းမည်')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) setState(() => shortcuts = result);
  }

  Widget panel(Widget child) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
  Widget metric(String label, int amount, IconData icon) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        MoneyText(amount, size: 20),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final current = data;
    final recent = _recentWithSyncedSales(
      (current?['recent'] as List?)?.cast<Map<String, Object?>>() ?? [],
      current,
    );
    if (AppCapabilities.windows) return desktopOverview(current, recent);
    final scaled = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return RefreshIndicator(
      onRefresh: reload,
      child: DesktopListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 104),
        children: [
          if (loading) const LinearProgressIndicator(),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Business overview', 'လုပ်ငန်းအခြေအနေ'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: t('Refresh', 'ပြန်စစ်ရန်'),
                onPressed: loading ? null : reload,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (error != null) ...[
            SelectableText(error!),
            TextButton(
              onPressed: reload,
              child: Text(t('Retry', 'ပြန်စမ်းရန်')),
            ),
          ],
          if (branches.isEmpty && !loading)
            Text(
              t(
                'No available branch. Check Branches and your POS license.',
                'ဆိုင်ခွဲမရှိပါ။ Branches နှင့် POS လိုင်စင်ကို စစ်ပါ။',
              ),
            ),
          DropdownButtonFormField<int>(
            key: ValueKey(branch),
            initialValue: branch,
            isExpanded: true,
            decoration: InputDecoration(
              fillColor: AppCapabilities.windows
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF233E62)
                        : const Color(0xFFE5EEFF))
                  : null,
              prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
              labelText: t('Change branch', 'ဆိုင်ခွဲပြောင်းရန်'),
            ),
            items: [
              for (final b in branches)
                DropdownMenuItem(
                  value: b['id'] as int,
                  child: Text('${b['name']} (${b['code']})'),
                ),
            ],
            onChanged: loading ? null : selectBranch,
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(t('Today', 'ဒီနေ့'))),
              ButtonSegment(value: false, label: Text(t('This month', 'ဒီလ'))),
            ],
            selected: {today},
            onSelectionChanged: loading
                ? null
                : (v) {
                    setState(() => today = v.single);
                    reload();
                  },
          ),
          if (current != null) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (c, box) {
                final children = [
                  metric(
                    today
                        ? t('Today’s sales', 'ယနေ့အရောင်း')
                        : t('Monthly sales', 'ဒီလအရောင်း'),
                    current['sales'] as int,
                    Icons.trending_up,
                  ),
                  metric(
                    today
                        ? t('Today’s expenses', 'ယနေ့အသုံးစရိတ်')
                        : t('Monthly expenses', 'ဒီလအသုံးစရိတ်'),
                    current['expenses'] as int,
                    Icons.receipt_long_outlined,
                  ),
                ];
                return scaled || box.maxWidth < 300
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: children[0]),
                          const SizedBox(width: 8),
                          Expanded(child: children[1]),
                        ],
                      );
              },
            ),
            panel(
              LayoutBuilder(
                builder: (c, box) {
                  final label = Text(
                    t('Current account balance', 'လက်ရှိငွေအကောင့်လက်ကျန်'),
                    style: Theme.of(c).textTheme.bodySmall,
                  );
                  final amount = MoneyText(current['balance'] as int, size: 20);
                  return scaled || box.maxWidth < 320
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 6), amount],
                        )
                      : Row(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: label),
                            const SizedBox(width: 10),
                            Flexible(child: amount),
                          ],
                        );
                },
              ),
            ),
            if (recent.any((row) => row['live_voucher'] != null))
              Text(
                t(
                  'Summary totals are from this device.',
                  'စုစုပေါင်းငွေစာရင်းသည် ဤစက်၏ စာရင်းဖြစ်သည်။',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              '${t('Updated', 'နောက်ဆုံးစစ်ချိန်')}: ${AppDateTime.format(current['loaded_at'])}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Quick actions', 'အမြန်ဝင်ရန်'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: loading || preferenceKey == null
                    ? null
                    : editActions,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: Text(t('Edit', 'ပြင်ရန်')),
              ),
            ],
          ),
          if (shortcuts.isEmpty)
            Text(
              t(
                'Tap Edit to add shortcuts.',
                'အမြန်ဝင်ရန်များ ထည့်ဖို့ Edit ကိုနှိပ်ပါ။',
              ),
            ),
          LayoutBuilder(
            builder: (c, box) {
              final columns = scaled || box.maxWidth < 340 ? 2 : 3;
              final width = (box.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in shortcuts)
                    SizedBox(
                      width: width,
                      child: OutlinedButton(
                        onPressed: loading || branch == null
                            ? null
                            : () async {
                                await widget.onAction(action, branch!);
                                if (mounted) await reload();
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Icon(dashboardIcon(action), size: 18),
                            Text(
                              dashboardLabel(action),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Recent', 'နောက်ဆုံးစာရင်းများ'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: branch == null || loading
                    ? null
                    : () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DashboardRecentPage(
                              branch: branch!,
                              onOpen: widget.onRecent,
                            ),
                          ),
                        );
                        if (mounted) reload();
                      },
                child: Text(t('See all', 'အားလုံးကြည့်ရန်')),
              ),
            ],
          ),
          Text(
            t(
              'Latest recorded transactions in this branch',
              'ဤဆိုင်ခွဲ၏ နောက်ဆုံးသိမ်းထားသောစာရင်းများ',
            ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (!loading && recent.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t('No transactions yet.', 'စာရင်းမရှိသေးပါ။')),
            ),
          for (final row in recent)
            RecentTransactionTile(
              row: row,
              onTap: () => widget.onRecent(row, branch!).then((_) {
                if (mounted) reload();
              }),
            ),
        ],
      ),
    );
  }

  void changeDesktopPeriod(bool value) => setState(() => today = value);
}

String dashboardReference(Map<String, Object?> row) {
  final reference = row['live_number'] as String?;
  if (reference != null) return reference;
  if (row['kind'] == 'sale') return VoucherCode.displayNumber(row);
  final prefix = row['kind'] == 'purchase' ? 'PUR' : 'RCPT';
  return '$prefix-${(row['id'] as int).toString().padLeft(6, '0')}';
}

class RecentTransactionTile extends StatelessWidget {
  const RecentTransactionTile({
    super.key,
    required this.row,
    required this.onTap,
  });
  final Map<String, Object?> row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final kind = row['kind'];
    return Card(
      child: DesktopListTile(
        onTap: onTap,
        leading: Icon(
          kind == 'sale'
              ? Icons.shopping_cart_outlined
              : kind == 'purchase'
              ? Icons.shopping_bag_outlined
              : Icons.payments_outlined,
          size: 20,
        ),
        title: Text(VoucherCode.displayReference(row, dashboardReference(row))),
        subtitle: Text(
          '${AppDateTime.format(row['recorded_at'])}${row['status'] == 'void' ? ' · VOID' : ''}',
        ),
        trailing: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .36,
          ),
          child: MoneyText(row['amount'] as int, size: 14),
        ),
      ),
    );
  }
}

class DashboardRecentPage extends StatefulWidget {
  const DashboardRecentPage({
    super.key,
    required this.branch,
    required this.onOpen,
  });
  final int branch;
  final Future<void> Function(Map<String, Object?>, int) onOpen;
  @override
  State<DashboardRecentPage> createState() => _DashboardRecentPageState();
}

class _DashboardRecentPageState extends State<DashboardRecentPage> {
  List<Map<String, Object?>> rows = [];
  int page = 0;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final result = await DashboardRepository.recent(
        db,
        widget.branch,
        limit: 50,
        offset: page * 50,
      );
      if (mounted) {
        setState(() {
          rows = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(
        AppLanguage.current.value == 'my'
            ? 'နောက်ဆုံးစာရင်းများ'
            : 'Recent transactions',
      ),
    ),
    body: DesktopListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!),
          TextButton(onPressed: load, child: const Text('Retry')),
        ],
        for (final row in rows)
          RecentTransactionTile(
            row: row,
            onTap: () async {
              await widget.onOpen(row, widget.branch);
              if (mounted) load();
            },
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: loading || page == 0
                  ? null
                  : () {
                      page--;
                      load();
                    },
              child: const Text('‹'),
            ),
            Text('${page + 1}'),
            TextButton(
              onPressed: loading || rows.length < 50
                  ? null
                  : () {
                      page++;
                      load();
                    },
              child: const Text('›'),
            ),
          ],
        ),
      ],
    ),
  );
}
