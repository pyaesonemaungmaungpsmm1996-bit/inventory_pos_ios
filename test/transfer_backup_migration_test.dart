import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:inventory_pos/app_database.dart';
import 'package:inventory_pos/sqlite_backup.dart';
import 'package:inventory_pos/subscription_runtime.dart';
void main(){test('real v40 backup restores and upgrades to v41 without losing stock',()async{
 ffi.sqfliteFfiInit();sq.databaseFactory=ffi.databaseFactoryFfi;final dir=await Directory.systemTemp.createTemp('tp-transfer-migration-');await sq.databaseFactory.setDatabasesPath(dir.path);
 await SubscriptionRuntime.bind({'business_id':'migration','owner_id':'fixture','plan':'premium','server_now':DateTime.now().toUtc().toIso8601String(),'ends_at':DateTime.now().toUtc().add(const Duration(days:1)).toIso8601String()},null,null);
 final app=AppDatabase.instance;await app.saveBusinessProfile(name:'Migration',countryCode:'MM',currencyCode:'MMK');await app.saveBranch(code:'A',name:'A',phone:'',address:'');final branch=(await app.getBranches()).single['id'] as int;
 await app.addProduct(name:'Phone',price:100,stock:5,branchId:branch);final db=await app.database;expect(await db.getVersion(),41);final schema=await SqliteBackup.schema(db);
 final file=p.join(dir.path,'v40.tppos');await SqliteBackup.create(db,file);final old=await sq.openDatabase(file,singleInstance:false);
 await old.execute('DROP TABLE transfer_voucher_lots');await old.execute('DROP TABLE transfer_voucher_items');await old.execute('DROP TABLE transfer_vouchers');await old.setVersion(40);await old.close();
 expect((await SqliteBackup.inspect(file,expectedSchema:schema,expectedVersion:41)).version,40);
 await app.restoreLocalBackup(file);final restored=await app.database;expect(await restored.getVersion(),41);expect((await restored.query('branch_stocks')).single['stock'],5);expect(await restored.query('transfer_vouchers'),isEmpty);expect(await SqliteBackup.schema(restored),schema);await restored.close();await dir.delete(recursive:true);
 });}
