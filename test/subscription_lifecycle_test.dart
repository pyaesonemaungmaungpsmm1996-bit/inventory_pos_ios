import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/subscription_runtime.dart';
import 'package:inventory_pos/subscription_reminders.dart';
void main(){
 final now=DateTime.utc(2026,11,10,12);
 Map<String,dynamic> active(String plan)=>{'bound':true,'plan':plan,'ends_at':now.add(const Duration(days:10)).toIso8601String(),'local_branch':1,'wall_seen':now.toIso8601String(),'offset_ms':0};
 test('Expired and unbound licenses stay read-only without deleting their metadata',(){
  expect(SubscriptionRuntime.effective({},now)['writable'],isFalse);
  final expired={...active('premium'),'ends_at':now.toIso8601String()};
  expect(SubscriptionRuntime.effective(expired,now)['writable'],isFalse);
  expect(expired['plan'],'premium');
  expect(SubscriptionRuntime.effective({...active('premium'),'paused':true},now)['writable'],isFalse);
 });
 test('Scheduled downgrade changes branch only at its boundary; missing mapping is read-only',(){
  final v={...active('premium'),'next_plan':'standard','next_from':now.add(const Duration(hours:1)).toIso8601String(),
   'next_until':now.add(const Duration(days:31)).toIso8601String(),'next_local_branch':2};
  expect(SubscriptionRuntime.effective(v,now)['plan'],'premium');
  final after=SubscriptionRuntime.effective(v,now.add(const Duration(hours:1)));
  expect(after['plan'],'standard');expect(after['local_branch'],2);expect(after['writable'],isTrue);
  expect(SubscriptionRuntime.effective({...v,'next_local_branch':null},now.add(const Duration(hours:1)))['writable'],isFalse);
 });
 test('Clock rollback requires online verification; local restore cannot renew a cached expiry',(){
  expect(SubscriptionRuntime.effective(active('premium'),now.subtract(const Duration(minutes:6)))['clock_warning'],isTrue);
  expect(SubscriptionRuntime.effective({...active('premium'),'paused':true},now)['writable'],isFalse);
 });
 test('Reminders start within five days and deduplicate per expiry and local date',(){
  final v={...active('premium'),'reminders':true,'ends_at':now.add(const Duration(days:5)).toIso8601String()};
  expect(SubscriptionReminders.due(v,now.subtract(const Duration(seconds:1))),isFalse);
  expect(SubscriptionReminders.due(v,now),isTrue);
  final key='${v['ends_at']}|${now.toLocal().toIso8601String().substring(0,10)}';
  expect(SubscriptionReminders.due({...v,'last_reminder':key},now),isFalse);
  expect(SubscriptionReminders.due({...v,'last_reminder':key},now.add(const Duration(days:1))),isTrue);
  expect(SubscriptionReminders.due({...v,'reminders':false},now),isFalse);
 });
}
