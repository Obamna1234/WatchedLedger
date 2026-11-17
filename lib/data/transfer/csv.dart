/// Small RFC 4180 CSV reader/writer (quotes, embedded commas/newlines).
library;

const int _maxFields = 200;

/// Parses CSV text into rows of fields. Handles quoted fields, doubled
/// quotes, CRLF/LF line endings and a leading byte-order mark.
List<List<String>> parseCsv(String text, {String separator = ','}) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  void endField() {
    if (row.length < _maxFields) row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == separator) {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Quotes a value for CSV. Values that a spreadsheet would run as a
/// formula (starting with = + - @ tab or CR) get a leading apostrophe.
String csvField(Object? value) {
  var s = value?.toString() ?? '';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) {
    s = '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String toCsv(List<List<Object?>> rows) =>
    rows.map((r) => r.map(csvField).join(',')).join('\r\n');
