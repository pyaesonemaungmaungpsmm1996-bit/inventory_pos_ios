import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'online_account_service.dart';
import 'shared_sale_draft_page.dart';
import 'voucher_code.dart';

class BranchActivity {
  static final _preferences = SharedPreferencesAsync();
  static bool _running = false;
  static String _key(SharedDraftBranch b) =>
      'branch_activity:${b.account}:${b.business}:${b.id}:${b.localId}';

  static void start() {
    Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_publish()));
  }

  static Future<void> configure(BuildContext context, String business) async {
    try {
      final local = await AppDatabase.instance.getBranches();
      final approved = (await SharedDraftBranch.approved(local))
          .where((branch) => branch.business == business)
          .toList();
      if (!context.mounted) return;
      if (approved.isEmpty) {
        throw StateError(
          'An approved device and a matching local branch are required',
        );
      }
      final branch = await showDialog<SharedDraftBranch>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Share branch activity with the business owner'),
          children: [
            for (final branch in approved)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, branch),
                child: Text(branch.name),
              ),
          ],
        ),
      );
      if (branch == null || !context.mounted) return;
      await enable(branch);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Branch activity sharing enabled on this device.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  static Future<void> enable(SharedDraftBranch b) async {
    await _send(b);
    await _preferences.setBool(_key(b), true);
  }

  static Future<void> _publish() async {
    if (_running) return;
    _running = true;
    try {
      await OnlineAccounts.initialize();
      if (OnlineAccounts.client.auth.currentUser == null) return;
      final local = await AppDatabase.instance.getBranches();
      for (final branch in await SharedDraftBranch.approved(local)) {
        if (await _preferences.getBool(_key(branch)) == true) {
          try {
            await _send(branch);
          } catch (_) {
            // Keep the last successful report online and retry on the next tick.
          }
        }
      }
    } catch (_) {
      // A device can continue local operations during an outage.
    } finally {
      _running = false;
    }
  }

  static Future<void> _send(SharedDraftBranch branch) async {
    final db = await AppDatabase.instance.database;
    final report = await db.transaction((txn) async {
      final id = [branch.localId];
      final sales = await txn.rawQuery(
        '''SELECT id, branch_id, branch_code_snapshot,
        invoice_date, status, total, paid FROM sale_invoices
        WHERE branch_id = ? ORDER BY id DESC LIMIT 100''',
        id,
      );
      return <String, Object?>{
        'sales': [
          for (final row in sales)
            {
              'reference': VoucherCode.displayNumber(row),
              'date': row['invoice_date'],
              'status': row['status'],
              'total': row['total'],
              'paid': row['paid'],
            },
        ],
        'purchases': await txn.rawQuery(
          '''SELECT printf('PUR-%06d',id) reference,
          invoice_date date, supplier_name supplier, status, total, paid
          FROM purchase_invoices WHERE branch_id = ? ORDER BY id DESC LIMIT 100''',
          id,
        ),
        'expenses': await txn.rawQuery(
          '''SELECT expense_date date, category, status, amount
          FROM expenses WHERE branch_id = ? ORDER BY id DESC LIMIT 100''',
          id,
        ),
        'expense_summary': await txn.rawQuery(
          '''SELECT category, count(*) entries, sum(amount) amount
          FROM expenses WHERE branch_id = ? AND status = 'posted' GROUP BY category ORDER BY category''',
          id,
        ),
        'stock': await txn.rawQuery(
          '''SELECT p.item_code, p.name, s.stock quantity
          FROM branch_stocks s JOIN products p ON p.id = s.product_id
          WHERE s.branch_id = ? ORDER BY p.item_code, p.id LIMIT 100''',
          id,
        ),
        'wallet': await txn.rawQuery(
          '''SELECT a.name, a.type, COALESCE(sum(e.amount),0) balance
          FROM money_accounts a LEFT JOIN money_entries e ON e.account_id = a.id
          WHERE a.branch_id = ? GROUP BY a.id ORDER BY a.name, a.id LIMIT 100''',
          id,
        ),
        'ledger': await txn.rawQuery(
          '''SELECT e.entry_date date, a.name account, e.kind, e.amount
          FROM money_entries e JOIN money_accounts a ON a.id = e.account_id
          WHERE a.branch_id = ? ORDER BY e.entry_date DESC, e.id DESC LIMIT 100''',
          id,
        ),
        'currency': (await txn.query(
          'business_profile',
          columns: ['currency_code'],
          where: 'id = 1',
        )).single['currency_code'],
      };
    });
    if (OnlineAccounts.client.auth.currentUser?.id != branch.account) {
      throw StateError('The signed-in account changed');
    }
    if (utf8.encode(jsonEncode(report)).length > 480000) {
      throw StateError('Branch report exceeds the upload limit');
    }
    await OnlineAccounts.client
        .rpc(
          'tp_publish_branch_activity',
          params: {
            'p_business': branch.business,
            'p_branch': branch.id,
            'p_installation': branch.installation,
            'p_report': report,
          },
        )
        .timeout(const Duration(seconds: 12));
  }
}

class BranchActivityPage extends StatefulWidget {
  const BranchActivityPage({
    super.key,
    required this.business,
    required this.branches,
  });
  final String business;
  final List<Map<String, dynamic>> branches;

  @override
  State<BranchActivityPage> createState() => _BranchActivityPageState();
}

class _BranchActivityPageState extends State<BranchActivityPage> {
  late final _account = OnlineAccounts.client.auth.currentUser?.id;
  String? _branch;
  Timer? _timer;
  Object? _error;
  List<dynamic> _reports = [];
  int _request = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _branch = widget.branches.firstOrNull?['id'] as String?;
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_loading) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _field(MapEntry<dynamic, dynamic> field, Object? currency) {
    final value = field.value;
    if (value is int &&
        currency is String &&
        AppCurrency.precision.containsKey(currency) &&
        const ['amount', 'total', 'paid', 'balance'].contains(field.key)) {
      return '${field.key}: ${AppCurrency.format(value, currency: currency)}';
    }
    return '${field.key}: ${value ?? '—'}';
  }

  Future<void> _load() async {
    final branch = _branch;
    if (branch == null) return;
    final request = ++_request;
    setState(() => _loading = true);
    try {
      if (_account == null ||
          _account != OnlineAccounts.client.auth.currentUser?.id) {
        throw StateError('Sign in again to view branch activity');
      }
      final rows = await OnlineAccounts.client
          .rpc(
            'tp_owner_branch_activity',
            params: {'p_business': widget.business, 'p_branch': branch},
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted || request != _request) return;
      if (OnlineAccounts.client.auth.currentUser?.id != _account) {
        throw StateError('The signed-in account changed');
      }
      setState(() {
        _reports = rows as List;
        _error = null;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = e;
          _reports = [];
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Branch activity'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _branch,
          decoration: const InputDecoration(labelText: 'Branch'),
          items: [
            for (final b in widget.branches)
              DropdownMenuItem(
                value: b['id'] as String,
                child: Text('${b['name']}'),
              ),
          ],
          onChanged: (branch) {
            setState(() {
              _branch = branch;
              _reports = [];
              _error = null;
            });
            unawaited(_load());
          },
        ),
        if (_reports.isNotEmpty)
          const Text(
            'Reports show up to 100 rows per section from each device.',
          ),
        if (_loading && _reports.isEmpty) const LinearProgressIndicator(),
        if (_error != null) Text('Branch activity unavailable. $_error'),
        if (!_loading && _error == null && _reports.isEmpty)
          const Text('No reports received for this branch.'),
        for (final row in _reports.whereType<Map>())
          if (row['report'] case final Map report)
            Card(
              child: ExpansionTile(
                title: Text('Device ${row['installation_id']}'),
                subtitle: Text(
                  'Last changed ${row['updated_at']} · ${report['currency']}',
                ),
                children: [
                  for (final entry in const {
                    'sales': 'Sale invoices',
                    'purchases': 'Purchase history',
                    'expenses': 'Expenses',
                    'expense_summary': 'Expense summary',
                    'stock': 'Stock',
                    'wallet': 'Wallet',
                    'ledger': 'Ledger',
                  }.entries)
                    ExpansionTile(
                      title: Text(entry.value),
                      children: [
                        for (final item
                            in (report[entry.key] as List? ?? [])
                                .whereType<Map>())
                          ListTile(
                            title: Text(
                              item.entries
                                  .map((e) => _field(e, report['currency']))
                                  .join(' · '),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
      ],
    ),
  );
}
