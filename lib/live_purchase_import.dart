part of 'app_database.dart';

extension LivePurchaseImport on AppDatabase {
  Future<int> applyLivePurchase({
    required String account,
    required String voucher,
    required int revision,
    required Map<String, Object?> payload,
  }) async {
    final origin = LiveSaleSync.origin;
    if (origin == null ||
        origin.account != account ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(voucher) ||
        revision < 1) {
      throw StateError('Sign in to the account that owns the synced purchase.');
    }
    if (payload['posting_payload_version'] != 1 ||
        payload['status'] != 'posted') {
      throw StateError(
        'Sync the posted purchase again from its original device.',
      );
    }
    final date = payload['date'];
    final recorded = DateTime.tryParse(
      payload['recorded_at']?.toString() ?? '',
    );
    final rawItems = payload['items'];
    final rawPayments = payload['payments'];
    final total = payload['total'];
    final paid = payload['paid'];
    final due = payload['balance_due'];
    if (date is! String ||
        !_businessDate(date) ||
        recorded == null ||
        rawItems is! List ||
        rawItems.isEmpty ||
        rawItems.length > 300 ||
        rawPayments is! List ||
        rawPayments.length > 100 ||
        total is! int ||
        total < 0 ||
        total > 9000000000000 ||
        paid is! int ||
        paid < 0 ||
        due is! int ||
        due < 0 ||
        paid + due != total) {
      throw StateError('The purchase amounts or dates could not be verified.');
    }
    final key = '${LivePurchaseSync.requestPrefix}$account:$voucher';
    final db = await database;
    final outcome = await db.transaction((txn) async {
      if (LiveSaleSync.accountId != account) {
        throw StateError(
          'The signed-in account changed. Reopen this purchase.',
        );
      }
      final existing = await txn.query(
        'purchase_invoices',
        columns: ['id'],
        where: 'request_key = ?',
        whereArgs: [key],
      );
      if (existing.isNotEmpty)
        return (id: existing.single['id'] as int, applied: false);

      final branchCode = payload['branch_code']?.toString().trim();
      if (branchCode == null || branchCode.isEmpty) {
        throw StateError('The source purchase has no branch code.');
      }
      final branch = await _uniquePurchaseMatch(
        txn,
        'branches',
        'code = ? COLLATE NOCASE',
        [branchCode],
        'branch $branchCode',
      );
      final branchId = branch['id'] as int;
      final profile = (await txn.query(
        'business_profile',
        where: 'id = 1',
      )).single;
      if (profile['currency_code'] != payload['currency_code'] ||
          profile['currency_digits'] != payload['currency_digits']) {
        throw StateError(
          'The source purchase currency differs from this device.',
        );
      }

      final supplierName = payload['supplier_name']?.toString().trim();
      if (supplierName == null || supplierName.isEmpty) {
        throw StateError('The source purchase has no supplier name.');
      }
      final supplier = await _uniquePurchaseMatch(
        txn,
        'contacts',
        "kind = 'supplier' AND active = 1 AND name = ? COLLATE NOCASE",
        [supplierName],
        'supplier $supplierName',
      );
      final supplierId = supplier['id'] as int;
      final possibleDuplicate = await txn.query(
        'purchase_invoices',
        columns: ['id'],
        where: 'branch_id = ? AND supplier_id = ? AND invoice_date = ? AND total = ?',
        whereArgs: [branchId, supplierId, date, total],
        limit: 1,
      );
      if (possibleDuplicate.isNotEmpty) {
        throw StateError(
          'A purchase with the same supplier, date and total is already on this device. Check Purchase History.',
        );
      }

      final items = <Map<String, Object?>>[];
      var itemTotal = 0;
      for (final raw in rawItems) {
        if (raw is! Map)
          throw StateError('The purchase contains an invalid item.');
        final sku = raw['item_code']?.toString().trim();
        final qty = raw['qty'];
        final price = raw['purchase_price'];
        final lots = raw['lots'];
        if (sku == null ||
            sku.isEmpty ||
            qty is! int ||
            qty < 1 ||
            qty > 2147483647 ||
            price is! int ||
            price < 0 ||
            price > 2147483647 ||
            raw['amount'] != qty * price ||
            lots is! List) {
          throw StateError('Item quantities or costs could not be verified.');
        }
        final product = await _uniquePurchaseMatch(
          txn,
          'products',
          'item_code = ? COLLATE NOCASE',
          [sku],
          'item $sku',
        );
        if (product['tracking'] != raw['tracking'] ||
            product['category_id'] is! int) {
          throw StateError(
            'Item $sku has different tracking or is missing a category on this device.',
          );
        }
        itemTotal += qty * price;
        if (itemTotal > 9000000000000)
          throw StateError('Purchase total exceeds the limit.');
        items.add({
          'product_id': product['id'],
          'category_id': product['category_id'],
          'qty': qty,
          'purchase_price': price,
          'sale_price': product['price'],
          'tracking': raw['tracking'],
          'lots': lots,
        });
      }
      if (itemTotal != total)
        throw StateError('Item totals do not match the purchase.');

      final payments = <Map<String, int>>[];
      var paidTotal = 0;
      for (final raw in rawPayments) {
        if (raw is! Map)
          throw StateError('The purchase contains an invalid payment.');
        final name = raw['account_name']?.toString().trim();
        final type = raw['type'];
        final amount = raw['amount'];
        if (name == null ||
            name.isEmpty ||
            type is! String ||
            amount is! int ||
            amount <= 0 ||
            amount > 9000000000000) {
          throw StateError(
            'The payment accounts or amounts could not be verified.',
          );
        }
        final target = await _uniquePurchaseMatch(
          txn,
          'money_accounts',
          'branch_id = ? AND name = ? COLLATE NOCASE AND type = ?',
          [branchId, name, type],
          'payment account $name',
        );
        paidTotal += amount;
        if (paidTotal > 9000000000000)
          throw StateError('Payment total exceeds the limit.');
        payments.add({'account_id': target['id'] as int, 'amount': amount});
      }
      if (paidTotal != paid) {
        throw StateError(
          'The purchase has a later payment or its original payment details are incomplete.',
        );
      }
      if (LiveSaleSync.accountId != account) {
        throw StateError(
          'The signed-in account changed. Reopen this purchase.',
        );
      }
      final id = await _postPurchaseTx(
        txn,
        requestKey: key,
        branchId: branchId,
        supplierId: supplierId,
        invoiceDate: date,
        items: items,
        payments: payments,
        replica: (
          account: account,
          installation: origin.installation,
          voucher: voucher,
          revision: revision,
        ),
        recordedAt: recorded,
      );
      return (id: id, applied: true);
    });
    if (outcome.applied) LivePurchaseSync.applied.value++;
    return outcome.id;
  }

  Future<Map<String, Object?>> _uniquePurchaseMatch(
    DatabaseExecutor txn,
    String table,
    String where,
    List<Object?> args,
    String name,
  ) async {
    final matches = await txn.query(
      table,
      where: where,
      whereArgs: args,
      limit: 2,
    );
    if (matches.length != 1) {
      throw StateError(
        'Expected one local match for $name. Check the receiving device setup.',
      );
    }
    return matches.single;
  }
}
