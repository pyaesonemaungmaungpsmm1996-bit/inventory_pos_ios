import 'dart:async';

import 'package:flutter/material.dart';

import 'desktop_ui.dart';
import 'live_sale_sync.dart';
import 'online_account_service.dart';

class LiveSalesPage extends StatelessWidget {
  const LiveSalesPage({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: OnlineAccounts.initialize(),
    builder: (context, initialized) {
      if (initialized.hasError) {
        return const _LiveMessage('Could not connect to the online account.');
      }
      if (initialized.connectionState != ConnectionState.done) {
        return const DesktopScaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      return StreamBuilder(
        stream: OnlineAccounts.client.auth.onAuthStateChange,
        builder: (context, _) {
          final account = LiveSaleSync.accountId;
          if (account == null) {
            return const _LiveMessage(
              'Sign in to the same online account on each device.',
            );
          }
          return _AccountSales(key: ValueKey(account), account: account);
        },
      );
    },
  );
}

class _AccountSales extends StatefulWidget {
  const _AccountSales({super.key, required this.account});
  final String account;

  @override
  State<_AccountSales> createState() => _AccountSalesState();
}

class _AccountSalesState extends State<_AccountSales> {
  late Stream<List<Map<String, dynamic>>> _sales = _watch();
  String? _selected;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _sales = _watch());
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Stream<List<Map<String, dynamic>>> _watch() => OnlineAccounts.client
      .from(LiveSaleSync.table)
      .stream(primaryKey: ['account_id', 'voucher_id'])
      .eq('account_id', widget.account)
      .order('updated_at', ascending: false)
      .limit(100);

  Widget _money(Map<String, dynamic> sale, String key) => desktopMoney(
    sale[key],
    currency: sale['currency_code'] as String? ?? 'MMK',
    digits: sale['currency_digits'] as int? ?? 0,
  );

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(_selected == null ? 'Live sales' : 'Live voucher'),
      leading: _selected == null
          ? null
          : BackButton(onPressed: () => setState(() => _selected = null)),
      actions: [
        IconButton(
          tooltip: 'Reconnect',
          onPressed: () {
            LiveSaleSync.wake();
            setState(() => _sales = _watch());
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: _sales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Live sales unavailable. Check the connection and reconnect.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!.where(
          (row) => (row['payload'] as Map)['status'] != 'removed',
        );
        final selected = _selected;
        if (selected != null) {
          final row = rows
              .where((row) => row['voucher_id'] == selected)
              .firstOrNull;
          if (row == null) {
            return const Center(
              child: Text('Voucher is no longer in the live list.'),
            );
          }
          final sale = Map<String, dynamic>.from(row['payload'] as Map);
          return ListView(
            children: [
              ListTile(
                title: Text('${sale['number']} · ${sale['status']}'),
                subtitle: Text('${sale['branch']} · ${sale['date']}'),
              ),
              for (final item in sale['items'] as List)
                ListTile(
                  title: Text('${item['item_name']}'),
                  subtitle: Text('${item['item_code']} · Qty ${item['qty']}'),
                  trailing: desktopMoney(
                    item['amount'],
                    currency: sale['currency_code'] as String? ?? 'MMK',
                    digits: sale['currency_digits'] as int? ?? 0,
                  ),
                ),
              ListTile(
                title: const Text('Total'),
                trailing: _money(sale, 'total'),
              ),
              if (sale['paid'] != null)
                ListTile(
                  title: const Text('Paid'),
                  trailing: _money(sale, 'paid'),
                ),
              if (sale['balance_due'] != null)
                ListTile(
                  title: const Text('Balance at posting'),
                  trailing: _money(sale, 'balance_due'),
                ),
            ],
          );
        }
        if (rows.isEmpty) {
          return const Center(child: Text('No live vouchers yet.'));
        }
        return ListView(
          children: [
            for (final row in rows)
              _tile(
                row['voucher_id'] as String,
                Map<String, dynamic>.from(row['payload'] as Map),
              ),
          ],
        );
      },
    ),
  );

  Widget _tile(String id, Map<String, dynamic> sale) => ListTile(
    title: Text('${sale['number']} · ${sale['status']}'),
    subtitle: Text('${sale['branch']} · ${sale['date']}'),
    trailing: _money(sale, 'total'),
    onTap: () => setState(() => _selected = id),
  );
}

class _LiveMessage extends StatelessWidget {
  const _LiveMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: const Text('Live sales')),
    body: Center(child: Text(message)),
  );
}
