# smart_refresh_token

A smart Flutter package for **automatic Dio token refresh handling**. This package simplifies managing access and refresh tokens in your Flutter apps and automatically retries failed requests after refreshing tokens.

## Features

- Automatic refresh of expired access tokens using a refresh token.
- Transparent request retry after token refresh.
- Secure storage of tokens using `flutter_secure_storage`.
- Customizable token refresher function.
- Handles network errors gracefully.
- Easy integration with Dio interceptors.

## Getting Started

### Prerequisites

- Flutter >= 1.17.0
- Dart >= 3.9.0
- Add dependencies in your `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.9.0
  synchronized: ^3.4.0
  flutter_secure_storage: ^9.2.4
  smart_refresh_token:
    path: ../smart_refresh_token  # or use published version from pub.dev
