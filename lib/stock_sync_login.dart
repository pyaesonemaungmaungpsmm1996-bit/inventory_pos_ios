import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'stock_sync.dart';

/// Keeps the stock sync login separate from the regular online account.
class StockSyncLogin {
  StockSyncLogin(String url, this.client)
    : _storageKey = 'tp_stock_sync_session:${Uri.parse(url).host}' {
    client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (session != null) {
        _queueWrite(jsonEncode(session.toJson()));
      } else if (state.event == AuthChangeEvent.signedOut) {
        _queueWrite(null);
      }
    }, onError: (Object _) {});
  }

  static final _instances = <String, StockSyncLogin>{};
  static const _storage = FlutterSecureStorage();

  static StockSyncLogin connect(String url, String key) =>
      _instances.putIfAbsent(
        url,
        () => StockSyncLogin(url, StockSyncApi.connect(url, key)),
      );

  final SupabaseClient client;
  final String _storageKey;
  Future<void> _writes = Future.value();
  Future<Session?>? _restoring;

  void _queueWrite(String? value) {
    _writes = _writes.catchError((Object _) {}).then((_) {
      return value == null
          ? _storage.delete(key: _storageKey)
          : _storage.write(key: _storageKey, value: value);
    });
    unawaited(_writes.catchError((Object _) {}));
  }

  Future<void> remember(Session session) async {
    _queueWrite(jsonEncode(session.toJson()));
    await _writes;
  }

  Future<Session?> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<Session?> _restore() async {
    final existing = client.auth.currentSession;
    if (existing != null && !existing.isExpired) return existing;
    await _writes.catchError((Object _) {});
    final saved = await _storage.read(key: _storageKey);
    if (saved == null) return null;
    try {
      final response = await client.auth.recoverSession(saved);
      if (response.session case final session?) await remember(session);
      return response.session;
    } on AuthException catch (error) {
      if (const {
        'refresh_token_not_found',
        'refresh_token_already_used',
        'session_not_found',
        'session_expired',
        'session_missing',
        'user_not_found',
      }.contains(error.code)) {
        _queueWrite(null);
        await _writes;
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    _queueWrite(null);
    await _writes;
    await client.auth.signOut(scope: SignOutScope.local);
    await _writes;
  }
}
