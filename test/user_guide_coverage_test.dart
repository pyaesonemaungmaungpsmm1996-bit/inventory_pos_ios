import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/user_guide_data.dart';
void main(){
 test('offline tutorials cover all root sections with matching bilingual steps',(){
  final ids=<String>{};
  for(final guide in userGuideTopics){
   expect(ids.add(guide.id),isTrue,reason:'Duplicate topic ${guide.id}');
   expect(guide.en.trim(),isNotEmpty);expect(guide.my.trim(),isNotEmpty);
   expect(guide.stepsEn.length,guide.stepsMy.length);expect(guide.stepsEn,isNotEmpty);
   for(final step in [...guide.stepsEn,...guide.stepsMy]){expect(step.trim(),isNotEmpty);}
  }
  final instructions=userGuideTopics.expand((g)=>g.stepsEn).join(' ').toLowerCase();
  expect(instructions, isNot(contains('submit owner identity')));
  expect(instructions, isNot(contains('checking identity and real funds')));
  for(final section in ['general','sale','inventory','expense','ledger','account']){expect(userGuideTopics.any((g)=>g.section==section),isTrue,reason:section);}
  for(final id in ['app-updates','sale','returns','serial','expiry','balance-stock','expense','money','subscription','restore','cloud','feedback','provider','start','login','device-approval','dashboard','quick-actions','serial-search','brand-entry']){expect(ids,contains(id));}
 });
}
