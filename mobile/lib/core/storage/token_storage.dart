import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokenlar Android Keystore bilan shifrlangan xotirada saqlanadi.
/// Har so'rovda diskdan o'qimaslik uchun xotirada ham nusxasi turadi.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kMe = 'cached_me';

  String? _access;
  String? _refresh;
  bool _loaded = false;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> load() async {
    if (_loaded) return;
    final values = await _storage.readAll();
    _access = values[_kAccess];
    _refresh = values[_kRefresh];
    _loaded = true;
  }

  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    await Future.wait([
      _storage.write(key: _kAccess, value: access),
      _storage.write(key: _kRefresh, value: refresh),
    ]);
  }

  /// Oxirgi /me javobi: internet bo'lmasa ham ilova darhol ochilishi uchun.
  Future<void> cacheMe(Map<String, dynamic> json) =>
      _storage.write(key: _kMe, value: jsonEncode(json));

  Future<Map<String, dynamic>?> cachedMe() async {
    final raw = await _storage.read(key: _kMe);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.deleteAll();
  }
}
