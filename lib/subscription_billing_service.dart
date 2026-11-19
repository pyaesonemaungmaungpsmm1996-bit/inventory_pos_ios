import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'online_account_service.dart';

class BillingImage {
  const BillingImage(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
  String get digest => sha256.convert(bytes).toString();
  static const maxBytes = 8 * 1024 * 1024;
  static BillingImage parse(Uint8List bytes) {
    if (bytes.length < 16 || bytes.length > maxBytes) {
      throw const FormatException('Choose a JPG or PNG image up to 8 MB');
    }
    final png =
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    final jpeg = bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    if (!png && !jpeg) {
      throw const FormatException(
        'Only JPG and PNG images are supported. PDF, ZIP and other files are not accepted',
      );
    }
    final dimensions = png ? _pngSize(bytes) : _jpegSize(bytes);
    if (dimensions.$1 < 1 ||
        dimensions.$2 < 1 ||
        dimensions.$1 > 10000 ||
        dimensions.$2 > 10000 ||
        dimensions.$1 * dimensions.$2 > 40000000) {
      throw const FormatException(
        'Image dimensions are too large. Resize to at most 10,000 pixels per side and 40 megapixels',
      );
    }
    return BillingImage(bytes, png ? 'image/png' : 'image/jpeg');
  }

  static (int, int) _pngSize(Uint8List b) {
    if (b.length < 33 ||
        b[12] != 73 ||
        b[13] != 72 ||
        b[14] != 68 ||
        b[15] != 82 ||
        ByteData.sublistView(b).getUint32(8) != 13) {
      throw const FormatException('Invalid PNG image header');
    }
    final data = ByteData.sublistView(b);
    return (data.getUint32(16), data.getUint32(20));
  }

  static (int, int) _jpegSize(Uint8List b) {
    var offset = 2, segments = 0;
    while (offset < b.length && segments++ < 4096) {
      if (b[offset++] != 255) {
        break;
      }
      while (offset < b.length && b[offset] == 255) {
        offset++;
      }
      if (offset >= b.length) {
        break;
      }
      final marker = b[offset++];
      if (marker == 217 || marker == 218) {
        break;
      }
      if (marker == 1 || marker == 216 || (marker >= 208 && marker <= 215)) {
        continue;
      }
      if (offset + 2 > b.length) {
        break;
      }
      final length = (b[offset] << 8) | b[offset + 1];
      if (length < 2 || offset + length > b.length) {
        break;
      }
      if (const [
        192,
        193,
        194,
        195,
        197,
        198,
        199,
        201,
        202,
        203,
        205,
        206,
        207,
      ].contains(marker)) {
        if (length < 8) {
          break;
        }
        return (
          (b[offset + 5] << 8) | b[offset + 6],
          (b[offset + 3] << 8) | b[offset + 4],
        );
      }
      offset += length;
    }
    throw const FormatException(
      'Cannot read JPEG dimensions. Choose a valid JPG image',
    );
  }
}

class BillingService {
  static const bucket = 'toe-pwar-subscription-docs';
  static void guard(String owner) {
    if (OnlineAccounts.client.auth.currentUser?.id != owner) {
      throw StateError('Account changed. Reopen Subscription');
    }
  }

  static Future<Map<String, dynamic>> call(
    String rpc,
    Map<String, dynamic> params,
    String owner,
  ) async {
    guard(owner);
    final response = await OnlineAccounts.client.rpc(rpc, params: params);
    guard(owner);
    return Map<String, dynamic>.from(response as Map);
  }

  static Future<BillingImage?> choose() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose JPG or PNG (up to 8 MB)',
      type: FileType.any,
    );
    if (file == null) {
      return null;
    }
    final length = await file.length();
    if (length != null && length > BillingImage.maxBytes) {
      throw const FormatException('Maximum image size is 8 MB');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (builder.length + chunk.length > BillingImage.maxBytes) {
        throw const FormatException('Maximum image size is 8 MB');
      }
      builder.add(chunk);
    }
    return BillingImage.parse(builder.takeBytes());
  }

  static void validateDocument(Map<String, dynamic> row, {String? business}) {
    final id = row['id'], b = row['business_id'];
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    final mime = row['mime'];
    if (id is! String ||
        b is! String ||
        !uuid.hasMatch(id) ||
        !uuid.hasMatch(b) ||
        (business != null && business != b) ||
        !['image/jpeg', 'image/png'].contains(mime) ||
        row['object_name'] !=
            '$b/$id${mime == 'image/png' ? '.png' : '.jpg'}' ||
        row['bytes'] is! int ||
        (row['bytes'] as int) < 16 ||
        (row['bytes'] as int) > BillingImage.maxBytes ||
        row['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String)) {
      throw const FormatException('Invalid private document metadata');
    }
  }

  static void verify(Map<String, dynamic> row, Uint8List bytes) {
    validateDocument(row);
    if (bytes.length != row['bytes'] ||
        sha256.convert(bytes).toString() != row['sha256']) {
      throw const FormatException('Document checksum failed');
    }
    BillingImage.parse(bytes);
  }

  static Future<String> upload(
    String business,
    String kind,
    BillingImage image,
    String owner,
  ) async {
    final row = await call('tp_billing_document_start', {
      'p_business': business,
      'p_kind': kind,
      'p_bytes': image.bytes.length,
      'p_sha256': image.digest,
      'p_mime': image.mime,
    }, owner);
    validateDocument(row, business: business);
    if (row['bytes'] != image.bytes.length ||
        row['sha256'] != image.digest ||
        row['kind'] != kind) {
      throw const FormatException('Upload reservation differs');
    }
    guard(owner);
    try {
      await OnlineAccounts.client.storage
          .from(bucket)
          .uploadBinary(
            row['object_name'] as String,
            image.bytes,
            fileOptions: FileOptions(
              contentType: image.mime,
              upsert: false,
              cacheControl: '0',
            ),
          );
    } catch (_) {
      guard(owner);
      final existing = await OnlineAccounts.client.storage
          .from(bucket)
          .download(row['object_name'] as String);
      verify(row, existing);
    }
    guard(owner);
    final uploaded = await OnlineAccounts.client.storage
        .from(bucket)
        .download(row['object_name'] as String);
    verify(row, uploaded);
    guard(owner);
    await OnlineAccounts.client.rpc(
      'tp_billing_document_finish',
      params: {'p_document': row['id']},
    );
    guard(owner);
    return row['id'] as String;
  }

  static Future<Uint8List> download(String document, String owner) async {
    final row = await call('tp_billing_document_get', {
      'p_document': document,
    }, owner);
    validateDocument(row);
    final bytes = await OnlineAccounts.client.storage
        .from(bucket)
        .download(row['object_name'] as String);
    verify(row, bytes);
    guard(owner);
    return bytes;
  }

  static String friendly(Object error) => error is PostgrestException
      ? error.message
      : error is StateError
      ? error.message
      : error is FormatException
      ? error.message
      : error is AuthException
      ? 'Sign-in failed. Check your account and connection.'
      : 'Could not complete this request. Check your connection and refresh before retrying.';
  static int discountBps(String text) {
    final match = RegExp(r'^(\d{1,2})(?:\.(\d{1,2}))?$')
        .firstMatch(text.trim());
    if (match == null) {
      throw const FormatException(
        'Discount must be 0 to 99.99 percent, with at most two decimals',
      );
    }
    return int.parse(match[1]!) * 100 +
        int.parse((match[2] ?? '').padRight(2, '0'));
  }
}
