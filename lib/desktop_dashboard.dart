part of 'dashboard_page.dart';

extension _DesktopDashboard on DashboardPageState {
  Widget desktopOverview(
    Map<String, Object?>? current,
    List<Map<String, Object?>> recent,
  ) {
    final theme = Theme.of(context);
    Future<void> period(bool value) async {
      changeDesktopPeriod(value);
      await reload();
    }

    Widget metricTile(String label, int amount, IconData icon, Color accent) =>
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: label,
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MoneyText(amount, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    final workspace = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<int>(
                  key: ValueKey(branch),
                  initialValue: branch,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
                    labelText: t('Branch', 'ဆိုင်ခွဲ'),
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
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(t('Today', 'ယနေ့'))),
                  ButtonSegment(
                    value: false,
                    label: Text(t('This month', 'ယခုလ')),
                  ),
                ],
                selected: {today},
                onSelectionChanged: loading
                    ? null
                    : (values) => period(values.single),
              ),
              IconButton(
                tooltip: t('Refresh', 'ပြန်တင်ရန်'),
                onPressed: loading ? null : reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Row(
              children: [
                Expanded(child: SelectableText(error!)),
                TextButton(
                  onPressed: reload,
                  child: Text(t('Retry', 'ပြန်ကြိုးစားရန်')),
                ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 94,
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: box.maxWidth < 690 ? 690 : box.maxWidth,
                  child: Row(
                    children: [
                      Expanded(
                        child: metricTile(
                          today
                              ? t("Today's sales", 'ယနေ့အရောင်း')
                              : t('Monthly sales', 'ယခုလအရောင်း'),
                          current?['sales'] as int? ?? 0,
                          Icons.trending_up,
                          const Color(0xFF008C79),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: metricTile(
                          today
                              ? t("Today's expenses", 'ယနေ့အသုံးစရိတ်')
                              : t('Monthly expenses', 'ယခုလအသုံးစရိတ်'),
                          current?['expenses'] as int? ?? 0,
                          Icons.receipt_long_outlined,
                          const Color(0xFFB47B16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: metricTile(
                          t(
                            'Current account balance',
                            'လက်ရှိငွေစာရင်းလက်ကျန်',
                          ),
                          current?['balance'] as int? ?? 0,
                          Icons.account_balance_wallet_outlined,
                          const Color(0xFF4272AD),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Quick actions', 'အမြန်လုပ်ဆောင်ချက်များ'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: loading || preferenceKey == null
                    ? null
                    : editActions,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(t('Edit', 'ပြင်ရန်')),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final action in shortcuts)
                OutlinedButton.icon(
                  onPressed: loading || branch == null
                      ? null
                      : () async {
                          await widget.onAction(action, branch!);
                          if (mounted) await reload();
                        },
                  icon: Icon(dashboardIcon(action), size: 17),
                  label: Text(dashboardLabel(action)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  t('Recent transactions', 'လတ်တလောအရောင်းအဝယ်'),
                  style: theme.textTheme.titleSmall,
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
                        if (mounted) await reload();
                      },
                child: Text(t('See all', 'အားလုံးကြည့်ရန်')),
              ),
            ],
          ),
          Expanded(
            child: DesktopGrid(
              key: const ValueKey('desktop-dashboard-transactions'),
              minWidth: 650,
              columns: [
                t('Reference', 'အမှတ်'),
                t('Type', 'အမျိုးအစား'),
                t('Date & time', 'ရက်စွဲနှင့်အချိန်'),
                t('Amount', 'ပမာဏ'),
                t('Status', 'အခြေအနေ'),
              ],
              flexes: const [2, 2, 3, 2, 1],
              rows: [
                for (final row in recent)
                  [
                    Text(
                      '${row['kind'] == 'sale'
                          ? 'INV'
                          : row['kind'] == 'purchase'
                          ? 'PUR'
                          : 'RCPT'}-${(row['id'] as int).toString().padLeft(6, '0')}',
                    ),
                    Text('${row['kind']}'),
                    Text(AppDateTime.format(row['recorded_at'])),
                    MoneyText(row['amount'] as int, size: 13),
                    Text('${row['status'] ?? 'posted'}'),
                  ],
              ],
              onRowTap: branch == null
                  ? null
                  : (index) async {
                      await widget.onRecent(recent[index], branch!);
                      if (mounted) await reload();
                    },
              emptyText: t('No transactions yet.', 'မှတ်တမ်းမရှိသေးပါ။'),
            ),
          ),
          if (current != null)
            Text(
              '${t('Updated', 'နောက်ဆုံးတင်ချိန်')}: ${AppDateTime.format(current['loaded_at'])}',
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxHeight < 650
          ? SingleChildScrollView(
              child: SizedBox(height: 760, child: workspace),
            )
          : workspace,
    );
  }
}
