import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_datetime.dart';

void main(){
 final original=AppDateTime.current.value;
 tearDown(()=>AppDateTime.configure(original));
 test('Yangon local midnight maps to the prior UTC evening',(){
  AppDateTime.configure('Asia/Yangon');
  final range=AppDateTime.currentDayUtcRange(at:DateTime.utc(2026,11,11,10));
  expect(range.$1,DateTime.utc(2026,11,10,17,30));
  expect(range.$2,DateTime.utc(2026,11,11,17,30));
 });
 test('DST day uses next local midnight rather than adding 24 hours',(){
  AppDateTime.configure('America/New_York');
  final range=AppDateTime.currentDayUtcRange(at:DateTime.utc(2026,3,8,12));
  expect(range.$2.difference(range.$1),const Duration(hours:23));
 });
}
