import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/amount_input.dart';
import 'package:inventory_pos/app_currency.dart';
void main(){
 const formatter=AmountInputFormatter();
 TextEditingValue value(String s,int cursor)=>TextEditingValue(text:s,selection:TextSelection.collapsed(offset:cursor));
 test('typing, paste, middle edit and grouped parsing retain exact minor units',(){
  expect(formatter.formatEditUpdate(value('100',3),value('1000',4)).text,'1,000');
  expect(formatter.formatEditUpdate(value('',0),value('1234567.89',10)).text,'1,234,567.89');
  final middle=formatter.formatEditUpdate(value('12,345',2),value('129,345',3));
  expect(middle.text,'129,345');expect(middle.selection.baseOffset,3);
  expect(AppCurrency.tryParse('1,234,567',currency:'MMK'),1234567);
  expect(AppCurrency.tryParse('1,234.56',currency:'USD'),123456);
  expect(AppCurrency.tryParse('12,34',currency:'MMK'),isNull);
  expect(AppCurrency.tryParse('1,234.5',currency:'MMK'),isNull);
 });
 test('backspace immediately after a comma deletes a digit and never sticks',(){
  final result=formatter.formatEditUpdate(value('1,000',2),value('1000',1));
  expect(result.text,'000');expect(result.selection.baseOffset,0);
 });
 test('rejects exponent and preserves active composing input',(){
  expect(formatter.formatEditUpdate(value('12',2),value('12e3',4)).text,'12');
  const composing=TextEditingValue(text:'1000',composing:TextRange(start:0,end:4));
  expect(formatter.formatEditUpdate(TextEditingValue.empty,composing),composing);
 });
}
