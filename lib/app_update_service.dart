import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_policy.dart';

abstract class UpdateDriver {
  Future<AppUpdateInfo> check();
  Future<AppUpdateResult> download();
  Future<void> install();
}

class PlayUpdateDriver implements UpdateDriver {
  @override
  Future<AppUpdateInfo> check() => InAppUpdate.checkForUpdate();
  @override
  Future<AppUpdateResult> download() => InAppUpdate.startFlexibleUpdate();
  @override
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    UpdateDriver? driver,
    Future<PackageInfo> Function()? packageInfo,
    SharedPreferencesAsync? preferences,
    DateTime Function()? clock,
    bool? supported,
  }) : driver = driver ?? PlayUpdateDriver(),
       packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       preferences = preferences ?? SharedPreferencesAsync(),
       clock = clock ?? DateTime.now,
       supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  final UpdateDriver driver;
  final Future<PackageInfo> Function() packageInfo;
  final SharedPreferencesAsync preferences;
  final DateTime Function() clock;
  final bool supported;
  static const deferredBuildKey = 'app_update_deferred_build_v1',
      deferredUntilKey = 'app_update_deferred_until_v1';
  bool checking = false,
      downloading = false,
      ready = false,
      visible = false,
      unavailable = false,
      availableUpdate = false;
  int? available;
  String? packageName;
  DateTime? lastCheck;
  AppUpdateInfo? info;
  bool _closed = false;
  void changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> check({bool manual = false, bool force = false}) async {
    if (_closed || !supported || checking || downloading) return;
    if (!manual &&
        !force &&
        lastCheck != null &&
        clock().difference(lastCheck!) < AppUpdatePolicy.checkInterval) {
      return;
    }
    checking = true;
    unavailable = false;
    changed();
    try {
      final local = await packageInfo().timeout(const Duration(seconds: 10));
      final result = await driver.check().timeout(const Duration(seconds: 15));
      if (_closed) return;
      if (result.packageName != local.packageName) {
        throw StateError('Package mismatch');
      }
      lastCheck = clock();
      info = result;
      packageName = local.packageName;
      available = result.availableVersionCode;
      final installed = int.tryParse(local.buildNumber) ?? 0;
      ready = result.installStatus == InstallStatus.downloaded;
      final update =
          result.updateAvailability == UpdateAvailability.updateAvailable ||
          ready;
      availableUpdate = update;
      final deferred = await preferences.getInt(deferredBuildKey);
      final until = DateTime.tryParse(
        await preferences.getString(deferredUntilKey) ?? '',
      );
      if (_closed) return;
      visible =
          update &&
          (manual ||
              (available != null &&
                  AppUpdatePolicy.shouldPrompt(
                    installed: installed,
                    available: available!,
                    now: clock(),
                    deferredBuild: deferred,
                    deferredUntil: until,
                  )));
    } catch (_) {
      unavailable = true; /* Offline or sideloaded builds must remain usable. */
    } finally {
      checking = false;
      changed();
    }
  }

  Future<void> later() async {
    visible = false;
    changed();
    if (available == null) return;
    try {
      await preferences.setInt(deferredBuildKey, available!);
      await preferences.setString(
        deferredUntilKey,
        clock().add(AppUpdatePolicy.snooze).toIso8601String(),
      );
    } catch (_) {
      /* Dismiss still works if preferences cannot be saved. */
    }
  }

  Future<bool> openStore() async {
    try {
      packageName ??= (await packageInfo()).packageName;
      return await launchUrl(
        AppUpdatePolicy.storeUri(packageName!),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> download() async {
    if (downloading || checking) return;
    if (info?.flexibleUpdateAllowed != true) {
      if (!await openStore()) {
        unavailable = true;
        changed();
      }
      return;
    }
    downloading = true;
    unavailable = false;
    changed();
    try {
      final result = await driver.download();
      if (_closed) return;
      if (result == AppUpdateResult.success) {
        ready = true;
        // Keep a Later decision made while the download was running.
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        await later();
      } else {
        unavailable = true;
      }
    } catch (_) {
      unavailable = true;
    } finally {
      downloading = false;
      changed();
    }
  }

  Future<void> install() async {
    if (!ready) return;
    try {
      await driver.install();
    } catch (_) {
      unavailable = true;
      changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
