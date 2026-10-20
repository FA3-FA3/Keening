import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/export_handle.dart';
import 'package:keening/utils/sheet_model.dart';
import 'package:keening/widgets/sheet_editor.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool ctrl = false,
  bool shift = false,
}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  final saved = <SheetData>[];
  var failSave = false;
  late SheetHandle handle;

  setUp(() {
    clipboard = null;
    saved.clear();
    failSave = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          } else if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
  });

  Future<void> mount(WidgetTester tester, [SheetData? data]) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    handle = SheetHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetEditor(
            initialData: data ?? SheetData(),
            handle: handle,
            autosaveDelay: const Duration(milliseconds: 50),
            onSave: (d) async {
              if (failSave) throw StateError('Nope.');
              saved.add(d);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset cell(WidgetTester tester, int row, int col, [double width = 110]) =>
      tester.getTopLeft(find.byKey(const ValueKey('sheet-grid'))) +
      Offset(col * width + 20, row * 28 + 14);

  Future<void> select(WidgetTester tester, int row, int col) async {
    await tester.tapAt(cell(tester, row, col));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> typeInto(
    WidgetTester tester,
    int row,
    int col,
    String text,
  ) async {
    await select(tester, row, col);
    await key(tester, LogicalKeyboardKey.f2);
    await tester.enterText(
      find.byKey(const ValueKey('sheet-cell-editor')),
      text,
    );
    await key(tester, LogicalKeyboardKey.enter);
  }

  String name(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('sheet-cell-name'))).data!;

  testWidgets('starts empty with A1 selected and the size shown', (
    tester,
  ) async {
    await mount(tester);
    expect(name(tester), 'A1');
    expect(
      find.text('$sheetDefaultRows rows · $sheetDefaultCols columns'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sheet-cell-editor')), findsNothing);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a cell is edited with F2 and Enter moves down', (tester) async {
    await mount(tester);
    await typeInto(tester, 0, 0, '42');
    expect(handle.data().cellAt(0, 0).raw, '42');
    expect(name(tester), 'A2');
    expect(find.byKey(const ValueKey('sheet-cell-editor')), findsNothing);
  });

  testWidgets('typing starts editing and replaces the cell; Esc cancels', (
    tester,
  ) async {
    await mount(tester, SheetData()..setRaw(0, 0, 'old'));
    await select(tester, 0, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX, character: 'x');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    final editor = find.byKey(const ValueKey('sheet-cell-editor'));
    expect(editor, findsOneWidget);
    expect(tester.widget<TextField>(editor).controller!.text, 'x');
    await key(tester, LogicalKeyboardKey.escape);
    expect(editor, findsNothing);
    expect(handle.data().cellAt(0, 0).raw, 'old');
  });

  testWidgets('Tab moves right and a formula is kept as typed', (tester) async {
    await mount(tester);
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.f2);
    await tester.enterText(
      find.byKey(const ValueKey('sheet-cell-editor')),
      '=1+2',
    );
    await key(tester, LogicalKeyboardKey.tab);
    expect(handle.data().cellAt(0, 0).raw, '=1+2');
    expect(name(tester), 'B1');
  });

  testWidgets('the formula bar shows and edits the active cell', (
    tester,
  ) async {
    await mount(tester, SheetData()..setRaw(1, 1, '=SUM(A1:A3)'));
    await select(tester, 1, 1);
    final bar = find.byKey(const ValueKey('sheet-formula-bar'));
    expect(tester.widget<TextField>(bar).controller!.text, '=SUM(A1:A3)');
    await tester.tap(bar);
    await tester.pump();
    await tester.enterText(bar, '=SUM(A1:A9)');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(handle.data().cellAt(1, 1).raw, '=SUM(A1:A9)');
    expect(name(tester), 'B3');
  });

  testWidgets('arrow keys move the selection and Shift extends it', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 2, 2);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(name(tester), 'D4');
    await key(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    await key(tester, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(name(tester), 'B4:D4'.replaceFirst('B4:D4', 'B4:D4'));
    await key(tester, LogicalKeyboardKey.arrowUp, shift: true);
    expect(name(tester), 'B3:D4');
    // Not past the edges.
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(name(tester), 'A1');
  });

  testWidgets('Delete clears the selection; undo and redo bring it back', (
    tester,
  ) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'a');
    await typeInto(tester, 1, 0, 'b');
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await key(tester, LogicalKeyboardKey.delete);
    expect(handle.data().cells, isEmpty);
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(handle.data().cellAt(0, 0).raw, 'a');
    expect(handle.data().cellAt(1, 0).raw, 'b');
    await key(tester, LogicalKeyboardKey.keyY, ctrl: true);
    expect(handle.data().cells, isEmpty);
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
    expect(handle.data().cells, isEmpty, reason: 'Ctrl+Shift+Z redoes too');
  });

  testWidgets('bold, italic and alignment apply to the selection and toggle', (
    tester,
  ) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'a');
    await typeInto(tester, 1, 0, 'b');
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await tester.tap(find.byKey(const ValueKey('sheet-bold')));
    await tester.tap(find.byKey(const ValueKey('sheet-italic')));
    await tester.tap(find.byKey(const ValueKey('sheet-align-right')));
    await tester.pump();
    for (final r in [0, 1]) {
      final c = handle.data().cellAt(r, 0);
      expect([c.bold, c.italic, c.align], [true, true, CellAlign.right]);
    }
    await tester.tap(find.byKey(const ValueKey('sheet-bold')));
    await tester.tap(find.byKey(const ValueKey('sheet-align-right')));
    await tester.pump();
    final c = handle.data().cellAt(1, 0);
    expect([c.bold, c.italic, c.align], [false, true, CellAlign.auto]);
    // Ctrl+B works too, and formatting an empty cell leaves a formatted cell.
    await select(tester, 5, 5);
    await key(tester, LogicalKeyboardKey.keyB, ctrl: true);
    expect(handle.data().cellAt(5, 5).bold, isTrue);
  });

  testWidgets('rows and columns are inserted and deleted', (tester) async {
    await mount(
      tester,
      SheetData(rows: 10, cols: 5)
        ..setRaw(1, 1, 'x')
        ..setRaw(2, 1, '=B2'),
    );
    await select(tester, 1, 1);
    await tester.tap(find.byKey(const ValueKey('sheet-row-above')));
    await tester.pump();
    expect(handle.data().rows, 11);
    expect(handle.data().cellAt(2, 1).raw, 'x');
    expect(handle.data().cellAt(3, 1).raw, '=B3', reason: 'formulas follow');
    await tester.tap(find.byKey(const ValueKey('sheet-col-right')));
    await tester.pump();
    expect(handle.data().cols, 6);
    await tester.tap(find.byKey(const ValueKey('sheet-row-delete')));
    await tester.pump();
    expect(handle.data().rows, 10);
    await tester.tap(find.byKey(const ValueKey('sheet-col-delete')));
    await tester.pump();
    expect(handle.data().cols, 5);
    expect(find.text('10 rows · 5 columns'), findsOneWidget);
    // Undo walks it all back.
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    }
    expect([handle.data().rows, handle.data().cols], [10, 5]);
    expect(handle.data().cellAt(1, 1).raw, 'x');
  });

  testWidgets('a sheet keeps at least one row and column', (tester) async {
    await mount(tester, SheetData(rows: 1, cols: 1));
    await tester.tap(find.byKey(const ValueKey('sheet-row-delete')));
    await tester.pump();
    expect(find.text('A sheet needs at least one row.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sheet-col-delete')));
    await tester.pump();
    expect(find.text('A sheet needs at least one column.'), findsOneWidget);
    expect([handle.data().rows, handle.data().cols], [1, 1]);
  });

  testWidgets('copy and paste keep formulas and looks between cells', (
    tester,
  ) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'a');
    await typeInto(tester, 0, 1, '=1+2');
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
    await key(tester, LogicalKeyboardKey.keyB, ctrl: true);
    await key(tester, LogicalKeyboardKey.keyC, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(clipboard, 'a\t3', reason: 'other programs get the values');
    await select(tester, 3, 3);
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(handle.data().cellAt(3, 3).raw, 'a');
    expect(handle.data().cellAt(3, 3).bold, isTrue);
    expect(handle.data().cellAt(3, 4).raw, '=1+2');
    expect(name(tester), 'D4:E4');
  });

  testWidgets('cut removes the cells; text from elsewhere pastes by tabs', (
    tester,
  ) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'x');
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.keyX, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(handle.data().cells, isEmpty);
    clipboard = 'one\ttwo\n3\t4.5\n"quoted\nline"\tz';
    await select(tester, 1, 1);
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    final d = handle.data();
    expect([d.cellAt(1, 1).raw, d.cellAt(1, 2).raw], ['one', 'two']);
    expect([d.cellAt(2, 1).raw, d.cellAt(2, 2).raw], ['3', '4.5']);
    expect([d.cellAt(3, 1).raw, d.cellAt(3, 2).raw], ['quoted\nline', 'z']);
  });

  testWidgets('one copied value fills the whole selection', (tester) async {
    await mount(tester);
    clipboard = 'fill';
    await select(tester, 0, 0);
    await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
    await key(tester, LogicalKeyboardKey.arrowRight, shift: true);
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(handle.data().cells.length, 4);
  });

  testWidgets('pasting past the edge grows the sheet up to its limits', (
    tester,
  ) async {
    await mount(tester, SheetData(rows: 3, cols: 2));
    clipboard = List.generate(5, (i) => 'a\tb\tc').join('\n');
    await select(tester, 2, 1);
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect([handle.data().rows, handle.data().cols], [7, 4]);
    expect(handle.data().cellAt(6, 3).raw, 'c');
  });

  testWidgets('changes autosave, and a failure can be retried', (tester) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'hello');
    expect(find.text('Unsaved changes…'), findsOneWidget);
    await settle(tester);
    expect(saved.last.cellAt(0, 0).raw, 'hello');
    expect(find.text('Saved'), findsOneWidget);
    failSave = true;
    await typeInto(tester, 1, 0, 'more');
    await settle(tester);
    expect(find.text('Not saved'), findsOneWidget);
    failSave = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Saved'), findsOneWidget);
    expect(saved.last.cellAt(1, 0).raw, 'more');
  });

  testWidgets('leaving with unsaved edits still saves them', (tester) async {
    await mount(tester);
    await typeInto(tester, 0, 0, 'late');
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved.last.cellAt(0, 0).raw, 'late');
  });

  testWidgets('dragging a column edge resizes it, as one undo step', (
    tester,
  ) async {
    await mount(tester);
    final headers = find.byKey(const ValueKey('sheet-col-headers'));
    final top = tester.getTopLeft(headers);
    final g = await tester.startGesture(
      top + const Offset(110, 14),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(60, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump();
    expect(handle.data().widthOf(0), closeTo(200, 1));
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(handle.data().widthOf(0), sheetDefaultColWidth);
  });

  testWidgets('clicking a column header selects the column', (tester) async {
    await mount(tester, SheetData(rows: 20, cols: 5));
    final top = tester.getTopLeft(
      find.byKey(const ValueKey('sheet-col-headers')),
    );
    final g = await tester.startGesture(
      top + const Offset(165, 14),
      kind: PointerDeviceKind.mouse,
    );
    await g.up();
    await tester.pump();
    expect(name(tester), 'B1:B20');
  });

  testWidgets('a mouse can drag out a selection', (tester) async {
    await mount(tester);
    final g = await tester.startGesture(
      cell(tester, 1, 1),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveTo(cell(tester, 3, 3));
    await g.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(name(tester), 'B2:D4');
  });

  testWidgets('replacing the contents (an import) is one undo step', (
    tester,
  ) async {
    await mount(tester, SheetData()..setRaw(0, 0, 'before'));
    handle.replace(sheetFromCsv('a,b\n1,2').data);
    await tester.pump();
    expect(handle.data().cellAt(0, 0).raw, 'a');
    expect(handle.data().cellAt(1, 1).raw, '2');
    expect(name(tester), 'A1');
    await settle(tester);
    expect(saved.last.cellAt(1, 1).raw, '2');
    await select(tester, 5, 5);
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(handle.data().cellAt(0, 0).raw, 'before');
  });

  testWidgets('a sheet cannot hold more filled cells than the limit', (
    tester,
  ) async {
    final big = SheetData(rows: sheetMaxRows, cols: sheetMaxCols);
    for (var i = 0; i < sheetMaxCells; i++) {
      big.setRaw(30 + i ~/ sheetMaxCols, i % sheetMaxCols, 'x');
    }
    await mount(tester, big);
    await select(tester, 0, 0);
    clipboard = 'new';
    await key(tester, LogicalKeyboardKey.keyV, ctrl: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.textContaining('up to $sheetMaxCells filled cells'),
      findsOneWidget,
    );
    expect(handle.data().cells.length, sheetMaxCells);
  });
}
