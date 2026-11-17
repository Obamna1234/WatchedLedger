import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when Offline mode is on. Nothing was sent.
class OfflineException implements Exception {
  const OfflineException();
  @override
  String toString() => 'Offline mode is on';
}

/// Thrown when the phone is on mobile data and the "Use mobile data"
/// setting doesn't allow this kind of request. Nothing was sent.
class NotOnWifiException extends OfflineException {
  const NotOnWifiException();
  @override
  String toString() => 'Not on Wi-Fi';
}

/// What a request is for, so the mobile data setting can allow lookups
/// (tiny) while holding back cover images (bigger).
enum NetPurpose { lookup, image }

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
  NetClient({
    required bool Function() isOffline,
    bool Function(NetPurpose purpose)? mayUseConnection,
    http.Client? inner,
  })  : _isOffline = isOffline,
        _mayUseConnection = mayUseConnection ?? _always,
        _inner = inner ?? http.Client();

  static bool _always(NetPurpose _) => true;

  final bool Function() _isOffline;
  final bool Function(NetPurpose purpose) _mayUseConnection;
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
    'www.wikidata.org', // last-resort title search
    // Pasted links: title + thumbnail via each site's public oEmbed.
    'www.youtube.com',
    'vimeo.com',
    'www.tiktok.com',
    'www.dailymotion.com',
    'open.spotify.com',
    'soundcloud.com',
    'www.reddit.com',
  };

  /// Image CDNs that the services above redirect cover downloads to.
  static const List<String> allowedHostSuffixes = [
    '.mzstatic.com', // Apple artwork
    '.archive.org', // Open Library covers
    '.wikimedia.org', // Wikipedia images (upload.wikimedia.org)
    '.ytimg.com', // YouTube thumbnails
    '.vimeocdn.com', // Vimeo thumbnails
    '.tiktokcdn.com', // TikTok thumbnails
    '.tiktokcdn-us.com',
    '.dmcdn.net', // Dailymotion thumbnails
    '.scdn.co', // Spotify artwork
    '.spotifycdn.com',
    '.sndcdn.com', // SoundCloud artwork
  ];

  static const Duration timeout = Duration(seconds: 12);
  static const String userAgent = 'WatchedLedger';
  static const int maxJsonBytes = 2 * 1024 * 1024;
  static const int maxImageBytes = 4 * 1024 * 1024;
  static const int _maxRedirects = 3;

  bool get isOffline => _isOffline();

  /// True if a request for [purpose] would be allowed right now.
  bool mayUse(NetPurpose purpose) => !_isOffline() && _mayUseConnection(purpose);

  static bool isAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    if (url.userInfo.isNotEmpty) return false;
    if (url.hasPort && url.port != 443) return false;
    final host = url.host.toLowerCase();
    return allowedHosts.contains(host) ||
        allowedHostSuffixes.any(host.endsWith);
  }

  /// Fetches [url] and returns the body, following up to 3 redirects.
  /// The whole fetch (redirects and body) must finish within [timeout].
  Future<Uint8List> getBytes(
    Uri url, {
    int maxBytes = maxJsonBytes,
    String accept = 'application/json',
    NetPurpose purpose = NetPurpose.lookup,
  }) =>
      _fetch(url, maxBytes, accept, purpose).timeout(timeout);

  Future<Uint8List> _fetch(
      Uri url, int maxBytes, String accept, NetPurpose purpose) async {
    var current = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      if (_isOffline()) throw const OfflineException();
      if (!_mayUseConnection(purpose)) throw const NotOnWifiException();
      if (!isAllowed(current)) {
        throw BlockedRequestException('${current.scheme}://${current.host}');
      }
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent
        ..headers['Accept'] = accept;
      final response = await _inner.send(request);
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
      await for (final chunk in response.stream) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw http.ClientException('Response too large', current);
        }
      }
      return builder.takeBytes();
    }
    throw http.ClientException('Too many redirects', url);
  }

  /// Phone-to-phone sync on the home network. Only plain addresses inside
  /// the private ranges (192.168.x.x, 10.x.x.x, 172.16-31.x.x) are allowed,
  /// and Offline mode blocks it like everything else. The body is already
  /// end-to-end encrypted by the caller.
  static bool isLocalSyncAddress(Uri url) {
    if (url.scheme != 'http' || url.path != '/sync') return false;
    if (url.hasQuery || url.hasFragment || url.userInfo.isNotEmpty) {
      return false;
    }
    final parts = url.host.split('.');
    if (parts.length != 4) return false;
    final n = [for (final p in parts) int.tryParse(p) ?? -1];
    if (n.any((x) => x < 0 || x > 255)) return false;
    return n[0] == 10 ||
        (n[0] == 192 && n[1] == 168) ||
        (n[0] == 172 && n[1] >= 16 && n[1] <= 31);
  }

  static const Duration localTimeout = Duration(seconds: 90);
  static const int maxLocalBytes = 64 * 1024 * 1024;

  Future<Uint8List> postLocal(Uri url, List<int> body) =>
      _postLocal(url, body).timeout(localTimeout);

  Future<Uint8List> _postLocal(Uri url, List<int> body) async {
    if (_isOffline()) throw const OfflineException();
    if (!isLocalSyncAddress(url)) {
      throw BlockedRequestException('${url.scheme}://${url.host}');
    }
    final request = http.Request('POST', url)
      ..followRedirects = false
      ..headers['User-Agent'] = userAgent
      ..headers['Content-Type'] = 'application/octet-stream'
      ..bodyBytes = body;
    final response = await _inner.send(request);
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw http.ClientException('HTTP ${response.statusCode}', url);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      if (builder.length > maxLocalBytes) {
        throw http.ClientException('Response too large', url);
      }
    }
    return builder.takeBytes();
  }

  /// Fetches and decodes JSON. Returns `null` for an empty body.
  Future<Object?> getJson(Uri url, {int maxBytes = maxJsonBytes}) async {
    final bytes = await getBytes(url, maxBytes: maxBytes);
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  }

  void close() => _inner.close();
}
