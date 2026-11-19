import 'voucher_code.dart';

class VoucherResolver {
  static Future<Map<String, Object?>> resolve(
    String code,
    Future<Map<String, Object?>> Function(String kind, int id) load,
  ) async {
    final ref = VoucherCode.parse(code);
    final snapshot = await load(ref.kind, ref.id);
    if (!ref.matches(snapshot)) {
      throw const FormatException(
        'This QR does not match the voucher stored on this device.',
      );
    }
    return snapshot;
  }
}
