import 'package:flutter/material.dart';

import 'app_database.dart';
import 'desktop_ui.dart';
import 'live_sale_sync.dart';
import 'online_account_service.dart';

class LiveVoucherPage extends StatefulWidget {
  const LiveVoucherPage({
    super.key,
    required this.account,
    required this.voucher,
    this.purchase = false,
  });

  final String account;
  final String voucher;
  final bool purchase;

  @override
  State<LiveVoucherPage> createState() => _LiveVoucherPageState();
}

class _LiveVoucherPageState extends State<LiveVoucherPage> {
  late final _auth = OnlineAccounts.client.auth.onAuthStateChange;
  late var _updates = _watch();
  bool _applying = false;

  Future<void> _apply(int revision, Map<String, Object?> payload) async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Apply purchase to this device?'),
          content: const Text(
            'This adds the received quantities to local stock and records the '
            'original payments in the matching local accounts. Only apply it '
            'if this purchase has not already been entered on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Apply purchase'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
      await AppDatabase.instance.applyLivePurchase(
        account: widget.account,
        voucher: widget.voucher,
        revision: revision,
        payload: payload,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase recorded on this device.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message.toString() : e.toString(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Stream<List<Map<String, dynamic>>> _watch() => LiveSaleSync.watch(
    widget.account,
    voucher: widget.voucher,
    purchase: widget.purchase,
  );

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(
      title: Text(widget.purchase ? 'Purchase Invoice' : 'Sale Invoice'),
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
            final row = snapshot.data!.firstOrNull;
            final sale = row?['payload'];
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
                if (widget.purchase && sale['status'] == 'posted')
                  if (sale['posting_payload_version'] == 1 &&
                      row?['revision'] is int)
                    ListTile(
                      title: FilledButton.icon(
                        onPressed: _applying
                            ? null
                            : () => _apply(
                                row!['revision'] as int,
                                Map<String, Object?>.from(sale),
                              ),
                        icon: const Icon(Icons.download_done),
                        label: const Text('Apply stock and payment'),
                      ),
                    )
                  else
                    const ListTile(
                      title: Text(
                        'Sync this purchase again on its original device to receive stock and payment details.',
                      ),
                    ),
                if (widget.purchase && sale['supplier_name'] != null)
                  ListTile(title: Text(sale['supplier_name'].toString())),
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
