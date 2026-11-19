import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/invoice_print_model.dart';
import 'package:inventory_pos/invoice_print_settings.dart';
void main(){
 test('customer invoice hides internal collection records while retaining paid and due',(){
  final sale=<String,Object?>{'id':1,'business_name':'Test Shop','invoice_date':'2026-11-11','confirmed_at':'2026-11-11T01:00:00Z','status':'posted','branch_name_snapshot':'A','branch_code_snapshot':'A','customer_name':'Customer','subtotal':100,'discount_amount':0,'total':100,'paid':80,'balance_due':20,
   'items':<Map<String,Object?>>[{'item_code':'A1','item_name':'Phone','qty':1,'price':100,'amount':100,'tracking_json':'[{"serial":"SERIAL-1","imei":"123456789012345","warranty_until":"2027-11-11"}]'}],
   'payments':[{'payment_date':'2026-11-11','account_name':'INTERNAL-ACCOUNT','amount':80,'created_at':'2026-11-11T01:00:00Z'}],
   'collections':[{'receipt_id':9,'payment_date':'2026-11-11','received_at':'2026-11-11T01:00:00Z','amount':20,'status':'posted'}]};
  final text=invoicePrintRows(sale,const InvoicePrintSettings(showPayments:true),myanmar:false).expand((r)=>r.cells).join('\n');
  expect(text,contains('Paid: 80 Ks'));expect(text,contains('Credit due: 20 Ks'));
  expect(text,contains('SERIAL-1'));expect(text,contains('123456789012345'));expect(text,contains('Warranty until: 2027-11-11'));
  for(final secret in ['INTERNAL-ACCOUNT','Recorded at','Payment status at printing','RCPT-']){expect(text, isNot(contains(secret)));}
  expect((sale['payments'] as List).length,1);
 });
}
