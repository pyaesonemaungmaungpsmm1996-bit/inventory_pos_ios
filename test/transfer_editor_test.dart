import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:inventory_pos/app_database.dart';
import 'package:inventory_pos/subscription_runtime.dart';
import 'package:inventory_pos/transfer_vouchers_page.dart';
void main(){
 late Directory dir;late List<Map<String,Object?>> branches;late int source;
 setUpAll(()async{
  ffi.sqfliteFfiInit();sq.databaseFactory=ffi.databaseFactoryFfi;dir=await Directory.systemTemp.createTemp('tp-transfer-ui-');await sq.databaseFactory.setDatabasesPath(dir.path);
  await SubscriptionRuntime.bind({'business_id':'ui','owner_id':'fixture','plan':'premium','server_now':DateTime.now().toUtc().toIso8601String(),'ends_at':DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String()},null,null);
  final app=AppDatabase.instance;await app.saveBusinessProfile(name:'UI test',countryCode:'MM',currencyCode:'MMK');await app.saveBranch(code:'A',name:'Source',phone:'',address:'');await app.saveBranch(code:'B',name:'Destination',phone:'',address:'');branches=await app.getBranches();source=branches.first['id'] as int;
  for(final code in ['BLACK-M','RED-L']){final id=await app.addProduct(name:'Shirt',price:100,stock:5,branchId:source,itemCode:code);await (await app.database).update('products',{'color':code.split('-').first,'size':code.split('-').last},where:'id=?',whereArgs:[id]);}
 });
 tearDownAll(()async{await (await AppDatabase.instance.database).close();await dir.delete(recursive:true);});
 testWidgets('phone editor adds two Color/Size variants to one draft without changing stock',(tester)async{
  tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(()async{await tester.pumpWidget(MaterialApp(home:TransferEditor(source:source,branches:branches)));await Future<void>.delayed(const Duration(milliseconds:150));});await tester.pumpAndSettle();
  for(final code in ['BLACK-M','RED-L']){
   await tester.tap(find.text('Add item / IMEI / Serial'));await tester.pumpAndSettle();await tester.tap(find.text('$code · Shirt'));
   await tester.runAsync(()async{await Future<void>.delayed(const Duration(milliseconds:150));});await tester.pumpAndSettle();
   await tester.tap(find.text('Add / Update'));await tester.pumpAndSettle();
  }
  expect(find.text('BLACK-M · Shirt × 1'),findsOneWidget);expect(find.text('RED-L · Shirt × 1'),findsOneWidget);expect(tester.takeException(),isNull);
  await tester.runAsync(()async{expect(await (await AppDatabase.instance.database).query('transfer_vouchers'),isEmpty);});
  await tester.pumpWidget(const SizedBox.shrink());
 });
}
