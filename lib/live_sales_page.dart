import 'package:flutter/material.dart';

import 'desktop_ui.dart';
import 'live_sale_sync.dart';
import 'online_account_service.dart';

class LiveVoucherPage extends StatefulWidget {
  const LiveVoucherPage({
    super.key,
    required this.account,
    required this.voucher,
  });

  final String account;
  final String voucher;

  @override
  State<LiveVoucherPage> createState() => _LiveVoucherPageState();
}

class _LiveVoucherPageState extends State<LiveVoucherPage> {
  late final _auth = OnlineAccounts.client.auth.onAuthStateChange;
  late var _updates = _watch();

  Stream<List<Map<String, dynamic>>> _watch() =>
      LiveSaleSync.watch(widget.account, voucher: widget.voucher);

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: const Text('Sale Invoice'),
      actions: [
        IconButton(
          tooltip: 'Reconnect',
          onPressed: () => setState(() => _updates = _watch()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: StreamBuilder(
      stream: _auth,
      builder: (context, _) {
        if (LiveSaleSync.accountId != widget.account) {
          return const Center(child: Text('Sign in to view this invoice.'));
        }
        return StreamBuilder(
          stream: _updates,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Invoice updates unavailable. Tap Reconnect to retry.',
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sale = snapshot.data!.firstOrNull?['payload'];
            if (sale is! Map || sale['status'] == 'removed') {
              return const Center(
                child: Text('This invoice is no longer available.'),
              );
            }
            Widget money(Object? amount) => desktopMoney(
              amount,
              currency: sale['currency_code']?.toString() ?? 'MMK',
              digits: sale['currency_digits'] is int
                  ? sale['currency_digits'] as int
                  : 0,
            );
            final items = sale['items'];
            return ListView(
              children: [
                ListTile(
                  title: Text('${sale['number']} · ${sale['status']}'),
                  subtitle: Text('${sale['branch']} · ${sale['date']}'),
                ),
                if (items is List)
                  for (final item in items.whereType<Map>())
                    ListTile(
                      title: Text('${item['item_name']}'),
                      subtitle: Text(
                        '${item['item_code']} · Qty ${item['qty']}',
                      ),
                      trailing: money(item['amount']),
                    ),
                ListTile(
                  title: const Text('Total'),
                  trailing: money(sale['total']),
                ),
                if (sale['paid'] != null)
                  ListTile(
                    title: const Text('Paid'),
                    trailing: money(sale['paid']),
                  ),
                if (sale['balance_due'] != null)
                  ListTile(
                    title: const Text('Balance at posting'),
                    trailing: money(sale['balance_due']),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
