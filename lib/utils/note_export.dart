import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'equation_png.dart';
import 'export_layout.dart';
import 'file_export.dart';
import 'rich_text.dart';

typedef ImageLoader = Future<Uint8List> Function(String imageId);
typedef EquationRenderer =
    Future<RenderedEquation?> Function(String latex, Color color);

/// The base size of note text: 16 px, which is 12 pt.
const _basePx = 16.0;
const _ptPerPx = 0.75;

/// Writes a Notepad out as a plain text, Word or PDF file.
class NoteExporter {
  NoteExporter({
    required this.text,
    required this.runs,
    required this.loadImage,
    required this.renderEquation,
  }) : lines = exportLines(text, runs);

  final String text;
  final List<StyleRun> runs;
  final ImageLoader loadImage;
  final EquationRenderer renderEquation;
  final List<ExportLine> lines;

  static String _key(ExportPiece p) {
    final e = p.embed!;
    return e.isImage ? 'i:${e.imageId}' : 'e:${e.latex}|${p.format.color}';
  }

  /// Every picture and equation in the note, ready to embed; null for one that
  /// could not be loaded or drawn.
  Future<Map<String, ExportPicture?>> _pictures() async {
    final out = <String, ExportPicture?>{};
    for (final line in lines) {
      for (final piece in line.pieces) {
        final embed = piece.embed;
        if (embed == null) continue;
        final key = _key(piece);
        if (out.containsKey(key)) continue;
        out[key] = embed.isImage
            ? await _loadPicture(embed.imageId!)
            : await _drawEquation(embed.latex!, piece.format.color);
      }
    }
    return out;
  }

  Future<ExportPicture?> _loadPicture(String id) async {
    try {
      final bytes = await loadImage(id);
      final size = await pictureSize(bytes);
      if (size == null) return null;
      final shown = notePictureSize(
        size.width.toDouble(),
        size.height.toDouble(),
      );
      return ExportPicture(
        bytes,
        size.width,
        size.height,
        'Picture',
        shownWidth: shown.width,
        shownHeight: shown.height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ExportPicture?> _drawEquation(String latex, String? color) async {
    final drawn = await renderEquation(
      latex,
      color == null ? Colors.black : colorOfHex(color),
    );
    if (drawn == null) return null;
    final size = await pictureSize(drawn.png);
    return ExportPicture(
      drawn.png,
      size?.width ?? (drawn.width * 3).round(),
      size?.height ?? (drawn.height * 3).round(),
      latex,
      shownWidth: drawn.width,
      shownHeight: drawn.height,
    );
  }

  // -------------------------------------------------------------------- txt

  /// Plain text: formatting is dropped, a picture shows as [picture] and an
  /// equation as its LaTeX between dollar signs.
  Uint8List toTxt() {
    final out = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.pageBreak) {
        out.write('\f');
        if (i < lines.length - 1) out.write('\n');
        continue;
      }
      out.write(' ' * line.indent);
      if (line.bullet) out.write(line.mark);
      for (final piece in line.pieces) {
        final embed = piece.embed;
        if (embed == null) {
          out.write(piece.text);
        } else {
          out.write(embed.isImage ? '[picture]' : '\$${embed.latex}\$');
        }
      }
      if (i < lines.length - 1) out.write('\n');
    }
    return Uint8List.fromList(utf8.encode(out.toString()));
  }

  // ------------------------------------------------------------------- docx

  Future<Uint8List> toDocx() async {
    final pictures = await _pictures();
    final media = <String, ExportPicture>{}; // media file name -> picture
    final relOf = <String, String>{};
    var nextRel = 10, nextDoc = 1;

    String drawing(ExportPicture pic, String key) {
      final rel = relOf.putIfAbsent(key, () {
        final id = 'rId${nextRel++}';
        media['image${media.length + 1}.${pic.extension}'] = pic;
        return id;
      });
      final file = media.entries.firstWhere((e) => identical(e.value, pic)).key;
      final cx = (pic.shownWidth * 9525).round();
      final cy = (pic.shownHeight * 9525).round();
      final id = nextDoc++;
      return '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
          '<wp:extent cx="$cx" cy="$cy"/>'
          '<wp:docPr id="$id" name="Picture $id" descr="${xmlText(pic.alt)}"/>'
          '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
          '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
          '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="$file"/><pic:cNvPicPr/></pic:nvPicPr>'
          '<pic:blipFill><a:blip r:embed="$rel"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
          '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
          '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
          '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
    }

    final body = StringBuffer();
    for (final line in lines) {
      if (line.pageBreak) {
        body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
        continue;
      }
      final left = line.indent * 120 + (line.bullet ? 360 : 0);
      body.write('<w:p>');
      if (left > 0 || line.bullet) {
        body.write(
          '<w:pPr><w:ind w:left="$left"${line.bullet ? ' w:hanging="360"' : ''}/></w:pPr>',
        );
      }
      if (line.bullet) {
        body.write('<w:r><w:t>${line.square ? '▪' : '•'}</w:t><w:tab/></w:r>');
      }
      for (final piece in line.pieces) {
        final embed = piece.embed;
        if (embed == null) {
          body.write(
            '<w:r>${_runProperties(piece.format)}${_runText(piece.text)}</w:r>',
          );
          continue;
        }
        final pic = pictures[_key(piece)];
        if (pic == null) {
          body.write(
            '<w:r><w:t>${embed.isImage ? '[picture]' : xmlText('\$${embed.latex}\$')}</w:t></w:r>',
          );
        } else {
          body.write(drawing(pic, _key(piece)));
        }
      }
      body.write('</w:p>');
    }

    final rels = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    relOf.forEach((key, rel) {
      final pic = pictures[key]!;
      final file = media.entries.firstWhere((e) => identical(e.value, pic)).key;
      rels.write(
        '<Relationship Id="$rel" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$file"/>',
      );
    });
    rels.write('</Relationships>');

    final document =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';

    final archive = Archive()
      ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..add(ArchiveFile.string('_rels/.rels', _packageRels))
      ..add(ArchiveFile.string('word/document.xml', document))
      ..add(ArchiveFile.string('word/_rels/document.xml.rels', rels.toString()))
      ..add(ArchiveFile.string('word/styles.xml', _styles));
    media.forEach((name, pic) {
      archive.add(ArchiveFile.bytes('word/media/$name', pic.bytes));
    });
    return ZipEncoder().encodeBytes(archive);
  }

  static String _runProperties(TextFormat f) {
    final p = StringBuffer();
    if (f.bold) p.write('<w:b/>');
    if (f.italic) p.write('<w:i/>');
    if (f.underline) p.write('<w:u w:val="single"/>');
    if (f.color != null) p.write('<w:color w:val="${hexDigits(f.color!)}"/>');
    if (f.size != null) p.write('<w:sz w:val="${(f.size! * 1.5).round()}"/>');
    if (f.highlight != null) {
      p.write(
        '<w:shd w:val="clear" w:color="auto" w:fill="${hexDigits(f.highlight!)}"/>',
      );
    }
    if (f.superscript) p.write('<w:vertAlign w:val="superscript"/>');
    if (f.subscript) p.write('<w:vertAlign w:val="subscript"/>');
    return p.isEmpty ? '' : '<w:rPr>$p</w:rPr>';
  }

  /// Text as Word wants it: a tab character is a tab, not a space.
  static String _runText(String text) {
    final parts = text.split('\t');
    final out = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) out.write('<w:tab/>');
      if (parts[i].isNotEmpty) {
        out.write('<w:t xml:space="preserve">${xmlText(parts[i])}</w:t>');
      }
    }
    return out.toString();
  }

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '</Types>';

  static const _packageRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  static const _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="Arial" w:cs="Arial"/>'
      '<w:sz w:val="24"/><w:szCs w:val="24"/><w:lang w:val="en-GB"/>'
      '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr>'
      '<w:spacing w:after="0" w:line="276" w:lineRule="auto"/>'
      '</w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '</w:styles>';

  // -------------------------------------------------------------------- pdf

  Future<Uint8List> toPdf() async {
    final pictures = await _pictures();
    final theme = await loadPdfTheme();
    final doc = pw.Document(theme: theme);
    final content = <pw.Widget>[
      for (final line in lines)
        if (line.pageBreak)
          pw.NewPage()
        else
          pdfLine(
            line,
            basePt: _basePx * _ptPerPx,
            baseColor: PdfColors.black,
            embed: (piece) {
              final pic = pictures[_key(piece)];
              if (pic == null) return null;
              return pw.Image(
                pw.MemoryImage(pic.bytes),
                width: pic.shownWidth * _ptPerPx,
                height: pic.shownHeight * _ptPerPx,
              );
            },
            fallback: (piece) => piece.embed!.isImage
                ? '[picture]'
                : '\$${piece.embed!.latex}\$',
          ),
    ];
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(72),
        build: (_) => content,
      ),
    );
    return doc.save();
  }
}

// ------------------------------------------------------------ shared by PDFs

/// The Roboto family used in PDFs, so text with accents, Greek letters and
/// many symbols prints properly (the standard PDF fonts only cover Latin-1).
Future<pw.ThemeData> loadPdfTheme() async {
  Future<pw.Font> font(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-$name.ttf'));
  return pw.ThemeData.withFont(
    base: await font('regular'),
    bold: await font('bold'),
    italic: await font('italic'),
    boldItalic: await font('bolditalic'),
  );
}

PdfColor pdfColorOfHex(String hex) {
  final v = int.parse(hexDigits(hex), radix: 16);
  return PdfColor.fromInt(0xFF000000 | v);
}

/// One line of a note or text box as a PDF widget.
pw.Widget pdfLine(
  ExportLine line, {
  required double basePt,
  required PdfColor baseColor,
  required pw.Widget? Function(ExportPiece piece) embed,
  required String Function(ExportPiece piece) fallback,
}) {
  final spans = <pw.InlineSpan>[];
  for (final piece in line.pieces) {
    final f = piece.format;
    if (piece.embed != null) {
      final widget = embed(piece);
      spans.add(
        widget == null
            ? pw.TextSpan(text: fallback(piece))
            : pw.WidgetSpan(child: widget, baseline: 0),
      );
      continue;
    }
    final size = (f.size ?? basePx(basePt)) * _ptPerPx;
    final scaled = f.scripted ? size * 0.7 : size;
    spans.add(
      pw.TextSpan(
        text: piece.text.replaceAll('\t', '    '),
        baseline: f.superscript
            ? size * 0.4
            : f.subscript
            ? -size * 0.15
            : 0,
        style: pw.TextStyle(
          fontSize: scaled,
          color: f.color == null ? baseColor : pdfColorOfHex(f.color!),
          fontWeight: f.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: f.italic ? pw.FontStyle.italic : pw.FontStyle.normal,
          decoration: f.underline ? pw.TextDecoration.underline : null,
          background: f.highlight == null
              ? null
              : pw.BoxDecoration(color: pdfColorOfHex(f.highlight!)),
        ),
      ),
    );
  }
  final lineHeight = basePt * 1.4;
  final left = line.indent * basePt * 0.5;
  if (spans.isEmpty && !line.bullet) {
    return pw.SizedBox(height: lineHeight);
  }
  final text = pw.RichText(
    text: pw.TextSpan(
      children: spans.isEmpty ? [const pw.TextSpan(text: ' ')] : spans,
    ),
  );
  final style = pw.TextStyle(fontSize: basePt, color: baseColor, height: 1.35);
  return pw.Padding(
    padding: pw.EdgeInsets.only(left: left),
    child: pw.DefaultTextStyle(
      style: style,
      child: line.bullet
          ? pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: basePt * 1.5,
                  // A square bullet is drawn, not typed: the PDF's font has
                  // no square glyph.
                  child: line.square
                      ? pw.Align(
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Container(
                            width: basePt * 0.38,
                            height: basePt * 0.38,
                            color: baseColor,
                          ),
                        )
                      : pw.Text('•'),
                ),
                pw.Expanded(child: text),
              ],
            )
          : text,
    ),
  );
}

/// [basePt] (points) as pixels, for comparing with sizes in formats.
double basePx(double basePt) => basePt / _ptPerPx;

/// [text] with characters XML cannot hold removed and the rest escaped.
String xmlText(String text) {
  final clean = text.replaceAll(
    RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]'),
    '',
  );
  return clean
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// The MIME types and extensions of the note export formats.
const exportMimeTxt = 'text/plain;charset=utf-8';
const exportMimeDocx =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const exportMimePdf = 'application/pdf';
const exportMimeCsv = 'text/csv;charset=utf-8';

/// Convenience: the file name for a document export.
String exportNameFor(String document, String extension) =>
    exportFileName(document, extension);
