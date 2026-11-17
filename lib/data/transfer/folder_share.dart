import '../db/database.dart';
import '../models.dart';

/// Marks a shared folder message so WatchedLedger can read it back.
const String kFolderShareMark = '(from WatchedLedger)';
const String kFolderShareFooter = 'Shared from WatchedLedger';

/// A folder as a plain message anyone can read; links open in whatever
/// app the person has (YouTube, Instagram, a browser...). Someone with
/// WatchedLedger can share or paste it back in to add the whole folder.
String folderShareText(String folder, List<MediaItem> items) {
  final b = StringBuffer('"$folder" $kFolderShareMark\n\n');
  for (final i in items) {
    final title = i.year == null ? i.title : '${i.title} (${i.year})';
    final parts = [
      title,
      i.category.singular,
      if (i.whereToWatch != null) 'on ${i.whereToWatch}',
      if (i.link != null) i.link!,
    ];
    b.writeln('• ${parts.join(' · ')}');
  }
  b
    ..writeln()
    ..write('$kFolderShareFooter: private lists with no account. '
        'https://github.com/Obamna1234/WatchedLedger');
  return b.toString();
}
