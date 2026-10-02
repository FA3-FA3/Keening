import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';

class ScheduleTimeline extends StatelessWidget {
  const ScheduleTimeline({
    super.key,
    required this.week,
    required this.days,
    required this.onToggleEarly,
    required this.onToggleLate,
    required this.onExtentChanged,
    required this.onAnimationEnd,
    required this.selected,
    required this.blocks,
    required this.width,
    required this.early,
    required this.late,
    required this.onCreate,
    required this.onEdit,
  });
  final DateTime week, selected;
  final int days;
  final VoidCallback onToggleEarly,
      onToggleLate,
      onExtentChanged,
      onAnimationEnd;
  final List<Map<String, dynamic>> blocks;
  final double width;
  final bool early, late;
  final void Function(DateTime, int) onCreate;
  final void Function(DateTime, Map<String, dynamic>) onEdit;
  static const hourHeight = 96.0, gutter = 55.0;
  String _locationLabel(Map<String, dynamic> session) {
    final location = session['location'] as String? ?? '';
    return location.isEmpty ? '' : '\n$location';
  }

  int _minutes(String v) {
    final p = v.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  String _label(int hour) => hour == 24
      ? '12am'
      : hour == 0
      ? '12am'
      : hour < 12
      ? '${hour}am'
      : hour == 12
      ? '12pm'
      : '${hour - 12}pm';
  Color _color(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

  // Assign overlapping events separate lanes, including transitive overlaps.
  List<({Map<String, dynamic> block, int lane, int lanes})> _layout(
    List<Map<String, dynamic>> events,
  ) {
    events.sort((a, b) => _minutes(a['start']).compareTo(_minutes(b['start'])));
    final result = <({Map<String, dynamic> block, int lane, int lanes})>[];
    var index = 0;
    while (index < events.length) {
      final group = <Map<String, dynamic>>[events[index++]];
      var end = _minutes(group.first['end']);
      while (index < events.length && _minutes(events[index]['start']) < end) {
        end = math.max(end, _minutes(events[index]['end']));
        group.add(events[index++]);
      }
      final ends = <int>[], assigned = <int>[];
      for (final b in group) {
        var lane = ends.indexWhere((end) => end <= _minutes(b['start']));
        if (lane < 0) {
          lane = ends.length;
          ends.add(0);
        }
        ends[lane] = _minutes(b['end']);
        assigned.add(lane);
      }
      for (var i = 0; i < group.length; i++) {
        result.add((block: group[i], lane: assigned[i], lanes: ends.length));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 7, end: early ? 0 : 7),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 350),
    curve: Curves.easeInOutCubic,
    builder: (context, first, _) => TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 20, end: late ? 24 : 20),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      onEnd: onAnimationEnd,
      builder: (context, last, _) {
        onExtentChanged();
        return _timeline(context, first, last);
      },
    ),
  );
  Widget _control({required bool before}) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: gutter,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        key: ValueKey(
          before ? 'schedule-toggle-early' : 'schedule-toggle-late',
        ),
        onPressed: before ? onToggleEarly : onToggleLate,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              before
                  ? (early ? Icons.expand_more : Icons.expand_less)
                  : (late ? Icons.expand_less : Icons.expand_more),
              size: 18,
            ),
            Text(
              before
                  ? (early ? 'Hide before' : 'Show before')
                  : (late ? 'Hide after' : 'Show after'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _timeline(BuildContext context, double first, double last) {
    final dayWidth = (width - gutter) / days;
    final line = AppColors.grey500.withValues(alpha: .25);
    final height = (last - first) * hourHeight;
    return Column(
      children: [
        _control(before: true),
        SizedBox(
          width: width,
          height: height + 24,
          child: Stack(
            children: [
              for (var h = first.floor(); h <= last; h++)
                Positioned(
                  top: (h - first) * hourHeight,
                  left: 0,
                  right: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: gutter,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            _label(h),
                            key: ValueKey('schedule-hour-$h'),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      Expanded(child: Container(height: 1, color: line)),
                    ],
                  ),
                ),
              for (var i = 0; i < days; i++) ...[
                Positioned(
                  left: gutter + i * dayWidth,
                  top: 0,
                  width: dayWidth,
                  height: height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: line),
                        right: i == days - 1
                            ? BorderSide(color: line)
                            : BorderSide.none,
                      ),
                      color:
                          DateUtils.isSameDay(
                            DateTime(week.year, week.month, week.day + i),
                            selected,
                          )
                          ? AppColors.primary(context).withValues(alpha: .025)
                          : null,
                    ),
                  ),
                ),
                for (var h = first.floor(); h < last; h++)
                  Positioned(
                    left: gutter + i * dayWidth,
                    top: (h - first) * hourHeight,
                    width: dayWidth,
                    height: hourHeight,
                    child: Semantics(
                      button: true,
                      label:
                          'Add session ${DateFormat('yyyy-MM-dd').format(DateTime(week.year, week.month, week.day + i))} ${_label(h)}',
                      child: InkWell(
                        key: ValueKey(
                          'schedule-add-${DateFormat('yyyy-MM-dd').format(DateTime(week.year, week.month, week.day + i))}-$h',
                        ),
                        onTap: () => onCreate(
                          DateTime(week.year, week.month, week.day + i),
                          h,
                        ),
                      ),
                    ),
                  ),
                for (final entry in _layout(
                  blocks
                      .where(
                        (b) =>
                            b['date'] ==
                                DateFormat('yyyy-MM-dd').format(
                                  DateTime(week.year, week.month, week.day + i),
                                ) &&
                            _minutes(b['end']) > first * 60 &&
                            _minutes(b['start']) < last * 60,
                      )
                      .toList(),
                ))
                  Positioned(
                    left:
                        gutter +
                        i * dayWidth +
                        entry.lane * dayWidth / entry.lanes +
                        2,
                    width: math.max(1, dayWidth / entry.lanes - 4),
                    top:
                        (math.max(_minutes(entry.block['start']), first * 60) -
                            first * 60) /
                        60 *
                        hourHeight,
                    height: math.max(
                      16,
                      (math.min(_minutes(entry.block['end']), last * 60) -
                                  math.max(
                                    _minutes(entry.block['start']),
                                    first * 60,
                                  )) /
                              60 *
                              hourHeight -
                          2,
                    ),
                    child: Tooltip(
                      message:
                          '${entry.block['start']} – ${entry.block['end']} · ${entry.block['title']}${_locationLabel(entry.block)}',
                      child: Material(
                        color: Color.alphaBlend(
                          _color(entry.block['color']).withValues(alpha: .18),
                          AppColors.surface(context),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                          side: BorderSide(
                            color: _color(
                              entry.block['color'],
                            ).withValues(alpha: .6),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('schedule-block-${entry.block['id']}'),
                          onTap: () => onEdit(
                            DateTime(week.year, week.month, week.day + i),
                            entry.block,
                          ),
                          child: LayoutBuilder(
                            builder: (ctx, size) => Padding(
                              padding: EdgeInsets.all(
                                size.maxHeight < 36 ? 2 : 6,
                              ),
                              child: Text(
                                size.maxHeight < 40
                                    ? '${entry.block['title']}'
                                    : '${entry.block['start']} – ${entry.block['end']}\n${entry.block['title']}${_locationLabel(entry.block)}',
                                maxLines: math.max(
                                  1,
                                  (size.maxHeight / 17).floor(),
                                ),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        _control(before: false),
      ],
    );
  }
}

class ScheduleDayHeader extends StatelessWidget {
  const ScheduleDayHeader({
    super.key,
    required this.week,
    required this.selected,
    required this.days,
    required this.width,
  });
  final DateTime week, selected;
  final int days;
  final double width;
  static const height = 38.0;
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('schedule-day-header'),
    height: height,
    child: Row(
      children: [
        const SizedBox(width: ScheduleTimeline.gutter),
        for (var i = 0; i < days; i++)
          Container(
            key: ValueKey('schedule-header-day-$i'),
            width: (width - ScheduleTimeline.gutter) / days,
            height: height,
            decoration: BoxDecoration(
              color:
                  DateUtils.isSameDay(
                    DateTime(week.year, week.month, week.day + i),
                    selected,
                  )
                  ? Color.alphaBlend(
                      AppColors.primary(context).withValues(alpha: .12),
                      AppColors.surface(context),
                    )
                  : AppColors.surface(context),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.grey500.withValues(alpha: .25),
                ),
              ),
            ),
            child: Center(
              child: Text(
                DateFormat(
                  'EEE d',
                ).format(DateTime(week.year, week.month, week.day + i)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
