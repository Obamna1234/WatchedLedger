import 'package:flutter/material.dart';

/// IMPORTANT: these enums are stored in the database by their index.
/// Only ever ADD new values at the end. Never reorder or remove.
enum MediaCategory { movie, series, book, audiobook, podcast }

enum ListStatus { todo, done }

enum MatchState { unmatched, matched, manual }

const String kUncategorised = 'Uncategorised';

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

extension MediaCategoryLabels on MediaCategory {
  String get tabLabel => switch (this) {
        MediaCategory.movie => 'Movies',
        MediaCategory.series => 'Series',
        MediaCategory.book => 'Books',
        MediaCategory.audiobook => 'Audiobooks',
        MediaCategory.podcast => 'Podcasts',
      };

  String get singular => switch (this) {
        MediaCategory.movie => 'movie',
        MediaCategory.series => 'series',
        MediaCategory.book => 'book',
        MediaCategory.audiobook => 'audiobook',
        MediaCategory.podcast => 'podcast',
      };

  /// "To Watch" / "To Read" / "To Listen"
  String get todoLabel => switch (this) {
        MediaCategory.movie || MediaCategory.series => 'To Watch',
        MediaCategory.book => 'To Read',
        MediaCategory.audiobook || MediaCategory.podcast => 'To Listen',
      };

  /// "Watched" / "Read" / "Listened"
  String get doneLabel => switch (this) {
        MediaCategory.movie || MediaCategory.series => 'Watched',
        MediaCategory.book => 'Read',
        MediaCategory.audiobook || MediaCategory.podcast => 'Listened',
      };

  String labelFor(ListStatus status) =>
      status == ListStatus.todo ? todoLabel : doneLabel;

  IconData get icon => switch (this) {
        MediaCategory.movie => Icons.movie_outlined,
        MediaCategory.series => Icons.live_tv_outlined,
        MediaCategory.book => Icons.menu_book_outlined,
        MediaCategory.audiobook => Icons.headphones_outlined,
        MediaCategory.podcast => Icons.podcasts_outlined,
      };
}

/// "Watched March 2026"
String completedLabel(MediaCategory category, DateTime when) =>
    '${category.doneLabel} ${_monthNames[when.month - 1]} ${when.year}';
