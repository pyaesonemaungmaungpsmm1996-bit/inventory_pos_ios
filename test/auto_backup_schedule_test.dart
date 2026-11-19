import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/auto_backup_store.dart';
void main() {
  final captured = DateTime.utc(2026, 11, 9, 10);
  Map<String, dynamic> config(int minutes) => {'enabled': true, 'minutes': minutes, 'capturedAt': captured.toIso8601String()};
  test('Disabled config never runs even with pending or force flags', () {
    expect(AutoBackupStore.due({'enabled': false, 'pending': {}, 'force': true}, captured), isFalse);
  });
  test('Each interval is due at the boundary, not before it', () {
    for (final minutes in [60,180,1440]) {
      final row = config(minutes);
      expect(AutoBackupStore.due(row, captured.add(Duration(minutes: minutes)).subtract(const Duration(milliseconds: 1))), isFalse);
      expect(AutoBackupStore.due(row, captured.add(Duration(minutes: minutes))), isTrue);
    }
  });
  test('An offline pending snapshot resumes without waiting another interval', () {
    expect(AutoBackupStore.due({...config(1440), 'pending': {'id': 'existing-job'}}, captured), isTrue);
    expect(AutoBackupStore.due({...config(1440), 'force': true}, captured), isTrue);
  });
  test('Late upload of an old snapshot still requires a fresh catch-up capture', () {
    final row = {...config(60), 'uploadedAt': captured.add(const Duration(hours: 5)).toIso8601String()};
    expect(AutoBackupStore.due(row, captured.add(const Duration(hours: 5))), isTrue);
    expect(AutoBackupStore.due({...row, 'capturedAt': captured.add(const Duration(hours: 5)).toIso8601String()}, captured.add(const Duration(hours: 5))), isFalse);
  });
  test('Missing capture starts first backup; invalid intervals cannot loop', () {
    expect(AutoBackupStore.due({'enabled': true, 'minutes': 180}, captured), isTrue);
    expect(AutoBackupStore.due({'enabled': true, 'minutes': 1}, captured), isFalse);
  });
}
