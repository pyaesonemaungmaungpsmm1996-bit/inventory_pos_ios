/// Projects the saved return onto the shared A4 layout without changing totals.
Map<String, Object?> saleReturnPrintSnapshot(Map<String, Object?> returned) => {
  ...returned,
  'document_prefix': 'RET',
  'document_title': 'Sale Return Invoice',
  'invoice_date': returned['return_date'],
  'confirmed_at': returned['created_at'],
  'subtotal': returned['total'],
  'discount_amount': 0,
  'paid': returned['total'],
  'balance_due': 0,
  'items': [
    for (final raw in returned['items'] as List)
      {
        ...Map<String, Object?>.from(raw as Map),
        'amount': raw['refund_amount'],
        // A partial refund can be indivisible by quantity; no invented unit price.
        'price': (raw['refund_amount'] as int) % (raw['qty'] as int) == 0
            ? (raw['refund_amount'] as int) ~/ (raw['qty'] as int)
            : null,
      },
  ],
};
