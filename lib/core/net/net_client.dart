import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when Offline mode is on. Nothing was sent.
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => 'Offline mode is on';
}

/// Thrown when a request is refused before sending (not HTTPS, or a host
/// that isn't on the allowlist).
class BlockedRequestException implements Exception {
  const BlockedRequestException(this.reason);
  final String reason;
  @override
  String toString() => 'Blocked request: $reason';
}

/// The ONLY way the app talks to the internet.
///
/// - Refuses everything while Offline mode is on.
/// - HTTPS only, to an allowlist of lookup/cover hosts (checked again on
///   every redirect).
/// - Sends a generic User-Agent and nothing else identifying; no cookies.
/// - Time-limited and size-capped so a bad server can't hang or flood us.
///
/// Every host here must also be listed on the in-app Privacy page and in
/// PRIVACY.md.
class NetClient {
  NetClient({required bool Function() isOffline, http.Client? inner})
      : _isOffline = isOffline,
        _inner = inner ?? http.Client();

  final bool Function() _isOffline;
  final http.Client _inner;

  static const Set<String> allowedHosts = {
    'itunes.apple.com',
    'api.tvmaze.com',
    'static.tvmaze.com',
    'openlibrary.org',
    'covers.openlibrary.org',
    'www.googleapis.com',
    'books.google.com',
    'books.googleusercontent.com',
    'en.wikipedia.org',
  };

  /// Image CDNs that the services above redirect cover downloads to.
  static const List<String> allowedHostSuffixes = [
    '.mzstatic.com', // Apple artwork
    '.archive.org', // Open Library covers
    '.wikimedia.org', // Wikipedia images (upload.wikimedia.org)
  ];

  static const Duration timeout = Duration(seconds: 12);
  static const String userAgent = 'WatchedLedger';
  static const int maxJsonBytes = 2 * 1024 * 1024;
  static const int maxImageBytes = 4 * 1024 * 1024;
  static const int _maxRedirects = 3;

  bool get isOffline => _isOffline();

  static bool isAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    if (url.userInfo.isNotEmpty) return false;
    if (url.hasPort && url.port != 443) return false;
    final host = url.host.toLowerCase();
    return allowedHosts.contains(host) ||
        allowedHostSuffixes.any(host.endsWith);
  }

  /// Fetches [url] and returns the body, following up to 3 redirects.
  Future<Uint8List> getBytes(
    Uri url, {
    int maxBytes = maxJsonBytes,
    String accept = 'application/json',
  }) async {
    var current = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (_isOffline()) throw const OfflineException();
      if (!isAllowed(current)) {
        throw BlockedRequestException('${current.scheme}://${current.host}');
      }
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent
        ..headers['Accept'] = accept;
      final response = await _inner.send(request).timeout(timeout);
      final status = response.statusCode;

      if (status >= 300 && status < 400) {
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (location == null) {
          throw http.ClientException('Redirect without a location', current);
        }
        current = current.resolve(location);
        continue;
      }
      if (status != 200) {
        await response.stream.drain<void>();
        throw http.ClientException('HTTP $status', current);
      }
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        await response.stream.drain<void>();
        throw http.ClientException('Response too large', current);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw http.ClientException('Response too large', current);
        }
      }
      return builder.takeBytes();
    }
    throw http.ClientException('Too many redirects', url);
  }

  /// Fetches and decodes JSON. Returns `null` for an empty body.
  Future<Object?> getJson(Uri url) async {
    final bytes = await getBytes(url);
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  }

  void close() => _inner.close();
}
