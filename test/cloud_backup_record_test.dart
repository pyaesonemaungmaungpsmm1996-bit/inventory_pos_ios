import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/cloud_backup_record.dart';

void main() {
  const business = '11111111-1111-4111-8111-111111111111';
  const other = '22222222-2222-4222-8222-222222222222';
  const id = '33333333-3333-4333-8333-333333333333';
  final data = Uint8List.fromList(List.generate(256, (i) => i));
  Map<String, dynamic> fixture() => {
    'id': id, 'business_id': business, 'object_name': '$business/$id.tppos', 'state': 'ready',
    'bytes': data.length, 'sha256': sha256.convert(data).toString(),
    'schema_sha256': sha256.convert([1, 2, 3]).toString(), 'db_version': 39,
    'source_business': 'တိုးပွား', 'created_at': '2026-11-08T15:00:00+00:00', 'counts': {'products': 2},
  };
  test('Downloaded data must match the exact reserved bytes and SHA-256', () {
    final record = CloudBackupRecord.fromJson(fixture(), business);
    record.verify(data);
    expect(record.createdAt, DateTime.utc(2026, 11, 8, 15));
    final changed = Uint8List.fromList(data); changed[0] ^= 1;
    expect(() => record.verify(changed), throwsFormatException);
    expect(() => record.verify(Uint8List.fromList(data.sublist(1))), throwsFormatException);
  });
  test('Cross-business metadata and modified object paths are refused', () {
    expect(() => CloudBackupRecord.fromJson(fixture(), other), throwsFormatException);
    for (final path in ['../$id.tppos', '$other/$id.tppos', '$business/other.tppos', 'https://example.invalid/backup']) {
      expect(() => CloudBackupRecord.fromJson({...fixture(), 'object_name': path}, business), throwsFormatException);
    }
  });
  test('Malformed states, oversized files, fractional sizes and bad checksums are refused', () {
    for (final change in <Map<String, dynamic>>[
      {'state': 'uploaded'}, {'bytes': CloudBackupRecord.maxBytes + 1}, {'bytes': 99}, {'bytes': 100.5},
      {'sha256': 'not-a-digest'}, {'schema_sha256': 'invalid'}, {'db_version': 0}, {'created_at': '2026-11-08'},
      {'counts': {'products': -1}}, {'counts': {'products': 2.5}},
    ]) {
      expect(() => CloudBackupRecord.fromJson({...fixture(), ...change}, business), throwsFormatException);
    }
  });
  test('Different database versions remain downloadable but are not claimed to be restorable', () {
    final record = CloudBackupRecord.fromJson({...fixture(), 'db_version': 40}, business);
    record.verify(data); expect(record.dbVersion, 40);
    expect(() => record.counts['products'] = 9, throwsUnsupportedError);
  });
}
