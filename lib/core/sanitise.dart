/// Input cleaning shared by every way text enters the app
/// (typing, pasting, imports, share-to-app and lookup responses).
library;

const int kMaxTitleLength = 300;
const int kMaxNoteLength = 200;

// C0/C1 control characters except tab/newline (those become spaces below).
final RegExp _control =
    RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]');

// Zero-width characters and bidirectional overrides ("Trojan Source" style
// tricks), plus the byte-order mark.
final RegExp _invisible =
    RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]');

final RegExp _whitespace = RegExp(r'\s+');

/// Cleans a single line of user-visible text and caps its length.
String cleanText(String raw, {int maxLength = kMaxTitleLength}) {
  var s = raw.replaceAll(_control, ' ').replaceAll(_invisible, '');
  s = s.replaceAll(_whitespace, ' ').trim();
  if (s.length > maxLength) {
    // Cut on a whole character so emoji and other surrogate pairs never split.
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (b.length + ch.length > maxLength) break;
      b.write(ch);
    }
    s = b.toString().trimRight();
  }
  return s;
}

String cleanTitle(String raw) => cleanText(raw);

final RegExp _nonAlphanumeric = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _leadingArticle = RegExp(r'^(the|a|an) ');

const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
  'ç': 'c', 'č': 'c', 'ć': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'ñ': 'n', 'ń': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'ý': 'y', 'ÿ': 'y',
  'š': 's', 'ś': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z', 'ł': 'l',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
};

String _foldDiacritics(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b.toString();
}

/// Sort key: lower-case, accents folded, punctuation removed and a leading
/// "The/A/An" dropped, so "The Matrix" sorts under M.
String sortKey(String title) {
  var s = _foldDiacritics(cleanTitle(title).toLowerCase());
  s = s.replaceAll('&', ' and ');
  s = s.replaceAll(_nonAlphanumeric, ' ').trim();
  return s.replaceFirst(_leadingArticle, '');
}

/// Duplicate-detection key: the sort key with spaces removed, so
/// "Spider-Man", "Spiderman" and "spider man" all match.
String matchKey(String title) => sortKey(title).replaceAll(' ', '');
