import 'package:flutter/material.dart';

import '../../core/sanitise.dart';
import '../../data/db/database.dart';

/// Samsung-Notes-style search state: the query, how many matches the
/// visible list has, and which one is current ("3 of 12").
///
/// The search bar writes the query and moves next/previous; the visible
/// list reports how many matches it has and scrolls whenever
/// [jumpRequest] changes.
class ListSearch extends ChangeNotifier {
  bool _active = false;
  String _query = '';
  int _total = 0;
  int _current = 0;
  int _jumpRequest = 0;

  bool get active => _active;

  /// The cleaned query, or '' when search is closed.
  String get query => _active ? _query : '';
  bool get hasQuery => query.isNotEmpty;

  int get total => _total;

  /// Zero-based index of the current match.
  int get current => _current;

  /// Changes every time the list should scroll to the current match.
  int get jumpRequest => _jumpRequest;

  void open() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void close() {
    if (!_active) return;
    _active = false;
    _query = '';
    _total = 0;
    _current = 0;
    notifyListeners();
  }

  void setQuery(String raw) {
    final q = cleanText(raw, maxLength: 100);
    if (q == _query) return;
    _query = q;
    _current = 0;
    _jumpRequest++;
    notifyListeners();
  }

  void next() {
    if (_total == 0) return;
    _current = (_current + 1) % _total;
    _jumpRequest++;
    notifyListeners();
  }

  void previous() {
    if (_total == 0) return;
    _current = (_current - 1 + _total) % _total;
    _jumpRequest++;
    notifyListeners();
  }

  /// Start again from the first match (after switching tab or list).
  void restart() {
    _current = 0;
    _jumpRequest++;
    notifyListeners();
  }

  /// Called by the visible list after it has counted its matches.
  void reportTotal(int total) {
    if (total == _total) return;
    _total = total;
    if (_current >= total) _current = total == 0 ? 0 : total - 1;
    notifyListeners();
  }

  /// "3 of 12", "No matches", or '' with no query.
  String get counterLabel {
    if (!hasQuery) return '';
    if (_total == 0) return 'No matches';
    return '${_current + 1} of $_total';
  }
}

/// True if [query] appears in the item's title, creator or note.
bool itemMatches(MediaItem item, String query) =>
    query.isNotEmpty &&
    (containsMatch(item.title, query) ||
        containsMatch(item.creator, query) ||
        containsMatch(item.note, query));

/// Makes [ListSearch] available to the lists; they rebuild when it changes.
class SearchScope extends InheritedNotifier<ListSearch> {
  const SearchScope({
    super.key,
    required ListSearch search,
    required super.child,
  }) : super(notifier: search);

  static ListSearch of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SearchScope>();
    assert(scope != null, 'No SearchScope above this widget');
    return scope!.notifier!;
  }

  /// Null when there's no search (e.g. in tests or other screens).
  static ListSearch? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchScope>()?.notifier;
}

/// Splits [text] into spans with every match of [query] highlighted.
TextSpan highlightSpan(
  String text,
  String query, {
  TextStyle? style,
  required TextStyle highlight,
}) {
  final ranges = query.isEmpty ? const <(int, int)>[] : findMatches(text, query);
  if (ranges.isEmpty) return TextSpan(text: text, style: style);
  final children = <TextSpan>[];
  var pos = 0;
  for (final (start, end) in ranges) {
    if (start > pos) children.add(TextSpan(text: text.substring(pos, start)));
    children.add(TextSpan(text: text.substring(start, end), style: highlight));
    pos = end;
  }
  if (pos < text.length) children.add(TextSpan(text: text.substring(pos)));
  return TextSpan(style: style, children: children);
}
