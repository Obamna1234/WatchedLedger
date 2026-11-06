import '../../core/net/net_client.dart';
import '../models.dart';
import 'candidate.dart';
import 'genre_map.dart';
import 'json_read.dart';

/// A free, keyless title-lookup service.
abstract class LookupProvider {
  const LookupProvider(this.net);
  final NetClient net;

  /// Shown on the "Did you mean…?" sheet, e.g. "iTunes".
  String get displayName;

  Future<List<LookupCandidate>> search(String query, MediaCategory category);
}

const int _limit = 12;

// ------------------------------------------------------------------ iTunes

enum ItunesMedia { movie, tvShow, audiobook, podcast }

/// Apple's iTunes Search API: movies, TV seasons, audiobooks and podcasts.
/// https://performance-partners.apple.com/search-api
class ItunesProvider extends LookupProvider {
  const ItunesProvider(super.net, this.media);
  final ItunesMedia media;

  @override
  String get displayName => 'iTunes';

  static final RegExp _artSize = RegExp(r'/\d+x\d+bb\.');
  static final RegExp _seasonSuffix =
      RegExp(r',?\s*(Season|Series)\s+\d+.*$', caseSensitive: false);

  String get _entity => switch (media) {
        ItunesMedia.movie => 'movie',
        ItunesMedia.tvShow => 'tvSeason',
        ItunesMedia.audiobook => 'audiobook',
        ItunesMedia.podcast => 'podcast',
      };

  static String? _art(Map<String, Object?> r) {
    final url = safeImageUrl(r['artworkUrl600']) ??
        safeImageUrl(r['artworkUrl100']) ??
        safeImageUrl(r['artworkUrl60']);
    return url?.replaceFirst(_artSize, '/300x300bb.');
  }

  @override
  Future<List<LookupCandidate>> search(
      String query, MediaCategory category) async {
    final json = await net.getJson(Uri.https('itunes.apple.com', '/search', {
      'term': query,
      'media': media.name,
      'entity': _entity,
      'limit': '$_limit',
    }));
    final out = <LookupCandidate>[];
    final seen = <String>{};
    for (final raw in asList(asMap(json)?['results'])) {
      final r = asMap(raw);
      if (r == null) continue;
      final String? title;
      final String? id;
      String? creator = str(r, 'artistName');
      switch (media) {
        case ItunesMedia.movie:
          title = str(r, 'trackName');
          id = idString(r, 'trackId');
        case ItunesMedia.tvShow:
          // "Breaking Bad, Season 1" → one entry for the show.
          final show = str(r, 'artistName') ?? str(r, 'collectionName');
          title = show?.replaceFirst(_seasonSuffix, '').trim();
          id = idString(r, 'artistId') ?? idString(r, 'collectionId');
          creator = null;
        case ItunesMedia.audiobook:
        case ItunesMedia.podcast:
          title = str(r, 'collectionName') ?? str(r, 'trackName');
          id = idString(r, 'collectionId') ?? idString(r, 'trackId');
      }
      if (title == null || title.isEmpty || id == null) continue;
      // Seasons of one show collapse to a single entry; remakes with the
      // same title (Dune 1984 / Dune 2021) are kept.
      if (media == ItunesMedia.tvShow && !seen.add(title.toLowerCase())) {
        continue;
      }
      out.add(LookupCandidate(
        title: title,
        year: yearOf(r['releaseDate']),
        genre: mapGenre(category, [
          ?str(r, 'primaryGenreName'),
          ...strList(r, 'genres'),
        ]),
        creator: creator,
        coverUrl: _art(r),
        source: 'itunes',
        sourceId: id,
      ));
    }
    return out;
  }
}

// ------------------------------------------------------------------ TVmaze

/// TVmaze: free TV database, no key. https://www.tvmaze.com/api
class TvmazeProvider extends LookupProvider {
  const TvmazeProvider(super.net);

  @override
  String get displayName => 'TVmaze';

  @override
  Future<List<LookupCandidate>> search(
      String query, MediaCategory category) async {
    final json = await net
        .getJson(Uri.https('api.tvmaze.com', '/search/shows', {'q': query}));
    final out = <LookupCandidate>[];
    for (final raw in asList(json)) {
      final show = asMap(asMap(raw)?['show']);
      final title = str(show, 'name');
      final id = idString(show, 'id');
      if (show == null || title == null || id == null) continue;
      final image = asMap(show['image']);
      out.add(LookupCandidate(
        title: title,
        year: yearOf(show['premiered']),
        genre: mapGenre(category, strList(show, 'genres')),
        coverUrl: safeImageUrl(image?['medium']) ??
            safeImageUrl(image?['original']),
        source: 'tvmaze',
        sourceId: id,
      ));
      if (out.length >= _limit) break;
    }
    return out;
  }
}

// ------------------------------------------------------------ Open Library

/// Open Library (Internet Archive): free book catalogue, no key.
/// https://openlibrary.org/developers/api
class OpenLibraryProvider extends LookupProvider {
  const OpenLibraryProvider(super.net);

  @override
  String get displayName => 'Open Library';

  @override
  Future<List<LookupCandidate>> search(
      String query, MediaCategory category) async {
    final json =
        await net.getJson(Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'limit': '$_limit',
      'fields': 'key,title,author_name,first_publish_year,cover_i,subject',
    }));
    final out = <LookupCandidate>[];
    for (final raw in asList(asMap(json)?['docs'])) {
      final d = asMap(raw);
      final title = str(d, 'title');
      final id = idString(d, 'key');
      if (d == null || title == null || id == null) continue;
      final authors = strList(d, 'author_name', max: 2);
      final coverId = d['cover_i'];
      out.add(LookupCandidate(
        title: title,
        year: yearOf(d['first_publish_year']),
        genre: mapGenre(category, strList(d, 'subject', max: 40)),
        creator: authors.isEmpty ? null : authors.join(', '),
        coverUrl: coverId is int && coverId > 0
            ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
            : null,
        source: 'openlibrary',
        sourceId: id,
      ));
    }
    return out;
  }
}

// ------------------------------------------------------------ Google Books

/// Google Books, used without an API key (low daily quota, fine for one
/// person). https://developers.google.com/books
class GoogleBooksProvider extends LookupProvider {
  const GoogleBooksProvider(super.net);

  @override
  String get displayName => 'Google Books';

  @override
  Future<List<LookupCandidate>> search(
      String query, MediaCategory category) async {
    final json =
        await net.getJson(Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': query,
      'maxResults': '$_limit',
      'printType': 'books',
    }));
    final out = <LookupCandidate>[];
    for (final raw in asList(asMap(json)?['items'])) {
      final item = asMap(raw);
      final info = asMap(item?['volumeInfo']);
      final title = str(info, 'title');
      final id = idString(item, 'id');
      if (info == null || title == null || id == null) continue;
      final authors = strList(info, 'authors', max: 2);
      final images = asMap(info['imageLinks']);
      out.add(LookupCandidate(
        title: title,
        year: yearOf(info['publishedDate']),
        genre: mapGenre(category, strList(info, 'categories')),
        creator: authors.isEmpty ? null : authors.join(', '),
        coverUrl: safeImageUrl(images?['thumbnail'])
                ?.replaceAll('&edge=curl', '') ??
            safeImageUrl(images?['smallThumbnail']),
        source: 'googlebooks',
        sourceId: id,
      ));
    }
    return out;
  }
}
