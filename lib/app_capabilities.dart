import 'package:flutter/foundation.dart';

/// Native camera integrations are not provided by these plugins on Windows.
class AppCapabilities {
  static String get defaultDeviceName => windows ? 'My Windows PC' : 'My phone';
  static bool get windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get camera =>
      kIsWeb ||
      const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);
  static bool get backgroundBackup =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.windows,
      ].contains(defaultTargetPlatform);
}
