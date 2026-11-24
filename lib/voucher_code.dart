import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A lookup key for a stored voucher, not a payment instruction or public URL.
class VoucherCode {
  const VoucherCode(this.kind, this.id, this.fingerprint);
  final String kind, fingerprint;
  final int id;
  static const kinds = ['INV', 'RET', 'PUR', 'EXP'];
  static String kindOf(Map<String, Object?> snapshot) =>
      snapshot['document_prefix'] as String? ?? 'INV';
  static String displayNumber(Map<String, Object?> snapshot) {
    final kind = kindOf(snapshot);
    final id = snapshot['id'];
    final original =
        snapshot['document_number'] as String? ??
        '$kind-${id.toString().padLeft(6, '0')}';
    if (kind != 'INV' || snapshot['shared_voucher'] == true) return original;
    final snapshotCode =
        snapshot['branch_code_snapshot']?.toString().trim() ?? '';
    final branch = snapshot['branch_id'];
    final prefix = snapshotCode.isNotEmpty
        ? snapshotCode
        : branch is int && branch > 0
        ? 'BR${branch.toString().padLeft(2, '0')}'
        : 'BR00';
    final suffix = RegExp(r'[0-9]+$').stringMatch(original) ?? id.toString();
    return '$prefix-${suffix.padLeft(6, '0')}';
  }

  static String digest(Map<String, Object?> snapshot) {
    final stable = {
      'kind': kindOf(snapshot),
      'id': snapshot['id'],
      'branch': snapshot['branch_id'],
      'created': snapshot['created_at'] ?? snapshot['confirmed_at'],
      'date': snapshot['invoice_date'],
      'sale': snapshot['sale_id'],
      'currency': snapshot['currency_code'] ?? 'MMK',
      'digits': snapshot['currency_digits'] ?? 0,
      'customer': snapshot['customer_name'],
      'total': snapshot['total'],
      'items': [
        for (final raw in snapshot['items'] as List)
          {
            for (final key in [
              'item_code',
              'item_name',
              'qty',
              'amount',
              'tracking_json',
            ])
              key: (raw as Map)[key],
          },
      ],
    };
    return sha256.convert(utf8.encode(jsonEncode(stable))).toString();
  }

  static String encode(Map<String, Object?> snapshot) {
    final kind = kindOf(snapshot), id = snapshot['id'];
    if (!kinds.contains(kind) || id is! int || id <= 0) {
      throw const FormatException('Invalid voucher identity');
    }
    return 'TPV1:$kind:$id:${digest(snapshot)}';
  }

  static VoucherCode parse(String value) {
    final match = RegExp(
      r'^TPV1:(INV|RET|PUR|EXP):([1-9][0-9]{0,18}):([a-f0-9]{64})$',
    ).firstMatch(value.trim());
    if (match == null) {
      throw const FormatException('Scan a Toe Pwar voucher QR code.');
    }
    return VoucherCode(match[1]!, int.parse(match[2]!), match[3]!);
  }

  bool matches(Map<String, Object?> snapshot) =>
      kindOf(snapshot) == kind &&
      snapshot['id'] == id &&
      digest(snapshot) == fingerprint;
}
