import 'dart:convert';

import '../core/sanitise.dart';
import 'db/database.dart';

const int kMaxTagLength = 40;
const int kMaxTagsPerItem = 20;

/// A tag as the user will see it: cleaned, no commas or semicolons
/// (those separate tags in CSV exports).
String cleanTag(String raw) =>
    cleanText(raw.replaceAll(RegExp('[,;#]'), ' '), maxLength: kMaxTagLength);

/// Tags stored on an item (JSON list in the `tags` column).
List<String> decodeTags(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final t in decoded)
          if (t is String && cleanTag(t).isNotEmpty) cleanTag(t),
      ];
    }
  } on FormatException {
    // Damaged value: treat as no tags.
  }
  return const [];
}

/// Cleans, de-duplicates (ignoring case) and encodes tags; null if none.
String? encodeTags(Iterable<String> tags) {
  final seen = <String>{};
  final out = <String>[];
  for (final t in tags) {
    final c = cleanTag(t);
    if (c.isEmpty || !seen.add(c.toLowerCase())) continue;
    out.add(c);
    if (out.length >= kMaxTagsPerItem) break;
  }
  return out.isEmpty ? null : jsonEncode(out);
}

List<String> itemTags(MediaItem i) => decodeTags(i.tags);
