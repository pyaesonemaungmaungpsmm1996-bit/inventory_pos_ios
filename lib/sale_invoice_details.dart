import 'package:sqflite/sqflite.dart';

/// Existing gross amounts and combined discount totals retain their meaning.
/// Separate row discounts and voucher discounts are recorded for exact returns.
class SaleInvoiceDetails {
  static Future<void> install(DatabaseExecutor db) async {
    for (final table in ['sale_drafts', 'sale_invoices']) {
      await db.execute(
        "ALTER TABLE $table ADD COLUMN remark TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE $table ADD COLUMN voucher_discount_amount INTEGER NOT NULL DEFAULT 0 CHECK(voucher_discount_amount>=0)',
      );
      await db.execute(
        'UPDATE $table SET voucher_discount_amount=discount_amount',
      );
    }
    await db.execute(
      "ALTER TABLE sale_drafts ADD COLUMN desktop_payment_json TEXT NOT NULL DEFAULT '{}'",
    );
    for (final table in ['sale_draft_items', 'sale_items']) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN item_discount INTEGER NOT NULL DEFAULT 0 CHECK(item_discount>=0 AND item_discount<=amount)',
      );
      await db.execute(
        "ALTER TABLE $table ADD COLUMN color_snapshot TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE $table ADD COLUMN size_snapshot TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  /// Legacy invoices retain their original floor/last-line rounding policy.
  /// New item-discount invoices allocate only their residual voucher discount.
  static List<int> lineNets(List<Map<String, Object?>> items, int total) {
    final itemDiscounts = items.fold<int>(
      0,
      (sum, item) => sum + (item['item_discount'] as int? ?? 0),
    );
    final basis = items.fold<int>(
      0,
      (sum, item) =>
          sum + (item['amount'] as int) - (item['item_discount'] as int? ?? 0),
    );
    var allocated = 0, prefix = 0;
    return [
      for (var i = 0; i < items.length; i++)
        (() {
          final weight =
              (items[i]['amount'] as int) -
              (items[i]['item_discount'] as int? ?? 0);
          int net;
          if (itemDiscounts == 0) {
            net = i == items.length - 1
                ? total - allocated
                : basis == 0
                ? 0
                : (BigInt.from(weight) *
                          BigInt.from(total) ~/
                          BigInt.from(basis))
                      .toInt();
          } else {
            final end = prefix + weight;
            net = basis == 0
                ? 0
                : ((BigInt.from(end) *
                              BigInt.from(total) ~/
                              BigInt.from(basis)) -
                          (BigInt.from(prefix) *
                              BigInt.from(total) ~/
                              BigInt.from(basis)))
                      .toInt();
            prefix = end;
          }
          allocated += net;
          return net;
        })(),
    ];
  }
}
