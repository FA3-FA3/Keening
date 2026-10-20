import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// One phase on the timeline.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.completed,
  });
  final String id, title;
  final DateTime start, end;
  final bool completed;
}

/// A Gantt calendar's phases, drawn in its colour.
class TimelineGroup {
  const TimelineGroup({
    required this.id,
    required this.name,
    required this.color,
    required this.items,
  });
  final String id, name;
  final Color color;
  final List<TimelineItem> items;
}

const _rowHeight = 28.0;
const _headerHeight = 34.0;
const _labelWidth = 200.0;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// The phases of several Gantt calendars on one time axis: a bar for each phase
/// (faded when done, outlined red when overdue), a line for today, and the
/// calendar names as headings. Tapping a phase calls [onOpen].
class ProjectTimeline extends StatefulWidget {
  const ProjectTimeline({
    super.key,
    required this.groups,
    this.onOpen,
    this.today,
    this.compact = false,
  });
  final List<TimelineGroup> groups;
  final void Function(TimelineGroup group, TimelineItem item)? onOpen;

  /// The day to mark (the real today by default; tests set it).
  final DateTime? today;

  /// A smaller version without the zoom buttons, for the project overview.
  final bool compact;

  @override
  State<ProjectTimeline> createState() => _ProjectTimelineState();
}

class _ProjectTimelineState extends State<ProjectTimeline> {
  static const _zooms = [2.0, 4.0, 8.0, 16.0, 32.0];
  int _zoom = 2;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  bool _scrolledToToday = false;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  DateTime get _today => _day(widget.today ?? DateTime.now());

  ({DateTime start, DateTime end})? get _range {
    DateTime? lo, hi;
    for (final g in widget.groups) {
      for (final i in g.items) {
        if (lo == null || i.start.isBefore(lo)) lo = i.start;
        if (hi == null || i.end.isAfter(hi)) hi = i.end;
      }
    }
    if (lo == null || hi == null) return null;
    final t = _today;
    if (t.isBefore(lo)) lo = t;
    if (t.isAfter(hi)) hi = t;
    return (
      start: _day(lo).subtract(const Duration(days: 7)),
      end: _day(hi).add(const Duration(days: 21)),
    );
  }

  /// Rows down the page: a heading for each calendar, then its phases.
  List<({TimelineGroup group, TimelineItem? item})> get _rows => [
    for (final g in widget.groups) ...[
      (group: g, item: null),
      for (final i in g.items) (group: g, item: i),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final scheme = Theme.of(context).colorScheme;
    if (range == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          widget.groups.isEmpty
              ? 'No Gantt calendars are linked to this project yet.'
              : 'The linked Gantt calendars have no phases yet.',
          key: const ValueKey('timeline-empty'),
        ),
      );
    }
    final dayWidth = _zooms[_zoom];
    final days = _daysBetween(range.start, range.end) + 1;
    final width = days * dayWidth;
    final rows = _rows;
    final height = rows.length * _rowHeight;
    final today = _today;
    if (!_scrolledToToday) {
      _scrolledToToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_horizontal.hasClients) return;
        final x = _daysBetween(range.start, today) * dayWidth - 120;
        _horizontal.jumpTo(
          x.clamp(0.0, _horizontal.position.maxScrollExtent).toDouble(),
        );
      });
    }
    final label = Theme.of(context).textTheme.bodySmall;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _labelWidth,
          child: Column(
            children: [
              const SizedBox(height: _headerHeight),
              for (final r in rows)
                SizedBox(
                  height: _rowHeight,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: r.item == null ? 4 : 18,
                      right: 8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: r.item == null
                          ? Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: r.group.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    r.group.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              r.item!.title,
                              overflow: TextOverflow.ellipsis,
                              style: label,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: !widget.compact,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: GestureDetector(
                key: const ValueKey('timeline-chart'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final row =
                      ((d.localPosition.dy - _headerHeight) / _rowHeight)
                          .floor();
                  if (row < 0 || row >= rows.length) return;
                  final item = rows[row].item;
                  if (item == null) return;
                  final x0 = _daysBetween(range.start, item.start) * dayWidth;
                  final x1 =
                      (_daysBetween(range.start, item.end) + 1) * dayWidth;
                  if (d.localPosition.dx >= x0 - 3 &&
                      d.localPosition.dx <= x1 + 3) {
                    widget.onOpen?.call(rows[row].group, item);
                  }
                },
                child: CustomPaint(
                  size: Size(width, _headerHeight + height),
                  painter: _TimelinePainter(
                    rows: rows,
                    start: range.start,
                    days: days,
                    dayWidth: dayWidth,
                    today: today,
                    scheme: scheme,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          Row(
            children: [
              IconButton(
                key: const ValueKey('timeline-zoom-out'),
                tooltip: 'Zoom out',
                onPressed: _zoom == 0 ? null : () => setState(() => _zoom--),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                key: const ValueKey('timeline-zoom-in'),
                tooltip: 'Zoom in',
                onPressed: _zoom == _zooms.length - 1
                    ? null
                    : () => setState(() => _zoom++),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                key: const ValueKey('timeline-today'),
                tooltip: 'Go to today',
                onPressed: () {
                  if (!_horizontal.hasClients) return;
                  final x = _daysBetween(range.start, today) * dayWidth - 120;
                  _horizontal.animateTo(
                    x
                        .clamp(0.0, _horizontal.position.maxScrollExtent)
                        .toDouble(),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                icon: const Icon(Icons.today_outlined),
              ),
            ],
          ),
        if (widget.compact)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(
                _headerHeight + height + 8,
                _headerHeight + 8 * _rowHeight,
              ),
            ),
            child: SingleChildScrollView(controller: _vertical, child: body),
          )
        else
          Expanded(
            child: SingleChildScrollView(controller: _vertical, child: body),
          ),
      ],
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.rows,
    required this.start,
    required this.days,
    required this.dayWidth,
    required this.today,
    required this.scheme,
  });
  final List<({TimelineGroup group, TimelineItem? item})> rows;
  final DateTime start, today;
  final int days;
  final double dayWidth;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: .6)
      ..strokeWidth = 1;
    final headerFill = Paint()..color = scheme.surfaceContainerHighest;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _headerHeight), headerFill);
    // Month boundaries and names.
    var d = DateTime(start.year, start.month + 1, 1);
    void label(String text, double x, double y, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: scheme.onSurfaceVariant,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
      tp.dispose();
    }

    label(DateFormat('MMM yyyy').format(start), 4, 4, bold: true);
    while (d.isBefore(start.add(Duration(days: days)))) {
      final x = _daysBetween(start, d) * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      label(
        DateFormat(d.month == 1 ? 'MMM yyyy' : 'MMM').format(d),
        x + 4,
        4,
        bold: true,
      );
      d = DateTime(d.year, d.month + 1, 1);
    }
    // Day numbers when there is room.
    if (dayWidth >= 16) {
      for (var i = 0; i < days; i++) {
        final day = start.add(Duration(days: i));
        if (dayWidth >= 32 || day.day % 5 == 0 || day.day == 1) {
          label('${day.day}', i * dayWidth + 2, 18);
        }
      }
    }
    canvas.drawLine(
      Offset(0, _headerHeight),
      Offset(size.width, _headerHeight),
      line,
    );
    for (var r = 0; r < rows.length; r++) {
      final y = _headerHeight + r * _rowHeight;
      final row = rows[r];
      if (row.item == null) {
        canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, _rowHeight),
          Paint()..color = row.group.color.withValues(alpha: .10),
        );
        continue;
      }
      final item = row.item!;
      final x0 = _daysBetween(start, item.start) * dayWidth;
      final x1 = (_daysBetween(start, item.end) + 1) * dayWidth;
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTRB(x0, y + 6, math.max(x1, x0 + 6), y + _rowHeight - 6),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        bar,
        Paint()
          ..color = item.completed
              ? row.group.color.withValues(alpha: .35)
              : row.group.color,
      );
      final overdue = !item.completed && item.end.isBefore(today);
      if (overdue) {
        canvas.drawRRect(
          bar,
          Paint()
            ..color = scheme.error
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      if (item.completed && x1 - x0 >= 18) {
        final tp = TextPainter(
          text: TextSpan(
            text: '✓',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x0 + 5, y + (_rowHeight - tp.height) / 2));
        tp.dispose();
      }
    }
    // Today.
    final tx = (_daysBetween(start, today) + .5) * dayWidth;
    canvas.drawLine(
      Offset(tx, 0),
      Offset(tx, size.height),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.rows != rows ||
      old.start != start ||
      old.dayWidth != dayWidth ||
      old.today != today ||
      old.scheme != scheme;
}
