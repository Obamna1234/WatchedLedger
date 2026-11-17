import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../models.dart';
import 'candidate.dart';
import 'json_read.dart';

/// Pasted links: asks the site's own public "oEmbed" endpoint for the
/// title, channel and thumbnail. Only the link itself is sent, only to the
/// site it points to, and no account or key is involved.
///
/// Facebook and Instagram need a developer account for this, so their links
/// are kept but the title has to be typed.
class LinkLookup {
  LinkLookup(this.net);
  final NetClient net;

  /// A pasted link, if [text] is one (and nothing else).
  static Uri? asLink(String text) {
    final t = text.trim();
    if (t.contains(RegExp(r'\s'))) return null;
    final clean = cleanLink(t);
    return clean == null ? null : Uri.parse(clean);
  }

  static bool _on(Uri u, String domain) {
    final h = u.host.toLowerCase();
    return h == domain || h.endsWith('.$domain');
  }

  /// The site's oEmbed address for [link], or null if not supported.
  static Uri? endpointFor(Uri link) {
    final url = link.toString();
    if (_on(link, 'youtube.com') || _on(link, 'youtu.be')) {
      return Uri.https('www.youtube.com', '/oembed', {'url': url, 'format': 'json'});
    }
    if (_on(link, 'vimeo.com')) {
      return Uri.https('vimeo.com', '/api/oembed.json', {'url': url});
    }
    if (_on(link, 'tiktok.com')) {
      return Uri.https('www.tiktok.com', '/oembed', {'url': url});
    }
    if (_on(link, 'dailymotion.com') || _on(link, 'dai.ly')) {
      return Uri.https('www.dailymotion.com', '/services/oembed',
          {'url': url, 'format': 'json'});
    }
    if (_on(link, 'spotify.com')) {
      return Uri.https('open.spotify.com', '/oembed', {'url': url});
    }
    if (_on(link, 'soundcloud.com')) {
      return Uri.https('soundcloud.com', '/oembed', {'url': url, 'format': 'json'});
    }
    if (_on(link, 'reddit.com') || _on(link, 'redd.it')) {
      return Uri.https('www.reddit.com', '/oembed', {'url': url});
    }
    return null;
  }

  /// Which list a link belongs on, if it's obvious.
  static MediaCategory? categoryFor(Uri link) {
    if (_on(link, 'youtube.com') || _on(link, 'youtu.be') ||
        _on(link, 'vimeo.com') || _on(link, 'tiktok.com') ||
        _on(link, 'dailymotion.com') || _on(link, 'dai.ly') ||
        _on(link, 'facebook.com') || _on(link, 'fb.watch') ||
        _on(link, 'instagram.com') || _on(link, 'twitter.com') ||
        _on(link, 'x.com') || _on(link, 'reddit.com') ||
        _on(link, 'redd.it') || _on(link, 'threads.net') ||
        _on(link, 'threads.com') || _on(link, 'snapchat.com') ||
        _on(link, 'twitch.tv') || _on(link, 'rumble.com') ||
        _on(link, 'bilibili.com') || _on(link, 'kick.com')) {
      return MediaCategory.video;
    }
    if (_on(link, 'soundcloud.com') ||
        (_on(link, 'spotify.com') &&
            (link.path.contains('/show') || link.path.contains('/episode')))) {
      return MediaCategory.podcast;
    }
    return null;
  }

  /// Title, channel and thumbnail for [link], or null if the site isn't
  /// supported or has nothing. Throws [OfflineException] when offline.
  Future<LookupCandidate?> lookup(Uri link) async {
    final endpoint = endpointFor(link);
    if (endpoint == null) return null;
    final Object? json;
    try {
      json = await net.getJson(endpoint);
    } on OfflineException {
      rethrow;
    } catch (_) {
      return null; // private / removed video, or site trouble
    }
    final m = asMap(json);
    final title = str(m, 'title');
    if (title == null || cleanTitle(title).isEmpty) return null;
    final thumb = m?['thumbnail_url'];
    return LookupCandidate(
      title: cleanTitle(title),
      creator: str(m, 'author_name'),
      coverUrl: thumb is String ? safeImageUrl(thumb) : null,
      source: 'link',
      sourceId: link.toString(),
      link: link.toString(),
    );
  }
}
