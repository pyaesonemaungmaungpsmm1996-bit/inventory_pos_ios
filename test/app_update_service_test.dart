// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:inventory_pos/app_update_policy.dart';
import 'package:inventory_pos/app_update_service.dart';

class FakeDriver implements UpdateDriver {
  int checks = 0, downloads = 0, installs = 0, build = 2;
  bool fail = false;
  InstallStatus status = InstallStatus.unknown;
  AppUpdateResult result = AppUpdateResult.success;
  Completer<AppUpdateResult>? pendingDownload;
  @override
  Future<AppUpdateInfo> check() async {
    checks++;
    if (fail) throw StateError('offline');
    return AppUpdateInfo(
      updateAvailability: build > 1
          ? UpdateAvailability.updateAvailable
          : UpdateAvailability.updateNotAvailable,
      immediateUpdateAllowed: true,
      immediateAllowedPreconditions: null,
      flexibleUpdateAllowed: true,
      flexibleAllowedPreconditions: null,
      availableVersionCode: build,
      installStatus: status,
      packageName: 'com.test.pos',
      clientVersionStalenessDays: null,
      updatePriority: 0,
    );
  }

  @override
  Future<AppUpdateResult> download() async {
    downloads++;
    return pendingDownload == null ? result : pendingDownload!.future;
  }

  @override
  Future<void> install() async {
    installs++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDriver driver;
  late AppUpdateService service;
  late DateTime now;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    driver = FakeDriver();
    now = DateTime.utc(2026, 11, 14);
    service = AppUpdateService(
      driver: driver,
      supported: true,
      clock: () => now,
      packageInfo: () async => PackageInfo(
        appName: 'POS',
        packageName: 'com.test.pos',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
  });
  tearDown(() => service.dispose());
  test(
    'Later keeps POS usable and suppresses only the same build for 24 hours',
    () async {
      await service.check();
      expect(service.visible, isTrue);
      await service.later();
      expect(service.visible, isFalse);
      expect(driver.downloads, 0);
      expect(driver.installs, 0);
      now = now.add(const Duration(hours: 7));
      await service.check();
      expect(service.visible, isFalse);
      now = now.add(const Duration(hours: 18));
      await service.check();
      expect(service.visible, isTrue);
    },
  );
  test('a newer release overrides an older build deferral', () async {
    await service.check();
    await service.later();
    driver.build = 3;
    await service.check(force: true);
    expect(service.visible, isTrue);
    expect(service.available, 3);
  });
  test('manual check can show an update postponed earlier', () async {
    await service.check();
    await service.later();
    await service.check(manual: true);
    expect(service.visible, isTrue);
  });
  test('network errors do not start a download or lock the app', () async {
    driver.fail = true;
    await service.check();
    expect(service.unavailable, isTrue);
    expect(service.checking, isFalse);
    expect(service.downloading, isFalse);
    expect(driver.downloads, 0);
    expect(driver.installs, 0);
  });
  test('flexible download never installs until the user explicitly chooses install', () async {
    await service.check();
    await service.download();
    expect(service.ready, isTrue);
    expect(driver.installs, 0);
    await service.install();
    expect(driver.installs, 1);
  });
  test('declining Google Play consent defers without installing', () async {
    await service.check();
    driver.result = AppUpdateResult.userDeniedUpdate;
    await service.download();
    expect(service.visible, isFalse);
    expect(service.ready, isFalse);
    expect(driver.installs, 0);
  });
  test(
    'Later during download stays dismissed after download completes',
    () async {
      await service.check();
      driver.pendingDownload = Completer<AppUpdateResult>();
      final downloading = service.download();
      await service.later();
      driver.pendingDownload!.complete(AppUpdateResult.success);
      await downloading;
      expect(service.ready, isTrue);
      expect(service.visible, isFalse);
      expect(driver.installs, 0);
    },
  );
  test('downloaded update after restart offers an optional install', () async {
    driver.status = InstallStatus.downloaded;
    await service.check();
    expect(service.ready, isTrue);
    expect(service.visible, isTrue);
    expect(driver.installs, 0);
  });
  test(
    'background checks are throttled but a push hint can force a fresh check',
    () async {
      await service.check();
      await service.check();
      expect(driver.checks, 1);
      await service.check(force: true);
      expect(driver.checks, 2);
    },
  );
  test('no newer release stays quiet', () async {
    driver.build = 1;
    await service.check();
    expect(service.visible, isFalse);
    expect(service.unavailable, isFalse);
  });
  test(
    'store links use only the installed package and topic is deterministic',
    () {
      expect(AppUpdatePolicy.storeUri('com.test.pos').host, 'play.google.com');
      expect(
        AppUpdatePolicy.storeUri('com.test.pos').queryParameters['id'],
        'com.test.pos',
      );
      expect(AppUpdatePolicy.topic('com.test.pos'), 'tp_updates_com_test_pos');
    },
  );
}
