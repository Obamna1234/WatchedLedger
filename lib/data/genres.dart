import 'models.dart';

/// Curated genre names per category. Lookups (stage 2) map each source's
/// own genres onto these so grouping stays tidy. Users can still type any
/// genre they like.
const List<String> _screenGenres = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary', //
  'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music', 'Mystery',
  'Romance', 'Science Fiction', 'Thriller', 'War', 'Western',
];

const List<String> _bookGenres = [
  'Biography & Memoir', 'Business', "Children's", 'Comics & Graphic Novels', //
  'Fantasy', 'Historical Fiction', 'History', 'Horror', 'Literary Fiction',
  'Mystery & Crime', 'Non-fiction', 'Philosophy', 'Poetry', 'Romance',
  'Science', 'Science Fiction', 'Self-Help', 'Thriller', 'Travel',
  'True Crime', 'Young Adult',
];

const List<String> _podcastGenres = [
  'Arts', 'Business', 'Comedy', 'Education', 'Fiction', 'Health & Fitness', //
  'History', 'Kids & Family', 'Leisure', 'Music', 'News',
  'Religion & Spirituality', 'Science', 'Society & Culture', 'Sports',
  'Technology', 'True Crime', 'TV & Film',
];

List<String> curatedGenres(MediaCategory category) => switch (category) {
      MediaCategory.movie => _screenGenres,
      MediaCategory.series => const [
          ..._screenGenres,
          'Kids',
          'News',
          'Reality',
          'Talk',
        ],
      MediaCategory.book || MediaCategory.audiobook => _bookGenres,
      MediaCategory.podcast => _podcastGenres,
    };

/// Genres sorted A–Z with "Uncategorised" always last.
int compareGenres(String a, String b) {
  if (a == b) return 0;
  if (a == kUncategorised) return 1;
  if (b == kUncategorised) return -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}
