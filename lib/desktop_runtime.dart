import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Keep writable data outside the installation folder, including Program Files.
class DesktopRuntime {
  static Future<void>? _ready;
  static Future<void> initialize({
    Directory? supportDirectory,
    bool? windows,
  }) async {
    if (!(windows ?? Platform.isWindows)) return;
    final pending = _ready ??= _initialize(supportDirectory);
    try {
      await pending;
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  static Future<void> _initialize(Directory? override) async {
    final support = override ?? await getApplicationSupportDirectory();
    final data = Directory(p.join(support.path, 'local_data'));
    await data.create(recursive: true);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(data.path);
  }
}
