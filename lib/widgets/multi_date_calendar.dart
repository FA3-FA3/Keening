import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Month grid where any number of days can be toggled. [fixed] is always
/// shown as selected and cannot be toggled off.
class MultiDateCalendar extends StatefulWidget {
  const MultiDateCalendar({
    super.key,
    required this.fixed,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final DateTime fixed;
  final Set<DateTime> selected;
  final ValueChanged<Set<DateTime>> onChanged;
  final bool enabled;
  @override
  State<MultiDateCalendar> createState() => _MultiDateCalendarState();
}

class _MultiDateCalendarState extends State<MultiDateCalendar> {
  late DateTime _month = DateTime(widget.fixed.year, widget.fixed.month);

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fixed = DateUtils.dateOnly(widget.fixed);
    final lead = (DateTime(_month.year, _month.month).weekday + 6) % 7;
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final weeks = (lead + count + 6) ~/ 7;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(_month),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(child: Center(child: Text(d))),
          ],
        ),
        for (var week = 0; week < weeks; week++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _cell(week * 7 + i - lead + 1, count, fixed, scheme),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(int day, int count, DateTime fixed, ColorScheme scheme) {
    if (day < 1 || day > count) return const SizedBox(height: 40);
    final date = DateTime(_month.year, _month.month, day);
    final isFixed = date == fixed;
    final on = isFixed || widget.selected.contains(date);
    return SizedBox(
      height: 40,
      child: Semantics(
        selected: on,
        label: DateFormat.yMMMEd().format(date),
        child: InkResponse(
          key: ValueKey('repeat-${DateFormat('yyyy-MM-dd').format(date)}'),
          onTap: widget.enabled && !isFixed
              ? () {
                  final next = {...widget.selected};
                  if (!next.add(date)) next.remove(date);
                  widget.onChanged(next);
                }
              : null,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFixed
                  ? scheme.primary
                  : on
                  ? scheme.primaryContainer
                  : null,
              border: on && !isFixed ? Border.all(color: scheme.primary) : null,
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(color: isFixed ? scheme.onPrimary : null),
            ),
          ),
        ),
      ),
    );
  }
}
