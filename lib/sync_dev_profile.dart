import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SyncDevProfile {
  static const enabled = bool.fromEnvironment('TP_SYNC_DEV');
  static const url = 'https://ejhpsipqkhxddqjofhgk.supabase.co';
  static const key = String.fromEnvironment('TP_SYNC_DEV_PUBLISHABLE_KEY');
  static const supportFolder = 'Toe Pwar POS Sync Dev';
  static const iosBundleId = 'com.example.inventoryPos.syncdev';

  static Future<void> verify() async {
    final bool isolated;
    if (Platform.isWindows) {
      final support = await getApplicationSupportDirectory();
      isolated = p.basename(support.path) == supportFolder;
    } else if (Platform.isIOS) {
      isolated = (await PackageInfo.fromPlatform()).packageName == iosBundleId;
    } else {
      isolated = false;
    }
    if (enabled != isolated) {
      throw StateError(
        'Sync Dev build and application data profile do not match.',
      );
    }
    if (enabled && !key.startsWith('sb_publishable_')) {
      throw StateError('The Sync Dev Supabase publishable key is required.');
    }
  }
}
