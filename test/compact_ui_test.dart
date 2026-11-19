import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pos/app_currency.dart';
import 'package:inventory_pos/app_theme.dart';
import 'package:inventory_pos/app_language.dart';
import 'package:inventory_pos/pos_ui.dart';
import 'package:inventory_pos/pos_navigation_bar.dart';

void main(){
 testWidgets('long amount keeps exact digits in compact accessible summary', (tester)async{
  AppCurrency.current.value='MMK';
  await tester.pumpWidget(MaterialApp(theme:AppTheme.build(Brightness.light),
   builder:(context,child)=>MediaQuery(
    data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.6)),child:child!),
   home:const Scaffold(body:Center(child:SizedBox(width:260,
    child:AmountSummary(label:'Total amount',amount:9000000000000))))));
  expect(find.byType(MoneyText),findsOneWidget);
  final text=tester.widget<Text>(find.descendant(of:find.byType(MoneyText),matching:find.byType(Text)));
  expect(text.textSpan!.toPlainText(),'9,000,000,000,000 Ks');
  expect(tester.takeException(),isNull);
 });
 testWidgets('six bottom destinations retain labels and navigate', (tester)async{
  AppLanguage.current.value='en';int? selected;
  await tester.pumpWidget(MaterialApp(theme:AppTheme.build(Brightness.light),home:Scaffold(bottomNavigationBar:PosNavigationBar(selected:0,onSelected:(i)=>selected=i))));
  for(final label in PosNavigationBar.labels){expect(find.text(label),findsOneWidget);}
  await tester.tap(find.text('Inventory'));expect(selected,2);
  expect(tester.takeException(),isNull);
 });
 testWidgets('dark forms and dialogs use the shared compact theme', (tester)async{
  await tester.pumpWidget(MaterialApp(theme:AppTheme.build(Brightness.dark),home:const Scaffold(body:Column(children:[TextField(decoration:InputDecoration(labelText:'Amount')),Card(child:ListTile(title:Text('Settings')))]))));
  expect(tester.takeException(),isNull);
 });
}
