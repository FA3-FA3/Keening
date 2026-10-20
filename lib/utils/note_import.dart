import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'pdf_text.dart';
import 'rich_text.dart';

/// Pictures in an imported note are named like this until they are uploaded:
/// `import:0` is [NoteImport.images] index 0.
const importImagePrefix = 'import:';

/// Why a file could not be imported; [message] is fit to show.
class NoteImportException implements Exception {
  const NoteImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What was read from a file for a Notepad: the text and its formatting, the
/// pictures it holds (to be uploaded and renamed), and anything that was left
/// out or could not be kept.
class NoteImport {
  const NoteImport(this.text, this.runs, this.images, this.notes);
  final String text;
  final List<StyleRun> runs;
  final List<Uint8List> images;
  final List<String> notes;
}

/// The most a note holds (the same limits the editor and server use).
const _maxChars = 200000;
const _maxRuns = 5000;
const _maxEmbeds = 100;

/// The kinds of file a Notepad can be imported from.
const noteImportExtensions = ['docx', 'txt', 'pdf'];

/// Reads a Word (.docx), PDF or plain text file. The kind is worked out from
/// what is in the file, not its name.
NoteImport importNoteFile(String fileName, Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const NoteImportException('That file is empty.');
  }
  final head = String.fromCharCodes(
    bytes.length > 1024 ? bytes.sublist(0, 1024) : bytes,
  );
  if (head.contains('%PDF-')) {
    try {
      return _finish(extractPdfText(bytes), const [], const [], [
        'Only the text of a PDF is imported, not its layout or pictures.',
      ]);
    } on PdfTextException catch (e) {
      throw NoteImportException(e.message);
    }
  }
  if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return _docx(bytes);
  }
  if (bytes.length > 8 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0) {
    throw const NoteImportException(
      'That is an older Word file (.doc). Save it as .docx in Word first.',
    );
  }
  return _plainText(bytes);
}

/// [n] with its pictures renamed to the ids they were stored under ([ids] by
/// index in [NoteImport.images]). A picture with no id (it could not be stored)
/// is taken out of the text, and the formatting after it moves up to match.
({String text, List<StyleRun> runs}) withStoredPictures(
  NoteImport n,
  Map<int, String> ids,
) {
  int? indexOf(Embed e) =>
      int.tryParse(e.imageId!.replaceFirst(importImagePrefix, ''));
  final removed = <int>{};
  for (final r in n.runs) {
    final e = r.format.embed;
    if (e == null || !e.isImage) continue;
    final index = indexOf(e);
    if (index == null || ids[index] == null) {
      for (var i = r.start; i < r.end; i++) {
        removed.add(i);
      }
    }
  }
  final out = StringBuffer();
  // How many characters are kept before each position.
  final before = List<int>.filled(n.text.length + 1, 0);
  for (var i = 0; i < n.text.length; i++) {
    before[i] = out.length;
    if (!removed.contains(i)) out.write(n.text[i]);
  }
  before[n.text.length] = out.length;
  final runs = <StyleRun>[];
  for (final r in n.runs) {
    final e = r.format.embed;
    var format = r.format;
    if (e != null && e.isImage) {
      final index = indexOf(e);
      final id = index == null ? null : ids[index];
      if (id == null) continue;
      format = format.copyWith(embed: Embed.image(id));
    }
    final start = before[r.start], end = before[r.end];
    if (end > start) runs.add(StyleRun(start, end, format));
  }
  return (text: out.toString(), runs: runs);
}

// -------------------------------------------------------------------- text

NoteImport _plainText(Uint8List bytes) {
  String text;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = _utf16(bytes, 2, littleEndian: true);
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = _utf16(bytes, 2, littleEndian: false);
  } else {
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  var nul = 0;
  for (var i = 0; i < text.length && i < 4096; i++) {
    if (text.codeUnitAt(i) == 0) nul++;
  }
  if (nul > 8) {
    throw const NoteImportException(
      'That does not look like a text, Word or PDF file.',
    );
  }
  return _finish(text, const [], const [], const []);
}

String _utf16(Uint8List b, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Cleans line ends and stray characters, then trims to what a note can hold.
NoteImport _finish(
  String text,
  List<StyleRun> runs,
  List<Uint8List> images,
  List<String> notes,
) {
  final notes0 = List.of(notes);
  var cleaned = text;
  var kept = runs;
  // Line ends and control characters (not for rich text, whose runs would
  // slip: that text is already clean).
  if (runs.isEmpty) {
    cleaned = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￼￾￿]'), '');
  }
  if (cleaned.length > _maxChars) {
    var cut = cleaned.lastIndexOf('\n', _maxChars);
    if (cut < _maxChars ~/ 2) cut = _maxChars;
    cleaned = cleaned.substring(0, cut);
    notes0.add(
      'The text was longer than a note can hold ($_maxChars characters), '
      'so the end was left out.',
    );
  }
  kept = [
    for (final r in kept)
      if (r.end <= cleaned.length)
        r
      else if (r.start < cleaned.length)
        StyleRun(r.start, cleaned.length, r.format),
  ];
  var embeds = 0;
  final embedRuns = <StyleRun>[];
  var dropped = 0;
  for (final r in kept) {
    if (r.format.embed == null) {
      embedRuns.add(r);
    } else if (embeds + (r.end - r.start) <= _maxEmbeds) {
      embeds += r.end - r.start;
      embedRuns.add(r);
    } else {
      dropped += r.end - r.start;
    }
  }
  if (dropped > 0) {
    notes0.add(
      'A note holds up to $_maxEmbeds pictures, so $dropped were left out.',
    );
  }
  // Dropped pictures leave their placeholder out of the text.
  var finalText = cleaned;
  var finalRuns = embedRuns;
  if (dropped > 0) {
    final keepIndex = <int>[];
    final kept2 = <int>{
      for (final r in embedRuns)
        ...List.generate(r.end - r.start, (i) => r.start + i),
    };
    final buffer = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      if (cleaned[i] == embedChar && !kept2.contains(i)) continue;
      keepIndex.add(i);
      buffer.write(cleaned[i]);
    }
    finalText = buffer.toString();
    final newIndex = {
      for (var j = 0; j < keepIndex.length; j++) keepIndex[j]: j,
    };
    finalRuns = [
      for (final r in embedRuns)
        StyleRun(newIndex[r.start]!, newIndex[r.end - 1]! + 1, r.format),
    ];
  }
  if (finalRuns.length > _maxRuns) {
    finalRuns = finalRuns.sublist(0, _maxRuns);
    notes0.add('Some of the formatting was too detailed to keep.');
  }
  if (finalText.trim().isEmpty && images.isEmpty) {
    throw const NoteImportException('There is no text in that file.');
  }
  return NoteImport(finalText, finalRuns, images, notes0);
}

// -------------------------------------------------------------------- docx

class _Props {
  _Props({
    this.bold,
    this.italic,
    this.underline,
    this.size,
    this.color,
    this.highlight,
    this.script,
    this.numId,
    this.level,
    this.indent,
  });
  bool? bold, italic, underline;
  int? size; // half-points
  String? color, highlight, script;
  String? numId;
  int? level;
  int? indent; // twips

  /// [over] on top of this.
  _Props merged(_Props over) => _Props(
    bold: over.bold ?? bold,
    italic: over.italic ?? italic,
    underline: over.underline ?? underline,
    size: over.size ?? size,
    color: over.color ?? color,
    highlight: over.highlight ?? highlight,
    script: over.script ?? script,
    numId: over.numId ?? numId,
    level: over.level ?? level,
    indent: over.indent ?? indent,
  );
}

const _typedBullets = {'•', '●', '▪', '■', '◦', '·', '○', '□', '▫'};

/// Typed bullets that are square.
const _squareBullets = {'▪', '■', '□', '▫'};

const _highlightNames = {
  'black': '000000',
  'blue': '0000FF',
  'cyan': '00FFFF',
  'green': '00FF00',
  'magenta': 'FF00FF',
  'red': 'FF0000',
  'yellow': 'FFFF00',
  'white': 'FFFFFF',
  'darkBlue': '000080',
  'darkCyan': '008080',
  'darkGreen': '008000',
  'darkMagenta': '800080',
  'darkRed': '800000',
  'darkYellow': '808000',
  'darkGray': '808080',
  'lightGray': 'C0C0C0',
};

String? _attr(XmlElement e, String name) {
  for (final a in e.attributes) {
    if (a.name.local == name) return a.value;
  }
  return null;
}

Iterable<XmlElement> _kids(XmlElement e, String name) =>
    e.children.whereType<XmlElement>().where((c) => c.name.local == name);

XmlElement? _kid(XmlElement? e, String name) =>
    e == null ? null : _kids(e, name).firstOrNull;

String? _val(XmlElement? e) => e == null ? null : _attr(e, 'val');

/// A toggle such as `<w:b/>` (on) or `<w:b w:val="0"/>` (off); null when absent.
bool? _toggle(XmlElement? rPr, String name) {
  final e = _kid(rPr, name);
  if (e == null) return null;
  final v = _attr(e, 'val');
  return !(v == '0' || v == 'false' || v == 'off' || v == 'none');
}

_Props _runProps(XmlElement? rPr) {
  if (rPr == null) return _Props();
  final u = _kid(rPr, 'u');
  final color = _val(_kid(rPr, 'color'));
  final hl = _val(_kid(rPr, 'highlight'));
  final shd = _kid(rPr, 'shd');
  final fill = shd == null ? null : _attr(shd, 'fill');
  String? highlight;
  if (hl != null && hl != 'none') {
    highlight = _highlightNames[hl];
  } else if (fill != null &&
      RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(fill) &&
      fill.toUpperCase() != 'FFFFFF') {
    highlight = fill.toUpperCase();
  }
  final sz = _val(_kid(rPr, 'sz'));
  return _Props(
    bold: _toggle(rPr, 'b'),
    italic: _toggle(rPr, 'i'),
    underline: u == null
        ? null
        : (_attr(u, 'val') != 'none' && _attr(u, 'val') != '0'),
    size: sz == null ? null : int.tryParse(sz),
    color: color != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(color)
        ? color.toUpperCase()
        : (color == 'auto' ? '' : null),
    highlight: highlight,
    script: _val(_kid(rPr, 'vertAlign')),
  );
}

_Props _paragraphProps(XmlElement? pPr) {
  if (pPr == null) return _Props();
  final numPr = _kid(pPr, 'numPr');
  final ind = _kid(pPr, 'ind');
  final left = ind == null ? null : (_attr(ind, 'left') ?? _attr(ind, 'start'));
  final hanging = ind == null
      ? null
      : int.tryParse(_attr(ind, 'hanging') ?? '');
  // Where the first line starts: a hanging indent pulls it back from the left.
  final first = left == null
      ? null
      : ((int.tryParse(left) ?? 0) - (hanging ?? 0)).clamp(0, 1 << 30);
  return _Props(
    numId: _val(_kid(numPr, 'numId')),
    level: int.tryParse(_val(_kid(numPr, 'ilvl')) ?? ''),
    indent: first,
  );
}

class _DocxReader {
  _DocxReader(this.archive);
  final Archive archive;

  final images = <Uint8List>[];
  final _imageIndex = <String, int>{};
  var skippedImages = 0;
  final text = StringBuffer();
  final runs = <StyleRun>[];

  final _styles = <String, ({String? basedOn, _Props props})>{};
  final _numFormats = <String, Map<int, String>>{}; // numId -> level -> format
  final _counters = <String, List<int>>{};
  final _rels = <String, String>{};
  int _defaultSize = 22;

  /// True until something has been written on the paragraph's line.
  bool _lineFresh = false;

  XmlDocument? _xml(String name) {
    final f = archive.findFile(name);
    if (f == null) return null;
    try {
      return XmlDocument.parse(utf8.decode(f.content as List<int>));
    } catch (_) {
      return null;
    }
  }

  void _readStyles() {
    final doc = _xml('word/styles.xml');
    final root = doc?.rootElement;
    if (root == null) return;
    final dd = _kid(_kid(_kid(root, 'docDefaults'), 'rPrDefault'), 'rPr');
    final dsz = int.tryParse(_val(_kid(dd, 'sz')) ?? '');
    if (dsz != null && dsz > 0) _defaultSize = dsz;
    for (final s in _kids(root, 'style')) {
      final id = _attr(s, 'styleId');
      if (id == null) continue;
      final props = _runProps(
        _kid(s, 'rPr'),
      ).merged(_paragraphProps(_kid(s, 'pPr')));
      _styles[id] = (basedOn: _val(_kid(s, 'basedOn')), props: props);
    }
    // Text sized in the Normal style is the base size.
    final normal = _styles['Normal'];
    if (normal?.props.size != null) _defaultSize = normal!.props.size!;
  }

  _Props _style(String? id, [int depth = 0]) {
    final s = id == null ? null : _styles[id];
    if (s == null || depth > 12) return _Props();
    return _style(s.basedOn, depth + 1).merged(s.props);
  }

  void _readNumbering() {
    final root = _xml('word/numbering.xml')?.rootElement;
    if (root == null) return;
    final abstract = <String, Map<int, String>>{};
    for (final a in _kids(root, 'abstractNum')) {
      final id = _attr(a, 'abstractNumId');
      if (id == null) continue;
      abstract[id] = {
        for (final l in _kids(a, 'lvl'))
          int.tryParse(_attr(l, 'ilvl') ?? '0') ?? 0:
              _val(_kid(l, 'numFmt')) ?? 'bullet',
      };
    }
    for (final n in _kids(root, 'num')) {
      final id = _attr(n, 'numId');
      final a = _val(_kid(n, 'abstractNumId'));
      if (id != null && a != null && abstract[a] != null) {
        _numFormats[id] = abstract[a]!;
      }
    }
  }

  void _readRels() {
    final root = _xml('word/_rels/document.xml.rels')?.rootElement;
    if (root == null) return;
    for (final r in _kids(root, 'Relationship')) {
      final id = _attr(r, 'Id'), target = _attr(r, 'Target');
      if (id != null && target != null) _rels[id] = target;
    }
  }

  int? _picture(String? rId) {
    final target = rId == null ? null : _rels[rId];
    if (target == null) return null;
    final path = target.startsWith('/')
        ? target.substring(1)
        : 'word/${target.replaceFirst(RegExp(r'^\./'), '')}';
    final cached = _imageIndex[path];
    if (cached != null) return cached;
    final lower = path.toLowerCase();
    if (!RegExp(r'\.(png|jpe?g|gif|bmp|webp)$').hasMatch(lower)) {
      skippedImages++;
      return null;
    }
    final f = archive.findFile(path);
    if (f == null) {
      skippedImages++;
      return null;
    }
    final bytes = Uint8List.fromList(f.content as List<int>);
    images.add(bytes);
    return _imageIndex[path] = images.length - 1;
  }

  // ------------------------------------------------------------- building

  void _add(String s, TextFormat format) {
    if (s.isEmpty) return;
    final start = text.length;
    text.write(s);
    if (format.isPlain) return;
    final last = runs.isEmpty ? null : runs.last;
    if (last != null && last.end == start && last.format == format) {
      runs[runs.length - 1] = StyleRun(last.start, start + s.length, format);
    } else {
      runs.add(StyleRun(start, start + s.length, format));
    }
  }

  TextFormat _format(_Props p) {
    final size = p.size;
    double? px;
    if (size != null && _defaultSize > 0) {
      final ratio = size / _defaultSize;
      if ((ratio - 1).abs() >= 0.04) {
        px = ((16 * ratio) * 2).round() / 2;
        px = px.clamp(8.0, 200.0).toDouble();
      }
    }
    final color = p.color;
    return TextFormat(
      size: px,
      color: color == null || color.isEmpty || color == '000000'
          ? null
          : '#$color',
      highlight: p.highlight == null ? null : '#${p.highlight}',
      bold: p.bold ?? false,
      italic: p.italic ?? false,
      underline: p.underline ?? false,
      subscript: p.script == 'subscript',
      superscript: p.script == 'superscript',
    );
  }

  void _run(XmlElement r, _Props base, {required bool inCell}) {
    final own = _runProps(_kid(r, 'rPr'));
    final style = _style(_val(_kid(_kid(r, 'rPr'), 'rStyle')));
    final format = _format(base.merged(style).merged(own));
    final parts = r.children.whereType<XmlElement>().toList();
    for (var i = 0; i < parts.length; i++) {
      final c = parts[i];
      switch (c.name.local) {
        case 't':
          // A typed bullet and a tab at the start of a line (as this app and
          // some others write bullet points) is a bullet point here too.
          if (_lineFresh &&
              _typedBullets.contains(c.innerText.trim()) &&
              i + 1 < parts.length &&
              parts[i + 1].name.local == 'tab') {
            _add(
              _squareBullets.contains(c.innerText.trim())
                  ? squareBulletMark
                  : bulletMark,
              format,
            );
            _lineFresh = false;
            i++;
            continue;
          }
          if (c.innerText.isNotEmpty) _lineFresh = false;
          _add(c.innerText, format);
        case 'tab':
          _lineFresh = false;
          _add('\t', format);
        case 'br' || 'cr':
          _add(inCell ? ' ' : '\n', format);
        case 'noBreakHyphen':
          _add('-', format);
        case 'drawing' || 'pict' || 'object':
          _drawing(c);
        case 'AlternateContent':
          final choice = _kid(c, 'Choice') ?? _kid(c, 'Fallback');
          if (choice != null) {
            for (final d in choice.children.whereType<XmlElement>()) {
              if (d.name.local == 'drawing' || d.name.local == 'pict') {
                _drawing(d);
              }
            }
          }
      }
    }
  }

  void _drawing(XmlElement e) {
    String? rId;
    for (final d in e.descendants.whereType<XmlElement>()) {
      if (d.name.local == 'blip') {
        rId = _attr(d, 'embed');
        break;
      }
      if (d.name.local == 'imagedata') {
        rId = _attr(d, 'id');
        break;
      }
    }
    final index = _picture(rId);
    if (index != null) {
      final start = text.length;
      text.write(embedChar);
      runs.add(
        StyleRun(
          start,
          start + 1,
          TextFormat(embed: Embed.image('$importImagePrefix$index')),
        ),
      );
    }
  }

  void _inline(XmlElement parent, _Props base, {required bool inCell}) {
    for (final c in parent.children.whereType<XmlElement>()) {
      switch (c.name.local) {
        case 'r':
          _run(c, base, inCell: inCell);
        case 'hyperlink' ||
            'ins' ||
            'smartTag' ||
            'sdt' ||
            'fldSimple' ||
            'sdtContent' ||
            'customXml':
          _inline(c, base, inCell: inCell);
      }
    }
  }

  static String _roman(int n) {
    const parts = [
      (1000, 'm'),
      (900, 'cm'),
      (500, 'd'),
      (400, 'cd'),
      (100, 'c'),
      (90, 'xc'),
      (50, 'l'),
      (40, 'xl'),
      (10, 'x'),
      (9, 'ix'),
      (5, 'v'),
      (4, 'iv'),
      (1, 'i'),
    ];
    var v = n;
    final out = StringBuffer();
    for (final (value, sym) in parts) {
      while (v >= value) {
        out.write(sym);
        v -= value;
      }
    }
    return out.toString();
  }

  static String _letters(int n) {
    var v = n;
    final out = <int>[];
    while (v > 0) {
      v--;
      out.add(97 + v % 26);
      v ~/= 26;
    }
    return String.fromCharCodes(out.reversed);
  }

  String _marker(String numId, int level) {
    final format = _numFormats[numId]?[level] ?? 'bullet';
    if (format == 'bullet' || format == 'none') return bulletMark;
    final counters = _counters.putIfAbsent(numId, () => List.filled(10, 0));
    final l = level.clamp(0, 9);
    counters[l]++;
    for (var i = l + 1; i < counters.length; i++) {
      counters[i] = 0;
    }
    final n = counters[l];
    final label = switch (format) {
      'lowerLetter' => _letters(n),
      'upperLetter' => _letters(n).toUpperCase(),
      'lowerRoman' => _roman(n),
      'upperRoman' => _roman(n).toUpperCase(),
      _ => '$n',
    };
    return '$label. ';
  }

  void _paragraph(XmlElement p, {required bool inCell}) {
    final pPr = _kid(p, 'pPr');
    final styleId = _val(_kid(pPr, 'pStyle'));
    final styleProps = _style(styleId);
    final direct = _paragraphProps(pPr);
    // The paragraph's style gives its runs their default look.
    final base = styleProps;
    final numId = direct.numId ?? styleProps.numId;
    final level = direct.level ?? styleProps.level ?? 0;
    if (!inCell) {
      if (numId != null && numId != '0') {
        text.write(' ' * (level.clamp(0, 5) * indentWidth));
        text.write(_marker(numId, level));
      } else {
        final left = direct.indent ?? styleProps.indent ?? 0;
        final spaces = ((left / 480).round() * indentWidth).clamp(0, 24);
        if (spaces > 0) text.write(' ' * spaces);
      }
    }
    _lineFresh = !inCell && (numId == null || numId == '0');
    _inline(p, base, inCell: inCell);
    _lineFresh = false;
  }

  void _block(XmlElement parent) {
    for (final c in parent.children.whereType<XmlElement>()) {
      switch (c.name.local) {
        case 'p':
          if (text.isNotEmpty || runs.isNotEmpty) text.write('\n');
          _paragraph(c, inCell: false);
        case 'tbl':
          for (final tr in _kids(c, 'tr')) {
            if (text.isNotEmpty) text.write('\n');
            var first = true;
            for (final tc in _kids(tr, 'tc')) {
              if (!first) text.write('\t');
              first = false;
              var firstPara = true;
              for (final p in _kids(tc, 'p')) {
                if (!firstPara) text.write(' ');
                firstPara = false;
                _paragraph(p, inCell: true);
              }
            }
          }
        case 'sdt':
          final content = _kid(c, 'sdtContent');
          if (content != null) _block(content);
      }
    }
  }

  NoteImport read() {
    final doc = _xml('word/document.xml');
    final body = doc == null ? null : _kid(doc.rootElement, 'body');
    if (body == null) {
      throw const NoteImportException(
        'That file is not a Word document (.docx).',
      );
    }
    _readStyles();
    _readNumbering();
    _readRels();
    _block(body);
    final notes = <String>[];
    if (skippedImages > 0) {
      notes.add(
        '$skippedImages picture${skippedImages == 1 ? '' : 's'} in a format '
        'that cannot be imported ${skippedImages == 1 ? 'was' : 'were'} left out.',
      );
    }
    return _finish(text.toString(), runs, images, notes);
  }
}

NoteImport _docx(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const NoteImportException(
      'That file could not be read. It may be damaged.',
    );
  }
  if (archive.findFile('word/document.xml') == null) {
    throw const NoteImportException(
      'That file is not a Word document (.docx).',
    );
  }
  return _DocxReader(archive).read();
}
