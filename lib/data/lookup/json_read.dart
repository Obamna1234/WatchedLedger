import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';

/// Defensive readers for untrusted JSON from lookup services. Anything of the
/// wrong type is treated as missing; every string is cleaned.

Map<String, Object?>? asMap(Object? v) => v is Map<String, Object?> ? v : null;

List<Object?> asList(Object? v) => v is List<Object?> ? v : const [];

String? str(Map<String, Object?>? m, String key, {int maxLength = kMaxTitleLength}) {
  final v = m?[key];
  if (v is! String) return null;
  final s = cleanText(v, maxLength: maxLength);
  return s.isEmpty ? null : s;
}

/// Strings from a JSON list field (e.g. genres, authors).
List<String> strList(Map<String, Object?>? m, String key, {int max = 30}) {
  final out = <String>[];
  for (final v in asList(m?[key])) {
    if (v is String) {
      final s = cleanText(v, maxLength: 80);
      if (s.isNotEmpty) out.add(s);
    }
    if (out.length >= max) break;
  }
  return out;
}

String? idString(Map<String, Object?>? m, String key) {
  final v = m?[key];
  if (v is int) return '$v';
  if (v is String) {
    final s = cleanText(v, maxLength: 100);
    return s.isEmpty ? null : s;
  }
  return null;
}

final RegExp _leadingYear = RegExp(r'^\s*(\d{4})');

/// Year from "2021-10-22T07:00:00Z", "2021-10-22", "2021" or an int.
int? yearOf(Object? v) {
  int? y;
  if (v is int) y = v;
  if (v is String) {
    final m = _leadingYear.firstMatch(v);
    if (m != null) y = int.tryParse(m.group(1)!);
  }
  if (y == null || y < 1000 || y > DateTime.now().year + 10) return null;
  return y;
}

/// Accepts a cover URL only if it is HTTPS on an allowed host. Plain-HTTP
/// links from Google Books are upgraded to HTTPS.
String? safeImageUrl(Object? v) {
  if (v is! String || v.length > 1000) return null;
  var raw = v.trim();
  if (raw.startsWith('http://')) raw = 'https://${raw.substring(7)}';
  final uri = Uri.tryParse(raw);
  if (uri == null || !NetClient.isAllowed(uri)) return null;
  return uri.toString();
}
