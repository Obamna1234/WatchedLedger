import 'dart:typed_data';

import 'zip_reader.dart';

/// One line of a Samsung Notes note.
class NoteLine {
  const NoteLine(this.text, {this.checkbox = false, this.checked = false});
  final String text;

  /// The line is a checklist item ("tick box").
  final bool checkbox;

  /// The box is ticked (Samsung Notes shows it crossed out).
  final bool checked;
}

class SamsungNotesException implements Exception {
  const SamsungNotesException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// True if [bytes] look like a ZIP archive (a .sdocx file is one).
bool looksLikeZip(Uint8List bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Reads the text and tick boxes of a Samsung Notes file (.sdocx, saved
/// with "Save as file" in Samsung Notes). Pictures and drawings are ignored.
///
/// The note's text is stored as one block (UTF-16), followed by text styles
/// and then per-line paragraph settings; a checklist line has a paragraph
/// record of type 5 with list kind 2 and a "ticked" flag.
List<NoteLine> readSamsungNote(Uint8List sdocx) {
  final Uint8List? note;
  try {
    note = readZipEntry(sdocx, 'note.note');
  } on ZipException {
    throw const SamsungNotesException(
        "That file couldn't be opened as a Samsung Notes file.");
  }
  if (note == null) {
    throw const SamsungNotesException(
        "That doesn't look like a Samsung Notes file (.sdocx).");
  }
  final parsed = parseSamsungNoteBody(note);
  if (parsed == null) {
    throw const SamsungNotesException(
        "This Samsung Notes file couldn't be read. Try copying the note's "
        'text and pasting it instead.');
  }
  return parsed;
}

/// Finds the note's text inside note.note. Several places can look like a
/// block of text; the longest one whose style and paragraph sections also
/// read cleanly is the note body.
List<NoteLine>? parseSamsungNoteBody(Uint8List b) {
  final data = ByteData.sublistView(b);
  List<NoteLine>? best;
  var bestLength = 0;
  for (var o = 0; o + 4 <= b.length; o += 2) {
    final n = data.getUint32(o, Endian.little);
    if (n == 0 || n <= bestLength || n > 4000000) continue;
    final end = o + 4 + 2 * n;
    if (end > b.length) continue;
    final spans = _records(data, end, const {24, 28});
    if (spans == null) continue;
    final paras = _records(data, spans.next, const {20, 24, 28, 32});
    if (paras == null) continue;

    final String text;
    try {
      text = _utf16(b, o + 4, n);
    } on FormatException {
      continue;
    }
    final lines = text.split('\n');
    final boxes = <int, bool>{};
    var ok = true;
    for (final r in paras.items) {
      if (r.length >= 5 && r[0] == 5 && r[3] == 2) {
        if (r[1] >= lines.length) {
          ok = false;
          break;
        }
        boxes[r[1]] = r[4] == 1;
      }
    }
    if (!ok) continue;
    bestLength = n;
    best = [
      for (var i = 0; i < lines.length; i++)
        NoteLine(lines[i],
            checkbox: boxes.containsKey(i), checked: boxes[i] ?? false),
    ];
  }
  return best;
}

String _utf16(Uint8List b, int start, int units) {
  final codes = Uint16List(units);
  final data = ByteData.sublistView(b);
  for (var i = 0; i < units; i++) {
    codes[i] = data.getUint16(start + 2 * i, Endian.little);
  }
  // Rejects broken surrogate pairs (i.e. "not really text").
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= codes.length ||
          codes[i + 1] < 0xDC00 ||
          codes[i + 1] > 0xDFFF) {
        throw const FormatException('broken text');
      }
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      throw const FormatException('broken text');
    }
  }
  return String.fromCharCodes(codes);
}

class _Block {
  const _Block(this.items, this.next);
  final List<List<int>> items;
  final int next;
}

/// A count, then that many records each starting with a 2-byte size.
_Block? _records(ByteData data, int p, Set<int> sizes) {
  if (p + 4 > data.lengthInBytes) return null;
  final count = data.getUint32(p, Endian.little);
  if (count > 500000) return null;
  p += 4;
  final items = <List<int>>[];
  for (var k = 0; k < count; k++) {
    if (p + 2 > data.lengthInBytes) return null;
    final size = data.getUint16(p, Endian.little);
    if (!sizes.contains(size) || p + 2 + size > data.lengthInBytes) {
      return null;
    }
    items.add([
      for (var q = p + 2; q + 4 <= p + 2 + size; q += 4)
        data.getUint32(q, Endian.little),
    ]);
    p += 2 + size;
  }
  return _Block(items, p);
}
