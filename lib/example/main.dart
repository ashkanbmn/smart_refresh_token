import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';
import 'package:dio/dio.dart';

// Implementation of TokenStorage
class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage secureStorage;
  SecureTokenStorage({required this.secureStorage});

  static const _kKey = 'app_credentials_v1';

  @override
  Future<void> delete() => secureStorage.delete(key: _kKey);

  @override
  Future<Credentials?> read() async {
    final s = await secureStorage.read(key: _kKey);
    if (s == null) return null;
    final m = json.decode(s) as Map<String, dynamic>;
    return Credentials(
      accessToken: m['accessToken'],
      refreshToken: m['refreshToken'],
      accessTokenExpireAt: DateTime.parse(m['accessTokenExpireAt']).toUtc(),
      refreshTokenExpireAt: m['refreshTokenExpireAt'] != null
          ? DateTime.parse(m['refreshTokenExpireAt']).toUtc()
          : null,
    );
  }

  @override
  Future<void> write(Credentials credentials) {
    final m = {
      'accessToken': credentials.accessToken,
      'refreshToken': credentials.refreshToken,
      'accessTokenExpireAt': credentials.accessTokenExpireAt.toIso8601String(),
      'refreshTokenExpireAt': credentials.refreshTokenExpireAt?.toIso8601String(),
    };
    return secureStorage.write(key: _kKey, value: json.encode(m));
  }
}

// Example token refresher
Future<Credentials?> myRefresher(String refreshToken, Dio client) async {
  try {
    final resp = await client.post(
      'https://api.yourdomain.com/v2/mobile/login/refresh/',
      data: {'refresh': refreshToken},
    );

    if (resp.statusCode == 200) {
      final data = resp.data as Map<String, dynamic>;
      // parse according to your API shape:
      final newAccess = data['access_token'] ?? data['token'] ?? data['access'];
      final newRefresh = data['refresh'] ?? refreshToken;
      final accessExpiresIn = data['access_expires_in'] ?? 3600; // seconds
      final refreshExpiresIn = data['refresh_expires_in']; // optional

      return Credentials(
        accessToken: newAccess as String,
        refreshToken: newRefresh as String,
        accessTokenExpireAt: DateTime.now().toUtc().add(Duration(seconds: accessExpiresIn as int)),
        refreshTokenExpireAt: refreshExpiresIn != null
            ? DateTime.now().toUtc().add(Duration(seconds: refreshExpiresIn as int))
            : null,
      );
    }
  } catch (e) {
    // network error or parse error -> return null
  }
  return null;
}

// When creating your Dio client:
final tokenStorage = SecureTokenStorage(secureStorage: FlutterSecureStorage());
final interceptor = RefreshTokenInterceptor(
  tokenStorage: tokenStorage,
  tokenRefresher: myRefresher,
  onAuthFailure: () async {
    // app-specific: navigate to login, clear state, etc.
  },
);

final dioAuth = Dio(BaseOptions(baseUrl: 'https://api.yourdomain.com'))
  ..interceptors.add(interceptor);
