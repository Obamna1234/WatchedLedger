import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// Reads one file out of a ZIP archive (Samsung Notes .sdocx files are ZIPs).
/// Small and strict on purpose: size limits everywhere so a crafted file
/// (a "zip bomb") can't use up the phone's memory.
class ZipException implements Exception {
  const ZipException(this.message);
  final String message;
  @override
  String toString() => 'ZipException: $message';
}

const int _maxEntries = 2000;

/// Names of the files in [zip].
List<String> zipEntryNames(Uint8List zip) =>
    [for (final e in _entries(zip)) e.name];

/// The unpacked bytes of [name], or null if it isn't in the archive.
/// Throws [ZipException] if it is damaged or larger than [maxBytes].
Uint8List? readZipEntry(Uint8List zip, String name,
    {int maxBytes = 32 * 1024 * 1024}) {
  for (final e in _entries(zip)) {
    if (e.name != name) continue;
    if (e.size > maxBytes) throw const ZipException('file is too large');
    final data = ByteData.sublistView(zip);
    final h = e.localOffset;
    if (h + 30 > zip.length || data.getUint32(h, Endian.little) != 0x04034b50) {
      throw const ZipException('damaged archive');
    }
    final start = h +
        30 +
        data.getUint16(h + 26, Endian.little) +
        data.getUint16(h + 28, Endian.little);
    final end = start + e.compressedSize;
    if (end > zip.length) throw const ZipException('damaged archive');
    final raw = Uint8List.sublistView(zip, start, end);
    switch (e.method) {
      case 0:
        if (raw.length > maxBytes) throw const ZipException('file is too large');
        return Uint8List.fromList(raw);
      case 8:
        return _inflate(raw, maxBytes);
      default:
        throw const ZipException('unsupported compression');
    }
  }
  return null;
}

class _Entry {
  const _Entry(this.name, this.method, this.compressedSize, this.size,
      this.localOffset);
  final String name;
  final int method;
  final int compressedSize;
  final int size;
  final int localOffset;
}

List<_Entry> _entries(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  // End of central directory: in the last 64 KB + 22 bytes.
  var eocd = -1;
  final lowest = zip.length - 22 - 0xFFFF < 0 ? 0 : zip.length - 22 - 0xFFFF;
  for (var i = zip.length - 22; i >= lowest; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const ZipException('not a ZIP archive');
  final count = data.getUint16(eocd + 10, Endian.little);
  var p = data.getUint32(eocd + 16, Endian.little);
  if (count > _maxEntries) throw const ZipException('too many files');
  final out = <_Entry>[];
  for (var k = 0; k < count; k++) {
    if (p + 46 > zip.length || data.getUint32(p, Endian.little) != 0x02014b50) {
      throw const ZipException('damaged archive');
    }
    final method = data.getUint16(p + 10, Endian.little);
    final compressed = data.getUint32(p + 20, Endian.little);
    final size = data.getUint32(p + 24, Endian.little);
    final nameLen = data.getUint16(p + 28, Endian.little);
    final extraLen = data.getUint16(p + 30, Endian.little);
    final commentLen = data.getUint16(p + 32, Endian.little);
    final offset = data.getUint32(p + 42, Endian.little);
    if (p + 46 + nameLen > zip.length) throw const ZipException('damaged archive');
    final name = String.fromCharCodes(zip, p + 46, p + 46 + nameLen);
    out.add(_Entry(name, method, compressed, size, offset));
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

Uint8List _inflate(Uint8List raw, int maxBytes) {
  final out = BytesBuilder(copy: false);
  final sink = _CapSink(out, maxBytes);
  final conv = ZLibDecoder(raw: true).startChunkedConversion(sink);
  const step = 64 * 1024;
  try {
    for (var i = 0; i < raw.length; i += step) {
      conv.add(Uint8List.sublistView(
          raw, i, i + step > raw.length ? raw.length : i + step));
    }
    conv.close();
  } on ZipException {
    rethrow;
  } on Object {
    throw const ZipException('damaged archive');
  }
  return out.takeBytes();
}

class _CapSink implements Sink<List<int>> {
  _CapSink(this._out, this._cap);
  final BytesBuilder _out;
  final int _cap;

  @override
  void add(List<int> data) {
    _out.add(data);
    if (_out.length > _cap) throw const ZipException('file is too large');
  }

  @override
  void close() {}
}
