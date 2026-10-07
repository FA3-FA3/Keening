import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/colour_library.dart';
import 'package:keening/widgets/colour_picker.dart';

Future<ColourLibrary> open(
  WidgetTester tester,
  void Function(ColourChoice?) done, {
  String? initial,
  String? noneLabel,
  List<String> recent = const [],
  List<String> favourites = const [],
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = <String, String>{
    'keening.colours.recent': '[${recent.map((c) => '"$c"').join(',')}]',
    'keening.colours.favourites':
        '[${favourites.map((c) => '"$c"').join(',')}]',
  };
  final library = ColourLibrary(
    read: (k) => store[k],
    write: (k, v) => store[k] = v,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('open'),
            onPressed: () async => done(
              await showColourPicker(
                context,
                title: 'Text colour',
                initial: initial,
                noneLabel: noneLabel,
                library: library,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
  return library;
}

String hexField(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('colour-hex')))
    .controller!
    .text;

List<int> _channels(String hex) => [
  for (var i = 1; i < 7; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  testWidgets('a typed hex colour is applied and remembered as recent', (
    tester,
  ) async {
    ColourChoice? result;
    var closed = false;
    final library = await open(tester, (c) {
      result = c;
      closed = true;
    }, initial: '#2563EB');
    expect(hexField(tester), '#2563EB');
    await tester.enterText(find.byKey(const ValueKey('colour-hex')), 'dc2626');
    await tester.pump();
    final preview = tester.widget<Container>(
      find.byKey(const ValueKey('colour-preview')),
    );
    expect(
      (preview.decoration! as BoxDecoration).color,
      const Color(0xFFDC2626),
    );
    await tester.tap(find.byKey(const ValueKey('colour-apply')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result!.hex, '#DC2626');
    expect(library.recent, ['#DC2626']);
  });

  testWidgets('an invalid hex colour is refused and the picker stays open', (
    tester,
  ) async {
    var closed = false;
    await open(tester, (_) => closed = true);
    await tester.enterText(find.byKey(const ValueKey('colour-hex')), 'banana');
    await tester.tap(find.byKey(const ValueKey('colour-apply')));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('Enter a colour like #2563EB.'), findsOneWidget);
  });

  testWidgets('dragging the colour square and hue slider changes the colour', (
    tester,
  ) async {
    await open(tester, (_) {}, initial: '#FF0000');
    expect(hexField(tester), '#FF0000');
    final box = find.byKey(const ValueKey('colour-sv'));
    final topLeft = tester.getTopLeft(box);
    // Bottom-left of the square is black; top-left is white.
    await tester.tapAt(topLeft + const Offset(1, 159));
    await tester.pump();
    expect(_channels(hexField(tester)).every((c) => c <= 6), isTrue);
    await tester.tapAt(topLeft + const Offset(1, 1));
    await tester.pump();
    expect(_channels(hexField(tester)).every((c) => c >= 249), isTrue);
    // Full saturation and brightness at the hue slider's far ends gives red.
    await tester.tapAt(topLeft + const Offset(299, 1));
    await tester.pump();
    expect(hexField(tester), isNot('#FFFFFF'));
    final hue = find.byKey(const ValueKey('colour-hue'));
    await tester.tapAt(tester.getCenter(hue));
    await tester.pump();
    expect(hexField(tester), isNot('#FF0000'), reason: 'the hue moved');
  });

  testWidgets('recent and favourite colours apply in one tap', (tester) async {
    ColourChoice? result;
    await open(
      tester,
      (c) => result = c,
      recent: ['#111111', '#059669'],
      favourites: ['#7C3AED'],
    );
    expect(find.byKey(const ValueKey('colour-recent-#059669')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('colour-favourite-chip-#7C3AED')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('colour-favourite-chip-#7C3AED')),
    );
    await tester.pumpAndSettle();
    expect(result!.hex, '#7C3AED');
  });

  testWidgets('the star adds and removes favourites', (tester) async {
    final library = await open(tester, (_) {}, initial: '#DC2626');
    expect(find.text('Star a colour to keep it here.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('colour-favourite')));
    await tester.pumpAndSettle();
    expect(library.favourites, ['#DC2626']);
    expect(
      find.byKey(const ValueKey('colour-favourite-chip-#DC2626')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('colour-favourite')));
    await tester.pumpAndSettle();
    expect(library.favourites, isEmpty);
  });

  testWidgets('cancel returns nothing; the none button returns no colour', (
    tester,
  ) async {
    ColourChoice? result = const ColourChoice('#000000');
    var calls = 0;
    await open(tester, (c) {
      result = c;
      calls++;
    }, noneLabel: 'No highlight');
    await tester.tap(find.byKey(const ValueKey('colour-cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('colour-none')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(result, isNotNull);
    expect(result!.hex, isNull);
  });

  testWidgets('there is no none button unless one is asked for', (
    tester,
  ) async {
    await open(tester, (_) {});
    expect(find.byKey(const ValueKey('colour-none')), findsNothing);
  });
}
