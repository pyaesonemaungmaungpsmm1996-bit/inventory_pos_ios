import 'package:flutter/foundation.dart';

/// Amounts in the database are integers in the configured smallest unit.
/// Existing MMK data uses whole kyat, so that operational precision stays 0.
class AppCurrency {
  static const precision = <String, int>{
    'MMK': 0,
    'USD': 2,
    'THB': 2,
    'CNY': 2,
    'JPY': 0,
  };
  static const names = <String, String>{
    'MMK': 'Myanmar Kyat',
    'USD': 'US Dollar',
    'THB': 'Thai Baht',
    'CNY': 'Chinese Yuan',
    'JPY': 'Japanese Yen',
  };
  static final current = ValueNotifier<String>('MMK');
  static String get code => current.value;
  static String get displayCode => code == 'MMK' ? 'Ks' : code;
  static String display(String currency) => currency == 'MMK' ? 'Ks' : currency;
  static int get digits => precision[code]!;
  static void apply(Map<String, Object?> profile) {
    final value = profile['currency_code'] as String;
    if (!precision.containsKey(value) ||
        precision[value] != profile['currency_digits']) {
      throw StateError('Unsupported currency configuration.');
    }
    current.value = value;
  }

  /// Strict ASCII decimal input: no double, exponent or silent rounding. Valid grouped commas are accepted.
  /// Caps before multiplication to stay exact on all Flutter targets.
  static int? tryParse(String input, {String? currency}) {
    final trimmed = input.trim();
    if (trimmed.contains(',') &&
        !RegExp(r'^[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?$').hasMatch(trimmed)) {
      return null;
    }
    final value = trimmed.replaceAll(',', '');
    final places = precision[currency ?? code];
    if (places == null || !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > places) return null;
    final whole = int.tryParse(parts.first);
    if (whole == null || whole > 9000000000000) return null;
    final scale = places == 0 ? 1 : 100;
    if (whole > 9000000000000 ~/ scale) return null;
    final minor = places == 0 ? 0 : int.parse(fraction.padRight(places, '0'));
    final amount = whole * scale + minor;
    return amount > 9000000000000 ? null : amount;
  }

  static int parse(String text) {
    final value = tryParse(text);
    if (value == null) throw const FormatException('Invalid currency amount');
    return value;
  }

  static String input(int amount, {String? currency}) {
    final places = precision[currency ?? code]!;
    final sign = amount < 0 ? '-' : '';
    final n = amount.abs();
    if (places == 0) return '$sign$n';
    return '$sign${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
  }

  static String format(int amount, {String? currency, int? decimalPlaces}) {
    final selected = currency ?? code;
    final places = decimalPlaces ?? precision[selected]!;
    if (places != precision[selected]) {
      throw StateError('Invalid currency precision');
    }
    final text = input(amount, currency: selected);
    final parts = text.split('.');
    final negative = parts.first.startsWith('-');
    final whole = negative ? parts.first.substring(1) : parts.first;
    final b = StringBuffer(negative ? '-' : '');
    for (int i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    if (parts.length > 1) b.write('.${parts[1]}');
    return '$b ${display(selected)}';
  }
}
