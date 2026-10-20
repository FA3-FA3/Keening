import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/sheet_model.dart';

SheetEvaluator sheet(
  Map<String, String> cells, {
  int rows = 20,
  int cols = 10,
}) {
  final data = SheetData(rows: rows, cols: cols);
  cells.forEach((k, v) {
    final at = parseCellName(k)!;
    data.setRaw(at.row, at.col, v);
  });
  return SheetEvaluator(data);
}

String show(SheetEvaluator e, String name) {
  final at = parseCellName(name)!;
  return e.display(at.row, at.col);
}

void main() {
  test('column names', () {
    expect(columnName(0), 'A');
    expect(columnName(25), 'Z');
    expect(columnName(26), 'AA');
    expect(columnName(51), 'AZ');
    expect(columnIndex('AZ'), 51);
    expect(columnIndex('a'), 0);
    expect(columnIndex('1'), isNull);
    expect(parseCellName('B7'), (row: 6, col: 1));
    expect(parseCellName(r'$C$3'), (row: 2, col: 2));
    expect(parseCellName('7B'), isNull);
  });

  group('formulas', () {
    test('arithmetic and precedence', () {
      final e = sheet({
        'A1': '=1+2*3',
        'A2': '=(1+2)*3',
        'A3': '=2^3^2',
        'A4': '=-2^2',
        'A5': '=10/4',
        'A6': '=50%',
        'A7': '=7-2-1',
      });
      expect(show(e, 'A1'), '7');
      expect(show(e, 'A2'), '9');
      expect(show(e, 'A3'), '64'); // left to right, as Excel does
      expect(show(e, 'A4'), '4'); // Excel: unary minus binds tighter
      expect(show(e, 'A5'), '2.5');
      expect(show(e, 'A6'), '0.5');
      expect(show(e, 'A7'), '4');
    });

    test('cell references, ranges and functions', () {
      final e = sheet({
        'A1': '1',
        'A2': '2',
        'A3': '3',
        'B1': '=SUM(A1:A3)',
        'B2': '=AVERAGE(A1:A3)',
        'B3': '=MAX(A1:A3, 10)',
        'B4': '=MIN(A1:A3)',
        'B5': '=COUNT(A1:A3, "x")',
        'B6': '=A1+A2*A3',
        'B7': '=PRODUCT(A1:A3)',
        'B8': '=MEDIAN(A1:A3)',
        'B9': '=SUM(A:A)',
      });
      expect(show(e, 'B1'), '6');
      expect(show(e, 'B2'), '2');
      expect(show(e, 'B3'), '10');
      expect(show(e, 'B4'), '1');
      expect(show(e, 'B5'), '3');
      expect(show(e, 'B6'), '7');
      expect(show(e, 'B7'), '6');
      expect(show(e, 'B8'), '2');
      expect(show(e, 'B9'), '#ERROR!'); // whole-column ranges are not supported
    });

    test('text, logic and rounding', () {
      final e = sheet({
        'A1': 'hello',
        'B1': '=UPPER(A1)&" "&LEN(A1)',
        'B2': '=IF(1<2,"yes","no")',
        'B3': '=IF(A1="HELLO",1,0)',
        'B4': '=ROUND(2.345,2)',
        'B5': '=ROUND(-2.5)',
        'B6': '=MOD(-3,5)',
        'B7': '=AND(1,0)',
        'B8': '=OR(1,0)',
        'B9': '=SQRT(16)',
        'C1': '=ABS(-4)',
        'C2': '=INT(-1.5)',
        'C3': '=CONCAT("a",1,"b")',
      });
      expect(show(e, 'B1'), 'HELLO 5');
      expect(show(e, 'B2'), 'yes');
      expect(show(e, 'B3'), '1'); // text compares without case
      expect(show(e, 'B4'), '2.35');
      expect(show(e, 'B5'), '-3');
      expect(show(e, 'B6'), '2');
      expect(show(e, 'B7'), 'FALSE');
      expect(show(e, 'B8'), 'TRUE');
      expect(show(e, 'B9'), '4');
      expect(show(e, 'C1'), '4');
      expect(show(e, 'C2'), '-2');
      expect(show(e, 'C3'), 'a1b');
    });

    test('errors', () {
      final e = sheet({
        'A1': '=1/0',
        'A2': '=A1+1',
        'A3': '=NOPE(1)',
        'A4': '=1+',
        'A5': '=B5',
        'B5': '=A5',
        'A6': '="a"+1',
        'A7': '=AVERAGE(B1:B2)',
        'A8': '=SUM(A1:A2)',
      });
      expect(show(e, 'A1'), '#DIV/0!');
      expect(show(e, 'A2'), '#DIV/0!');
      expect(show(e, 'A3'), '#NAME?');
      expect(show(e, 'A4'), '#ERROR!');
      expect(show(e, 'A5'), '#CIRC!');
      expect(show(e, 'A6'), '#VALUE!');
      expect(show(e, 'A7'), '#DIV/0!');
      expect(show(e, 'A8'), '#DIV/0!');
    });

    test('numbers are recognised when typed; text stays text', () {
      final e = sheet({
        'A1': '12',
        'A2': ' 3.5 ',
        'A3': '1e3',
        'A4': '12abc',
        'B1': '=A1+A2+A3',
      });
      expect(show(e, 'A1'), '12');
      expect(show(e, 'A4'), '12abc');
      expect(show(e, 'B1'), '1015.5');
    });

    test('long decimals are trimmed', () {
      final e = sheet({'A1': '=1/3', 'A2': '=0.1+0.2'});
      expect(show(e, 'A1'), '0.333333333333');
      expect(show(e, 'A2'), '0.3');
    });
  });

  group('rows and columns', () {
    test('inserting a row moves cells and updates formulas', () {
      final data = SheetData(rows: 10, cols: 5);
      data.setRaw(0, 0, '5');
      data.setRaw(1, 0, '7');
      data.setRaw(2, 0, '=SUM(A1:A2)');
      data.setRaw(3, 0, r'=$A$2*2');
      expect(data.insertRows(1), isTrue);
      expect(data.rows, 11);
      expect(data.cellAt(2, 0).raw, '7');
      expect(data.cellAt(3, 0).raw, '=SUM(A1:A3)');
      expect(data.cellAt(4, 0).raw, r'=$A$3*2');
      expect(SheetEvaluator(data).display(3, 0), '12');
    });

    test('deleting a row makes references to it #REF!', () {
      final data = SheetData(rows: 10, cols: 5);
      data.setRaw(0, 0, '5');
      data.setRaw(1, 0, '7');
      data.setRaw(2, 0, '=A2+1');
      data.setRaw(3, 0, '=A1+1');
      expect(data.deleteRows(1), isTrue);
      expect(data.cellAt(1, 0).raw, '=#REF!+1');
      expect(data.cellAt(2, 0).raw, '=A1+1');
      expect(SheetEvaluator(data).display(1, 0), '#REF!');
      expect(SheetEvaluator(data).display(2, 0), '6');
    });

    test('columns move their widths too', () {
      final data = SheetData(rows: 5, cols: 4);
      data.colWidths[1] = 200;
      data.colWidths[2] = 80;
      data.setRaw(0, 2, 'x');
      expect(data.insertCols(1), isTrue);
      expect(data.colWidths, {2: 200, 3: 80});
      expect(data.cellAt(0, 3).raw, 'x');
      expect(data.deleteCols(2), isTrue);
      expect(data.colWidths, {2: 80});
      expect(data.cellAt(0, 2).raw, 'x');
    });

    test('limits', () {
      final data = SheetData(rows: sheetMaxRows, cols: sheetMaxCols);
      expect(data.insertRows(0), isFalse);
      expect(data.insertCols(0), isFalse);
      final tiny = SheetData(rows: 1, cols: 1);
      expect(tiny.deleteRows(0), isFalse);
      expect(tiny.deleteCols(0), isFalse);
    });

    test('text in quotes is not touched when formulas shift', () {
      expect(shiftFormula('="A1"&A1', rowAt: 0, rowBy: 1), '="A1"&A2');
      expect(shiftFormula('=SUM(A1:B2)', colAt: 0, colBy: 1), '=SUM(B1:C2)');
      expect(shiftFormula('=LOG10(A1)', rowAt: 0, rowBy: 1), '=LOG10(A2)');
    });
  });

  group('json', () {
    test('round trip keeps cells, formats and widths', () {
      final data = SheetData(rows: 30, cols: 6);
      data.setRaw(0, 0, 'Name');
      data.put(
        0,
        0,
        data.cellAt(0, 0).copyWith(bold: true, align: CellAlign.center),
      );
      data.setRaw(2, 3, '=1+1');
      data.colWidths[3] = 150;
      final back = SheetData.fromJson(data.toJson());
      expect(back.rows, 30);
      expect(back.cols, 6);
      expect(back.cellAt(0, 0).bold, isTrue);
      expect(back.cellAt(0, 0).align, CellAlign.center);
      expect(back.cellAt(2, 3).raw, '=1+1');
      expect(back.colWidths, {3: 150});
      expect(
        data.toJson()['cells'],
        containsPair('A1', {'v': 'Name', 'b': true, 'a': 'c'}),
      );
    });

    test('bad input gives an empty sheet, not a crash', () {
      expect(SheetData.fromJson(null).cells, isEmpty);
      final d = SheetData.fromJson({
        'rows': 'x',
        'cells': {
          'Z99': 5,
          'A1': {'v': 7},
          'ZZZ1': {},
        },
      });
      expect(d.cells, isEmpty);
    });
  });

  group('csv', () {
    test('parses quotes, separators and line breaks', () {
      final rows = parseCsv(
        'a,"b,c","say ""hi""","line1\nline2"\r\n1,2,3,4\r\n',
      );
      expect(rows, [
        ['a', 'b,c', 'say "hi"', 'line1\nline2'],
        ['1', '2', '3', '4'],
      ]);
    });

    test('guesses semicolons and tabs, and drops a byte order mark', () {
      expect(parseCsv('﻿a;b;c\n1;2;3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
      expect(parseCsv('a\tb\n1\t2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
      expect(parseCsv('"a;b",c\n1,2'), [
        ['a;b', 'c'],
        ['1', '2'],
      ]);
    });

    test('empty fields, ragged rows, no final newline', () {
      expect(parseCsv('a,,c\n,,\nx'), [
        ['a', '', 'c'],
        ['', '', ''],
        ['x'],
      ]);
      expect(parseCsv(''), isEmpty);
      expect(parseCsv('a\n\nb'), [
        ['a'],
        [''],
        ['b'],
      ]);
      expect(parseCsv('""'), [
        [''],
      ]);
    });

    test('encoding quotes only what needs it and round trips', () {
      final rows = [
        ['plain', 'a,b', 'q"uote', 'two\nlines', ' pad', ''],
        ['1', '2.5', '', '', '', 'x'],
      ];
      final text = encodeCsv(rows);
      expect(
        text.split('\r\n').first,
        'plain,"a,b","q""uote","two\nlines"," pad",',
      );
      expect(parseCsv(text), rows);
    });

    test('import makes a sheet and says when something was cut', () {
      final imported = sheetFromCsv('Item,Qty\nApple,3\nPear,=A2');
      expect(imported.cut, isFalse);
      final d = imported.data;
      expect(d.rows, sheetDefaultRows);
      expect(d.cellAt(1, 1).raw, '3');
      expect(SheetEvaluator(d).display(2, 1), 'Apple');
      final wide = sheetFromCsv(List.filled(sheetMaxCols + 3, 'x').join(','));
      expect(wide.cutCols, isTrue);
      expect(wide.data.cols, sheetMaxCols);
      final tall = sheetFromCsv(List.filled(sheetMaxRows + 3, 'x').join('\n'));
      expect(tall.cutRows, isTrue);
      expect(tall.data.rows, sheetMaxRows);
    });

    test('export writes values, not formulas, up to the last used cell', () {
      final data = SheetData(rows: 20, cols: 8);
      data.setRaw(0, 0, 'Total');
      data.setRaw(0, 1, '=1+2');
      data.setRaw(1, 0, 'a,b');
      expect(sheetToCsv(data), 'Total,3\r\n"a,b",\r\n');
      expect(sheetToCsv(SheetData()), '\r\n');
    });
  });
}
