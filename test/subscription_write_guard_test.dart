import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:inventory_pos/subscription_runtime.dart';
import 'package:inventory_pos/sqlite_backup.dart';
void main(){
 late Directory folder;late Database db;
 Map<String,dynamic> policy(String plan,DateTime until)=>{'business_id':'business-a','owner_id':'owner-a','plan':plan,'ends_at':until.toIso8601String(),'server_now':DateTime.now().toUtc().toIso8601String()};
 setUp(()async{
  ffi.sqfliteFfiInit();databaseFactory=ffi.databaseFactoryFfi;
  folder=await Directory.systemTemp.createTemp('tp_license_guard');await databaseFactory.setDatabasesPath(folder.path);
  db=await openDatabase(p.join(folder.path,'records.db'));
  await db.execute('PRAGMA foreign_keys=ON');
  await db.execute('CREATE TABLE branches(id INTEGER PRIMARY KEY,name TEXT)');
  await db.execute('CREATE TABLE invoices(id INTEGER PRIMARY KEY,branch_id INTEGER REFERENCES branches(id),value TEXT)');
  await db.execute('CREATE TABLE items(id INTEGER PRIMARY KEY,invoice_id INTEGER REFERENCES invoices(id),value TEXT)');
  await db.execute('CREATE TABLE app_settings(key TEXT PRIMARY KEY,value TEXT)');
  await db.insert('branches',{'id':1,'name':'kept'});await db.insert('branches',{'id':2,'name':'historic'});
  await db.insert('invoices',{'id':1,'branch_id':1,'value':'kept'});await db.insert('invoices',{'id':2,'branch_id':2,'value':'historic'});
 });
 tearDown(()async{await db.close();await folder.delete(recursive:true);});
 test('active Standard may seed only its first explicitly mapped branch',()async{
  await db.delete('invoices');await db.delete('branches');
  await SubscriptionRuntime.bind(policy('standard',DateTime.now().toUtc().add(const Duration(days:1))),1,null);
  await SubscriptionRuntime.install(db);
  await expectLater(db.insert('branches',{'id':2,'name':'wrong mapping'}),throwsA(isA<DatabaseException>()));
  await db.insert('branches',{'id':1,'name':'first branch'});
  await expectLater(db.insert('branches',{'id':2,'name':'extra branch'}),throwsA(isA<DatabaseException>()));
  await expectLater(db.delete('branches',where:'id=1'),throwsA(isA<DatabaseException>()));
  expect((await db.query('branches')).single['id'],1);
 });
 test('unbound setup cannot create a first branch',()async{
  await db.delete('invoices');await db.delete('branches');
  await SubscriptionRuntime.install(db);
  await expectLater(db.insert('branches',{'id':1,'name':'blocked'}),throwsA(isA<DatabaseException>()));
  expect(await db.query('branches'),isEmpty);
 });
 test('Standard protects the other branch and indirect invoice items, while rows stay readable',()async{
  await SubscriptionRuntime.bind(policy('standard',DateTime.now().toUtc().add(const Duration(days:1))),1,null);
  await SubscriptionRuntime.install(db);
  await db.insert('invoices',{'id':3,'branch_id':1,'value':'allowed'});
  await expectLater(db.insert('invoices',{'id':4,'branch_id':2,'value':'blocked'}),throwsA(isA<DatabaseException>()));
  await expectLater(db.insert('items',{'id':1,'invoice_id':2,'value':'blocked'}),throwsA(isA<DatabaseException>()));
  await expectLater(db.update('invoices',{'value':'blocked'},where:'id=2'),throwsA(isA<DatabaseException>()));
  expect((await db.query('invoices',where:'id=2')).single['value'],'historic');
  await db.insert('app_settings',{'key':'view_branch','value':'2'});
 });
 test('Expired license denies writes while select and native local backup remain available',()async{
  await SubscriptionRuntime.bind(policy('premium',DateTime.now().toUtc().subtract(const Duration(seconds:1))),null,null);
  await SubscriptionRuntime.install(db);
  await expectLater(db.delete('invoices',where:'id=1'),throwsA(isA<DatabaseException>()));
  expect((await db.query('invoices')).length,2);
  final file=p.join(folder.path,'snapshot.tppos');await SqliteBackup.create(db,file);
  final copy=await openDatabase(file,readOnly:true,singleInstance:false);
  try{
   expect((await copy.query('invoices')).length,2);
   expect(await SqliteBackup.schema(copy),await SqliteBackup.schema(db));
  }finally{await copy.close();}
  await SubscriptionRuntime.pauseAfterRestore();
  expect(SubscriptionRuntime.effective(await SubscriptionRuntime.read(),DateTime.now())['writable'],isFalse);
 });
}
