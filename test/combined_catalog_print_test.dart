import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/invoice_print_model.dart';
import 'package:inventory_pos/invoice_print_settings.dart';

void main(){
 final sale=<String,Object?>{'id':3,'business_name':'Shop','invoice_date':'2026-11-13','confirmed_at':'2026-11-13T12:00:00Z','status':'posted','branch_name_snapshot':'BRANCH-SECRET','branch_code_snapshot':'A','customer_name':'CUSTOMER-SECRET','subtotal':200,'discount_amount':0,'total':200,'paid':200,'balance_due':0,'items':[{'product_id':5,'item_code':'CODE-SECRET','item_name':'Shirt','qty':1,'price':200,'amount':200,'tracking_json':'[]'}],'business_logo':Uint8List.fromList([1]),'item_images':{5:Uint8List.fromList([2])}};
 test('older print preferences retain compatible defaults and new settings round trip',(){
  final old=InvoicePrintSettings.fromJson({'paper':'receipt80','language':'en','width':80,'height':200,'payments':true,'sale_person':true,'footer':''});
  expect(old.showItemPhotos,isFalse);expect(old.showLogo,isTrue);
  const customized=InvoicePrintSettings(paper:'a4',showLogo:false,showItemPhotos:true,showCustomer:false,showBranch:false,showDate:false,showItemCode:false,showPrices:false,showDiscount:false,layout:'compact');
  final restored=InvoicePrintSettings.fromJson(customized.toJson());
  expect(restored.toJson(),customized.toJson());expect(restored.narrow,isTrue);
  expect(const InvoicePrintSettings().showItemPhotos,isFalse);
 });
 test('field and image switches are independent without changing totals or saved data',(){
  const settings=InvoicePrintSettings(paper:'a4',showLogo:false,showItemPhotos:true,showCustomer:false,showBranch:false,showDate:false,showItemCode:false,showPrices:false,showDiscount:false);
  final rows=invoicePrintRows(sale,settings,myanmar:false);
  final text=rows.expand((r)=>r.cells).join('\n');
  expect(rows.where((r)=>r.picture!=null).single.picture,orderedEquals([2]));
  for(final hidden in ['CUSTOMER-SECRET','BRANCH-SECRET','CODE-SECRET','Discount:','Invoice date']){expect(text,isNot(contains(hidden)));}
  expect(text,contains('Total: 200 Ks'));expect(text,contains('Paid: 200 Ks'));
  expect((sale['items'] as List).single['price'],200);
  final logoOnly=invoicePrintRows(sale,const InvoicePrintSettings(),myanmar:false);
  expect(logoOnly.where((r)=>r.picture!=null).single.picture,orderedEquals([1]));
 });
 test('invalid layout and dimensions fail before rendering',(){
  expect(()=>const InvoicePrintSettings(layout:'bad').validate(),throwsFormatException);
  expect(()=>const InvoicePrintSettings(customWidthMm:20).validate(),throwsFormatException);
 });
}
