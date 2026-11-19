import 'cloud_proxy_client.dart';

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnlineAccounts {
  static const url = 'https://hylxyyzwsppaufzmqcbg.supabase.co';
  // Client-side publishable key. Never put a secret/service-role key here.
  static const key = 'sb_publishable_LofdBSh-6F93h-ypBMZ7NA_7wPemrNo';
  static Future<void>? _ready;
  static Future<void> initialize() => _ready ??= _initialize();
  static Future<void> _initialize() async {
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        httpClient: CloudProxyClient.forBuild(),
      );
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
  static const roles = ['manager', 'cashier', 'stock', 'accountant'];
  static const roleDescriptions = {
    'owner': 'Owner · account administration',
    'manager': 'Manager · branch operations',
    'cashier': 'Cashier · sales and receipts',
    'stock': 'Stock staff · inventory and transfers',
    'accountant': 'Accountant · money and reports',
  };
  static Future<List<Map<String, dynamic>>> snapshot() async {
    final rows = await client.rpc('tp_account_snapshot');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<String> installation() async {
    final storage = SharedPreferencesAsync();
    final stored = await storage.getString('tp_installation_id');
    if (stored != null &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(stored)) {
      return stored;
    }
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final id =
        '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    await storage.setString('tp_installation_id', id);
    return id;
  }
}
