import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/product_tracking.dart';
import 'package:inventory_pos/sqlite_backup.dart';
void main(){
 late Database db;
 late String legacySchema;
 setUp(()async{
  sqfliteFfiInit();db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(singleInstance:false));
  await db.execute('PRAGMA foreign_keys=ON');
  for(final ddl in [
   'CREATE TABLE products(id INTEGER PRIMARY KEY,name TEXT,category_id INTEGER)',
   'CREATE TABLE product_categories(id INTEGER PRIMARY KEY)',
   'CREATE TABLE branches(id INTEGER PRIMARY KEY)',
   'CREATE TABLE purchase_invoices(id INTEGER PRIMARY KEY)',
   'CREATE TABLE sale_draft_items(id INTEGER PRIMARY KEY)',
   'CREATE TABLE sale_items(id INTEGER PRIMARY KEY,sale_id INTEGER,product_id INTEGER)',
   'CREATE TABLE purchase_items(id INTEGER PRIMARY KEY)',
   "CREATE TABLE sale_returns(id INTEGER PRIMARY KEY,status TEXT,branch_id INTEGER)",
  ]){await db.execute(ddl);}
  legacySchema=await SqliteBackup.schema(db);
  await ProductTracking.install(db);
  for(final table in ['product_categories','branches','purchase_invoices']){await db.insert(table,{'id':1});}
  await db.insert('products',{'id':1,'name':'Phone','category_id':1,'tracking':'both','warranty_days':365});
  await db.insert('sale_items',{'id':1,'sale_id':1,'product_id':1});
  await db.insert('sale_items',{'id':2,'sale_id':2,'product_id':1});
 });
 tearDown(()async=>db.close());
 Future<void> receive()async=>db.transaction((t)=>ProductTracking.receive(t,1,1,1,{'qty':1,'lots':[{'qty':1,'serial':'SERIAL-1','imei':'123456789012345','expires_on':'2099-12-31'}]}));
 test('v40 schema projects exactly to the trusted v39 backup schema',()async{expect(SqliteBackup.legacy39Schema(await SqliteBackup.schema(db)),legacySchema);});
 test('existing product permits brand/warranty choice but rejects a stale tracking or variant change',()async{
  await ProductTracking.validatePurchasePolicy(db,1,{'tracking':'both','color':'','size':'','brand_id':2,'warranty_days':90});
  await expectLater(ProductTracking.validatePurchasePolicy(db,1,{'tracking':'none'}),throwsStateError);
  await expectLater(ProductTracking.validatePurchasePolicy(db,1,{'color':'Black'}),throwsStateError);
  expect((await db.query('products')).single['tracking'],'both');
 });
 test('required selection and all stock changes roll back if quantity or posting fails',()async{
  await receive();
  await expectLater(db.transaction((t)=>ProductTracking.sell(t,1,1,1,'[]',1,'2026-11-11')),throwsStateError);
  expect((await db.query('stock_lots')).single['available'],1);
  await expectLater(db.transaction((t)async{await ProductTracking.sell(t,1,1,1,'[{"lot_id":1,"qty":1}]',1,'2026-11-11');throw StateError('Payment failed');}),throwsStateError);
  expect((await db.query('stock_lots')).single['available'],1);expect(await db.query('sale_lot_allocations'),isEmpty);
 });
 test('unique identity, exact warranty, no double sale, return identity and reversal',()async{
  await receive();await expectLater(receive(),throwsStateError);
  final result=await db.transaction((t)=>ProductTracking.sell(t,1,1,1,'[{"lot_id":1,"qty":1}]',1,'2026-11-11'));
  expect((jsonDecode(result) as List).single['warranty_until'],'2027-11-11');
  await expectLater(db.transaction((t)=>ProductTracking.sell(t,1,1,1,'[{"lot_id":1,"qty":1}]',2,'2026-11-11')),throwsStateError);
  await db.insert('sale_returns',{'id':1,'status':'posted','branch_id':1});
  await db.transaction((t)=>ProductTracking.returnItems(t,1,1,1,'[{"lot_id":1,"qty":1}]'));
  expect((await db.query('stock_lots')).single['available'],1);
  await db.transaction((t)=>ProductTracking.reverseReturn(t,1));
  expect((await db.query('stock_lots')).single['available'],0);
  await db.transaction((t)=>ProductTracking.reverseSale(t,1));
  expect((await db.query('stock_lots')).single['available'],1);
 });
 test('quantity mismatch rolls back received identities',()async{
  await expectLater(db.transaction((t)=>ProductTracking.receive(t,1,1,1,{'qty':2,'lots':[{'qty':1,'serial':'ONE','imei':'123456789012345'}]})),throwsArgumentError);
  expect(await db.query('stock_lots'),isEmpty);
 });
 test('existing serial is checked without case sensitivity',()async{
  await receive();
  await expectLater(db.transaction((t)=>ProductTracking.receive(t,1,1,1,{'qty':1,'lots':[{'qty':1,'serial':'serial-1','imei':'223456789012345'}]})),throwsStateError);
  expect((await db.query('stock_lots')).length,1);
 });
 test('expired or wrong-branch identities cannot be sold',()async{
  await receive();await db.update('stock_lots',{'expires_on':'2000-01-01'});
  await expectLater(db.transaction((t)=>ProductTracking.sell(t,1,1,1,'[{"lot_id":1,"qty":1}]',1,'2026-11-11')),throwsStateError);
  await expectLater(db.transaction((t)=>ProductTracking.sell(t,1,2,1,'[{"lot_id":1,"qty":1}]',1,'2026-11-11')),throwsStateError);
  expect((await db.query('stock_lots')).single['available'],1);
 });
}
