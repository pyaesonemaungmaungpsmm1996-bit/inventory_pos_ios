import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/subscription_runtime.dart';
void main(){
 test('provider pause disables new writes without discarding plan dates or record access',(){
  final now=DateTime.utc(2026,11,11);
  final policy=<String,dynamic>{'bound':true,'plan':'premium','ends_at':'2026-12-11T00:00:00Z'};
  expect(SubscriptionRuntime.effective(policy,now)['writable'],true);
  for(final flag in ['provider_blocked','actor_provider_blocked']){
   final result=SubscriptionRuntime.effective({...policy,flag:true},now);
   expect(result['writable'],false);expect(result['plan'],'premium');expect(result['ends_at'],policy['ends_at']);
  }
  expect(SubscriptionRuntime.effective({...policy,'provider_blocked':false,'actor_provider_blocked':false},now)['writable'],true);
 });
}
