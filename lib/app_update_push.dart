import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_policy.dart';

class AppUpdatePush {
  AppUpdatePush({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();
  static const configured = bool.fromEnvironment(
    'TP_UPDATE_PUSH_ENABLED',
    defaultValue: false,
  );
  static const preferenceKey = 'app_update_push_enabled_v1';
  final SharedPreferencesAsync preferences;
  StreamSubscription<RemoteMessage>? foreground, opened;
  bool initialized = false;
  bool _closed = false;
  Future<void>? _initializing;
  String? topic;
  VoidCallback? onUpdate;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> initialize() async {
    if (_closed || initialized) return;
    if (_initializing != null) return _initializing;
    _initializing = _initialize();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initialize() async {
    if (!supported || !configured) {
      throw StateError('Notifications are not connected yet');
    }
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    final package = (await PackageInfo.fromPlatform()).packageName;
    topic = AppUpdatePolicy.topic(package);
    if (_closed) return;
    void notify(RemoteMessage message) {
      if (message.data['type'] == 'app_update') onUpdate?.call();
    }

    foreground = FirebaseMessaging.onMessage.listen(notify);
    opened = FirebaseMessaging.onMessageOpenedApp.listen(notify);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) notify(initial);
    initialized = true;
  }

  Future<bool> enabled() =>
      preferences.getBool(preferenceKey).then((v) => v ?? false);
  Future<void> start() async {
    try {
      if (!await enabled()) return;
      await initialize();
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      await FirebaseMessaging.instance.subscribeToTopic(topic!);
    } catch (_) {
      /* Startup and ordinary POS work never depend on push. */
    }
  }

  Future<bool> enable() async {
    await initialize();
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    await FirebaseMessaging.instance.subscribeToTopic(topic!);
    await preferences.setBool(preferenceKey, true);
    return true;
  }

  Future<void> disable() async {
    await initialize();
    await FirebaseMessaging.instance.unsubscribeFromTopic(topic!);
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    await FirebaseMessaging.instance.unregister();
    await preferences.setBool(preferenceKey, false);
  }

  Future<void> dispose() async {
    _closed = true;
    onUpdate = null;
    await foreground?.cancel();
    await opened?.cancel();
  }
}
