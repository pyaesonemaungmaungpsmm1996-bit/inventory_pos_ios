import 'dart:async';
import 'dart:convert';

import 'live_sale_sync.dart';
import 'live_sales_page.dart';
import 'shared_sale_draft_page.dart';
import 'sync_dev_profile.dart';

import 'voucher_code.dart';

import 'package:sqflite/sqflite.dart';

import 'contact_search.dart';
import 'history_date_filter.dart';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'desktop_ui.dart';
import 'sale_confirmation_page.dart';
import 'sale_invoices_page.dart';

class SaleInvoiceHistoryRepository {
  static Future<List<Map<String, Object?>>> list(
    DatabaseExecutor db, {
    String? identityPrefix,
  }) => db.rawQuery(
    '''
 SELECT * FROM (SELECT s.id,s.branch_id,b.name branch_name,s.customer_id,s.customer_name,s.customer_phone,s.invoice_date,s.total,s.balance_due,s.currency_code,s.currency_digits,s.status,s.branch_code_snapshot,'invoice' record_kind,s.confirmed_at updated_at, v.value live_identity FROM sale_invoices s JOIN branches b ON b.id=s.branch_id LEFT JOIN app_settings v ON v.key=? || s.draft_id
 UNION ALL
 SELECT d.id,d.branch_id,b.name branch_name,d.customer_id,d.customer_name,d.customer_phone,d.invoice_date,d.total,0 balance_due,d.currency_code,d.currency_digits,'draft' status,NULL branch_code_snapshot,'draft' record_kind,d.updated_at, v.value FROM sale_drafts d JOIN branches b ON b.id=d.branch_id LEFT JOIN app_settings v ON v.key=? || d.id WHERE NOT EXISTS(SELECT 1 FROM sale_invoices s WHERE s.draft_id=d.id)
 AND d.correction_source_sale_id IS NULL
 ) ORDER BY updated_at DESC,id DESC
 ''',
    [identityPrefix, identityPrefix],
  );

  static List<Map<String, Object?>> mergeSales(
    List<Map<String, Object?>> rows,
    List<Map<String, Object?>> branches,
  ) {
    final updates = LiveSaleSync.feed.value;
    final localVouchers = <String>{};
    for (final row in rows) {
      final identity = row['live_identity'];
      if (identity is! String) continue;
      try {
        final value = jsonDecode(identity);
        if (value is Map &&
            value['account'] == updates.account &&
            value['voucher'] is String) {
          localVouchers.add(value['voucher'] as String);
        }
      } on FormatException {
        // A legacy or damaged setting does not hide a voucher.
      }
    }
    final combined = [...rows];
    for (final row in updates.rows) {
      final id = row['voucher_id'];
      final sale = row['payload'];
      if (id is! String ||
          sale is! Map ||
          sale['status'] == 'removed' ||
          localVouchers.contains(id)) {
        continue;
      }
      final code = sale['branch_code']?.toString().trim().toLowerCase();
      final name = sale['branch']?.toString().trim().toLowerCase();
      final localBranch = branches.where((b) {
        final sameCode = b['code'].toString().trim().toLowerCase() == code;
        final sameName = b['name'].toString().trim().toLowerCase() == name;
        return code == null || code.isEmpty ? sameName : sameCode;
      }).firstOrNull;
      combined.add({
        'live_voucher': id,
        'live_number': sale['number']?.toString() ?? id,
        'branch_id': localBranch?['id'],
        'branch_name': sale['branch'],
        'invoice_date': sale['date'],
        'status': sale['status'],
        'total': sale['total'],
        'balance_due': sale['balance_due'],
        'currency_code': sale['currency_code']?.toString() ?? 'MMK',
        'currency_digits': sale['currency_digits'] is int
            ? sale['currency_digits']
            : 0,
        'customer_name': '',
        'customer_phone': '',
        'updated_at': row['updated_at'],
      });
    }
    return combined..sort((a, b) {
      final byTime = (b['updated_at']?.toString() ?? '').compareTo(
        a['updated_at']?.toString() ?? '',
      );
      if (byTime != 0) return byTime;
      return (b['id'] as int? ?? 0).compareTo(a['id'] as int? ?? 0);
    });
  }
}

class SaleInvoiceHistoryPage extends StatefulWidget {
  const SaleInvoiceHistoryPage({super.key});
  @override
  State<SaleInvoiceHistoryPage> createState() => _SaleInvoiceHistoryPageState();
}

class _SaleInvoiceHistoryPageState extends State<SaleInvoiceHistoryPage> {
  List<Map<String, Object?>> branches = [], rows = [];
  int _loadRequest = 0;
  bool _loadingShared = false;
  Timer? _sharedTimer;
  List<SharedDraftBranch> _sharedBranches = [];
  List<Map<String, Object?>> _sharedRows = [];
  String? _sharedError;
  int? branch;
  String filter = 'all', search = '';
  DateTime? fromDate, toDate;
  bool loading = true;
  String? error;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    initializeDefaultBranch();
    LiveSaleSync.feed.addListener(_feedChanged);
    if (SyncDevProfile.enabled) {
      _sharedTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshShared()),
      );
    }
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LiveSaleSync.feed.removeListener(_feedChanged);
    _sharedTimer?.cancel();
    super.dispose();
  }

  Future<void> initializeDefaultBranch() async {
    try {
      branch ??= await AppDatabase.instance.getDefaultBranchId();
    } catch (_) {
      /* The normal load shows any storage error. */
    }
    if (mounted) await load();
  }

  Future<void> _refreshShared() async {
    if (!SyncDevProfile.enabled ||
        !mounted ||
        _loadingShared ||
        branches.isEmpty) {
      return;
    }
    _loadingShared = true;
    try {
      final approved = await SharedDraftBranch.approved(branches);
      final pages = await Future.wait(approved.map((branch) => branch.list()));
      if (!mounted) return;
      setState(() {
        _sharedBranches = approved;
        _sharedRows = pages.expand((rows) => rows).toList();
        _sharedError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sharedBranches = [];
        _sharedRows = [];
        _sharedError = 'Shared drafts are unavailable. Check the connection and device approval.';
      });
    } finally {
      _loadingShared = false;
    }
  }

  Future<void> _openShared(SharedDraftBranch branch, {String? id}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SharedSaleDraftPage(branch: branch, id: id),
      ),
    );
    if (mounted) await _refreshShared();
  }

  Future<void> load() async {
    final request = ++_loadRequest;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final b = await AppDatabase.instance.getBranches();
      final r = await SaleInvoiceHistoryRepository.list(
        db,
        identityPrefix: LiveSaleSync.localIdentityPrefix,
      );
      if (mounted && request == _loadRequest) {
        setState(() {
          branches = b;
          rows = r;
          loading = false;
        });
        unawaited(_refreshShared());
      }
    } catch (e) {
      if (mounted && request == _loadRequest) {
        setState(() {
          loading = false;
          error = t(
            'Could not load invoices. Retry.',
            'ဘောင်ချာများ ဖတ်မရပါ။ ပြန်စမ်းပါ။',
          );
        });
      }
    }
  }

  String number(Map<String, Object?> row) =>
      (row['shared_id'] is String
          ? 'DRAFT-${(row['shared_id'] as String).split('-').first.toUpperCase()}'
          : null) ??
      row['live_number'] as String? ??
      (row['record_kind'] == 'draft'
          ? 'DRAFT-${row['id'].toString().padLeft(6, '0')}'
          : VoucherCode.displayNumber(row));
  Future<void> open(Map<String, Object?> row) async {
    final shared = row['shared_branch'];
    if (shared is SharedDraftBranch) {
      await _openShared(shared, id: row['shared_id'] as String);
      return;
    }
    final voucher = row['live_voucher'] as String?;
    final account = LiveSaleSync.feed.value.account;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => voucher != null && account != null
            ? LiveVoucherPage(account: account, voucher: voucher)
            : row['record_kind'] == 'draft'
            ? SaleInvoicesPage(
                initialBranchId: row['branch_id'] as int,
                initialDraftId: row['id'] as int,
              )
            : ConfirmedSaleDetailPage(saleId: row['id'] as int),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final q = search.trim().toLowerCase();
    final account = LiveSaleSync.accountId;
    final approvedBranch = _sharedBranches
        .where((b) => b.localId == branch && b.canEdit && b.account == account)
        .firstOrNull;
    final allRows =
        [
          ...SaleInvoiceHistoryRepository.mergeSales(rows, branches),
          ..._sharedRows.where(
            (row) =>
                (row['shared_branch'] as SharedDraftBranch).account == account,
          ),
        ]..sort(
          (a, b) => (b['updated_at']?.toString() ?? '').compareTo(
            a['updated_at']?.toString() ?? '',
          ),
        );
    final visible = allRows
        .where(
          (r) =>
              (branch == null || r['branch_id'] == branch) &&
              (filter == 'all' || r['status'] == filter) &&
              HistoryDates.includes(r['invoice_date'], fromDate, toDate) &&
              (q.isEmpty ||
                  [
                    number(r),
                    if (r['record_kind'] == 'invoice')
                      'INV-${r['id'].toString().padLeft(6, '0')}',
                    r['customer_name'],
                    r['customer_phone'],
                    ContactSearch.code(r['customer_id']),
                    r['branch_name'],
                  ].any((v) => v.toString().toLowerCase().contains(q))),
        )
        .toList();
    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DesktopPropertyFields(
              children: [
                DropdownButtonFormField<int>(
                  key: ValueKey(
                    'sale-history-branch-${branches.length}-$branch',
                  ),
                  initialValue: branches.any((b) => b['id'] == branch)
                      ? branch
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t('Branch', 'ဆိုင်ခွဲ'),
                  ),
                  items: [
                    DropdownMenuItem<int>(
                      value: null,
                      child: Text(t('All branches', 'ဆိုင်ခွဲအားလုံး')),
                    ),
                    for (final b in branches)
                      DropdownMenuItem(
                        value: b['id'] as int,
                        child: Text(b['name'].toString()),
                      ),
                  ],
                  onChanged: (v) => setState(() => branch = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: filter,
                  decoration: InputDecoration(
                    labelText: t('Invoice status', 'ဘောင်ချာအခြေအနေ'),
                  ),
                  items: [
                    for (final k in ['all', 'posted', 'draft', 'void'])
                      DropdownMenuItem(
                        value: k,
                        child: Text(
                          k == 'all'
                              ? t(
                                  'All invoices and drafts',
                                  'ဘောင်ချာနှင့် Draft အားလုံး',
                                )
                              : k,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => filter = v ?? 'all'),
                ),
                TextField(
                  decoration: InputDecoration(
                    labelText: t(
                      'Find invoice / customer ID / phone',
                      'ဘောင်ချာ / ဝယ်သူ ID / ဖုန်း ရှာရန်',
                    ),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
                HistoryDateFilter(
                  from: fromDate,
                  to: toDate,
                  onChanged: (from, to) => setState(() {
                    fromDate = from;
                    toDate = to;
                  }),
                ),
                OutlinedButton.icon(
                  onPressed: loading
                      ? null
                      : () {
                          LiveSaleSync.wake();
                          unawaited(LiveSaleSync.refreshFeed());
                          unawaited(load());
                        },
                  icon: const Icon(Icons.refresh, size: 17),
                  label: Text(t('Refresh', 'ပြန်ဖတ်ရန်')),
                ),
              ],
            ),
          ),
          if (error != null) Text(error!),
          if (_sharedError != null) Text(_sharedError!),
          if (approvedBranch != null)
            FilledButton.icon(
              onPressed: () => _openShared(approvedBranch),
              icon: const Icon(Icons.add),
              label: const Text('New Draft'),
            ),
          if (LiveSaleSync.feed.value.unavailable)
            Text(
              t(
                'Live updates unavailable. Use Refresh to reconnect.',
                'တိုက်ရိုက် အပ်ဒိတ် ပြတ်နေသည်။ Refresh နှိပ်၍ ပြန်ချိတ်ပါ။',
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : DesktopListView.builder(
                    itemCount: visible.length,
                    desktopColumns: const [
                      'Invoice No.',
                      'Date',
                      'Branch',
                      'Customer',
                      'Phone',
                      'Total',
                      'Balance',
                      'Status',
                    ],
                    desktopCells: (context, i) {
                      final r = visible[i];
                      return [
                        desktopCellText(number(r)),
                        desktopCellText(r['invoice_date']),
                        desktopCellText(r['branch_name']),
                        desktopCellText(r['customer_name']),
                        desktopCellText(r['customer_phone']),
                        desktopMoney(
                          r['total'],
                          currency: r['currency_code'] as String,
                          digits: r['currency_digits'] as int,
                        ),
                        desktopMoney(
                          r['balance_due'],
                          currency: r['currency_code'] as String,
                          digits: r['currency_digits'] as int,
                        ),
                        desktopCellText(r['status']),
                      ];
                    },
                    itemBuilder: (context, i) {
                      final r = visible[i];
                      return DesktopListTile(
                        title: Text(
                          [
                            number(r),
                            if (r['customer_name']?.toString().isNotEmpty ??
                                false)
                              r['customer_name'].toString(),
                          ].join(' · '),
                        ),
                        subtitle: Text(
                          '${r['branch_name']} · ${r['invoice_date']} · ${r['status']}',
                        ),
                        trailing: desktopMoney(r['total']),
                        onTap: () => open(r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
