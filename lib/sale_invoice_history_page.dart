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
  static Future<List<Map<String, Object?>>> list(DatabaseExecutor db) =>
      db.rawQuery('''
 SELECT * FROM (SELECT s.id,s.branch_id,b.name branch_name,s.customer_id,s.customer_name,s.customer_phone,s.invoice_date,s.total,s.balance_due,s.currency_code,s.currency_digits,s.status,s.branch_code_snapshot,'invoice' record_kind,s.confirmed_at updated_at FROM sale_invoices s JOIN branches b ON b.id=s.branch_id
 UNION ALL
 SELECT d.id,d.branch_id,b.name branch_name,d.customer_id,d.customer_name,d.customer_phone,d.invoice_date,d.total,0 balance_due,d.currency_code,d.currency_digits,'draft' status,NULL branch_code_snapshot,'draft' record_kind,d.updated_at FROM sale_drafts d JOIN branches b ON b.id=d.branch_id WHERE NOT EXISTS(SELECT 1 FROM sale_invoices s WHERE s.draft_id=d.id)
 AND d.correction_source_sale_id IS NULL
 ) ORDER BY updated_at DESC,id DESC
 ''');
}

class SaleInvoiceHistoryPage extends StatefulWidget {
  const SaleInvoiceHistoryPage({super.key});
  @override
  State<SaleInvoiceHistoryPage> createState() => _SaleInvoiceHistoryPageState();
}

class _SaleInvoiceHistoryPageState extends State<SaleInvoiceHistoryPage> {
  List<Map<String, Object?>> branches = [], rows = [];
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
  }

  Future<void> initializeDefaultBranch() async {
    try {
      branch ??= await AppDatabase.instance.getDefaultBranchId();
    } catch (_) {
      /* The normal load shows any storage error. */
    }
    if (mounted) await load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final b = await AppDatabase.instance.getBranches();
      final r = await SaleInvoiceHistoryRepository.list(db);
      if (mounted) {
        setState(() {
          branches = b;
          rows = r;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  String number(Map<String, Object?> row) => row['record_kind'] == 'draft'
      ? 'DRAFT-${row['id'].toString().padLeft(6, '0')}'
      : VoucherCode.displayNumber(row);
  Future<void> open(Map<String, Object?> row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => row['record_kind'] == 'draft'
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
    final visible = rows
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
                  onPressed: loading ? null : load,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: Text(t('Refresh', 'ပြန်ဖတ်ရန်')),
                ),
              ],
            ),
          ),
          if (error != null) Text(error!),
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
                        title: Text('${number(r)} · ${r['customer_name']}'),
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
