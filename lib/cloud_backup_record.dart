import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CloudBackupRecord {
  const CloudBackupRecord({
    required this.id,
    required this.businessId,
    required this.objectName,
    required this.state,
    required this.bytes,
    required this.sha256Hex,
    required this.schemaSha256,
    required this.dbVersion,
    required this.sourceBusiness,
    required this.createdAt,
    required this.counts,
  });
  static const bucket = 'toe-pwar-backups';
  static const maxBytes = 20 * 1024 * 1024;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final _digest = RegExp(r'^[0-9a-f]{64}$');
  final String id,
      businessId,
      objectName,
      state,
      sha256Hex,
      schemaSha256,
      sourceBusiness;
  final int bytes, dbVersion;
  final DateTime createdAt;
  final Map<String, int> counts;

  factory CloudBackupRecord.fromJson(
    Map<String, dynamic> row,
    String expectedBusiness,
  ) {
    final id = row['id'], business = row['business_id'];
    final bytes = row['bytes'],
        version = row['db_version'],
        hash = row['sha256'],
        schema = row['schema_sha256'];
    final name = row['object_name'],
        state = row['state'],
        source = row['source_business'],
        timestamp = row['created_at'];
    if (id is! String ||
        business is! String ||
        !_uuid.hasMatch(id) ||
        !_uuid.hasMatch(business) ||
        business != expectedBusiness ||
        name != '$business/$id.tppos' ||
        !['pending', 'ready', 'deleting'].contains(state) ||
        bytes is! int ||
        bytes < 100 ||
        bytes > maxBytes ||
        version is! int ||
        version < 1 ||
        version > 100000 ||
        hash is! String ||
        !_digest.hasMatch(hash) ||
        schema is! String ||
        !_digest.hasMatch(schema) ||
        source is! String ||
        source.length > 150 ||
        timestamp is! String ||
        !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(timestamp)) {
      throw const FormatException('Invalid cloud backup metadata');
    }
    final counts = <String, int>{};
    final rawCounts = row['counts'];
    if (rawCounts is! Map || rawCounts.length > 100) {
      throw const FormatException('Invalid cloud record counts');
    }
    for (final item in rawCounts.entries) {
      if (item.key is! String ||
          item.value is! int ||
          ((item.value as int) < 0 || (item.value as int) > 2147483647)) {
        throw const FormatException('Invalid cloud record count');
      }
      counts[item.key as String] = item.value as int;
    }
    return CloudBackupRecord(
      id: id,
      businessId: business,
      objectName: name as String,
      state: state as String,
      bytes: bytes,
      sha256Hex: hash,
      schemaSha256: schema,
      dbVersion: version,
      sourceBusiness: source,
      createdAt: DateTime.parse(timestamp).toUtc(),
      counts: Map.unmodifiable(counts),
    );
  }

  void verify(Uint8List data) {
    if (data.length != bytes || sha256.convert(data).toString() != sha256Hex) {
      throw const FormatException(
        'Cloud backup checksum or size mismatch. Keep your local data and try downloading again',
      );
    }
  }
}
