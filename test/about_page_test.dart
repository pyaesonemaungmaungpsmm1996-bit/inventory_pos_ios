import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:inventory_pos/about_page.dart';
import 'package:inventory_pos/app_language.dart';

void main(){
 testWidgets('About displays installed package version and publisher',(tester)async{
  AppLanguage.current.value='en';
  PackageInfo.setMockInitialValues(appName:'TP POS',packageName:'com.example.tp_pos',version:'2.4.1',buildNumber:'73',buildSignature:'');
  await tester.pumpWidget(const MaterialApp(home:AboutPage()));
  await tester.pumpAndSettle();
  expect(find.text('2.4.1'),findsOneWidget);
  expect(find.text('73'),findsOneWidget);
  expect(find.text('PSM IT Company'),findsNWidgets(2));
  expect(tester.takeException(),isNull);
 });
}
