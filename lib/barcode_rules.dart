import 'package:barcode/barcode.dart' as bc;

class BarcodeRules {
  static String itemCode(int id) => 'ITEM-${id.toString().padLeft(6, '0')}';
  // Product codes are human-readable and case-insensitively unique.
  static bool validItemCode(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(value);
  static String forItemCode(String? input, int productId) {
    final value = input?.trim() ?? '';
    final code = value.isEmpty ? itemCode(productId) : value;
    if (!validItemCode(code)) {
      throw ArgumentError(
        'Item code needs 1–32 English letters, digits, - or _, with no spaces.',
      );
    }
    if (RegExp(r'^ITEM-[0-9]{6,}$', caseSensitive: false).hasMatch(code) &&
        code.toUpperCase() != itemCode(productId)) {
      throw StateError(
        'Automatic ITEM-number codes are reserved for their own product.',
      );
    }
    return code;
  }

  // Leading zeroes and case are significant. Stored codes are printable ASCII.
  static bool valid(String value) => RegExp(r'^[!-~]{1,32}$').hasMatch(value);
  static String forProduct(
    String? input,
    int productId, {
    String? itemCodeValue,
  }) {
    final value = input?.trim() ?? '';
    final code = value.isEmpty ? (itemCodeValue ?? itemCode(productId)) : value;
    if (!valid(code)) {
      throw ArgumentError(
        'Barcode must be 1–32 printable ASCII characters without spaces.',
      );
    }
    if (code.toUpperCase().startsWith('ITEM-') &&
        code != itemCode(productId) &&
        code != itemCodeValue) {
      throw StateError(
        'ITEM- codes are reserved for the matching product. Use its own item code or another barcode.',
      );
    }
    return code;
  }

  // UPC-A may be reported by a camera as EAN-13 with a leading zero.
  // Treat only that specific pair as equivalent; preserve every other zero.
  static String lookupKey(String input) {
    final code = input.trim();
    if (RegExp(r'^0[0-9]{12}$').hasMatch(code)) return code.substring(1);
    return code;
  }

  static double narrowBarRatio(String code) {
    final encoding = bc.Barcode.code128();
    if (!valid(code) || !encoding.isValid(code)) {
      throw ArgumentError('Invalid label barcode');
    }
    double smallest = 1;
    for (final element in encoding.make(
      code,
      width: 1,
      height: 1,
      drawText: false,
    )) {
      if (element is bc.BarcodeBar &&
          element.width > 0 &&
          element.width < smallest) {
        smallest = element.width;
      }
    }
    return smallest;
  }

  // Keep >=0.25mm narrow bars and 10-module quiet zones on both sides.
  static double minimumLabelWidthMm(String code) =>
      (1 / narrowBarRatio(code) + 20) * 0.25 + 3;
}
