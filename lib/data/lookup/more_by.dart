import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../models.dart';
import 'candidate.dart';
import 'genre_map.dart';
import 'json_read.dart';
import 'providers.dart';

/// "More by this director / author / host". Only the person's name is sent,
/// to the same services used for lookups.
class MoreByService {
  MoreByService(this.net);
  final NetClient net;

  /// The first person in "Joel Coen, Ethan Coen" / "A & B" / "A and B".
  static String primaryName(String creator) {
    final first = creator.split(RegExp(r',|&| and ')).first;
    return cleanText(first, maxLength: 80);
  }

  static bool available(MediaCategory category, String? creator) =>
      category != MediaCategory.game &&
      creator != null &&
      primaryName(creator).length >= 3;

  /// Works by [creator], newest first, without duplicates.
  Future<List<LookupCandidate>> worksBy(
      String creator, MediaCategory category) async {
    final name = primaryName(creator);
    if (name.length < 3) return const [];
    final List<LookupCandidate> found = switch (category) {
      MediaCategory.movie => await _films(name),
      MediaCategory.series => await _shows(name),
      MediaCategory.book => await _books(name, category),
      MediaCategory.audiobook => _byPerson(
          await ItunesProvider(net, ItunesMedia.audiobook,
                  attribute: 'authorTerm', limit: 50)
              .search(name, category),
          name),
      MediaCategory.podcast => _byPerson(
          await ItunesProvider(net, ItunesMedia.podcast,
                  attribute: 'authorTerm', limit: 50)
              .search(name, category),
          name),
      MediaCategory.game => const <LookupCandidate>[],
    };
    final seen = <String>{};
    final unique = [
      for (final c in found)
        if (seen.add(matchKey(c.title))) c,
    ];
    unique.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return unique;
  }

  static List<LookupCandidate> _byPerson(
      List<LookupCandidate> list, String name) {
    final key = _surnameKey(name);
    return [
      for (final c in list)
        if (c.creator != null && matchKey(c.creator!).contains(key)) c,
    ];
  }

  static String _surnameKey(String name) =>
      matchKey(name.trim().split(' ').last);

  /// Wikipedia full-text search for "directed by NAME", keeping pages
  /// whose short description is "YEAR film by ...NAME".
  Future<List<LookupCandidate>> _films(String name) async {
    final json = asMap(await net.getJson(Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrsearch': '"directed by $name"',
      'gsrnamespace': '0',
      'gsrlimit': '50',
      'prop': 'description|pageimages',
      'piprop': 'thumbnail',
      'pithumbsize': '300',
    })));
    final surname = _surnameKey(name);
    final film = RegExp(r'^((?:18|19|20)\d{2})\b.*\bfilm\b', caseSensitive: false);
    final by = RegExp(r'\bby (.+)$');
    final qualifier = RegExp(r'\s*\([^()]*film\)$');
    final out = <LookupCandidate>[];
    for (final raw in asList(asMap(json?['query'])?['pages'])) {
      final page = asMap(raw);
      final title = str(page, 'title');
      final description = str(page, 'description') ?? '';
      final m = film.firstMatch(description);
      final director = by.firstMatch(description)?.group(1);
      if (page == null || title == null || m == null || director == null) {
        continue;
      }
      if (!matchKey(director).contains(surname)) continue;
      final thumb = asMap(page['thumbnail'])?['source'];
      out.add(LookupCandidate(
        title: title.replaceFirst(qualifier, '').trim(),
        year: yearOf(m.group(1)),
        creator: cleanText(director, maxLength: 120),
        coverUrl: thumb is String ? safeImageUrl(thumb) : null,
        source: 'wikipedia',
        sourceId: title.replaceAll(' ', '_'),
      ));
    }
    return out;
  }

  /// TVmaze: find the person, then the shows they made (crew credits).
  Future<List<LookupCandidate>> _shows(String name) async {
    final people = asList(await net
        .getJson(Uri.https('api.tvmaze.com', '/search/people', {'q': name})));
    final person = asMap(asMap(people.firstOrNull)?['person']);
    final id = idString(person, 'id');
    if (id == null || !RegExp(r'^\d+$').hasMatch(id)) return const [];
    final credits = asList(await net.getJson(Uri.https(
        'api.tvmaze.com', '/people/$id/crewcredits', {'embed': 'show'})));
    final personName = str(person, 'name') ?? name;
    final out = <LookupCandidate>[];
    for (final raw in credits) {
      final show = asMap(asMap(asMap(raw)?['_embedded'])?['show']);
      final title = str(show, 'name');
      final showId = idString(show, 'id');
      if (show == null || title == null || showId == null) continue;
      final image = asMap(show['image']);
      out.add(LookupCandidate(
        title: title,
        year: yearOf(show['premiered']),
        genre: mapGenre(MediaCategory.series, strList(show, 'genres')),
        creator: personName,
        coverUrl: safeImageUrl(image?['medium']),
        source: 'tvmaze',
        sourceId: showId,
      ));
    }
    return out;
  }

  /// Open Library author search.
  Future<List<LookupCandidate>> _books(
      String name, MediaCategory category) async {
    final json = asMap(await net.getJson(Uri.https('openlibrary.org', '/search.json', {
      'author': name,
      'limit': '50',
      'fields': 'key,title,author_name,first_publish_year,cover_i,subject,'
          'number_of_pages_median',
    })));
    final out = <LookupCandidate>[];
    for (final raw in asList(json?['docs'])) {
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
        pages: pageCount(d['number_of_pages_median']),
        source: 'openlibrary',
        sourceId: id,
      ));
    }
    return _byPerson(out, name);
  }
}
