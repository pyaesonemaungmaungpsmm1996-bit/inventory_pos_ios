import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inventory_pos/stock_sync.dart';
import 'package:inventory_pos/stock_sync_login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://stock-sync.example.test';
  const storageKey = 'tp_stock_sync_session:stock-sync.example.test';
  const storage = FlutterSecureStorage();

  Map<String, dynamic> fixtureSession(Duration validFor, String refreshToken) {
    final expiry = DateTime.now().add(validFor).millisecondsSinceEpoch ~/ 1000;
    final payload = base64UrlEncode(utf8.encode(jsonEncode({'exp': expiry})));
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
      'refresh_token': refreshToken,
      'token_type': 'bearer',
      'user': {
        'id': 'fixture-owner',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-11-23T00:00:00Z',
      },
    };
  }

  test(
    'restores the same account on app restart and clears it on sign out',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = StockSyncApi.connect(url, 'sb_publishable_fixture');
      addTearDown(first.dispose);
      await StockSyncLogin(url, first).remember(
        Session.fromJson(
          fixtureSession(const Duration(hours: 1), 'fixture-refresh'),
        )!,
      );
      final requests = <String>[];
      final restarted = StockSyncApi.connect(
        url,
        'sb_publishable_fixture',
        httpClient: MockClient((request) async {
          requests.add(request.url.path);
          return http.Response('', 204);
        }),
      );
      addTearDown(restarted.dispose);
      final login = StockSyncLogin(url, restarted);
      expect((await login.restore())?.user.id, 'fixture-owner');
      expect(requests, isEmpty);
      await login.signOut();
      expect(await storage.read(key: storageKey), isNull);
      expect(await login.restore(), isNull);
    },
  );

  test(
    'restores expired sessions using refresh token and stores its replacement',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        storageKey: jsonEncode(
          fixtureSession(const Duration(hours: -1), 'fixture-old'),
        ),
      });
      final client = StockSyncApi.connect(
        url,
        'sb_publishable_fixture',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['grant_type'], 'refresh_token');
          return http.Response(
            jsonEncode(fixtureSession(const Duration(hours: 1), 'fixture-new')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        (await StockSyncLogin(url, client).restore())?.user.id,
        'fixture-owner',
      );
      final stored = jsonDecode((await storage.read(key: storageKey))!) as Map;
      expect(stored['refresh_token'], 'fixture-new');
    },
  );
}
