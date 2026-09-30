import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A right-angled finish-to-start connector in the scrolling timeline's coordinates.
class CalendarDependencyLink {
  final String prerequisiteKey;
  final String dependentKey;
  final List<Offset> points;
  const CalendarDependencyLink(
    this.prerequisiteKey,
    this.dependentKey,
    this.points,
  );
}

List<CalendarDependencyLink> calendarDependencyLinks(
  List<Map<String, dynamic>> items,
  DateTime start,
  int days,
  double dayWidth,
  double rowHeight,
) {
  String keyOf(Map<String, dynamic> item) => '${item['kind']}:${item['id']}';
  int offset(String value) {
    final date = DateTime.parse(value);
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  }

  final rows = {for (var i = 0; i < items.length; i++) keyOf(items[i]): i};
  final links = <CalendarDependencyLink>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final sourceKey = '${item['prerequisite_kind']}:${item['prerequisite_id']}';
    final sourceIndex = rows[sourceKey];
    if (sourceIndex == null || sourceIndex == i) continue;
    final source = items[sourceIndex];
    if (source['end_date'] == null ||
        item['start_date'] == null ||
        source['start_date'] == null ||
        item['end_date'] == null) {
      continue;
    }
    if (offset(source['end_date'] as String) < 0 ||
        offset(source['start_date'] as String) >= days ||
        offset(item['end_date'] as String) < 0 ||
        offset(item['start_date'] as String) >= days) {
      continue;
    }

    final from = Offset(
      math.min(days, offset(source['end_date'] as String) + 1) * dayWidth - 3,
      rowHeight * (sourceIndex + 1.5),
    );
    final to = Offset(
      math.max(0, offset(item['start_date'] as String)) * dayWidth + 3,
      rowHeight * (i + 1.5),
    );
    final points = <Offset>[from];
    if (to.dx - from.dx >= 20) {
      final middle = (from.dx + to.dx) / 2;
      points.addAll([Offset(middle, from.dy), Offset(middle, to.dy)]);
    } else {
      // Overlapping or backwards dates route through the gap between rows.
      final out = math.min(days * dayWidth - 1, from.dx + 10);
      final into = math.max(1.0, to.dx - 10);
      final gapY = rowHeight * (sourceIndex + 2) - 8;
      points.addAll([
        Offset(out, from.dy),
        Offset(out, gapY),
        Offset(into, gapY),
        Offset(into, to.dy),
      ]);
    }
    points.add(to);
    links.add(CalendarDependencyLink(sourceKey, keyOf(item), points));
  }
  return links;
}

class CalendarDependencyPainter extends CustomPainter {
  final List<CalendarDependencyLink> links;
  final Color color;
  const CalendarDependencyPainter({required this.links, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final link in links) {
      final points = link.points;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
      final tip = points.last;
      final arrow = Path()
        ..moveTo(tip.dx - 5, tip.dy - 4)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 5, tip.dy + 4);
      canvas.drawPath(arrow, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CalendarDependencyPainter oldDelegate) =>
      oldDelegate.links != links || oldDelegate.color != color;
}
