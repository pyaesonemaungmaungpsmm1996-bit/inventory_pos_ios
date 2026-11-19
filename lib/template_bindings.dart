import 'app_currency.dart';
import 'app_datetime.dart';
import 'contact_search.dart';
import 'product_tracking.dart';
import 'voucher_code.dart';

/// Explicit printable fields only. Templates never execute SQL or expressions
/// and cannot expose stock, cost, internal payment-account details or secrets.
class TemplateBindings {
  static const invoiceFields = [
    'business.name',
    'business.subtitle',
    'branch.info',
    'branch.left',
    'branch.right',
    'invoice.title',
    'invoice.status',
    'invoice.void_reason',
    'invoice.number',
    'invoice.qr',
    'invoice.date',
    'invoice.recorded',
    'customer.id',
    'customer.name',
    'customer.phone',
    'customer.company',
    'customer.address',
    'employee.name',
    'invoice.remark',
    'totals.subtotal',
    'totals.item_discount',
    'totals.voucher_discount',
    'totals.discount',
    'totals.total',
    'totals.paid',
    'totals.balance',
    'footer',
    'page.number',
    'page.count',
  ];
  static const itemFields = [
    'item.no',
    'item.code',
    'item.name',
    'item.description',
    'item.unit',
    'item.color',
    'item.size',
    'item.serial',
    'item.imei',
    'item.qty',
    'item.unit_price',
    'item.discount',
    'item.amount',
    'item.barcode',
  ];
  static String resolve(String expression, Map<String, String> fields) =>
      expression.replaceAllMapped(
        RegExp(r'\{([A-Za-z0-9_.]+)\}'),
        (m) => fields[m[1]] ?? '',
      );
  static Map<String, String> invoice(
    Map<String, Object?> sale,
    Map<String, Object?> options,
  ) {
    String text(Object? v) => v?.toString() ?? '';
    bool show(String key) => options[key] != false;
    String money(Object? v) => AppCurrency.format(
      v is int ? v : 0,
      currency: sale['currency_code'] as String? ?? 'MMK',
      decimalPlaces: sale['currency_digits'] as int? ?? 0,
    );
    final itemDiscount = ((sale['items'] as List?) ?? []).fold<int>(
      0,
      (n, v) => n + ((v as Map)['item_discount'] as int? ?? 0),
    );
    return {
      'business.name': text(sale['business_name']),
      'business.subtitle': text((options['a4'] as Map?)?['subtitle']),
      'invoice.qr':
          sale['status'] != 'draft' &&
              sale['id'] is int &&
              (sale['id'] as int) > 0
          ? VoucherCode.encode({...sale, 'items': sale['items'] ?? []})
          : '',
      'branch.left': show('branch')
          ? ((sale['print_branch_blocks'] as List?)?.firstOrNull?.toString() ??
                [
                  sale['branch_name_snapshot'],
                  sale['branch_address_snapshot'],
                  sale['branch_phone_snapshot'],
                ].where((v) => v != null && text(v).isNotEmpty).join('\n'))
          : '',
      'branch.right':
          show('branch') &&
              ((sale['print_branch_blocks'] as List?)?.length ?? 0) > 1
          ? text((sale['print_branch_blocks'] as List)[1])
          : '',
      'branch.info': show('branch')
          ? ((sale['print_branch_blocks'] as List?)?.join('\n\n') ??
                [
                  sale['branch_name_snapshot'],
                  sale['branch_address_snapshot'],
                  sale['branch_phone_snapshot'],
                ].where((v) => v != null && text(v).isNotEmpty).join('\n'))
          : '',
      'invoice.status': text(sale['status']),
      'invoice.void_reason': text(sale['void_reason']),
      'invoice.title':
          (sale['status'] == 'void' ? 'VOID · ' : '') +
          text(
            sale['document_title'] ??
                (options['language'] == 'my'
                    ? 'အရောင်းဘောင်ချာ'
                    : 'SALE INVOICE'),
          ),
      'invoice.number':
          sale['document_number'] as String? ??
          '${text(sale['document_prefix'] ?? 'INV')}-${text(sale['id']).padLeft(6, '0')}',
      'invoice.date': show('date') ? text(sale['invoice_date']) : '',
      'invoice.recorded': show('date')
          ? AppDateTime.format(sale['confirmed_at'])
          : '',
      'customer.id': show('customer') && sale['customer_id'] != null
          ? ContactSearch.code(sale['customer_id'])
          : '',
      'customer.name': show('customer') ? text(sale['customer_name']) : '',
      'customer.phone': show('customer') ? text(sale['customer_phone']) : '',
      'customer.company': show('customer')
          ? text(sale['customer_company'])
          : '',
      'customer.address': show('customer')
          ? text(sale['customer_address'])
          : '',
      'employee.name': show('sale_person') ? text(sale['employee_name']) : '',
      'invoice.remark': text(sale['remark']),
      'totals.subtotal': money(sale['subtotal']),
      'totals.item_discount': show('discount') ? money(itemDiscount) : '',
      'totals.voucher_discount': show('discount')
          ? money(
              sale['voucher_discount_amount'] ??
                  ((sale['discount_amount'] as int? ?? 0) - itemDiscount),
            )
          : '',
      'totals.discount': show('discount') ? money(sale['discount_amount']) : '',
      'totals.total': money(sale['total']),
      'totals.paid': money(sale['paid']),
      'totals.balance': money(sale['balance_due']),
      'footer': text(options['footer']),
    };
  }

  static Map<String, String> item(
    Map row, {
    String currency = 'MMK',
    int digits = 0,
    bool prices = true,
    bool discounts = true,
    bool codes = true,
  }) {
    String text(Object? v) => v?.toString() ?? '';
    String money(Object? v) => AppCurrency.format(
      v is int ? v : 0,
      currency: currency,
      decimalPlaces: digits,
    );
    final lots = ProductTracking.decode(row['tracking_json'] ?? row['lots']);
    String ids(String key) => lots
        .map((v) => v[key])
        .where((v) => v != null && text(v).isNotEmpty)
        .map(text)
        .join(', ');
    final gross =
        row['amount'] as int? ??
        ((row['price'] as int? ?? 0) * (row['qty'] as int? ?? 1));
    return {
      'item.code': codes ? text(row['item_code']) : '',
      'item.name': text(row['item_name'] ?? row['name']),
      'item.unit': text(row['unit_snapshot'] ?? row['unit'] ?? 'Pcs'),
      'item.description': [
        text(row['item_name'] ?? row['name']),
        if (text(row['color_snapshot'] ?? row['color']).isNotEmpty)
          text(row['color_snapshot'] ?? row['color']),
        if (text(row['size_snapshot'] ?? row['size']).isNotEmpty)
          text(row['size_snapshot'] ?? row['size']),
        if (ids('serial').isNotEmpty) 'Serial: ${ids('serial')}',
        if (ids('imei').isNotEmpty) 'IMEI: ${ids('imei')}',
      ].join('\n'),
      'item.color': text(row['color_snapshot'] ?? row['color']),
      'item.size': text(row['size_snapshot'] ?? row['size']),
      'item.serial': ids('serial'),
      'item.imei': ids('imei'),
      'item.qty': text(row['qty'] ?? 1),
      'item.unit_price': prices ? money(row['price']) : '',
      'item.discount': discounts ? money(row['item_discount']) : '',
      'item.amount': money(gross - (row['item_discount'] as int? ?? 0)),
      'item.barcode': text(row['barcode'] ?? row['item_code']),
    };
  }
}
