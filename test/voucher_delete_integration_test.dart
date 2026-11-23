import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:inventory_pos/app_database.dart';
import 'package:inventory_pos/stock_sync.dart';
import 'package:inventory_pos/stock_sync_checkout.dart';
import 'package:inventory_pos/shared_pos_opening_import.dart';
import 'package:inventory_pos/account_transfer_repository.dart';
import 'package:inventory_pos/subscription_runtime.dart';

void main(){
 final app=AppDatabase.instance;
 late Directory root;late sq.Database db;
 late int branch,employee,product,cash,bank;
 const day='2026-11-13';
 setUpAll(()async{
  ffi.sqfliteFfiInit();sq.databaseFactory=ffi.databaseFactoryFfi;
  root=await Directory.systemTemp.createTemp('tp-combined-');
  await sq.databaseFactory.setDatabasesPath(root.path);
  final now=DateTime.now().toUtc();
  await SubscriptionRuntime.bind({'business_id':'fixture','owner_id':'fixture-owner','plan':'premium','server_now':now.toIso8601String(),'ends_at':now.add(const Duration(days:1)).toIso8601String()},null,null);
  await app.saveBusinessProfile(name:'Test Shop',countryCode:'MM',currencyCode:'MMK');
  await app.saveBranch(code:'QA',name:'QA Branch',phone:'',address:'');
  branch=(await app.getBranches()).single['id'] as int;
  await app.saveEmployee(code:'STAFF',name:'Staff',phone:'',position:'',branchId:branch,active:true,remark:'');
  employee=(await app.getEmployees(branchId:branch)).single['id'] as int;
  product=await app.addProduct(name:'Shirt',price:100,stock:20,branchId:branch);
  for(final pay in ['Cash','Bank']){await app.saveMoneyAccount(branchId:branch,name:pay,accountHolder:'Same Holder',type:pay=='Cash'?'cash':'bank',accountNumber:pay=='Cash'?'':'001',remark:'',openingBalance:10000,openingDate:day);}
  db=await app.database;
  final accounts=await app.getMoneyAccounts(branchId:branch);
  cash=accounts.firstWhere((a)=>a['name']=='Cash')['id'] as int;
  bank=accounts.firstWhere((a)=>a['name']=='Bank')['id'] as int;
 });
 tearDownAll(()async{await db.close();await root.delete(recursive:true);});
 Future<int> stock()async=>(await db.query('branch_stocks',where:'branch_id=? AND product_id=?',whereArgs:[branch,product])).single['stock'] as int;
 Future<int> balance(int account)async=>(await db.rawQuery('SELECT SUM(amount) n FROM money_entries WHERE account_id=?',[account])).single['n'] as int;
 Future<int> sell()async{
  final draft=await app.saveSaleDraft(branchId:branch,saveCustomer:false,customerName:'',customerPhone:'',customerCompany:'',customerAddress:'',employeeId:employee,invoiceDate:day,discountType:'amount',discountValue:0,items:[{'product_id':product,'qty':2,'price':100}]);
  final row=await app.getSaleDraft(draft);
  return app.confirmSaleDraft(draftId:draft,revision:row['revision'] as int,paymentDate:day,payments:[{'account_id':cash,'amount':200}]);
 }
 test('same holder on separate Pay Names, optional photos and duplicate barcode rollback',()async{
  final accounts=await app.getMoneyAccounts(branchId:branch);
  expect(accounts.where((a)=>a['account_holder']=='Same Holder').length,2);
  final image=Uint8List.fromList([255,216,255,217]);
  await app.updateProduct(id:product,name:'Shirt',price:100,barcode:'0012345678',imageBytes:image);
  expect(await app.getProductImage(product),orderedEquals(image));
  final second=await app.addProduct(name:'Other',price:1,stock:0,branchId:branch);
  await expectLater(app.updateProduct(id:second,name:'Should roll back',price:9,barcode:'0012345678',imageBytes:image),throwsA(isA<sq.DatabaseException>()));
  expect((await db.query('products',where:'id=?',whereArgs:[second])).single['name'],'Other');
  expect(await app.getProductImage(second),isNull);
  await app.updateProduct(id:product,name:'Shirt',price:100,removeImage:true);
  expect(await app.getProductImage(product),isNull);
 });
 test('posted walk-in sale can print/read then delete without Owner login; effects reversed and archive kept',()async{
  final beforeStock=await stock(),beforeCash=await balance(cash);
  final sale=await sell();
  final loaded=await app.getConfirmedSale(sale);
  expect(loaded['customer_name'],'');expect((loaded['payments'] as List).single['amount'],200);
  await app.deleteVoucher(kind:'sale',id:sale);
  expect(await stock(),beforeStock);expect(await balance(cash),beforeCash);
  expect(await db.query('sale_invoices',where:'id=?',whereArgs:[sale]),isEmpty);
  expect(await db.query('sale_items',where:'sale_id=?',whereArgs:[sale]),isEmpty);
  final archives=await db.query('app_settings',where:'key LIKE ?',whereArgs:['voucher_delete_archive:sale:$sale:%']);
  final archive=jsonDecode(archives.single['value'] as String) as Map;
  expect((archive['header'] as Map)['status'],'posted');expect((archive['sale_items'] as List).length,1);
  expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
 });
 test('failed reversal rolls back stock, header, money and archive',()async{
  final sale=await sell();final afterSaleStock=await stock();
  final cashBalance=await balance(cash);
  final transfer=await AccountTransferRepository.save(requestKey:'drain-cash',fromAccount:cash,toAccount:bank,amount:cashBalance,date:day,note:'Test');
  await expectLater(app.deleteVoucher(kind:'sale',id:sale),throwsStateError);
  expect(await stock(),afterSaleStock);expect(await balance(cash),0);
  expect((await db.query('sale_invoices',where:'id=?',whereArgs:[sale])).single['status'],'posted');
  expect(await db.query('app_settings',where:'key LIKE ?',whereArgs:['voucher_delete_archive:sale:$sale:%']),isEmpty);
  await app.deleteVoucher(kind:'account_transfer',id:transfer);
  expect(await balance(cash),cashBalance);
  await app.deleteVoucher(kind:'sale',id:sale);
  expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
 });
 test('opening import reads current stock, money and voucher history from SQLite', () async {
  final sale = await sell();
  try {
   final snapshot = await SharedPosOpeningImport.prepare('QA');
   final catalog = (snapshot['products'] as List).cast<Map>();
   final accounts = (snapshot['accounts'] as List).cast<Map>();
   final history = (snapshot['history'] as List).cast<Map>();
   expect(catalog.singleWhere((item) => item['name'] == 'Shirt')['quantity'], await stock());
   expect(accounts.singleWhere((account) => account['name'] == 'Cash')['balance'], await balance(cash));
   expect(history.single['kind'], 'sale');
   expect(history.single['total'], 200);
   expect(history.single['paid'], 200);
   final lines = (history.single['lines'] as List).cast<Map>();
   expect(lines.single['item_name'], 'Shirt');
   expect(lines.single['qty'], 2);
   await expectLater(SharedPosOpeningImport.prepare('WRONG'), throwsStateError);
  } finally {
   await app.deleteVoucher(kind:'sale',id:sale);
  }
 });
 test('approved offline checkout commits the existing invoice, cash, stock and one upload together',()async{
  final store=OfflineStockStore(shop:'checkout-shop',device:'checkout-device');
  await OfflineStockStore.ensureTables(db);
  const cloudProduct='00000000-0000-4000-8000-000000000001';
  const cloudAccount='00000000-0000-4000-8000-000000000002';
  final snapshot=<String,dynamic>{'currency':'MMK','accounts':[{'id':cloudAccount,'kind':'cash'}]};
  await store.applySnapshot(db,[
    {'id':cloudProduct,'device_granted':1,'device_consumed':0},
  ],snapshot:snapshot);
  final checkout=StockSyncCheckout(
    store:store,localBranchId:branch,products:{product:cloudProduct},cashAccounts:{cash:cloudAccount},
  );
  final draft=await app.saveSaleDraft(branchId:branch,saveCustomer:false,customerName:'',customerPhone:'',customerCompany:'',customerAddress:'',employeeId:employee,invoiceDate:day,discountType:'amount',discountValue:15,items:[{'product_id':product,'qty':2,'price':100}]);
  final revision=(await app.getSaleDraft(draft))['revision'] as int;
  Future<int> confirm()=>app.confirmSaleDraft(draftId:draft,revision:revision,paymentDate:day,payments:[{'account_id':cash,'amount':185}],offlineCheckout:checkout);
  final beforeStock=await stock(), beforeCash=await balance(cash);
  await expectLater(confirm(),throwsStateError);
  expect(await stock(),beforeStock);
  expect(await balance(cash),beforeCash);
  expect(await db.query('sale_invoices',where:'draft_id=?',whereArgs:[draft]),isEmpty);
  expect(await store.pending(db),isEmpty);
  await store.applySnapshot(db,[{'id':cloudProduct,'device_granted':2,'device_consumed':0}],snapshot:snapshot);
  final id=await confirm();
  expect(await confirm(),id);
  expect(await stock(),beforeStock-2);
  expect(await balance(cash),beforeCash+185);
  expect(await store.remaining(db,cloudProduct),0);
  final pending=(await store.pending(db)).single;
  expect(pending.command['lines'],[{'product_id':cloudProduct,'quantity':2,'unit_minor':100,'line_minor':185}]);
  expect(pending.command['payments'],[{'account_id':cloudAccount,'amount_minor':185}]);
  expect(pending.command['voucher'],isNotEmpty);
  expect((await app.getConfirmedSale(id))['total'],185);
  await expectLater(app.deleteVoucher(kind:'sale',id:id),throwsStateError);
  expect(await stock(),beforeStock-2);
  expect(await balance(cash),beforeCash+185);
 });

 test('online checkout retries the same server operation after an accepted request loses its reply',()async{
  final store=OfflineStockStore(shop:'online-shop',device:'online-device');
  await OfflineStockStore.ensureTables(db);
  const cloudProduct='00000000-0000-4000-8000-000000000011';
  const cloudAccount='00000000-0000-4000-8000-000000000012';
  await store.applySnapshot(db,[
    {'id':cloudProduct,'device_granted':0,'device_consumed':0},
  ],snapshot:{'currency':'MMK','accounts':[{'id':cloudAccount,'kind':'cash'}]});
  final api=_OnlineSaleApi();
  addTearDown(api.client.dispose);
  final checkout=StockSyncCheckout(
    store:store,localBranchId:branch,products:{product:cloudProduct},
    cashAccounts:{cash:cloudAccount},onlineApi:api,onlineSecret:'test-secret',
  );
  final draft=await app.saveSaleDraft(branchId:branch,saveCustomer:false,customerName:'',customerPhone:'',customerCompany:'',customerAddress:'',employeeId:employee,invoiceDate:day,discountType:'amount',discountValue:15,items:[{'product_id':product,'qty':2,'price':100}]);
  final revision=(await app.getSaleDraft(draft))['revision'] as int;
  Future<int> confirm(StockSyncCheckout? mode)=>app.confirmSaleDraft(draftId:draft,revision:revision,paymentDate:day,payments:[{'account_id':cash,'amount':185}],offlineCheckout:mode);
  final beforeStock=await stock(), beforeCash=await balance(cash);
  await expectLater(confirm(checkout),throwsStateError);
  expect(await stock(),beforeStock);
  expect(await balance(cash),beforeCash);
  expect(await db.query('sale_invoices',where:'draft_id=?',whereArgs:[draft]),isEmpty);
  await expectLater(confirm(null),throwsStateError);
  final sale=await confirm(checkout);
  expect(await confirm(checkout),sale);
  expect(api.operationIds,hasLength(2));
  expect(api.operationIds.toSet(),hasLength(1));
  expect(api.commands.first,api.commands.last);
  expect(api.commands.first['offline'],isFalse);
  expect(await stock(),beforeStock-2);
  expect(await balance(cash),beforeCash+185);
  expect(await store.pending(db),isEmpty);
 });

}

class _OnlineSaleApi extends StockSyncApi {
  _OnlineSaleApi() : super(SupabaseClient('https://example.invalid','test-publishable'));

  final operationIds=<String>[];
  final commands=<Map<String,Object?>>[];

  @override
  Future<void> post({
    required String shop,
    required String device,
    required String secret,
    required String operation,
    required Map<String,Object?> command,
  }) async {
    operationIds.add(operation);
    commands.add(command);
    if(operationIds.length==1) throw TimeoutException('Response lost after posting');
  }
}
