import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/calendar_service.dart';
import '../widgets/item_links.dart';
import '../widgets/tag_manager_dialog.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    this.searchTarget,
    this.service,
    this.today,
    this.onOpenSchedule,
    this.onChanged,
  });
  final ValueChanged<DateTime>? onOpenSchedule;
  final VoidCallback? onChanged;
  final CalendarService? service;
  final Map<String, dynamic>? searchTarget;
  final DateTime? today;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late final _service = widget.service ?? CalendarService();
  late final _today = DateUtils.dateOnly(widget.today ?? DateTime.now());
  late DateTime _selected = _today;
  late DateTime _month = DateTime(_today.year, _today.month);
  List<Map<String, dynamic>> _calendars = [], _events = [];
  List<Map<String, dynamic>> _tags = [];
  bool _loading = true;
  bool _showEvents = false;
  String? _error;

  Future<void> _openSearch() async {
    final target = widget.searchTarget!;
    final date = DateTime.tryParse(target['date'] as String? ?? '');
    if (date != null) {
      _selected = date;
      _month = DateTime(date.year, date.month);
    }
    await _load();
    if (!mounted || widget.searchTarget != target || _error != null) return;
    final event = _events.where((i) => i['id'] == target['id']).firstOrNull;
    if (event != null) await _edit(event);
  }

  @override
  void initState() {
    super.initState();
    if (widget.searchTarget != null) {
      _openSearch();
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchTarget != oldWidget.searchTarget &&
        widget.searchTarget != null) {
      _openSearch();
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to load calendar. Please try again.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call('listCalendars');
      final calendars = (result['calendars'] as List)
          .map((c) => Map<String, dynamic>.from(c))
          .toList();
      final events = <Map<String, dynamic>>[];
      // Small batches keep larger accounts from flooding the API.
      for (var i = 0; i < calendars.length; i += 5) {
        final batch = calendars.skip(i).take(5);
        final results = await Future.wait(
          batch.map((c) async {
            final response = await _service.call('listItems', {
              'calendar_id': c['id'],
            });
            return (response['items'] as List).map(
              (e) => <String, dynamic>{
                ...Map<String, dynamic>.from(e),
                'calendar_id': c['id'],
                'calendar_name': c['name'],
                'color': c['color'],
              },
            );
          }),
        );
        for (final entries in results) {
          events.addAll(entries);
        }
      }
      if (mounted) {
        setState(() {
          _tags = (result['tagDefinitions'] as List? ?? [])
              .map((t) => Map<String, dynamic>.from(t))
              .toList();
          _calendars = calendars;
          _events = events;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _on(DateTime day) {
    final date = _iso(day);
    return _events
        .where(
          (e) =>
              (e['start_date'] as String).compareTo(date) <= 0 &&
              (e['end_date'] as String).compareTo(date) >= 0,
        )
        .toList()
      ..sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
  }

  Color _color(Map<String, dynamic> event) {
    final tag = _tags.where((t) => t['id'] == event['tag_id']).firstOrNull;
    final hex = (tag?['color'] as String? ?? event['color'] as String? ?? '')
        .replaceFirst('#', '');
    return hex.length == 6 && int.tryParse(hex, radix: 16) != null
        ? Color(0xFF000000 | int.parse(hex, radix: 16))
        : AppColors.primary(context);
  }

  void _move(int offset) => setState(() {
    _month = DateTime(_month.year, _month.month + offset);
    _selected = DateTime(
      _month.year,
      _month.month,
      _selected.day.clamp(
        1,
        DateUtils.getDaysInMonth(_month.year, _month.month),
      ),
    );
  });

  Future<void> _editTags() async {
    final saved = await showDialog<TagList>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TagManagerDialog.list(
        title: 'Event tags',
        deleteWarning: 'This removes the tag from all events.',
        tags: _tags,
        save: (tags) async {
          final data = await _service.call('saveTagDefinitions', {
            'tags': tags,
          });
          return (data['tagDefinitions'] as List)
              .map((t) => Map<String, dynamic>.from(t))
              .toList();
        },
      ),
    );
    if (saved != null && mounted) await _load();
  }

  Widget _tagBadge(Map<String, dynamic> event) {
    final tag = _tags.where((t) => t['id'] == event['tag_id']).firstOrNull;
    if (tag == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Chip(
        avatar: Icon(
          Icons.circle,
          size: 12,
          color: tagColor(tag['color'] as String),
        ),
        label: Text(tag['name'] as String),
      ),
    );
  }

  Future<void> _edit([Map<String, dynamic>? event]) async {
    String? calendar =
        event?['calendar_id'] as String? ??
        _calendars.firstOrNull?['id'] as String?;
    var title = event?['title'] as String? ?? '';
    var description = event?['description'] as String? ?? '';
    var location = event?['location'] as String? ?? '';
    String? tagId = event?['tag_id'] as String?;
    var completed = event?['completed'] == true;
    var range = DateTimeRange(
      start: event == null ? _selected : DateTime.parse(event['start_date']),
      end: event == null ? _selected : DateTime.parse(event['end_date']),
    );
    var hasEnd = !DateUtils.isSameDay(range.start, range.end);
    var timed = event?['start_time'] != null;
    var startTime = event?['start_time'] as String? ?? '09:00';
    var endTime = event?['end_time'] as String? ?? '10:00';
    var saving = false;
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Future<void> save() async {
            if (title.trim().isEmpty) {
              update(() => error = 'Enter a title.');
              return;
            }
            final timePattern = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
            if (timed &&
                (!timePattern.hasMatch(startTime) ||
                    !(endTime == '24:00' || timePattern.hasMatch(endTime)) ||
                    endTime.compareTo(startTime) <= 0)) {
              update(() => error = 'Enter HH:mm times, with end after start.');
              return;
            }
            update(() {
              saving = true;
              error = null;
            });
            try {
              // First use creates a default calendar, independent of Gantt.
              if (calendar == null) {
                final result = await _service.call('createCalendar', {
                  'name': 'Calendar',
                  'color': '#2E7D5B',
                });
                calendar = result['calendar']['id'] as String;
              }
              await _service.call('saveItem', {
                'calendar_id': calendar,
                'item_id': event?['id'],
                'kind': 'event',
                'title': title.trim(),
                'description': description.trim(),
                'location': location.trim(),
                'tag_id': tagId,
                'start_date': _iso(range.start),
                'end_date': _iso(hasEnd ? range.end : range.start),
                'start_time': timed ? startTime : null,
                'end_time': timed ? endTime : null,
                'completed': completed,
                'prerequisite_id': event?['prerequisite_id'],
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) {
                update(() {
                  saving = false;
                  error = _message(e);
                });
              }
            }
          }

          return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(event == null ? 'New event' : 'Event details'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        initialValue: title,
                        autofocus: true,
                        enabled: !saving,
                        maxLength: 200,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: (v) => title = v,
                      ),
                      const SizedBox(height: 12),
                      for (final endDate in [false, if (hasEnd) true])
                        OutlinedButton.icon(
                          key: ValueKey(
                            endDate ? 'event-end-date' : 'event-start-date',
                          ),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            (endDate ? 'End: ' : 'Date: ') +
                                DateFormat.yMMMd().format(
                                  endDate ? range.end : range.start,
                                ),
                          ),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: endDate
                                        ? range.end
                                        : range.start,
                                    firstDate: endDate
                                        ? range.start
                                        : DateTime(1900),
                                    lastDate: DateTime(2200, 12, 31),
                                  );
                                  if (picked != null && ctx.mounted) {
                                    update(() {
                                      range = endDate
                                          ? DateTimeRange(
                                              start: range.start,
                                              end: picked,
                                            )
                                          : DateTimeRange(
                                              start: picked,
                                              end:
                                                  !hasEnd ||
                                                      picked.isAfter(range.end)
                                                  ? picked
                                                  : range.end,
                                            );
                                    });
                                  }
                                },
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Add end date'),
                        value: hasEnd,
                        onChanged: saving
                            ? null
                            : (v) => update(() => hasEnd = v!),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Time slot'),
                        value: timed,
                        onChanged: saving
                            ? null
                            : (v) => update(() => timed = v),
                      ),
                      if (timed) ...[
                        const Text(
                          'Creates a linked Schedule session each day. Event changes update those sessions.',
                        ),
                        TextFormField(
                          key: const ValueKey('event-start-time'),
                          initialValue: startTime,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Start time',
                            hintText: '09:00',
                            helperText: '24-hour HH:mm',
                          ),
                          onChanged: (v) => startTime = v,
                        ),
                        TextFormField(
                          key: const ValueKey('event-end-time'),
                          initialValue: endTime,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'End time',
                            hintText: '10:00',
                            helperText: 'Same day; 24:00 is midnight',
                          ),
                          onChanged: (v) => endTime = v,
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text('Tag'),
                      if (_tags.isEmpty)
                        const Text(
                          'Create tags using the Tags menu on Calendar.',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('No tag'),
                            selected: tagId == null,
                            onSelected: saving
                                ? null
                                : (_) => update(() => tagId = null),
                          ),
                          for (final tag in _tags)
                            ChoiceChip(
                              label: Text(tag['name'] as String),
                              selected: tagId == tag['id'],
                              avatar: Icon(
                                Icons.circle,
                                size: 12,
                                color: tagColor(tag['color'] as String),
                              ),
                              onSelected: saving
                                  ? null
                                  : (_) => update(
                                      () => tagId = tag['id'] as String,
                                    ),
                            ),
                        ],
                      ),
                      TextFormField(
                        key: const ValueKey('event-location'),
                        initialValue: location,
                        enabled: !saving,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                        ),
                        onChanged: (v) => location = v,
                      ),
                      TextFormField(
                        initialValue: description,
                        enabled: !saving,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 5000,
                        decoration: const InputDecoration(labelText: 'Notes'),
                        onChanged: (v) => description = v,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Completed'),
                        value: completed,
                        onChanged: saving
                            ? null
                            : (v) => update(() => completed = v!),
                      ),
                      ItemLinks(
                        source: 'calendar',
                        calendarEventId: event?['id'] as String?,
                        enabled: !saving,
                      ),
                      if (error != null) Text(error!),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (changed == true && mounted) {
      widget.onChanged?.call();
      await _load();
    }
  }

  Widget _monthView() {
    final start = DateTime(_month.year, _month.month, 1 - (_month.weekday - 1));
    final count =
        ((_month.weekday -
                    1 +
                    DateUtils.getDaysInMonth(_month.year, _month.month)) /
                7)
            .ceil() *
        7;
    return Column(
      children: [
        Row(
          children: [
            for (final name in [
              'MON',
              'TUE',
              'WED',
              'THU',
              'FRI',
              'SAT',
              'SUN',
            ])
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (ctx, size) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: size.maxWidth < 380 ? 60 : 82,
            ),
            itemBuilder: (ctx, i) {
              final day = DateTime(start.year, start.month, start.day + i);
              final selected = DateUtils.isSameDay(day, _selected);
              final today = DateUtils.isSameDay(day, _today);
              final events = _on(day);
              return Semantics(
                selected: selected,
                label:
                    '${DateFormat.yMMMMEEEEd().format(day)}, ${events.length} events',
                child: InkWell(
                  key: ValueKey('calendar-day-${_iso(day)}'),
                  onDoubleTap: widget.onOpenSchedule == null
                      ? null
                      : () => widget.onOpenSchedule!(day),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _selected = day;
                    _month = DateTime(day.year, day.month);
                  }),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? AppColors.primary(context)
                              : today
                              ? AppColors.primary(
                                  context,
                                ).withValues(alpha: .10)
                              : null,
                        ),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: today || selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? AppColors.white
                                : day.month != _month.month
                                ? AppColors.grey500
                                : AppColors.text(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        height: 5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final e in events.take(3))
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _color(e),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _agenda() {
    final events = _on(_selected);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat('EEEE').format(_selected),
            style: TextStyle(
              color: AppColors.primary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMMM d').format(_selected),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 24),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 32,
                    color: AppColors.grey500,
                  ),
                  const SizedBox(height: 12),
                  const Text('No events', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text('A little room in your day.'),
                ],
              ),
            ),
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: _color(event).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  key: ValueKey('calendar-event-${event['id']}'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onTap: () => _edit(event),
                  leading: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _color(event),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    event['title'] as String,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: event['completed'] == true
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          event['start_time'] == null
                              ? 'All day'
                              : '${event['start_time']} - ${event['end_time']}',
                          if ((event['location'] as String? ?? '').isNotEmpty)
                            event['location'] as String,
                        ].join(' / '),
                      ),
                      _tagBadge(event),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 14),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onOpenSchedule == null
                ? null
                : () => widget.onOpenSchedule!(_selected),
            icon: const Icon(Icons.view_week_outlined),
            label: const Text('Open schedule'),
          ),
          TextButton.icon(
            onPressed: _loading || _error != null ? null : () => _edit(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add event'),
          ),
        ],
      ),
    );
  }

  Widget _eventsView() {
    final events = _events.toList()
      ..sort((a, b) {
        final date = (a['start_date'] as String).compareTo(
          b['start_date'] as String,
        );
        if (date != 0) return date;
        final time = (a['start_time'] as String? ?? '').compareTo(
          b['start_time'] as String? ?? '',
        );
        return time != 0
            ? time
            : (a['title'] as String).compareTo(b['title'] as String);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _loading || _error != null ? null : () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add event'),
          ),
        ),
        const SizedBox(height: 16),
        if (events.isEmpty && !_loading)
          const Padding(padding: EdgeInsets.all(24), child: Text('No events')),
        for (final event in events)
          Card(
            key: ValueKey('event-list-${event['id']}'),
            margin: const EdgeInsets.only(bottom: 12),
            color: _color(event).withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _edit(event),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event['title'] as String,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat.yMMMd().format(
                            DateTime.parse(event['start_date'] as String),
                          ) +
                          (event['start_date'] == event['end_date']
                              ? ''
                              : ' - ${DateFormat.yMMMd().format(DateTime.parse(event['end_date'] as String))}'),
                    ),
                    Text(
                      event['start_time'] == null
                          ? 'All day'
                          : '${event['start_time'] as String} - ${event['end_time'] as String}${event['start_date'] == event['end_date'] ? '' : ' each day'}',
                    ),
                    if ((event['location'] as String? ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Location: ${event['location'] as String}'),
                      ),
                    if ((event['description'] as String? ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(event['description'] as String),
                      ),
                    _tagBadge(event),
                    if (event['completed'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Completed'),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 850;
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(constraints.maxWidth < 420 ? 12 : 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Calendar',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const ValueKey('calendar-tags'),
                    onPressed: _loading || _error != null ? null : _editTags,
                    icon: const Icon(Icons.label_outline),
                    label: const Text('Tags'),
                  ),
                  IconButton(
                    tooltip: 'Refresh calendar',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Calendar'),
                      icon: Icon(Icons.calendar_month),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Events'),
                      icon: Icon(Icons.list),
                    ),
                  ],
                  selected: {_showEvents},
                  onSelectionChanged: (value) =>
                      setState(() => _showEvents = value.single),
                ),
              ),
              const SizedBox(height: 20),
              if (!_showEvents)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text(
                      DateFormat.yMMMM().format(_month),
                      key: const ValueKey('calendar-month'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.6,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Previous month',
                          onPressed: _month.year <= 1900 && _month.month == 1
                              ? null
                              : () => _move(-1),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            size: 20,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _selected = _today;
                            _month = DateTime(_today.year, _today.month);
                          }),
                          child: const Text('Today'),
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          onPressed: _month.year >= 2200 && _month.month == 12
                              ? null
                              : () => _move(1),
                          icon: const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (_showEvents)
                _eventsView()
              else if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _monthView()),
                    const SizedBox(width: 28),
                    Expanded(flex: 2, child: _agenda()),
                  ],
                )
              else ...[
                _monthView(),
                const SizedBox(height: 24),
                _agenda(),
              ],
            ],
          ),
        ),
      );
    },
  );
}
