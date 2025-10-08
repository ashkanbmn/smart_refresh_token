import 'package:flutter_test/flutter_test.dart';
import 'package:smart_refresh_token/example/main.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  test('SecureTokenStorage write and read', () async {
    final storage = SecureTokenStorage(secureStorage: FlutterSecureStorage());
    final creds = Credentials(
      accessToken: 'access123',
      refreshToken: 'refresh123',
      accessTokenExpireAt: DateTime.now().toUtc().add(Duration(hours: 1)),
      refreshTokenExpireAt: DateTime.now().toUtc().add(Duration(days: 1)),
    );

    await storage.write(creds);
    final readCreds = await storage.read();

    expect(readCreds?.accessToken, creds.accessToken);
    expect(readCreds?.refreshToken, creds.refreshToken);

    await storage.delete();
    final afterDelete = await storage.read();
    expect(afterDelete, isNull);
  });

  test('RefreshTokenInterceptor initializes correctly', () {
    final tokenStorage = SecureTokenStorage(secureStorage: FlutterSecureStorage());
    final interceptor = RefreshTokenInterceptor(
      tokenStorage: tokenStorage,
      tokenRefresher: (token, client) async => null,
      onAuthFailure: () async {},
    );

    expect(interceptor, isA<RefreshTokenInterceptor>());
  });
}
