import 'dart:typed_data';

import 'product_tracking.dart';
import 'app_currency.dart';
import 'app_datetime.dart';
import 'invoice_print_settings.dart';

class InvoicePrintRow {
  const InvoicePrintRow(
    this.cells, {
    this.bold = false,
    this.right = false,
    this.center = false,
    this.rule = false,
    this.large = false,
    this.columns = false,
    this.picture,
  });
  final List<String> cells;
  final Uint8List? picture;
  final bool bold, right, center, rule, large, columns;
}

/// Customer-facing projection: only explicit fields are copied. No stock fields
/// or live product prices are read. Reprints use the stored invoice snapshots.
List<InvoicePrintRow> invoicePrintRows(
  Map<String, Object?> sale,
  InvoicePrintSettings settings, {
  required bool myanmar,
}) {
  String t(String en, String my) => myanmar ? my : en;
  String text(Object? value) => value?.toString().trim() ?? '';
  final currency = sale['currency_code'] as String? ?? 'MMK';
  final digits = sale['currency_digits'] as int? ?? 0;
  String money(Object? value) => AppCurrency.format(
    value as int,
    currency: currency,
    decimalPlaces: digits,
  );
  String no(Object? id) => (id as int).toString().padLeft(6, '0');
  final result = <InvoicePrintRow>[];
  void line(
    String value, {
    bool bold = false,
    bool right = false,
    bool center = false,
    bool large = false,
  }) {
    if (value.trim().isNotEmpty) {
      result.add(
        InvoicePrintRow(
          [value],
          bold: bold,
          right: right,
          center: center,
          large: large,
        ),
      );
    }
  }

  void rule() => result.add(const InvoicePrintRow([], rule: true));
  if (settings.showLogo && sale['business_logo'] is Uint8List) {
    result.add(
      InvoicePrintRow(const [], picture: sale['business_logo'] as Uint8List),
    );
  }
  line(text(sale['business_name']), bold: true, center: true, large: true);
  line(
    sale['document_title'] as String? ?? t('SALE INVOICE', 'အရောင်းဘောင်ချာ'),
    bold: true,
    center: true,
  );
  if (sale['status'] == 'void') {
    line('VOID · ${text(sale['void_reason'])}', bold: true, center: true);
  }
  line(
    sale['document_number'] as String? ??
        '${sale['document_prefix'] ?? 'INV'}-${no(sale['id'])}',
    bold: true,
    center: true,
  );
  final invoiceDate = text(sale['invoice_date']);
  final confirmed = AppDateTime.parse(sale['confirmed_at']) == null
      ? ''
      : AppDateTime.format(sale['confirmed_at']);
  if (settings.showDate) {
    if (confirmed.isEmpty) {
      line('${t('Invoice date', 'ဘောင်ချာရက်')}: $invoiceDate');
    } else if (confirmed.startsWith('$invoiceDate ')) {
      // The business date and actual local confirmation date agree: use one line.
      line('${t('Invoice date/time', 'ဘောင်ချာရက်နှင့်အချိန်')}: $confirmed');
    } else {
      // A backdated invoice has two different dates; keep both on the same row.
      line(
        '${t('Invoice date', 'ဘောင်ချာရက်')}: $invoiceDate · '
        '${t('Confirmed', 'အတည်ပြုချိန်')}: $confirmed',
      );
    }
  }
  if (settings.showBranch) {
    line(
      '${t('Branch', 'ဆိုင်ခွဲ')}: ${text(sale['branch_name_snapshot'])} (${text(sale['branch_code_snapshot'])})',
    );
    line(text(sale['branch_phone_snapshot']));
    line(text(sale['branch_address_snapshot']));
  }
  rule();
  if (settings.showCustomer && sale['document_prefix'] != 'EXP') {
    final customerName = text(sale['customer_name']);
    line(
      '${(sale['document_prefix'] == 'PUR' ? t('Supplier', 'ပစ္စည်းပေးသွင်းသူ') : t('Customer', 'ဝယ်သူ'))}: ${customerName.isEmpty ? t('Walk-in', 'အမည်မမှတ်ထားသောဝယ်သူ') : customerName}',
    );
    final phone = text(sale['customer_phone']);
    if (phone.isNotEmpty) {
      line('${t('Phone', 'ဖုန်း')}: $phone');
    }
    final company = text(sale['customer_company']);
    if (company.isNotEmpty) {
      line('${t('Company', 'ကုမ္ပဏီ')}: $company');
    }
    final address = text(sale['customer_address']);
    if (address.isNotEmpty) {
      line('${t('Address', 'လိပ်စာ')}: $address');
    }
  }
  if (settings.showSalePerson) {
    line(
      '${t('Sale person', 'အရောင်းဝန်ထမ်း')}: ${text(sale['employee_name'])}',
    );
  }
  rule();
  if (!settings.narrow) {
    result.add(
      InvoicePrintRow(
        [
          settings.showItemCode
              ? t('Item code / Item name', 'ပစ္စည်းကုဒ် / အမည်')
              : t('Item name', 'ပစ္စည်းအမည်'),
          t('Qty', 'ဦးရေ'),
          settings.showPrices ? t('Price', 'တစ်ခုဈေး') : '',
          t('Amount', 'ကျသင့်ငွေ'),
        ],
        bold: true,
        columns: true,
      ),
    );
    rule();
  }
  for (final raw in sale['items'] as List) {
    final item = Map<String, Object?>.from(raw as Map);
    final photos = sale['item_images'];
    if (settings.showItemPhotos &&
        photos is Map &&
        photos[item['product_id']] is Uint8List) {
      result.add(
        InvoicePrintRow(
          const [],
          picture: photos[item['product_id']] as Uint8List,
        ),
      );
    }
    if (settings.narrow) {
      line(
        '${settings.showItemCode ? '${text(item['item_code'])} · ' : ''}${text(item['item_name'])}',
        bold: true,
      );
      result.add(
        InvoicePrintRow([
          '${item['qty']}${settings.showPrices ? ' × ${money(item['price'])}' : ''}',
          money((item['amount'] as int) - (item['item_discount'] as int? ?? 0)),
        ], columns: true),
      );
    } else {
      result.add(
        InvoicePrintRow([
          '${settings.showItemCode ? '${text(item['item_code'])}\n' : ''}${text(item['item_name'])}',
          '${item['qty']}',
          settings.showPrices ? money(item['price']) : '',
          money((item['amount'] as int) - (item['item_discount'] as int? ?? 0)),
        ], columns: true),
      );
    }
    if (settings.showDiscount && (item['item_discount'] as int? ?? 0) > 0) {
      line(
        '${t('Item discount', 'ပစ္စည်းလျှော့ဈေး')}: ${money(item['item_discount'])}',
      );
    }
    for (final lot in ProductTracking.decode(item['tracking_json'])) {
      if (lot['serial'] != null) line('Serial: ${lot['serial']}');
      if (lot['imei'] != null) line('IMEI: ${lot['imei']}');
      if (lot['expires_on'] != null) {
        line('${t('Expiry', 'သက်တမ်းကုန်')}: ${lot['expires_on']}');
      }
      if (lot['warranty_until'] != null) {
        line(
          '${t('Warranty until', 'အာမခံနောက်ဆုံးရက်')}: ${lot['warranty_until']}',
        );
      }
    }
  }
  rule();
  line(
    '${t('Subtotal', 'စုစုပေါင်း')}: ${money(sale['subtotal'])}',
    right: true,
  );
  if (settings.showDiscount) {
    final itemDiscount = (sale['items'] as List).fold<int>(
      0,
      (sum, raw) => sum + ((raw as Map)['item_discount'] as int? ?? 0),
    );
    if (itemDiscount > 0) {
      line(
        '${t('Item discounts', 'ပစ္စည်းလျှော့ဈေးစုစုပေါင်း')}: ${money(itemDiscount)}',
        right: true,
      );
      line(
        '${t('Voucher discount', 'ဘောင်ချာလျှော့ဈေး')}: ${money((sale['discount_amount'] as int) - itemDiscount)}',
        right: true,
      );
    } else {
      line(
        '${t('Discount', 'လျှော့ဈေး')}: ${money(sale['discount_amount'])}',
        right: true,
      );
    }
  }
  line(
    '${t('Total', 'ကျသင့်ငွေ')}: ${money(sale['total'])}',
    bold: true,
    right: true,
    large: true,
  );
  // Payment account allocations and recorded timestamps remain internal records.
  line('${t('Paid', 'ပေးပြီးငွေ')}: ${money(sale['paid'])}', right: true);
  line(
    '${t('Credit due', 'အကြွေးကျန်')}: ${money(sale['balance_due'])}',
    bold: true,
    right: true,
  );
  if (text(sale['remark']).isNotEmpty) {
    line('${t('Remark', 'မှတ်ချက်')}: ${text(sale['remark'])}');
  }
  rule();
  line(settings.footer, center: true);
  return result;
}
