import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/calendar_service.dart';
import '../utils/schedule_service.dart';

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
  late DateTime _today = DateUtils.dateOnly(widget.today ?? DateTime.now());
  List<Map<String, dynamic>> _events = [], _sessions = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  Timer? _timer;
  String _iso(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
  DateTime get _tomorrow => DateTime(_today.year, _today.month, _today.day + 1);
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active &&
          !DateUtils.isSameDay(_today, widget.today ?? DateTime.now())) {
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
      _today = DateUtils.dateOnly(widget.today ?? DateTime.now());
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
      final events = <Map<String, dynamic>>[];
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
            if ((item['start_date'] as String).compareTo(date) <= 0 &&
                (item['end_date'] as String).compareTo(date) >= 0) {
              final tag = tags
                  .where((t) => t['id'] == item['tag_id'])
                  .firstOrNull;
              events.add({
                ...Map<String, dynamic>.from(item),
                if (tag != null) 'tag_name': tag['name'],
              });
            }
          }
        }
      }
      events.sort((a, b) {
        final time = (a['start_time'] as String? ?? '').compareTo(
          b['start_time'] as String? ?? '',
        );
        return time != 0
            ? time
            : (a['title'] as String).compareTo(b['title'] as String);
      });
      final sessions =
          (results[1]['blocks'] as List)
              .where((s) => s['date'] == date || s['date'] == tomorrow)
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
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text(sessions ? 'No sessions planned.' : 'No events today.'),
        ),
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
                      ? '${item['start']} - ${item['end']}'
                      : item['start_time'] == null
                      ? 'All day'
                      : '${item['start_time']} - ${item['end_time']}',
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
                if (item['tag_name'] != null) Text(item['tag_name'] as String),
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
          _section("Today's events", _events),
          _section(
            "Today's sessions",
            _sessions.where((s) => s['date'] == _iso(_today)).toList(),
            sessions: true,
          ),
          _section(
            "Tomorrow's sessions",
            _sessions.where((s) => s['date'] == _iso(_tomorrow)).toList(),
            sessions: true,
          ),
        ],
      ],
    ),
  );
}
