import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Why a PDF's text could not be read; [message] is fit to show.
class PdfTextException implements Exception {
  const PdfTextException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The text of a PDF, a page after page, with line breaks where the lines
/// break and a blank line between paragraphs. It reads what a PDF writer put
/// in the file (text drawn with fonts that say which characters they show), so
/// it cannot read scanned pictures of text or password-protected files. Layout
/// is not kept: tables come out as lines of text and columns are read in the
/// order they were drawn.
String extractPdfText(Uint8List bytes) =>
    _PdfReader(bytes).text().replaceAll('\r', '');

// ----------------------------------------------------------------- objects

class _Ref {
  const _Ref(this.number);
  final int number;
}

class _Name {
  const _Name(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is _Name && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// A word in a content stream, such as Tj or BT.
class _Op {
  const _Op(this.name);
  final String name;
}

/// A PDF string: raw bytes (their meaning depends on the font).
class _Str {
  const _Str(this.bytes);
  final Uint8List bytes;
}

class _Stream {
  _Stream(this.dict, this.raw);
  final Map<String, Object?> dict;
  final Uint8List raw;
  Uint8List? _decoded;
}

bool _isSpace(int c) =>
    c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
bool _isDelimiter(int c) =>
    c == 0x28 || // (
    c == 0x29 || // )
    c == 0x3C || // <
    c == 0x3E || // >
    c == 0x5B || // [
    c == 0x5D || // ]
    c == 0x7B || // {
    c == 0x7D || // }
    c == 0x2F || // /
    c == 0x25; // %

/// Reads PDF syntax (objects in a file, or the words of a content stream).
class _Lexer {
  _Lexer(this.data, [this.pos = 0]);
  final Uint8List data;
  int pos;

  bool get atEnd {
    skipSpace();
    return pos >= data.length;
  }

  void skipSpace() {
    while (pos < data.length) {
      final c = data[pos];
      if (_isSpace(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < data.length && data[pos] != 10 && data[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// The next object; keywords (operators) come back as [_Op]. Null at the end.
  /// With [refs], "12 0 R" reads as a reference.
  Object? read({bool refs = true, int depth = 0}) {
    skipSpace();
    if (pos >= data.length) return null;
    if (depth > 64) throw const FormatException('too deep');
    final c = data[pos];
    if (c == 0x2F) return _name();
    if (c == 0x28) return _literalString();
    if (c == 0x3C) {
      if (pos + 1 < data.length && data[pos + 1] == 0x3C) {
        return _dict(refs, depth);
      }
      return _hexString();
    }
    if (c == 0x5B) return _array(refs, depth);
    if (c == 0x5D || c == 0x3E || c == 0x29 || c == 0x7B || c == 0x7D) {
      pos++;
      return _Op(String.fromCharCode(c));
    }
    final start = pos;
    while (pos < data.length &&
        !_isSpace(data[pos]) &&
        !_isDelimiter(data[pos])) {
      pos++;
    }
    final word = String.fromCharCodes(data, start, pos);
    final n = _number(word);
    if (n != null) {
      if (refs && n is int && n >= 0) {
        // "12 0 R"
        final save = pos;
        skipSpace();
        final s2 = pos;
        while (pos < data.length && data[pos] >= 0x30 && data[pos] <= 0x39) {
          pos++;
        }
        if (pos > s2) {
          skipSpace();
          if (pos < data.length &&
              data[pos] == 0x52 &&
              (pos + 1 >= data.length ||
                  _isSpace(data[pos + 1]) ||
                  _isDelimiter(data[pos + 1]))) {
            pos++;
            return _Ref(n);
          }
        }
        pos = save;
      }
      return n;
    }
    if (word == 'true') return true;
    if (word == 'false') return false;
    if (word == 'null') return null;
    return _Op(word);
  }

  static num? _number(String w) {
    if (w.isEmpty) return null;
    final c = w.codeUnitAt(0);
    if (!((c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E)) {
      return null;
    }
    return int.tryParse(w) ?? double.tryParse(w);
  }

  _Name _name() {
    pos++; // the slash
    final b = StringBuffer();
    while (pos < data.length &&
        !_isSpace(data[pos]) &&
        !_isDelimiter(data[pos])) {
      final c = data[pos];
      if (c == 0x23 && pos + 2 < data.length) {
        final v = int.tryParse(
          String.fromCharCodes(data, pos + 1, pos + 3),
          radix: 16,
        );
        if (v != null) {
          b.writeCharCode(v);
          pos += 3;
          continue;
        }
      }
      b.writeCharCode(c);
      pos++;
    }
    return _Name(b.toString());
  }

  _Str _literalString() {
    pos++; // (
    final out = <int>[];
    var depth = 1;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x5C) {
        if (pos >= data.length) break;
        final e = data[pos++];
        switch (e) {
          case 0x6E:
            out.add(10);
          case 0x72:
            out.add(13);
          case 0x74:
            out.add(9);
          case 0x62:
            out.add(8);
          case 0x66:
            out.add(12);
          case 10:
            break; // a line continuation
          case 13:
            if (pos < data.length && data[pos] == 10) pos++;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var i = 0; i < 2 && pos < data.length; i++) {
                final d = data[pos];
                if (d < 0x30 || d > 0x37) break;
                v = v * 8 + d - 0x30;
                pos++;
              }
              out.add(v & 0xFF);
            } else {
              out.add(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.add(c);
      } else if (c == 0x29) {
        if (--depth == 0) break;
        out.add(c);
      } else {
        out.add(c);
      }
    }
    return _Str(Uint8List.fromList(out));
  }

  _Str _hexString() {
    pos++; // <
    final out = <int>[];
    int? high;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x3E) break;
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high == null) {
        high = v;
      } else {
        out.add(high * 16 + v);
        high = null;
      }
    }
    if (high != null) out.add(high * 16);
    return _Str(Uint8List.fromList(out));
  }

  static int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  List<Object?> _array(bool refs, int depth) {
    pos++; // [
    final out = <Object?>[];
    while (true) {
      skipSpace();
      if (pos >= data.length) break;
      if (data[pos] == 0x5D) {
        pos++;
        break;
      }
      final v = read(refs: refs, depth: depth + 1);
      if (v is _Op && v.name == ']') break;
      out.add(v);
    }
    return out;
  }

  Map<String, Object?> _dict(bool refs, int depth) {
    pos += 2; // <<
    final out = <String, Object?>{};
    while (true) {
      skipSpace();
      if (pos >= data.length) break;
      if (data[pos] == 0x3E) {
        pos += pos + 1 < data.length && data[pos + 1] == 0x3E ? 2 : 1;
        break;
      }
      final key = read(refs: refs, depth: depth + 1);
      if (key is! _Name) {
        if (key == null && atEnd) break;
        continue;
      }
      skipSpace();
      if (pos < data.length && data[pos] == 0x3E) {
        continue;
      }
      out[key.value] = read(refs: refs, depth: depth + 1);
    }
    return out;
  }
}

// ----------------------------------------------------------------- streams

Uint8List _ascii85(Uint8List input) {
  final out = <int>[];
  final group = <int>[];
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (_isSpace(c)) continue;
    if (c == 0x7E) break; // ~>
    if (c == 0x7A && group.isEmpty) {
      out.addAll(const [0, 0, 0, 0]);
      continue;
    }
    if (c < 0x21 || c > 0x75) continue;
    group.add(c - 0x21);
    if (group.length == 5) {
      var v = 0;
      for (final g in group) {
        v = v * 85 + g;
      }
      out.addAll([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
      group.clear();
    }
  }
  if (group.length > 1) {
    final n = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var v = 0;
    for (final g in group) {
      v = v * 85 + g;
    }
    final all = [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255];
    out.addAll(all.sublist(0, n - 1));
  }
  return Uint8List.fromList(out);
}

Uint8List _asciiHex(Uint8List input) {
  final out = <int>[];
  int? high;
  for (final c in input) {
    if (c == 0x3E) break;
    final v = _Lexer._hexValue(c);
    if (v < 0) continue;
    if (high == null) {
      high = v;
    } else {
      out.add(high * 16 + v);
      high = null;
    }
  }
  if (high != null) out.add(high * 16);
  return Uint8List.fromList(out);
}

/// Undoes the PNG and TIFF predictors that go with Flate compression.
Uint8List _predict(
  Uint8List data,
  int predictor,
  int columns,
  int colors,
  int bits,
) {
  if (predictor < 10) return data;
  final bpp = ((colors * bits) + 7) ~/ 8;
  final row = ((colors * bits * columns) + 7) ~/ 8;
  final stride = row + 1;
  final rows = data.length ~/ stride;
  final out = Uint8List(rows * row);
  for (var r = 0; r < rows; r++) {
    final type = data[r * stride];
    for (var i = 0; i < row; i++) {
      final raw = data[r * stride + 1 + i];
      final left = i >= bpp ? out[r * row + i - bpp] : 0;
      final up = r > 0 ? out[(r - 1) * row + i] : 0;
      final upLeft = r > 0 && i >= bpp ? out[(r - 1) * row + i - bpp] : 0;
      int v;
      switch (type) {
        case 1:
          v = raw + left;
        case 2:
          v = raw + up;
        case 3:
          v = raw + ((left + up) >> 1);
        case 4:
          final p = left + up - upLeft;
          final pa = (p - left).abs(),
              pb = (p - up).abs(),
              pc = (p - upLeft).abs();
          v = raw + (pa <= pb && pa <= pc ? left : (pb <= pc ? up : upLeft));
        default:
          v = raw;
      }
      out[r * row + i] = v & 0xFF;
    }
  }
  return out;
}

// ------------------------------------------------------------------ reader

class _PdfReader {
  _PdfReader(this.bytes) : _latin = String.fromCharCodes(bytes);

  final Uint8List bytes;
  final String _latin;
  final _objects = <int, Object?>{};

  Object? _resolve(Object? o) {
    for (var i = 0; i < 40 && o is _Ref; i++) {
      o = _objects[o.number];
    }
    return o is _Ref ? null : o;
  }

  Map<String, Object?>? _dictOf(Object? o) {
    o = _resolve(o);
    if (o is Map<String, Object?>) return o;
    if (o is _Stream) return o.dict;
    return null;
  }

  List<Object?>? _listOf(Object? o) {
    o = _resolve(o);
    return o is List<Object?> ? o : null;
  }

  String? _nameOf(Object? o) {
    o = _resolve(o);
    return o is _Name ? o.value : null;
  }

  num? _numOf(Object? o) {
    o = _resolve(o);
    return o is num ? o : null;
  }

  // ------------------------------------------------------- reading the file

  void _scan() {
    if (!_latin.startsWith('%PDF', 0) && !_latin.contains('%PDF-')) {
      throw const PdfTextException('That file is not a PDF.');
    }
    final header = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    for (final m in header.allMatches(_latin)) {
      try {
        final lexer = _Lexer(bytes, m.end);
        final value = lexer.read();
        Object? stored = value;
        if (value is Map<String, Object?>) {
          lexer.skipSpace();
          if (_latin.startsWith('stream', lexer.pos)) {
            var start = lexer.pos + 6;
            if (start < bytes.length && bytes[start] == 13) start++;
            if (start < bytes.length && bytes[start] == 10) start++;
            var end = _latin.indexOf('endstream', start);
            if (end < 0) end = bytes.length;
            // The line break before "endstream" is not part of the data.
            if (end > start && bytes[end - 1] == 10) end--;
            if (end > start && bytes[end - 1] == 13) end--;
            stored = _Stream(value, Uint8List.sublistView(bytes, start, end));
          }
        }
        _objects[int.parse(m.group(1)!)] = stored;
      } catch (_) {
        // A damaged object is skipped.
      }
    }
    for (final e in _objects.entries.toList()) {
      final o = e.value;
      if (o is _Stream && _nameOf(o.dict['Type']) == 'ObjStm') {
        _expandObjectStream(o);
      }
    }
  }

  void _expandObjectStream(_Stream stream) {
    try {
      final data = _decode(stream);
      final n = _numOf(stream.dict['N'])?.toInt() ?? 0;
      final first = _numOf(stream.dict['First'])?.toInt() ?? 0;
      final head = _Lexer(data);
      final entries = <(int, int)>[];
      for (var i = 0; i < n; i++) {
        final num = head.read(refs: false);
        final off = head.read(refs: false);
        if (num is! int || off is! int) break;
        entries.add((num, off));
      }
      for (final (num, off) in entries) {
        try {
          _objects.putIfAbsent(num, () => _Lexer(data, first + off).read());
        } catch (_) {}
      }
    } catch (_) {}
  }

  Uint8List _decode(_Stream s) {
    final cached = s._decoded;
    if (cached != null) return cached;
    var data = s.raw;
    final filter = _resolve(s.dict['Filter']);
    final filters = filter is List
        ? [for (final f in filter) _nameOf(f)]
        : [_nameOf(filter)];
    final parmsRaw = _resolve(s.dict['DecodeParms'] ?? s.dict['DP']);
    final parms = parmsRaw is List
        ? [for (final p in parmsRaw) _dictOf(p)]
        : [_dictOf(parmsRaw)];
    for (var i = 0; i < filters.length; i++) {
      final f = filters[i];
      if (f == null) continue;
      switch (f) {
        case 'FlateDecode' || 'Fl':
          try {
            data = Uint8List.fromList(ZLibDecoder().decodeBytes(data));
          } catch (_) {
            // A damaged or cut-off stream: keep what is readable.
            try {
              data = Uint8List.fromList(
                ZLibDecoder().decodeBytes(data.sublist(0, data.length - 1)),
              );
            } catch (_) {
              data = Uint8List(0);
            }
          }
          final p = i < parms.length ? parms[i] : null;
          if (p != null) {
            data = _predict(
              data,
              _numOf(p['Predictor'])?.toInt() ?? 1,
              _numOf(p['Columns'])?.toInt() ?? 1,
              _numOf(p['Colors'])?.toInt() ?? 1,
              _numOf(p['BitsPerComponent'])?.toInt() ?? 8,
            );
          }
        case 'ASCII85Decode' || 'A85':
          data = _ascii85(data);
        case 'ASCIIHexDecode' || 'AHx':
          data = _asciiHex(data);
        default:
          // Pictures and other encodings carry no text for us.
          data = Uint8List(0);
      }
    }
    return s._decoded = data;
  }

  // ------------------------------------------------------------------ pages

  List<({Map<String, Object?> dict, Object? resources})> _pages() {
    final result = <({Map<String, Object?> dict, Object? resources})>[];
    Map<String, Object?>? catalog;
    for (final o in _objects.values) {
      final d = o is Map<String, Object?> ? o : null;
      if (d != null && _nameOf(d['Type']) == 'Catalog') catalog = d;
    }
    final seen = <Object>{};
    void walk(Object? node, Object? inherited, int depth) {
      final d = _dictOf(node);
      if (d == null || depth > 40 || !seen.add(d)) return;
      final res = d['Resources'] ?? inherited;
      final kids = _listOf(d['Kids']);
      if (kids != null && _nameOf(d['Type']) != 'Page') {
        for (final k in kids) {
          walk(k, res, depth + 1);
        }
      } else {
        result.add((dict: d, resources: res));
      }
    }

    if (catalog != null) walk(catalog['Pages'], null, 0);
    if (result.isEmpty) {
      final numbers = _objects.keys.toList()..sort();
      for (final n in numbers) {
        final d = _objects[n];
        if (d is Map<String, Object?> && _nameOf(d['Type']) == 'Page') {
          result.add((dict: d, resources: d['Resources']));
        }
      }
    }
    return result;
  }

  String text() {
    _scan();
    // An /Encrypt entry in the trailer (or the cross-reference stream) means
    // the streams are scrambled and need the password.
    if (RegExp(r'/Encrypt\s*(\d+\s+\d+\s+R|<<)').hasMatch(_latin)) {
      throw const PdfTextException(
        'That PDF is password protected, so its text cannot be read.',
      );
    }
    final pages = _pages();
    if (pages.isEmpty) {
      throw const PdfTextException('No pages could be found in that PDF.');
    }
    final out = <String>[];
    for (final page in pages) {
      final content = <int>[];
      final contents = _resolve(page.dict['Contents']);
      final parts = contents is List ? contents : [contents];
      for (final p in parts) {
        final s = _resolve(p);
        if (s is _Stream) {
          content.addAll(_decode(s));
          content.add(10);
        }
      }
      final interp = _TextInterpreter(this);
      interp.run(Uint8List.fromList(content), page.resources, 0);
      out.add(interp.finish());
    }
    var result = out.where((p) => p.trim().isNotEmpty).join('\n\n');
    result = result
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￼￾￿]'), '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (result.isEmpty) {
      throw const PdfTextException(
        'This PDF has no text to import (it may be scanned pictures of pages).',
      );
    }
    return result;
  }

  // ------------------------------------------------------------------ fonts

  final _fonts = <Object, _Font>{};

  _Font fontFor(Object? ref) {
    final d = _dictOf(ref);
    if (d == null) return _Font.fallback();
    return _fonts.putIfAbsent(d, () => _Font(this, d));
  }
}

/// How a font turns the bytes of a string into text, and how wide they are.
class _Font {
  _Font.fallback() : _isType0 = false;

  _Font(_PdfReader r, Map<String, Object?> d)
    : _isType0 = r._nameOf(d['Subtype']) == 'Type0' {
    final to = r._resolve(d['ToUnicode']);
    if (to is _Stream) _readCMap(r._decode(to));
    Map<String, Object?>? descendant;
    if (_isType0) {
      final kids = r._listOf(d['DescendantFonts']);
      descendant = kids == null || kids.isEmpty ? null : r._dictOf(kids.first);
      _defaultWidth = r._numOf(descendant?['DW'])?.toDouble() ?? 1000;
      final w = r._listOf(descendant?['W']);
      if (w != null) _readCidWidths(r, w);
    } else {
      final first = r._numOf(d['FirstChar'])?.toInt() ?? 0;
      final widths = r._listOf(d['Widths']);
      if (widths != null) {
        for (var i = 0; i < widths.length; i++) {
          final v = r._numOf(widths[i]);
          if (v != null) _widths[first + i] = v.toDouble();
        }
      }
      final fd = r._dictOf(d['FontDescriptor']);
      _defaultWidth = r._numOf(fd?['MissingWidth'])?.toDouble() ?? 500;
      _readEncoding(r, d['Encoding']);
    }
  }

  final bool _isType0;
  final _toUnicode = <int, String>{};
  final _encoding = <int, String>{};
  final _widths = <int, double>{};
  double _defaultWidth = 500;
  int _codeBytes = 0; // from the code space of a ToUnicode map, else by type

  int get codeBytes => _codeBytes != 0 ? _codeBytes : (_isType0 ? 2 : 1);

  void _readCMap(Uint8List data) {
    final lexer = _Lexer(data);
    final pending = <Object?>[];
    int codeOf(Object? o) {
      if (o is _Str) {
        var v = 0;
        for (final b in o.bytes) {
          v = v * 256 + b;
        }
        return v;
      }
      return o is int ? o : -1;
    }

    String textOf(Object? o) {
      if (o is _Str) {
        final b = o.bytes;
        if (b.length >= 2) {
          final units = <int>[];
          for (var i = 0; i + 1 < b.length; i += 2) {
            units.add(b[i] * 256 + b[i + 1]);
          }
          return String.fromCharCodes(units);
        }
        return b.isEmpty ? '' : String.fromCharCode(b.first);
      }
      return '';
    }

    String? mode;
    while (!lexer.atEnd) {
      final o = lexer.read(refs: false);
      if (o is _Op) {
        switch (o.name) {
          case 'begincodespacerange':
            mode = 'space';
            pending.clear();
          case 'beginbfchar':
            mode = 'char';
            pending.clear();
          case 'beginbfrange':
            mode = 'range';
            pending.clear();
          case 'endcodespacerange':
            for (var i = 0; i + 1 < pending.length; i += 2) {
              final a = pending[i];
              if (a is _Str && a.bytes.isNotEmpty) _codeBytes = a.bytes.length;
            }
            mode = null;
          case 'endbfchar':
            for (var i = 0; i + 1 < pending.length; i += 2) {
              _toUnicode[codeOf(pending[i])] = textOf(pending[i + 1]);
            }
            mode = null;
          case 'endbfrange':
            var i = 0;
            while (i + 2 < pending.length) {
              final lo = codeOf(pending[i]), hi = codeOf(pending[i + 1]);
              final dst = pending[i + 2];
              if (dst is List<Object?>) {
                for (var c = lo; c <= hi && c - lo < dst.length; c++) {
                  _toUnicode[c] = textOf(dst[c - lo]);
                }
              } else if (dst is _Str && hi - lo < 70000) {
                final base = textOf(dst);
                if (base.isNotEmpty) {
                  final head = base.substring(0, base.length - 1);
                  final last = base.codeUnitAt(base.length - 1);
                  for (var c = lo; c <= hi; c++) {
                    _toUnicode[c] = head + String.fromCharCode(last + c - lo);
                  }
                }
              }
              i += 3;
            }
            mode = null;
        }
        if (mode == null) pending.clear();
      } else if (mode != null) {
        pending.add(o);
      }
    }
  }

  void _readCidWidths(_PdfReader r, List<Object?> w) {
    var i = 0;
    while (i < w.length) {
      final first = r._numOf(w[i])?.toInt();
      if (first == null) break;
      final next = i + 1 < w.length ? r._resolve(w[i + 1]) : null;
      if (next is List<Object?>) {
        for (var k = 0; k < next.length; k++) {
          final v = r._numOf(next[k]);
          if (v != null) _widths[first + k] = v.toDouble();
        }
        i += 2;
      } else {
        final last = r._numOf(next)?.toInt();
        final v = i + 2 < w.length ? r._numOf(w[i + 2]) : null;
        if (last != null && v != null && last - first < 70000) {
          for (var c = first; c <= last; c++) {
            _widths[c] = v.toDouble();
          }
        }
        i += 3;
      }
    }
  }

  void _readEncoding(_PdfReader r, Object? enc) {
    final resolved = r._resolve(enc);
    String? base;
    if (resolved is _Name) {
      base = resolved.value;
    } else if (resolved is Map<String, Object?>) {
      base = r._nameOf(resolved['BaseEncoding']);
      final diffs = r._listOf(resolved['Differences']);
      if (diffs != null) {
        var code = 0;
        for (final item in diffs) {
          final v = r._resolve(item);
          if (v is num) {
            code = v.toInt();
          } else if (v is _Name) {
            final u = _glyphToUnicode(v.value);
            if (u != null) _encoding[code] = u;
            code++;
          }
        }
      }
    }
    if (base == 'MacRomanEncoding') {
      for (var c = 128; c < 256; c++) {
        _encoding.putIfAbsent(c, () => _macRoman[c - 128]);
      }
    } else {
      // WinAnsi, Standard and unspecified encodings: Windows-1252.
      for (var c = 128; c < 256; c++) {
        _encoding.putIfAbsent(c, () => _winAnsi(c));
      }
    }
  }

  /// The text of the string [b], and how far it moves the pen (1/1000 of the
  /// font size).
  ({String text, double advance}) decode(Uint8List b) {
    final out = StringBuffer();
    var advance = 0.0;
    final n = codeBytes;
    for (var i = 0; i + n <= b.length; i += n) {
      var code = 0;
      for (var k = 0; k < n; k++) {
        code = code * 256 + b[i + k];
      }
      final mapped = _toUnicode[code] ?? _encoding[code];
      if (mapped != null) {
        out.write(mapped);
      } else if (!_isType0 || _toUnicode.isEmpty) {
        // No map: the code is the character (plain ASCII, Latin-1).
        if (code >= 32 && code < 256) out.writeCharCode(code);
      }
      advance += _widths[code] ?? _defaultWidth;
    }
    return (text: out.toString(), advance: advance);
  }
}

// ----------------------------------------------------- the text operators

class _TextInterpreter {
  _TextInterpreter(this.reader);
  final _PdfReader reader;
  final _lines = <StringBuffer>[StringBuffer()];

  // The current transformation matrix (a b c d e f) and the saved ones.
  var _ctm = <double>[1, 0, 0, 1, 0, 0];
  final _saved = <List<double>>[];

  // Text state.
  double _a = 1, _b = 0, _c = 0, _d = 1, _e = 0, _f = 0; // text matrix
  double _lineE = 0, _lineF = 0, _leading = 0, _size = 12;
  _Font _font = _Font.fallback();
  // Where the last text ended, to tell spaces and new lines.
  double? _endX, _lastY;
  double _lastSize = 12;
  bool _any = false;

  String finish() {
    final text = _lines
        .map((l) => l.toString().replaceAll(RegExp(r' {2,}'), ' ').trim())
        .join('\n');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  void _newLine({bool blank = false}) {
    if (_lines.last.isEmpty && !blank) return;
    if (blank && _lines.last.isNotEmpty) _lines.add(StringBuffer());
    _lines.add(StringBuffer());
  }

  void run(Uint8List content, Object? resources, int depth) {
    final res = reader._dictOf(resources);
    final fonts = reader._dictOf(res?['Font']);
    final xobjects = reader._dictOf(res?['XObject']);
    final lexer = _Lexer(content);
    final stack = <Object?>[];
    var guard = 0;
    while (!lexer.atEnd && guard++ < 3000000) {
      Object? o;
      try {
        o = lexer.read(refs: false);
      } catch (_) {
        break;
      }
      if (o is! _Op) {
        stack.add(o);
        if (stack.length > 200) stack.removeAt(0);
        continue;
      }
      switch (o.name) {
        case 'q':
          _saved.add(List.of(_ctm));
        case 'Q':
          if (_saved.isNotEmpty) _ctm = _saved.removeLast();
        case 'cm':
          final n = _nums(stack, 6);
          if (n != null) {
            // The new matrix is applied before the current one.
            final m = _ctm;
            _ctm = [
              n[0] * m[0] + n[1] * m[2],
              n[0] * m[1] + n[1] * m[3],
              n[2] * m[0] + n[3] * m[2],
              n[2] * m[1] + n[3] * m[3],
              n[4] * m[0] + n[5] * m[2] + m[4],
              n[4] * m[1] + n[5] * m[3] + m[5],
            ];
          }
        case 'BT':
          _a = 1;
          _b = 0;
          _c = 0;
          _d = 1;
          _e = 0;
          _f = 0;
          _lineE = 0;
          _lineF = 0;
        case 'Tf':
          if (stack.length >= 2) {
            final name = stack[stack.length - 2];
            final size = stack.last;
            if (name is _Name && fonts != null) {
              _font = reader.fontFor(fonts[name.value]);
            }
            if (size is num && size != 0) _size = size.toDouble().abs();
          }
        case 'Tm':
          final n = _nums(stack, 6);
          if (n != null) {
            _a = n[0];
            _b = n[1];
            _c = n[2];
            _d = n[3];
            _e = n[4];
            _f = n[5];
            _lineE = _e;
            _lineF = _f;
          }
        case 'Td':
          final n = _nums(stack, 2);
          if (n != null) _move(n[0], n[1]);
        case 'TD':
          final n = _nums(stack, 2);
          if (n != null) {
            _leading = -n[1];
            _move(n[0], n[1]);
          }
        case 'TL':
          final n = _nums(stack, 1);
          if (n != null) _leading = n[0];
        case 'T*':
          _move(0, -_leading);
        case 'Tj':
          if (stack.isNotEmpty && stack.last is _Str) {
            _show((stack.last as _Str).bytes);
          }
        case "'":
          _move(0, -_leading);
          if (stack.isNotEmpty && stack.last is _Str) {
            _show((stack.last as _Str).bytes);
          }
        case '"':
          _move(0, -_leading);
          if (stack.isNotEmpty && stack.last is _Str) {
            _show((stack.last as _Str).bytes);
          }
        case 'TJ':
          if (stack.isNotEmpty && stack.last is List) {
            for (final item in stack.last as List) {
              if (item is _Str) {
                _show(item.bytes);
              } else if (item is num) {
                _e -= item / 1000 * _size * _a;
              }
            }
          }
        case 'Do':
          if (depth < 5 &&
              stack.isNotEmpty &&
              stack.last is _Name &&
              xobjects != null) {
            final x = reader._resolve(xobjects[(stack.last as _Name).value]);
            if (x is _Stream && reader._nameOf(x.dict['Subtype']) == 'Form') {
              final sa = _a, sb = _b, sc = _c, sd = _d, se = _e, sf = _f;
              final sle = _lineE, slf = _lineF, sfont = _font, ssize = _size;
              final sctm = List.of(_ctm), sstack = List.of(_saved);
              run(
                reader._decode(x),
                x.dict['Resources'] ?? resources,
                depth + 1,
              );
              _a = sa;
              _b = sb;
              _c = sc;
              _d = sd;
              _e = se;
              _f = sf;
              _lineE = sle;
              _lineF = slf;
              _font = sfont;
              _size = ssize;
              _ctm = sctm;
              _saved
                ..clear()
                ..addAll(sstack);
            }
          }
        case 'ET':
          break;
      }
      stack.clear();
    }
  }

  List<double>? _nums(List<Object?> stack, int count) {
    if (stack.length < count) return null;
    final out = <double>[];
    for (final v in stack.sublist(stack.length - count)) {
      if (v is! num) return null;
      out.add(v.toDouble());
    }
    return out;
  }

  void _move(double tx, double ty) {
    _lineE += tx * _a + ty * _c;
    _lineF += tx * _b + ty * _d;
    _e = _lineE;
    _f = _lineF;
  }

  /// Where the pen is on the page: the text matrix's origin, moved by the
  /// current transformation matrix.
  (double, double) _user() => (
    _e * _ctm[0] + _f * _ctm[2] + _ctm[4],
    _e * _ctm[1] + _f * _ctm[3] + _ctm[5],
  );

  void _show(Uint8List bytes) {
    final shown = _font.decode(bytes);
    // The font size on the page: the text and page matrices both scale it.
    final textScale = _hypot(_c, _d), pageScale = _hypot(_ctm[2], _ctm[3]);
    final scale = textScale * pageScale;
    final size = _size * (scale > 0 ? scale : 1);
    final here = _user();
    if (shown.text.isNotEmpty) {
      final y = here.$2;
      if (_any && _lastY != null) {
        final dy = (y - _lastY!).abs();
        final line = size > _lastSize ? size : _lastSize;
        if (dy > line * 0.35) {
          // A new line; a big jump leaves a blank line (a new paragraph).
          _newLine(blank: dy > line * 1.75);
        } else {
          final gap = here.$1 - (_endX ?? here.$1);
          final current = _lines.last.toString();
          if (current.isNotEmpty &&
              !current.endsWith(' ') &&
              !shown.text.startsWith(' ') &&
              gap > size * 0.12) {
            _lines.last.write(' ');
          }
        }
      }
      _lines.last.write(shown.text);
      _any = true;
      _lastY = y;
      _lastSize = size;
    }
    // The pen moves along the text by the width of what was shown.
    _e += shown.advance / 1000 * _size * _a;
    _f += shown.advance / 1000 * _size * _b;
    _endX = _user().$1;
  }
}

double _hypot(double a, double b) => math.sqrt(a * a + b * b);

// -------------------------------------------------------------- code tables

String _winAnsi(int c) {
  const specials = {
    0x80: '€',
    0x82: '‚',
    0x83: 'ƒ',
    0x84: '„',
    0x85: '…',
    0x86: '†',
    0x87: '‡',
    0x88: 'ˆ',
    0x89: '‰',
    0x8A: 'Š',
    0x8B: '‹',
    0x8C: 'Œ',
    0x8E: 'Ž',
    0x91: '‘',
    0x92: '’',
    0x93: '“',
    0x94: '”',
    0x95: '•',
    0x96: '–',
    0x97: '—',
    0x98: '˜',
    0x99: '™',
    0x9A: 'š',
    0x9B: '›',
    0x9C: 'œ',
    0x9E: 'ž',
    0x9F: 'Ÿ',
  };
  return specials[c] ?? String.fromCharCode(c);
}

const _macRoman =
    'ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø'
    '¿¡¬√ƒ≈∆«»… ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ';

String? _glyphToUnicode(String name) {
  if (name.length == 1) return name;
  final uni = RegExp(r'^uni([0-9A-Fa-f]{4})').firstMatch(name);
  if (uni != null) {
    return String.fromCharCode(int.parse(uni.group(1)!, radix: 16));
  }
  final u = RegExp(r'^u([0-9A-Fa-f]{4,6})$').firstMatch(name);
  if (u != null) return String.fromCharCode(int.parse(u.group(1)!, radix: 16));
  final dot = name.indexOf('.');
  if (dot > 0) return _glyphToUnicode(name.substring(0, dot));
  return _glyphNames[name];
}

const _glyphNames = <String, String>{
  'space': ' ',
  'exclam': '!',
  'quotedbl': '"',
  'numbersign': '#',
  'dollar': r'$',
  'percent': '%',
  'ampersand': '&',
  'quotesingle': "'",
  'parenleft': '(',
  'parenright': ')',
  'asterisk': '*',
  'plus': '+',
  'comma': ',',
  'hyphen': '-',
  'minus': '−',
  'period': '.',
  'slash': '/',
  'zero': '0',
  'one': '1',
  'two': '2',
  'three': '3',
  'four': '4',
  'five': '5',
  'six': '6',
  'seven': '7',
  'eight': '8',
  'nine': '9',
  'colon': ':',
  'semicolon': ';',
  'less': '<',
  'equal': '=',
  'greater': '>',
  'question': '?',
  'at': '@',
  'bracketleft': '[',
  'backslash': r'\',
  'bracketright': ']',
  'asciicircum': '^',
  'underscore': '_',
  'grave': '`',
  'braceleft': '{',
  'bar': '|',
  'braceright': '}',
  'asciitilde': '~',
  'bullet': '•',
  'endash': '–',
  'emdash': '—',
  'quoteleft': '‘',
  'quoteright': '’',
  'quotedblleft': '“',
  'quotedblright': '”',
  'quotesinglbase': '‚',
  'quotedblbase': '„',
  'ellipsis': '…',
  'fi': 'ﬁ',
  'fl': 'ﬂ',
  'ff': 'ﬀ',
  'ffi': 'ﬃ',
  'ffl': 'ﬄ',
  'Euro': '€',
  'copyright': '©',
  'registered': '®',
  'trademark': '™',
  'degree': '°',
  'plusminus': '±',
  'multiply': '×',
  'divide': '÷',
  'section': '§',
  'paragraph': '¶',
  'periodcentered': '·',
  'dagger': '†',
  'daggerdbl': '‡',
  'guillemotleft': '«',
  'guillemotright': '»',
  'guilsinglleft': '‹',
  'guilsinglright': '›',
  'sterling': '£',
  'yen': '¥',
  'cent': '¢',
  'currency': '¤',
  'brokenbar': '¦',
  'ordfeminine': 'ª',
  'ordmasculine': 'º',
  'questiondown': '¿',
  'exclamdown': '¡',
  'logicalnot': '¬',
  'mu': 'µ',
  'onequarter': '¼',
  'onehalf': '½',
  'threequarters': '¾',
  'germandbls': 'ß',
  'nbspace': ' ',
  'nonbreakingspace': ' ',
  'AE': 'Æ',
  'ae': 'æ',
  'Oslash': 'Ø',
  'oslash': 'ø',
  'OE': 'Œ',
  'oe': 'œ',
  'Aacute': 'Á',
  'aacute': 'á',
  'Agrave': 'À',
  'agrave': 'à',
  'Acircumflex': 'Â',
  'acircumflex': 'â',
  'Adieresis': 'Ä',
  'adieresis': 'ä',
  'Atilde': 'Ã',
  'atilde': 'ã',
  'Aring': 'Å',
  'aring': 'å',
  'Ccedilla': 'Ç',
  'ccedilla': 'ç',
  'Eacute': 'É',
  'eacute': 'é',
  'Egrave': 'È',
  'egrave': 'è',
  'Ecircumflex': 'Ê',
  'ecircumflex': 'ê',
  'Edieresis': 'Ë',
  'edieresis': 'ë',
  'Iacute': 'Í',
  'iacute': 'í',
  'Igrave': 'Ì',
  'igrave': 'ì',
  'Icircumflex': 'Î',
  'icircumflex': 'î',
  'Idieresis': 'Ï',
  'idieresis': 'ï',
  'Ntilde': 'Ñ',
  'ntilde': 'ñ',
  'Oacute': 'Ó',
  'oacute': 'ó',
  'Ograve': 'Ò',
  'ograve': 'ò',
  'Ocircumflex': 'Ô',
  'ocircumflex': 'ô',
  'Odieresis': 'Ö',
  'odieresis': 'ö',
  'Otilde': 'Õ',
  'otilde': 'õ',
  'Uacute': 'Ú',
  'uacute': 'ú',
  'Ugrave': 'Ù',
  'ugrave': 'ù',
  'Ucircumflex': 'Û',
  'ucircumflex': 'û',
  'Udieresis': 'Ü',
  'udieresis': 'ü',
  'Yacute': 'Ý',
  'yacute': 'ý',
  'ydieresis': 'ÿ',
  'Scaron': 'Š',
  'scaron': 'š',
  'Zcaron': 'Ž',
  'zcaron': 'ž',
  'Lslash': 'Ł',
  'lslash': 'ł',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'epsilon': 'ε',
  'theta': 'θ',
  'lambda': 'λ',
  'pi': 'π',
  'sigma': 'σ',
  'omega': 'ω',
  'Delta': 'Δ',
  'Omega': 'Ω',
  'Sigma': 'Σ',
  'infinity': '∞',
  'notequal': '≠',
  'lessequal': '≤',
  'greaterequal': '≥',
  'summation': '∑',
  'radical': '√',
};

/// Reads [bytes] as text for callers that need the file's own encoding.
String decodeLatin1(Uint8List bytes) =>
    latin1.decode(bytes, allowInvalid: true);
