import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/sheet_model.dart';

CfRule rule(
  String range,
  CfCondition condition, {
  String value = '',
  String value2 = '',
  String? bg = '#FFC7CE',
  String? fg,
  bool bold = false,
}) => CfRule(
  range: parseCellRange(range)!,
  condition: condition,
  value: value,
  value2: value2,
  bg: bg,
  fg: fg,
  bold: bold,
);

SheetData sheet(Map<String, String> cells, [List<CfRule> rules = const []]) {
  final d = SheetData();
  cells.forEach((k, v) {
    final at = parseCellName(k)!;
    d.setRaw(at.row, at.col, v);
  });
  d.rules = List.of(rules);
  return d;
}

void main() {
  group('ranges', () {
    test('cells and blocks are read, either corner first', () {
      expect(parseCellRange('B2'), (r1: 1, c1: 1, r2: 1, c2: 1));
      expect(parseCellRange('b2:d20'), (r1: 1, c1: 1, r2: 19, c2: 3));
      expect(parseCellRange('D20:B2'), (r1: 1, c1: 1, r2: 19, c2: 3));
      expect(parseCellRange(' A1 : C3 '), (r1: 0, c1: 0, r2: 2, c2: 2));
    });

    test('anything else is refused, as is a range outside the sheet', () {
      for (final bad in ['', 'x', 'A', '1', 'A0', 'A1:', ':A1', 'A1:B2:C3']) {
        expect(parseCellRange(bad), isNull, reason: bad);
      }
      expect(parseCellRange('A1:C10', rows: 10, cols: 3), isNotNull);
      expect(parseCellRange('A1:C11', rows: 10, cols: 3), isNull);
      expect(parseCellRange('A1:D10', rows: 10, cols: 3), isNull);
    });

    test('they print back as they were given', () {
      expect(cellRangeText(parseCellRange('c3')!), 'C3');
      expect(cellRangeText(parseCellRange('B2:D20')!), 'B2:D20');
    });
  });

  group('conditions', () {
    bool test_(CfRule r, Object? v) => r.matches(v);

    test('numbers compare as numbers', () {
      expect(test_(rule('A1', CfCondition.gt, value: '10'), 11), isTrue);
      expect(test_(rule('A1', CfCondition.gt, value: '10'), 10), isFalse);
      expect(test_(rule('A1', CfCondition.ge, value: '10'), 10), isTrue);
      expect(test_(rule('A1', CfCondition.lt, value: '10'), 9.5), isTrue);
      expect(test_(rule('A1', CfCondition.le, value: '10'), 10), isTrue);
      expect(test_(rule('A1', CfCondition.le, value: '10'), 11), isFalse);
      // A percentage is a number too (50% is 0.5).
      expect(test_(rule('A1', CfCondition.gt, value: '50%'), 0.6), isTrue);
    });

    test('text, blanks and errors never pass a numeric test', () {
      final gt = rule('A1', CfCondition.gt, value: '10');
      expect(test_(gt, 'abc'), isFalse);
      expect(test_(gt, null), isFalse);
      expect(test_(gt, const SheetError('#DIV/0!')), isFalse);
      expect(test_(gt, true), isFalse);
      expect(test_(rule('A1', CfCondition.gt, value: 'abc'), 5), isFalse);
    });

    test('between includes both ends and ignores their order', () {
      final r = rule('A1', CfCondition.between, value: '1', value2: '5');
      expect([0, 1, 3, 5, 6].map((v) => r.matches(v)), [
        false,
        true,
        true,
        true,
        false,
      ]);
      final backwards = rule(
        'A1',
        CfCondition.between,
        value: '5',
        value2: '1',
      );
      expect(backwards.matches(3), isTrue);
      expect(r.matches('3'), isFalse, reason: 'text is not a number');
    });

    test('equal compares numbers as numbers and text without case', () {
      expect(test_(rule('A1', CfCondition.eq, value: '5'), 5), isTrue);
      expect(test_(rule('A1', CfCondition.eq, value: '5.0'), 5), isTrue);
      expect(test_(rule('A1', CfCondition.eq, value: 'done'), 'Done'), isTrue);
      expect(
        test_(rule('A1', CfCondition.eq, value: 'done'), 'undone'),
        isFalse,
      );
      expect(test_(rule('A1', CfCondition.ne, value: 'done'), 'Done'), isFalse);
      expect(test_(rule('A1', CfCondition.ne, value: '5'), 6), isTrue);
      expect(test_(rule('A1', CfCondition.ne, value: '5'), null), isTrue);
    });

    test('text conditions look at what the cell shows, without case', () {
      expect(
        test_(rule('A1', CfCondition.contains, value: 'AR'), 'Mark'),
        isTrue,
      );
      expect(
        test_(rule('A1', CfCondition.contains, value: 'z'), 'Mark'),
        isFalse,
      );
      expect(
        test_(rule('A1', CfCondition.notContains, value: 'z'), 'Mark'),
        isTrue,
      );
      expect(
        test_(rule('A1', CfCondition.beginsWith, value: 'ma'), 'Mark'),
        isTrue,
      );
      expect(
        test_(rule('A1', CfCondition.beginsWith, value: 'ar'), 'Mark'),
        isFalse,
      );
      expect(
        test_(rule('A1', CfCondition.endsWith, value: 'RK'), 'Mark'),
        isTrue,
      );
      // Numbers are matched as they are shown.
      expect(
        test_(rule('A1', CfCondition.contains, value: '2.5'), 12.5),
        isTrue,
      );
      // A blank comparison value never matches.
      expect(test_(rule('A1', CfCondition.contains), 'x'), isFalse);
    });

    test('empty and not empty', () {
      final empty = rule('A1', CfCondition.empty);
      final filled = rule('A1', CfCondition.notEmpty);
      expect(empty.matches(null), isTrue);
      expect(empty.matches(''), isTrue);
      expect(empty.matches(0), isFalse);
      expect(filled.matches(null), isFalse);
      expect(filled.matches(0), isTrue);
      expect(filled.matches(' '), isTrue);
    });
  });

  group('what a cell looks like', () {
    test('a rule only applies inside its range', () {
      final d = sheet(
        {'A1': '5', 'A2': '5', 'B1': '5'},
        [rule('A1:A2', CfCondition.gt, value: '1')],
      );
      final e = SheetEvaluator(d);
      expect(d.styleAt(0, 0, e)?.bg, '#FFC7CE');
      expect(d.styleAt(1, 0, e)?.bg, '#FFC7CE');
      expect(d.styleAt(0, 1, e), isNull);
      expect(d.styleAt(2, 0, e), isNull);
    });

    test('it uses a formula\'s result, not its text', () {
      final d = sheet(
        {'A1': '4', 'A2': '=A1*3'},
        [rule('A2', CfCondition.gt, value: '10')],
      );
      expect(d.styleAt(1, 0, SheetEvaluator(d)), isNotNull);
    });

    test('empty cells can be coloured', () {
      final d = sheet({'A1': 'x'}, [rule('A1:A3', CfCondition.empty)]);
      final e = SheetEvaluator(d);
      expect(d.styleAt(0, 0, e), isNull);
      expect(d.styleAt(1, 0, e), isNotNull);
    });

    test('the first rule to set a colour wins; bold adds up', () {
      final d = sheet(
        {'A1': '50'},
        [
          rule('A1', CfCondition.gt, value: '10', bg: '#111111'),
          rule(
            'A1',
            CfCondition.gt,
            value: '20',
            bg: '#222222',
            fg: '#333333',
            bold: true,
          ),
          rule('A1', CfCondition.lt, value: '0', bg: '#444444'),
        ],
      );
      final look = d.styleAt(0, 0, SheetEvaluator(d))!;
      expect(look.bg, '#111111');
      expect(look.fg, '#333333');
      expect(look.bold, isTrue);
    });

    test('a rule that only sets bold leaves the colours alone', () {
      final d = sheet(
        {'A1': '5'},
        [rule('A1', CfCondition.gt, value: '1', bg: null, bold: true)],
      );
      final look = d.styleAt(0, 0, SheetEvaluator(d))!;
      expect(look.bg, isNull);
      expect(look.bold, isTrue);
    });
  });

  group('rows and columns', () {
    SheetData withRule() => sheet({}, [rule('B3:D6', CfCondition.notEmpty)]);

    String only(SheetData d) => cellRangeText(d.rules.single.range);

    test('rows inserted above push the range down', () {
      final d = withRule()..insertRows(0);
      expect(only(d), 'B4:D7');
    });

    test('rows inserted inside the range stretch it', () {
      final d = withRule()..insertRows(4, 2);
      expect(only(d), 'B3:D8');
    });

    test('rows inserted below leave it alone', () {
      final d = withRule()..insertRows(10);
      expect(only(d), 'B3:D6');
    });

    test('columns inserted before it push it right', () {
      final d = withRule()..insertCols(0);
      expect(only(d), 'C3:E6');
    });

    test('deleting rows above pulls it up', () {
      final d = withRule()..deleteRows(0, 2);
      expect(only(d), 'B1:D4');
    });

    test('deleting part of it shrinks it', () {
      final d = withRule()..deleteRows(4, 5);
      expect(only(d), 'B3:D4');
      final e = withRule()..deleteCols(2, 5);
      expect(only(e), 'B3:B6');
    });

    test('deleting all of it removes the rule', () {
      final d = withRule()..deleteRows(2, 4);
      expect(d.rules, isEmpty);
      final e = withRule()..deleteCols(1, 3);
      expect(e.rules, isEmpty);
    });
  });

  group('saving', () {
    test('rules are saved and read back', () {
      final d = sheet(
        {'A1': '1'},
        [
          rule(
            'A1:C3',
            CfCondition.between,
            value: '1',
            value2: '9',
            bg: '#ffc7ce',
            fg: '#9c0006',
            bold: true,
          ),
          rule('B2', CfCondition.empty),
        ],
      );
      final json = d.toJson();
      expect(json['rules'], [
        {
          'r': 'A1:C3',
          'c': 'between',
          'v': '1',
          'v2': '9',
          'bg': '#FFC7CE',
          'fg': '#9C0006',
          'b': true,
        },
        {'r': 'B2', 'c': 'empty', 'bg': '#FFC7CE'},
      ]);
      final back = SheetData.fromJson(json);
      expect(back.rules.length, 2);
      expect(back.rules[0].condition, CfCondition.between);
      expect(back.rules[0].value2, '9');
      expect(back.rules[0].bg, '#FFC7CE');
      expect(back.rules[1].condition, CfCondition.empty);
    });

    test('a sheet without rules saves none', () {
      expect(SheetData().toJson().containsKey('rules'), isFalse);
    });

    test('copies keep their own list of rules', () {
      final a = sheet({}, [rule('A1', CfCondition.empty)]);
      final b = a.copy();
      b.rules.clear();
      expect(a.rules.length, 1);
    });

    test('invalid or out-of-range rules are dropped when loading', () {
      final d = SheetData.fromJson({
        'rows': 5,
        'cols': 5,
        'cells': {},
        'rules': [
          {'r': 'A1', 'c': 'gt', 'v': '1', 'bg': '#FFFFFF'},
          {'r': 'F1', 'c': 'gt', 'v': '1', 'bg': '#FFFFFF'},
          {'r': 'A6', 'c': 'gt', 'v': '1', 'bg': '#FFFFFF'},
          {'r': 'A1', 'c': 'nope', 'v': '1', 'bg': '#FFFFFF'},
          {'r': 'A1', 'c': 'gt', 'v': '1'},
          {'r': 'A1', 'c': 'gt', 'v': '1', 'bg': 'red'},
          'x',
          null,
        ],
      });
      expect(d.rules.length, 1);
    });

    test('no more than the allowed number of rules are read', () {
      final d = SheetData.fromJson({
        'rules': [
          for (var i = 0; i < sheetMaxRules + 5; i++)
            {'r': 'A1', 'c': 'empty', 'bg': '#FFFFFF'},
        ],
      });
      expect(d.rules.length, sheetMaxRules);
    });
  });
}
