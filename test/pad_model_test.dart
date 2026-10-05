import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/pad_model.dart';

void main() {
  const red = Color(0xFFDC2626);
  final elements = <PadElement>[
    TextEl(
      id: 't',
      x: 10,
      y: 20,
      w: 200,
      text: 'Hello',
      fontSize: 24,
      color: red,
    ),
    const ImageEl(id: 'i', x: 5, y: 6, w: 100, h: 50, imageId: 'img-1'),
    const LineEl(
      id: 'l',
      a: Offset(0, 0),
      b: Offset(100, 0),
      width: 4,
      color: red,
    ),
    const PenEl(
      id: 'p',
      points: [Offset(1, 1), Offset(50, 40), Offset(90, 5)],
      width: 2,
      color: red,
    ),
  ];

  test('pads round-trip through their JSON document', () {
    final doc = padDocFromElements(elements);
    expect(doc['version'], 1);
    final back = padElementsFromDoc(doc);
    expect(back.map((e) => e.id), ['t', 'i', 'l', 'p']);
    expect((back[0] as TextEl).text, 'Hello');
    expect((back[0] as TextEl).color, red);
    expect((back[1] as ImageEl).imageId, 'img-1');
    expect((back[2] as LineEl).b, const Offset(100, 0));
    expect((back[3] as PenEl).points.length, 3);
    expect(padDocFromElements(back), doc);
    expect(padHex(red), '#DC2626');
    expect(padElementsFromDoc(null), isEmpty);
    expect(
      () => PadElement.fromJson({'id': 'x', 'type': 'nope'}),
      throwsFormatException,
    );
  });

  test('hit testing finds text, pictures, lines and strokes', () {
    final text = elements[0] as TextEl, image = elements[1], line = elements[2];
    final pen = elements[3];
    expect(text.hitTest(const Offset(50, 30)), isTrue);
    expect(text.hitTest(const Offset(500, 500)), isFalse);
    expect(image.hitTest(const Offset(50, 30)), isTrue);
    expect(image.hitTest(const Offset(50, 80)), isFalse);
    expect(line.hitTest(const Offset(50, 3)), isTrue); // within the line width
    expect(line.hitTest(const Offset(50, 30)), isFalse);
    expect(line.hitTest(const Offset(200, 0)), isFalse); // past the end
    expect(pen.hitTest(const Offset(25, 20)), isTrue);
    expect(pen.hitTest(const Offset(25, 40)), isFalse);
    const dot = PenEl(id: 'd', points: [Offset(10, 10)], width: 6, color: red);
    expect(dot.hitTest(const Offset(12, 10)), isTrue);
    expect(dot.hitTest(const Offset(40, 10)), isFalse);
  });

  test('moving an element shifts all of its geometry', () {
    const delta = Offset(15, -5);
    final line = elements[2].translated(delta) as LineEl;
    expect(line.a, const Offset(15, -5));
    expect(line.b, const Offset(115, -5));
    final pen = elements[3].translated(delta) as PenEl;
    expect(pen.points.first, const Offset(16, -4));
    final text = elements[0].translated(delta) as TextEl;
    expect([text.x, text.y], [25, 15]);
    expect(elements[2].bounds.contains(const Offset(50, 0)), isTrue);
  });

  test('text boxes grow taller as they hold more text', () {
    TextEl box(String text, double w) =>
        TextEl(id: 'x', x: 0, y: 0, w: w, text: text, fontSize: 20, color: red);
    final one = box('Hi', 300).height;
    final many = box(List.filled(30, 'word').join(' '), 120).height;
    expect(many, greaterThan(one * 2));
    expect(box('', 300).height, one, reason: 'empty boxes keep one line');
    expect(box('Hi', 300).bounds.height, one);
  });

  test('simplifying keeps the shape but drops redundant points', () {
    final straight = [for (var i = 0; i <= 50; i++) Offset(i * 2.0, 10)];
    expect(simplifyPoints(straight, 0.5), [straight.first, straight.last]);
    final corner = [
      for (var i = 0; i <= 20; i++) Offset(i * 5.0, 0),
      for (var i = 1; i <= 20; i++) Offset(100, i * 5.0),
    ];
    final simple = simplifyPoints(corner, 0.5);
    expect(simple.length, 3);
    expect(simple[1], const Offset(100, 0));
    expect(simplifyPoints([const Offset(1, 1)], 1), [const Offset(1, 1)]);
    expect(
      distanceToSegment(const Offset(5, 5), Offset.zero, const Offset(10, 0)),
      5,
    );
    expect(
      distanceToSegment(const Offset(20, 0), Offset.zero, const Offset(10, 0)),
      10,
    );
  });
}
