import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/calendar_service.dart';
import '../utils/schedule_service.dart';
import '../utils/time_settings.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    this.calendarService,
    this.scheduleService,
    this.today,
    this.active = true,
  });
  final CalendarService? calendarService;
  final ScheduleService? scheduleService;
  final DateTime? today;
  final bool active;
  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  late final _calendar = widget.calendarService ?? CalendarService();
  late final _schedule = widget.scheduleService ?? ScheduleService();
  late DateTime _today = DateUtils.dateOnly(widget.today ?? appNow());
  List<Map<String, dynamic>> _events = [], _tomorrowEvents = [], _sessions = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  Timer? _timer;

  /// Whether the day's sessions are shown (they are hidden to begin with).
  bool _sessionsOpen = false;
  String _iso(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
  DateTime get _tomorrow => DateTime(_today.year, _today.month, _today.day + 1);
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active &&
          !DateUtils.isSameDay(_today, widget.today ?? appNow())) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant OverviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.calendarService == null) _calendar.close();
    if (widget.scheduleService == null) _schedule.close();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _today = DateUtils.dateOnly(widget.today ?? appNow());
      _loading = true;
      _error = null;
    });
    final date = _iso(_today), tomorrow = _iso(_tomorrow);
    try {
      final results = await Future.wait([
        _calendar.call('listCalendars'),
        _schedule.call('getWeek', {'startDate': date}),
      ]);
      final calendars = results[0]['calendars'] as List;
      final tags = (results[0]['tagDefinitions'] as List? ?? []);
      final events = <Map<String, dynamic>>[],
          tomorrowEvents = <Map<String, dynamic>>[];
      for (var i = 0; i < calendars.length; i += 5) {
        final batch = await Future.wait(
          calendars
              .skip(i)
              .take(5)
              .map(
                (c) => _calendar.call('listItems', {'calendar_id': c['id']}),
              ),
        );
        for (final data in batch) {
          for (final item in data['items'] as List) {
            bool covers(String day) =>
                (item['start_date'] as String).compareTo(day) <= 0 &&
                (item['end_date'] as String).compareTo(day) >= 0;
            final tag = tags
                .where((t) => t['id'] == item['tag_id'])
                .firstOrNull;
            final entry = {
              ...Map<String, dynamic>.from(item),
              if (tag != null) 'tag_name': tag['name'],
            };
            if (covers(date)) events.add(entry);
            if (covers(tomorrow)) tomorrowEvents.add(entry);
          }
        }
      }
      int byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
        final time = (a['start_time'] as String? ?? '').compareTo(
          b['start_time'] as String? ?? '',
        );
        return time != 0
            ? time
            : (a['title'] as String).compareTo(b['title'] as String);
      }

      events.sort(byTime);
      tomorrowEvents.sort(byTime);
      final sessions =
          (results[1]['blocks'] as List)
              .where((s) => s['date'] == date)
              .map((s) => Map<String, dynamic>.from(s))
              .toList()
            ..sort((a, b) {
              final time = ('${a['date']} ${a['start']}').compareTo(
                '${b['date']} ${b['start']}',
              );
              return time != 0
                  ? time
                  : (a['title'] as String).compareTo(b['title'] as String);
            });
      if (mounted && request == _request) {
        setState(() {
          _events = events;
          _tomorrowEvents = tomorrowEvents;
          _sessions = sessions;
        });
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => _error = 'Unable to load your dashboard. Please try again.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> items, {
    bool sessions = false,
    String emptyEvents = 'No events today.',
    bool? open,
    VoidCallback? onToggle,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // A section that can be folded away has a button to open it.
      if (onToggle == null)
        Text(title, style: Theme.of(context).textTheme.titleLarge)
      else
        InkWell(
          key: ValueKey('${sessions ? 'sessions' : 'section'}-header'),
          onTap: onToggle,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '(${items.length})',
                key: const ValueKey('sessions-count'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              IconButton(
                key: const ValueKey('sessions-toggle'),
                tooltip: open == true ? 'Hide sessions' : 'Show sessions',
                onPressed: onToggle,
                icon: Icon(
                  open == true ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      if (open == false)
        const SizedBox.shrink()
      else if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(sessions ? 'No sessions planned.' : emptyEvents),
        ),
      if (open != false)
        for (final item in items)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sessions
                        ? formatTimeRange(item['start'], item['end'])
                        : item['start_time'] == null
                        ? 'All day'
                        : formatTimeRange(item['start_time'], item['end_time']),
                  ),
                  if (!sessions && item['start_date'] != item['end_date'])
                    Text(
                      '${DateFormat.yMMMd().format(DateTime.parse(item['start_date']))} - ${DateFormat.yMMMd().format(DateTime.parse(item['end_date']))}',
                    ),
                  if ((item['location'] as String? ?? '').isNotEmpty)
                    Text(item['location'] as String),
                  if ((item[sessions ? 'note' : 'description'] as String? ?? '')
                      .isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        item[sessions ? 'note' : 'description'] as String,
                      ),
                    ),
                  if (item['tag_name'] != null)
                    Text(item['tag_name'] as String),
                  if (item['completed'] == true) const Text('Completed'),
                ],
              ),
            ),
          ),
      const SizedBox(height: 24),
    ],
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Text(DateFormat.yMMMMEEEEd().format(_today)),
        const SizedBox(height: 24),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _load, child: const Text('Retry')),
          ),
        ] else if (!_loading) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final events = _section("Today's events", _events);
              final tomorrow = _section(
                "Tomorrow's events",
                _tomorrowEvents,
                emptyEvents: 'No events tomorrow.',
              );
              // The sessions are folded away until asked for.
              final sessions = _section(
                "Today's sessions",
                _sessions,
                sessions: true,
                open: _sessionsOpen,
                onToggle: () => setState(() => _sessionsOpen = !_sessionsOpen),
              );
              if (constraints.maxWidth < 800) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [events, sessions, tomorrow],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [events, tomorrow],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: sessions),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );
}
