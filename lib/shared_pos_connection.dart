import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'branch_records_sync.dart';
import 'shared_pos_session.dart';
import 'stock_sync.dart';

typedef SharedBranch = ({String shop, String branch, String code, String label});

class SharedPosConnection {
  SharedPosConnection(this.api, this.userId);

  final StockSyncApi api;
  final String userId;
  static const storage = FlutterSecureStorage();

  static String deviceKey(String user, String shop, String branch) =>
      'tp_stock_sync_${user}_${shop}_$branch';

  Future<List<SharedBranch>> branches() async => [
    for (final shop in await api.catalog())
      for (final branch in (shop['branches'] as List))
        (
          shop: shop['id'] as String,
          branch: branch['id'] as String,
          code: branch['code'] as String,
          label: "${shop['name']} · ${branch['name']} (${branch['code']})",
        ),
  ];

  Future<SharedPosSession?> connect(SharedBranch branch) async {
    final key = deviceKey(userId, branch.shop, branch.branch);
    final raw = await storage.read(key: key);
    final identity = raw == null
        ? {
            'id': newStockSyncId(),
            'label': Platform.operatingSystem,
            'secret': newStockSyncSecret(),
          }
        : Map<String, String>.from(jsonDecode(raw) as Map);
    if (raw == null) {
      await storage.write(key: key, value: jsonEncode(identity));
    }
    final approved = await api.enroll(
      shop: branch.shop,
      branch: branch.branch,
      device: identity['id']!,
      label: identity['label']!,
      secret: identity['secret']!,
    );
    if (!approved) return null;
    final session = SharedPosSession(
      BranchRecordsSync(
        client: api.client,
        shop: branch.shop,
        branchCode: branch.code,
        device: identity['id']!,
        secret: identity['secret']!,
      ),
    );
    await session.load();
    return session;
  }
}
