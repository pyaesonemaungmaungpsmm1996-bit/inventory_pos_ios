// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:inventory_pos/app_language.dart';
import 'package:inventory_pos/app_updates_page.dart';
import 'package:inventory_pos/app_update_service.dart';

import 'app_update_service_test.dart' show FakeDriver;

void main() {
  late AppUpdateService service;
  late FakeDriver driver;
  setUp(() {
    AppLanguage.current.value = 'en';
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    driver = FakeDriver();
    service = AppUpdateService(
      driver: driver,
      supported: true,
      packageInfo: () async => PackageInfo(
        appName: 'POS',
        packageName: 'com.test.pos',
        version: '1',
        buildNumber: '1',
      ),
    );
  });
  tearDown(() {
    service.dispose();
    AppLanguage.current.value = 'en';
  });
  testWidgets('Later dismisses banner while ordinary work remains usable', (
    tester,
  ) async {
    var taps = 0;
    await service.check();
    await tester.pumpWidget(
      MaterialApp(
        home: OptionalUpdateHost(
          service: service,
          child: Scaffold(
            body: TextButton(
              onPressed: () => taps++,
              child: const Text('New sale'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('New sale'));
    await tester.tap(find.text('Later'));
    await tester.pump();
    expect(find.text('Later'), findsNothing);
    expect(find.text('New sale'), findsOneWidget);
    expect(taps, 1);
    expect(driver.downloads, 0);
    expect(driver.installs, 0);
  });
  testWidgets('download needs a separate restart action to install', (
    tester,
  ) async {
    await service.check();
    await tester.pumpWidget(
      MaterialApp(home: AppUpdatesPage(service: service)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Restart & update'), findsOneWidget);
    expect(driver.downloads, 1);
    expect(driver.installs, 0);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(driver.installs, 0);
    expect(
      find.text('No newer update is available to this device on Google Play.'),
      findsNothing,
    );
  });
  testWidgets('Myanmar page has readable update controls', (tester) async {
    AppLanguage.current.value = 'my';
    await service.check();
    await tester.pumpWidget(
      MaterialApp(home: AppUpdatesPage(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('App Update များ'), findsOneWidget);
    expect(find.text('နောက်မှ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Later in Settings also dismisses the shared home banner', (
    tester,
  ) async {
    await service.check();
    await tester.pumpWidget(
      MaterialApp(
        home: OptionalUpdateHost(
          service: service,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AppUpdatesPage(
                      service: OptionalUpdateHost.serviceOf(context),
                    ),
                  ),
                ),
                child: const Text('Open settings'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
    expect(service.visible, isFalse);
    expect(driver.installs, 0);
  });
}
