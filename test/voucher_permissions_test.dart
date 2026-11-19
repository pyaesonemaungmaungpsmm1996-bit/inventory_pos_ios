import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/voucher_permissions.dart';
void main(){
 test('edit policy requires the active Owner of this licensed business',(){
  expect(VoucherPermissions.allowsOwner('shop',[{'id':'shop','role':'owner','active':true}]),isTrue);
  for(final role in ['manager','cashier','stock','accountant']){
   expect(VoucherPermissions.allowsOwner('shop',[{'id':'shop','role':role,'active':true}]),isFalse);
  }
  expect(VoucherPermissions.allowsOwner('shop',[{'id':'other','role':'owner','active':true}]),isFalse);
  expect(VoucherPermissions.allowsOwner('shop',[{'id':'shop','role':'owner','active':false}]),isFalse);
  expect(VoucherPermissions.allowsOwner(null,[{'id':null,'role':'owner','active':true}]),isFalse);
  expect(VoucherPermissions.allowsOwner('shop',[]),isFalse);
 });
}
