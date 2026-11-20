import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SyncDevProfile {
  static const enabled = bool.fromEnvironment('TP_SYNC_DEV');
  static const url = 'https://ejhpsipqkhxddqjofhgk.supabase.co';
  static const key = String.fromEnvironment('TP_SYNC_DEV_PUBLISHABLE_KEY');
  static const supportFolder = 'Toe Pwar POS Sync Dev';

  static Future<void> verify() async {
    if (!Platform.isWindows) {
      if (enabled) {
        throw UnsupportedError('Sync Dev requires the isolated Windows build.');
      }
      return;
    }
    final support = await getApplicationSupportDirectory();
    final isolated = p.basename(support.path) == supportFolder;
    if (enabled != isolated) {
      throw StateError(
        'Sync Dev build and Windows application data profile do not match.',
      );
    }
    if (enabled && !key.startsWith('sb_publishable_')) {
      throw StateError('The Sync Dev Supabase publishable key is required.');
    }
  }
}
