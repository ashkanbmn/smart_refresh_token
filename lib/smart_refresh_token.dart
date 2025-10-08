import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

class Credentials {
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpireAt;
  final DateTime? refreshTokenExpireAt;

  Credentials({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpireAt,
    this.refreshTokenExpireAt,
  });

  String get authorizationHeaderValue => 'Bearer $accessToken';

  bool get isAccessTokenExpired =>
      accessTokenExpireAt.isBefore(DateTime.now().toUtc());

  bool get isRefreshTokenExpired =>
      refreshTokenExpireAt != null && refreshTokenExpireAt!.isBefore(DateTime.now().toUtc());

  Credentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpireAt,
    DateTime? refreshTokenExpireAt,
  }) {
    return Credentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpireAt: accessTokenExpireAt ?? this.accessTokenExpireAt,
      refreshTokenExpireAt: refreshTokenExpireAt ?? this.refreshTokenExpireAt,
    );
  }
}

abstract class TokenStorage {
  Future<Credentials?> read();
  Future<void> write(Credentials credentials);
  Future<void> delete();
}

typedef TokenRefresher = Future<Credentials?> Function(
    String refreshToken,
    Dio client,
    );

typedef OnAuthFailure = FutureOr<void> Function();

class RefreshTokenInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final TokenRefresher tokenRefresher;
  final OnAuthFailure onAuthFailure;
  final Dio? refreshDio;
  final String authorizationHeaderKey;
  final Lock _lock = Lock();

  RefreshTokenInterceptor({
    required this.tokenStorage,
    required this.tokenRefresher,
    required this.onAuthFailure,
    this.refreshDio,
    this.authorizationHeaderKey = HttpHeaders.authorizationHeader,
  });

  Future<Dio> _getRefreshDio() async {
    return refreshDio ?? Dio();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _attachAuthorizationAndMaybeRefresh(options).then((shouldProceed) {
      if (shouldProceed) {
        handler.next(options);
      } else {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'Authentication failed - unable to refresh token',
          ),
        );
      }
    }).catchError((e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: 'Unexpected error in refresh interceptor: $e\n$st',
        ),
      );
    });
  }

  Future<bool> _attachAuthorizationAndMaybeRefresh(RequestOptions options) async {
    return await _lock.synchronized(() async {
      final credentials = await tokenStorage.read();

      if (credentials == null) {
        await onAuthFailure();
        return false;
      }

      if (!credentials.isAccessTokenExpired) {
        options.headers[authorizationHeaderKey] = credentials.authorizationHeaderValue;
        return true;
      }

      if (credentials.isRefreshTokenExpired) {
        await tokenStorage.delete();
        await onAuthFailure();
        return false;
      }

      final dioClient = await _getRefreshDio();
      final newCreds = await tokenRefresher(credentials.refreshToken, dioClient);

      if (newCreds != null) {
        await tokenStorage.write(newCreds);
        options.headers[authorizationHeaderKey] = newCreds.authorizationHeaderValue;
        return true;
      } else {
        await tokenStorage.delete();
        await onAuthFailure();
        return false;
      }
    });
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;

    if (status == HttpStatus.unauthorized) {
      try {
        final success = await _lock.synchronized(() async {
          final credentials = await tokenStorage.read();
          if (credentials == null) return false;

          if (!credentials.isAccessTokenExpired) return true;

          if (credentials.isRefreshTokenExpired) {
            await tokenStorage.delete();
            await onAuthFailure();
            return false;
          }

          final dioClient = await _getRefreshDio();
          final newCreds =
          await tokenRefresher(credentials.refreshToken, dioClient);

          if (newCreds != null) {
            await tokenStorage.write(newCreds);
            return true;
          } else {
            await tokenStorage.delete();
            await onAuthFailure();
            return false;
          }
        });

        if (!success) {
          handler.next(err);
          return;
        }

        final latest = await tokenStorage.read();
        if (latest == null) {
          handler.next(err);
          return;
        }

        options.headers[authorizationHeaderKey] =
            latest.authorizationHeaderValue;

        try {
          final retryResponse = await Dio().fetch(options);
          handler.resolve(retryResponse);
          return;
        } catch (_) {
          handler.next(err);
          return;
        }
      } catch (_) {
        handler.next(err);
        return;
      }
    }

    handler.next(err);
  }
}
