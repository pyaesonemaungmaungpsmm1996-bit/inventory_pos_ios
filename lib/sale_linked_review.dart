import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'product_tracking.dart';

class SaleLinkedReview {
  const SaleLinkedReview({
    required this.resolutions,
    required this.receipts,
    required this.returns,
    required this.exchanges,
    required this.allocated,
  });

  static const empty = SaleLinkedReview(
    resolutions: {},
    receipts: {},
    returns: {},
    exchanges: {},
    allocated: 0,
  );

  final Map<String, Set<int>> resolutions;
  final Map<int, ({int amount, Map<int, int> payments})> receipts;
  final Map<
    int,
    ({Map<int, int> quantities, Map<int, int> refunds, Map<int, String> lots})
  >
  returns;
  final Map<int, int> exchanges;
  final int allocated;
}

Future<SaleLinkedReview?> showSaleLinkedReview(
  BuildContext context, {
  required Map<String, Object?> draft,
  required int branchId,
  required List<Map<String, Object?>> lines,
  required List<Map<String, Object?>> products,
}) async {
  final saleId = draft['correction_source_sale_id'] as int?;
  if (saleId == null) return SaleLinkedReview.empty;
  final db = AppDatabase.instance;
  final links = await db.saleEditLinks(saleId);
  if (!context.mounted) return null;
  if (links.values.every((rows) => rows.isEmpty)) return SaleLinkedReview.empty;
  final returns = {
    for (final row in links['returns']!)
      row['id'] as int: await db.getSaleReturn(row['id'] as int),
  };
  final receipts = {
    for (final row in links['receipts']!)
      row['id'] as int: await db.getCustomerReceipt(row['id'] as int),
  };
  final accounts = await db.getMoneyAccounts(branchId: branchId);
  final receiptAccounts = await db.getMoneyAccounts(
    branchId: draft['branch_id'] as int,
  );
  if (!context.mounted) return null;
  final actions = <(String, int), String>{};
  final values = <(String, int, int, int), String>{};
  final existingExchanges = {
    for (final row in links['exchanges']!)
      row['id'] as int: row['replacement_sale_id'] as int,
  };

  bool isMoney(String group) =>
      const {'allocation', 'receiptPayment', 'refund'}.contains(group);
  String action(String group, int id) => actions[(group, id)] ?? 'keep';
  Widget field(
    String group,
    int id,
    int key,
    String label,
    int value, {
    int lot = 0,
  }) {
    final k = (group, id, key, lot);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        key: ValueKey(k),
        initialValue:
            values[k] ?? (isMoney(group) ? AppCurrency.input(value) : '$value'),
        keyboardType: TextInputType.numberWithOptions(decimal: isMoney(group)),
        decoration: InputDecoration(labelText: label),
        onChanged: (text) => values[k] = text,
      ),
    );
  }

  int number(String group, int id, int key, int initial, {int lot = 0}) {
    final text = values[(group, id, key, lot)]?.trim();
    if (text == null) return initial;
    final result = isMoney(group)
        ? AppCurrency.tryParse(text)
        : int.tryParse(text);
    if (result == null || result < 0 || result > 9000000000000) {
      throw const FormatException(
        'Enter a valid amount or a whole quantity of zero or more.',
      );
    }
    return result;
  }

  final returnQuantities = {
    for (final entry in returns.entries)
      entry.key: {
        for (final item in entry.value['items'] as List)
          item['product_id'] as int: item['qty'] as int,
      },
  };
  final returnRefunds = {
    for (final entry in returns.entries)
      entry.key: {
        for (final item in entry.value['refunds'] as List)
          item['account_id'] as int: item['amount'] as int,
      },
  };
  final receiptPayments = {
    for (final entry in receipts.entries)
      entry.key: {
        for (final item in entry.value['payments'] as List)
          item['account_id'] as int: item['amount'] as int,
      },
  };
  final existingLots = {
    for (final entry in returns.entries)
      entry.key: {
        for (final lot in entry.value['edit_lots'] as List)
          (lot['product_id'] as int, lot['lot_id'] as int):
              lot['quantity'] as int,
      },
  };
  final productsById = {for (final p in products) p['id']: p};
  Map<int, int> soldLots(Map line) => {
    for (final lot in ProductTracking.decode(line['tracking_json']))
      lot['lot_id'] as int: lot['qty'] as int,
  };
  List<Widget> paymentFields(
    String group,
    int id,
    List<Map<String, Object?>> rows,
    Map<int, int> existing,
  ) => [
    for (final account in rows)
      field(
        group,
        id,
        account['id'] as int,
        account['name'] as String,
        existing[account['id']] ?? 0,
      ),
  ];

  String? reviewError;
  return await showDialog<SaleLinkedReview>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, refresh) {
        Widget select(String group, int id, String label) {
          return DropdownButtonFormField<String>(
            initialValue: action(group, id),
            decoration: InputDecoration(labelText: label),
            items: [
              const DropdownMenuItem(value: 'keep', child: Text('Keep')),
              const DropdownMenuItem(value: 'edit', child: Text('Edit')),
              DropdownMenuItem(
                value: 'reverse',
                child: Text(group == 'exchange' ? 'Unlink' : 'Reverse'),
              ),
            ],
            onChanged: (value) => refresh(() {
              actions[(group, id)] = value!;
              reviewError = null;
            }),
          );
        }

        void confirm() {
          try {
            final reversedReturns = <int>{};
            final reversedReceipts = <int>{};
            final changedExchanges = <int>{};
            final returnEdits =
                <
                  int,
                  ({
                    Map<int, int> quantities,
                    Map<int, int> refunds,
                    Map<int, String> lots,
                  })
                >{};
            final receiptEdits =
                <int, ({int amount, Map<int, int> payments})>{};
            final exchangeEdits = <int, int>{};
            var allocationReduction = 0;
            for (final row in links['returns']!) {
              final id = row['id'] as int;
              final mode = action('return', id);
              if (mode == 'keep') continue;
              reversedReturns.add(id);
              if (mode == 'reverse') continue;
              final quantities = <int, int>{};
              final tracked = <int, String>{};
              for (final line in lines) {
                final product = line['product_id'] as int;
                final qty = number(
                  'quantity',
                  id,
                  product,
                  returnQuantities[id]![product] ?? 0,
                );
                if (qty == 0) continue;
                quantities[product] = qty;
                final lots = soldLots(line);
                if (lots.isNotEmpty) {
                  final choices = <Map<String, int>>[];
                  for (final lot in lots.keys) {
                    final n = number(
                      'lot',
                      id,
                      product,
                      existingLots[id]![(product, lot)] ?? 0,
                      lot: lot,
                    );
                    if (n > 0) choices.add({'lot_id': lot, 'qty': n});
                  }
                  if (choices.fold<int>(0, (sum, c) => sum + c['qty']!) !=
                      qty) {
                    throw const FormatException(
                      'Returned lot quantities must add up to the returned item quantity.',
                    );
                  }
                  tracked[product] = jsonEncode(choices);
                }
              }
              if (quantities.isEmpty) {
                throw const FormatException(
                  'Enter a return quantity or select Reverse.',
                );
              }
              returnEdits[id] = (
                quantities: quantities,
                refunds: {
                  for (final account in accounts)
                    account['id'] as int: number(
                      'refund',
                      id,
                      account['id'] as int,
                      returnRefunds[id]![account['id']] ?? 0,
                    ),
                },
                lots: tracked,
              );
              if (existingExchanges.containsKey(id) &&
                  action('exchange', id) == 'keep') {
                exchangeEdits[id] = existingExchanges[id]!;
              }
            }
            for (final row in links['receipts']!) {
              final id = row['id'] as int;
              final amount = row['amount'] as int;
              switch (action('receipt', id)) {
                case 'reverse':
                  reversedReceipts.add(id);
                  allocationReduction += amount;
                case 'edit':
                  final revised = number('allocation', id, 0, amount);
                  final payments = {
                    for (final account in receiptAccounts)
                      account['id'] as int: number(
                        'receiptPayment',
                        id,
                        account['id'] as int,
                        receiptPayments[id]![account['id']] ?? 0,
                      ),
                  };
                  if (payments.values.fold<int>(0, (sum, n) => sum + n) !=
                      (row['total'] as int) - amount + revised) {
                    throw const FormatException(
                      'Receipt payments must cover the revised allocation and allocations on the other invoices.',
                    );
                  }
                  allocationReduction += amount - revised;
                  receiptEdits[id] = (amount: revised, payments: payments);
              }
            }
            for (final entry in existingExchanges.entries) {
              final id = entry.key;
              final mode = action('exchange', id);
              if (mode == 'keep') continue;
              changedExchanges.add(id);
              if (mode == 'edit') {
                final replacement = number('exchange', id, 0, entry.value);
                if (replacement == 0 || action('return', id) == 'reverse') {
                  throw const FormatException(
                    'Enter a replacement invoice ID for a posted return.',
                  );
                }
                exchangeEdits[id] = replacement;
              }
            }
            final reviewedAllocations = links['receipts']!.fold<int>(
              0,
              (sum, r) => sum + (r['amount'] as int),
            );
            Navigator.pop(
              dialog,
              SaleLinkedReview(
                resolutions: {
                  'returns': reversedReturns,
                  'receipts': reversedReceipts,
                  'exchanges': changedExchanges,
                },
                receipts: receiptEdits,
                returns: returnEdits,
                exchanges: exchangeEdits,
                allocated: reviewedAllocations - allocationReduction,
              ),
            );
          } on FormatException catch (e) {
            refresh(() => reviewError = e.message);
          }
        }

        return AlertDialog(
          title: const Text('Review linked records'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Invoice number stays the same. Enter the quantity and payment amounts. Confirm only after checking the actual return and payment amounts.',
                  ),
                  for (final row in links['returns']!)
                    Builder(
                      builder: (_) {
                        final id = row['id'] as int;
                        return Column(
                          children: [
                            select(
                              'return',
                              id,
                              "Return #$id · ${row['return_date']}",
                            ),
                            if (action('return', id) == 'edit') ...[
                              for (final line in lines) ...[
                                field(
                                  'quantity',
                                  id,
                                  line['product_id'] as int,
                                  "Return quantity · ${productsById[line['product_id']]?['name'] ?? line['product_id']}",
                                  returnQuantities[id]![line['product_id']] ??
                                      0,
                                ),
                                for (final lot in soldLots(line).entries)
                                  field(
                                    'lot',
                                    id,
                                    line['product_id'] as int,
                                    "Returned quantity · lot #${lot.key} (sold ${lot.value})",
                                    existingLots[id]![(
                                          line['product_id'],
                                          lot.key,
                                        )] ??
                                        0,
                                    lot: lot.key,
                                  ),
                              ],
                              const Text('Refund by account'),
                              ...paymentFields(
                                'refund',
                                id,
                                accounts,
                                returnRefunds[id]!,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  for (final row in links['receipts']!)
                    Builder(
                      builder: (_) {
                        final id = row['id'] as int;
                        final amount = row['amount'] as int;
                        return Column(
                          children: [
                            select(
                              'receipt',
                              id,
                              "Receipt #$id · Allocated ${AppCurrency.input(amount)}",
                            ),
                            if (action('receipt', id) == 'reverse')
                              const Text(
                                'Reverses every allocation on this receipt, including other invoices.',
                              ),
                            if (action('receipt', id) == 'edit') ...[
                              Text(
                                "Other invoices keep ${AppCurrency.input((row['total'] as int) - amount)} in allocations.",
                              ),
                              field(
                                'allocation',
                                id,
                                0,
                                'Allocation to this invoice',
                                amount,
                              ),
                              const Text('Revised receipt payments by account'),
                              ...paymentFields(
                                'receiptPayment',
                                id,
                                receiptAccounts,
                                receiptPayments[id]!,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  for (final entry in existingExchanges.entries) ...[
                    select(
                      'exchange',
                      entry.key,
                      'Exchange for return #${entry.key}',
                    ),
                    if (action('exchange', entry.key) == 'edit')
                      field(
                        'exchange',
                        entry.key,
                        0,
                        'Replacement invoice numeric ID',
                        entry.value,
                      ),
                  ],
                  if (reviewError != null)
                    Text(
                      reviewError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: confirm,
              child: const Text('Confirm and save'),
            ),
          ],
        );
      },
    ),
  );
}
