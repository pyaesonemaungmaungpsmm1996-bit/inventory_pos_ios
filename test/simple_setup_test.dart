import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/simple_setup_service.dart';
import 'package:inventory_pos/user_guide_data.dart';
void main(){
 late Database db;
 setUp(()async{
  sqfliteFfiInit();db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(singleInstance:false));
  for(final ddl in [
   'CREATE TABLE app_settings(key TEXT PRIMARY KEY,value TEXT)',
   'CREATE TABLE money_accounts(id INTEGER PRIMARY KEY,branch_id INTEGER,name TEXT,type TEXT,account_number TEXT,remark TEXT,opening_date TEXT,created_at TEXT)',
   'CREATE TABLE money_entries(id INTEGER PRIMARY KEY,account_id INTEGER,kind TEXT,amount INTEGER,entry_date TEXT,note TEXT,created_at TEXT)',
   'CREATE TABLE employees(id INTEGER PRIMARY KEY,code TEXT UNIQUE,name TEXT,phone TEXT,position TEXT,default_branch_id INTEGER,active INTEGER,remark TEXT,created_at TEXT,updated_at TEXT)',
  ]){await db.execute(ddl);}
 });
 tearDown(()async=>db.close());
 test('first-setup defaults are zero balance and idempotent',()async{
  await db.insert('app_settings',{'key':'simple_setup_seed:b:1','value':'pending'});
  await SimpleSetupService.seedDefaults(db,business:'b',branch:1,phone:'+959123456789');
  expect((await db.query('money_accounts')).single['type'],'cash');
  expect((await db.query('money_entries')).single['amount'],0);
  expect((await db.query('employees')).single['name'],'Owner');
  await SimpleSetupService.seedDefaults(db,business:'b',branch:1);
  expect((await db.query('money_accounts')).length,1);
  expect((await db.query('employees')).length,1);
 });
 test('existing POS without setup marker is untouched',()async{
  await db.insert('money_accounts',{'id':1,'branch_id':1,'name':'Existing cash','type':'cash'});
  await SimpleSetupService.seedDefaults(db,business:'b',branch:1);
  expect((await db.query('money_accounts')).single['name'],'Existing cash');
  expect(await db.query('employees'),isEmpty);
 });
 test('a failed seed rolls back cash and retains the pending marker',()async{
  await db.insert('app_settings',{'key':'simple_setup_seed:b:1','value':'pending'});
  await db.execute("CREATE TRIGGER fail_employee BEFORE INSERT ON employees BEGIN SELECT RAISE(ABORT,'Test-only failure'); END");
  await expectLater(SimpleSetupService.seedDefaults(db,business:'b',branch:1),throwsA(isA<DatabaseException>()));
  expect(await db.query('money_accounts'),isEmpty);expect(await db.query('money_entries'),isEmpty);
  expect((await db.query('app_settings')).single['value'],'pending');
 });
 test('guide covers onboarding, devices and the two New Sale locations',(){
  final topics={for(final topic in userGuideTopics)topic.id:topic};
  for(final id in ['start','login','device-approval','subscription','dashboard','quick-actions']){expect(topics.containsKey(id),isTrue);}
  expect(topics['quick-actions']!.stepsEn.join(' '),contains('only on Dashboard and Sale'));
  expect(topics['subscription']!.stepsEn.join(' '),contains('Identity documents are not collected'));
 });
}
