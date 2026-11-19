import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/user_guide_data.dart';
void main(){test('transfer tutorial covers multi-item selection, receive and correction in both languages',(){final g=userGuideTopics.singleWhere((g)=>g.id=='transfer');expect(g.stepsEn.length,7);expect(g.stepsMy.length,7);expect(g.stepsEn.join(' '),contains('IMEI'));expect(g.stepsMy.join(' '),contains('IMEI'));expect(g.stepsEn.join(' '),contains('Receive all'));expect(g.stepsEn.join(' '),contains('Void'));expect(g.noteEn,contains('not live synchronization'));});}
