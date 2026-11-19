import 'package:inventory_pos/activity_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:inventory_pos/transfer_voucher_repository.dart';
import 'package:inventory_pos/product_tracking.dart';
import 'package:inventory_pos/sqlite_backup.dart';
void main(){
 late Database db;
 setUp(()async{
  sqfliteFfiInit();db=await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(singleInstance:false));await db.execute('PRAGMA foreign_keys=ON');
  for(final sql in [
   "CREATE TABLE branches(id INTEGER PRIMARY KEY,name TEXT)",
   "CREATE TABLE products(id INTEGER PRIMARY KEY,item_code TEXT,name TEXT,color TEXT,size TEXT,tracking TEXT)",
   "CREATE TABLE branch_stocks(branch_id INTEGER REFERENCES branches(id),product_id INTEGER REFERENCES products(id),stock INTEGER CHECK(stock BETWEEN 0 AND 2147483647),PRIMARY KEY(branch_id,product_id))",
   "CREATE TABLE purchase_invoices(id INTEGER PRIMARY KEY)",
   "CREATE TABLE stock_lots(id INTEGER PRIMARY KEY AUTOINCREMENT,product_id INTEGER REFERENCES products(id),branch_id INTEGER REFERENCES branches(id),purchase_id INTEGER REFERENCES purchase_invoices(id),serial TEXT UNIQUE,imei TEXT UNIQUE,expires_on TEXT,received_qty INTEGER,available INTEGER CHECK(available BETWEEN 0 AND received_qty),warranty_days INTEGER)",
   "CREATE TABLE sale_lot_allocations(sale_item_id INTEGER,lot_id INTEGER REFERENCES stock_lots(id),quantity INTEGER)",
   "CREATE TABLE stock_movements(id INTEGER PRIMARY KEY,branch_id INTEGER,product_id INTEGER,quantity INTEGER CHECK(quantity>0),kind TEXT,note TEXT,created_at TEXT)",
  ]){await db.execute(sql);}
  for(var i=1;i<=3;i++){await db.insert('branches',{'id':i,'name':'Branch $i'});}
  await db.insert('purchase_invoices',{'id':1});
  for(var i=1;i<=3;i++){
   await db.insert('products',{'id':i,'item_code':'ITEM$i','name':'Item','color':'Black','size':'M','tracking':i==1?'none':i==2?'both':'batch'});
   await db.insert('branch_stocks',{'branch_id':1,'product_id':i,'stock':i==2?1:10});
  }
  await db.insert('stock_lots',{'id':1,'product_id':2,'branch_id':1,'purchase_id':1,'serial':'S1','imei':'123456789012345','received_qty':1,'available':1,'warranty_days':365});
  await db.insert('stock_lots',{'id':2,'product_id':3,'branch_id':1,'purchase_id':1,'expires_on':'2099-01-01','received_qty':10,'available':10,'warranty_days':0});
  await TransferVoucherRepository.install(db);
 });
 tearDown(()async=>db.close());
 List<Map<String,Object?>> lines()=>[
  {'product_id':1,'quantity':3,'color':'Black','size':'M','tracking':'none','lots':[]},
  {'product_id':2,'quantity':1,'color':'Black','size':'M','tracking':'both','lots':[{'lot_id':1,'qty':1}]},
  {'product_id':3,'quantity':4,'color':'Black','size':'M','tracking':'batch','lots':[{'lot_id':2,'qty':4}]},
 ];
 Future<int> post({String key='one',List<Map<String,Object?>>? value})=>TransferVoucherRepository.post(db,requestKey:key,source:1,destination:2,date:'2026-01-01',note:'Note',transport:'Driver',lines:value??lines());
 Future<int> stock(int branch,int product)async{final r=await db.query('branch_stocks',where:'branch_id=? AND product_id=?',whereArgs:[branch,product]);return r.isEmpty?0:r.single['stock'] as int;}
 test('whole voucher dispatch, atomic receipt, variants and identities',()async{
  final id=await post();expect(await stock(1,1),7);expect(await stock(2,1),0);expect((await db.query('stock_lots',where:'id=1')).single['available'],0);
  await TransferVoucherRepository.receive(db,id,2);expect(await stock(2,1),3);expect(await stock(2,2),1);expect(await stock(2,3),4);
  expect((await db.query('stock_lots',where:'id=1')).single['branch_id'],2);expect((await TransferVoucherRepository.items(db,id)).first['color'],'Black');
  await expectLater(TransferVoucherRepository.receive(db,id,2),throwsStateError);expect(await stock(2,1),3);
  await TransferVoucherRepository.voidVoucher(db,id,'Test undo');expect(await stock(1,1),10);expect(await stock(1,2),1);expect(await stock(1,3),10);expect(await stock(2,3),0);expect((await db.query('stock_lots')).length,2);
 });
 test('bad final item rolls back all earlier stock and header writes',()async{final l=lines();l.last['quantity']=11; l.last['lots']=[{'lot_id':2,'qty':11}];await expectLater(post(value:l),throwsStateError);expect(await stock(1,1),10);expect(await db.query('transfer_vouchers'),isEmpty);expect((await db.query('stock_lots',where:'id=1')).single['available'],1);});
 test('duplicate lot, stale variant and duplicate product rejected',()async{
  var l=lines();l[1]['lots']=[{'lot_id':1,'qty':1},{'lot_id':1,'qty':1}];await expectLater(post(value:l),throwsStateError);
  l=lines();l.first['color']='Red';await expectLater(post(value:l),throwsStateError);
  l=lines();l.add(Map.from(l.first));await expectLater(post(value:l),throwsArgumentError);expect(await stock(1,1),10);
 });
 test('double submit has one voucher and pending void restores lots',()async{final id=await post();expect(await post(),id);expect(await stock(1,1),7);await TransferVoucherRepository.voidVoucher(db,id,'Cancel dispatch');expect(await stock(1,1),10);expect((await db.query('stock_lots',where:'id=1')).single['available'],1);await expectLater(TransferVoucherRepository.receive(db,id,2),throwsStateError);});
 test('wrong branch and used destination stock cannot partly receive or void',()async{final id=await post();await expectLater(TransferVoucherRepository.receive(db,id,3),throwsStateError);expect(await stock(2,1),0);await TransferVoucherRepository.receive(db,id,2);await db.update('stock_lots',{'available':0},where:'id=1');await db.insert('sale_lot_allocations',{'sale_item_id':1,'lot_id':1,'quantity':1});await expectLater(TransferVoucherRepository.voidVoucher(db,id,'Try undo'),throwsStateError);expect(await stock(1,1),7);expect(await stock(2,1),3);});
 test('tracked purchase reversal blocked while transfer is active',()async{await post();await expectLater(db.transaction((tx)=>ProductTracking.reversePurchase(tx,1)),throwsStateError);});
 test('destination overflow rolls back all received lines and serial relocation',()async{
  final id=await post();await db.insert('branch_stocks',{'branch_id':2,'product_id':3,'stock':2147483647});
  await expectLater(TransferVoucherRepository.receive(db,id,2),throwsStateError);
  expect(await stock(2,1),0);expect((await db.query('stock_lots',where:'id=1')).single['branch_id'],1);expect((await db.query('stock_lots',where:'id=1')).single['available'],0);expect((await db.query('transfer_vouchers')).single['received_at'],isNull);
 });
 test('same request cannot silently save a changed draft',()async{await post();final l=lines();l.first['quantity']=2;await expectLater(post(value:l),throwsStateError);expect(await stock(1,1),7);});
 test('transfer history blocks reversing source sale but permits destination reversal',()async{
  await db.execute('CREATE TABLE sale_invoices(id INTEGER PRIMARY KEY,branch_id INTEGER)');await db.insert('sale_invoices',{'id':1,'branch_id':1});await db.insert('sale_invoices',{'id':2,'branch_id':2});
  final id=await post();await expectLater(ProductTracking.requireLotAtTransactionBranch(db,1,'sale_invoices',1),throwsStateError);
  await TransferVoucherRepository.receive(db,id,2);await expectLater(ProductTracking.requireLotAtTransactionBranch(db,1,'sale_invoices',1),throwsStateError);await ProductTracking.requireLotAtTransactionBranch(db,1,'sale_invoices',2);
 });
 test('audit triggers are installed for new voucher tables when activity tracking exists',()async{
  await db.execute('DROP TABLE transfer_voucher_lots');await db.execute('DROP TABLE transfer_voucher_items');await db.execute('DROP TABLE transfer_vouchers');
  await ActivityStore.install(db);await TransferVoucherRepository.install(db);final id=await post();await TransferVoucherRepository.receive(db,id,2);
  expect((await db.query('activity_events',where:'source_table=?',whereArgs:['transfer_vouchers'])).length,greaterThanOrEqualTo(2));
 });
 test('migration projection preserves the old backup schema exactly',()async{final old=SqliteBackup.legacy40Schema(await SqliteBackup.schema(db));await db.execute('DROP TABLE transfer_voucher_lots');await db.execute('DROP TABLE transfer_voucher_items');await db.execute('DROP TABLE transfer_vouchers');expect(await SqliteBackup.schema(db),old);});
}
