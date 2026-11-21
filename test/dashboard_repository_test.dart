import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/dashboard_repository.dart';

void main(){
 late Database db;
 setUp(()async{
  sqfliteFfiInit();
  db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(singleInstance:false));
  for(final ddl in [
   'CREATE TABLE branches(id INTEGER PRIMARY KEY)',
   'CREATE TABLE sale_invoices(id INTEGER PRIMARY KEY,branch_id INTEGER,total INTEGER,status TEXT,confirmed_at TEXT,branch_code_snapshot TEXT)',
   'CREATE TABLE expenses(id INTEGER PRIMARY KEY,branch_id INTEGER,amount INTEGER,status TEXT,posted_at TEXT)',
   'CREATE TABLE purchase_invoices(id INTEGER PRIMARY KEY,branch_id INTEGER,total INTEGER,status TEXT,confirmed_at TEXT)',
   'CREATE TABLE customer_receipts(id INTEGER PRIMARY KEY,branch_id INTEGER,total INTEGER,status TEXT,created_at TEXT)',
   'CREATE TABLE money_accounts(id INTEGER PRIMARY KEY,branch_id INTEGER)',
   'CREATE TABLE money_entries(account_id INTEGER,amount INTEGER)',
  ]){await db.execute(ddl);}
  await db.insert('branches',{'id':1});await db.insert('branches',{'id':2});
  for(final row in [
   {'id':1,'branch_id':1,'total':100,'status':'posted','confirmed_at':'2026-11-10T17:30:00.000Z'},
   {'id':2,'branch_id':1,'total':200,'status':'posted','confirmed_at':'2026-11-11T17:29:59.999Z'},
   {'id':3,'branch_id':1,'total':900,'status':'posted','confirmed_at':'2026-11-11T17:30:00.000Z'},
   {'id':4,'branch_id':1,'total':700,'status':'void','confirmed_at':'2026-11-11T09:00:00.000Z'},
   {'id':5,'branch_id':2,'total':800,'status':'posted','confirmed_at':'2026-11-11T10:00:00.000Z'},
  ]){await db.insert('sale_invoices',row);}
  await db.insert('money_accounts',{'id':1,'branch_id':1});
  await db.insert('money_entries',{'account_id':1,'amount':450});
 });
 tearDown(()async=>db.close());
 test('snapshot respects branch, posted status and business date bounds',()async{
  final result=await DashboardRepository.read(db,1,DateTime.parse('2026-11-10T17:30:00Z'),DateTime.parse('2026-11-11T17:30:00Z'));
  expect(result['sales'],300);expect(result['expenses'],0);expect(result['balance'],450);
  expect((result['recent'] as List).length,4);
  expect((result['recent'] as List).where((r)=>r['id']==5),isEmpty);
  final other=await DashboardRepository.read(db,2,DateTime.utc(2026,11,1),DateTime.utc(2026,12,1));
  expect(other['sales'],800);expect(other['balance'],0);
 });
 test('recent pagination is deterministic and rejects invalid bounds',()async{
  final all=await DashboardRepository.recent(db,1,limit:50);
  final first=await DashboardRepository.recent(db,1,limit:2);
  final rest=await DashboardRepository.recent(db,1,limit:2,offset:2);
  expect([...first,...rest],all);
  await expectLater(DashboardRepository.recent(db,1,limit:100),throwsArgumentError);
  await expectLater(DashboardRepository.read(db,99,DateTime.utc(2026),DateTime.utc(2027)),throwsStateError);
 });
}
