import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/subscription_billing_service.dart';
void main(){
 const business='11111111-1111-4111-8111-111111111111';
 const other='22222222-2222-4222-8222-222222222222';
 const id='33333333-3333-4333-8333-333333333333';
 Uint8List image()=>base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8//8/AwMDEwMDAwMDAwAkBgMB/DXemwAAAABJRU5ErkJggg==');
 Map<String,dynamic> row()=>{'id':id,'business_id':business,'object_name':'$business/$id.png','bytes':image().length,'sha256':sha256.convert(image()).toString(),'mime':'image/png'};
 test('Document download binds bytes, digest, MIME and business path',(){
  BillingService.verify(row(),image());
  expect(()=>BillingService.validateDocument(row(),business:other),throwsFormatException);
  expect(()=>BillingService.validateDocument({...row(),'object_name':'$other/$id.png'}),throwsFormatException);
  expect(()=>BillingService.validateDocument({...row(),'object_name':'../$id.png'}),throwsFormatException);
  final changed=image();changed[20]=1;
  expect(()=>BillingService.verify(row(),changed),throwsFormatException);
  expect(()=>BillingService.verify({...row(),'bytes':100},image()),throwsFormatException);
 });
 test('Only bounded JPG and PNG signatures are accepted',(){
  expect(BillingImage.parse(image()).mime,'image/png');
  expect(BillingImage.parse(base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAACAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==')).mime,'image/jpeg');
  expect(()=>BillingImage.parse(Uint8List.fromList('%PDF sample content not accepted'.codeUnits)),throwsFormatException);
  expect(()=>BillingImage.parse(Uint8List(BillingImage.maxBytes+1)),throwsFormatException);
  expect(()=>BillingImage.parse(Uint8List(4)),throwsFormatException);
  final oversized=image();ByteData.sublistView(oversized).setUint32(16,10001);
  expect(()=>BillingImage.parse(oversized),throwsFormatException);
 });
 test('Percentage editor uses integer basis points and rejects ambiguous values',(){
  expect(BillingService.discountBps('15'),1500);
  expect(BillingService.discountBps('15.25'),1525);
  expect(BillingService.discountBps('0'),0);
  expect(BillingService.discountBps('99.99'),9999);
  for(final value in ['100','-1','15.555','abc','1e2','15,25']){
   expect(()=>BillingService.discountBps(value),throwsFormatException);
  }
 });
}
