// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:inventory_pos/app_database.dart';
import 'package:inventory_pos/app_language.dart';
import 'package:inventory_pos/dashboard_page.dart';
import 'package:inventory_pos/main.dart';
import 'package:inventory_pos/pos_navigation_bar.dart';
import 'package:inventory_pos/provider_connection.dart';
import 'package:inventory_pos/subscription_runtime.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    folder = await Directory.systemTemp.createTemp('tp-navigation-test-');
    await databaseFactory.setDatabasesPath(folder.path);
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // This local navigation test must not start network heartbeats or timers.
    ProviderConnection.instance.started = true;
    await SubscriptionRuntime.bind(
      {
        'business_id': 'navigation-fixture',
        'owner_id': 'fixture-owner',
        'plan': 'premium',
        'server_now': DateTime.now().toUtc().toIso8601String(),
        'ends_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 1))
            .toIso8601String(),
      },
      null,
      null,
    );
    await AppDatabase.instance.saveBusinessProfile(
      name: 'Test business',
      countryCode: 'MM',
      currencyCode: 'MMK',
    );
    await AppDatabase.instance.saveBranch(
      code: 'TEST',
      name: 'Test branch',
      phone: '',
      address: '',
    );
  });
  tearDownAll(() async {
    await (await AppDatabase.instance.database).close();
    await folder.delete(recursive: true);
    ProviderConnection.instance.started = false;
  });
  testWidgets('Navigation menus open the correct page', (tester) async {
    AppLanguage.current.value = 'en';
    await tester.pumpWidget(const InventoryPosApp());
    await tester.runAsync(
      () =>
          tester.state<DashboardPageState>(find.byType(DashboardPage)).reload(),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'TP POS'), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
    const pages = {
      'Sale': 'Sale Invoices',
      'Inventory': 'Item Name',
      'Expense': 'Expense Summary',
      'Ledger': 'Sales Reports',
      'Settings': 'Business & app settings',
      'Dashboard': '',
    };
    for (final entry in pages.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(PosNavigationBar),
          matching: find.text(entry.key),
        ),
      );
      if (entry.key == 'Dashboard') {
        await tester.pump();
        await tester.runAsync(
          () => tester
              .state<DashboardPageState>(find.byType(DashboardPage))
              .reload(),
        );
      } else {
        await tester.runAsync(() => AppDatabase.instance.getBusinessProfile());
      }
      await tester.pumpAndSettle();
      final navigation = tester.widget<PosNavigationBar>(
        find.byType(PosNavigationBar),
      );
      expect(PosNavigationBar.labels[navigation.selected], entry.key);
      if (entry.key == 'Dashboard') {
        expect(find.byType(DashboardPage), findsOneWidget);
      } else {
        expect(find.text(entry.value), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
