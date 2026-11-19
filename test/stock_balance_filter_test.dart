import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_language.dart';
import 'package:inventory_pos/stock_balance_filter.dart';
void main(){
 testWidgets('quick-action branch waits safely for choices then selects the requested branch',(tester)async{
  AppLanguage.current.value='en';final changes=<int>[];
  Widget screen(List<Map<String,Object?>> rows,bool loading)=>MaterialApp(home:Scaffold(body:StockBalanceFilter(
   title:'Branch',value:1,data:rows,loading:loading,onChanged:changes.add)));
  await tester.pumpWidget(screen([],true));
  expect(tester.takeException(),isNull);
  expect(tester.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>)).initialValue,isNull);
  expect(changes,isEmpty);
  await tester.pumpWidget(screen([{'id':1,'name':'Pazundaung'},{'id':2,'name':'Other branch'}],false));
  expect(tester.takeException(),isNull);
  expect(tester.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>)).initialValue,1);
  expect(find.text('Pazundaung'),findsOneWidget);expect(changes,isEmpty);
 });
 testWidgets('missing branch after load never silently selects All',(tester)async{
  AppLanguage.current.value='en';final changes=<int>[];
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:StockBalanceFilter(title:'Branch',value:99,
   data:const[{'id':1,'name':'Pazundaung'}],loading:false,onChanged:changes.add))));
  expect(tester.takeException(),isNull);
  expect(tester.widget<DropdownButtonFormField<int>>(find.byType(DropdownButtonFormField<int>)).initialValue,isNull);
  expect(changes,isEmpty);
  expect(find.text('Selected filter is unavailable. Retry or choose another.'),findsOneWidget);
 });
}
