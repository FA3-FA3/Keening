import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/schedule_service.dart';
import '../widgets/schedule_timeline.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.date,
    this.service,
    this.openRequest = 0,
  });
  final int openRequest;
  final DateTime date;
  final ScheduleService? service;
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final _service = widget.service ?? ScheduleService();
  late DateTime _selected = DateUtils.dateOnly(widget.date);
  late DateTime _start = _selected;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  int _days = 1;
  bool _followBottom = false;
  List<Map<String, dynamic>> _blocks = [];
  bool _early = false, _late = false;
  bool _loading = true;
  String? _error;
  int _request = 0;
  static const _colors = [
    '#D97706',
    '#2563EB',
    '#059669',
    '#7C3AED',
    '#0891B2',
  ];
  DateTime _day(int offset) =>
      DateTime(_start.year, _start.month, _start.day + offset);
  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to update schedule. Please try again.';
  Color _color(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openRequest != oldWidget.openRequest ||
        !DateUtils.isSameDay(widget.date, oldWidget.date)) {
      _selected = DateUtils.dateOnly(widget.date);
      _start = _selected;
      _load();
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.call('getWeek', {'startDate': _iso(_start)});
      if (mounted && request == _request) {
        setState(() {
          _blocks = (data['blocks'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = _message(e));
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _navigate(int periods) {
    setState(() {
      _start = _day(periods * _days);
      _selected = _start;
    });
    _load();
  }

  Future<void> _edit(
    DateTime date, {
    int hour = 9,
    Map<String, dynamic>? block,
  }) async {
    var title = block?['title'] as String? ?? '',
        note = block?['note'] as String? ?? '';
    var start =
            block?['start'] as String? ??
            '${hour.toString().padLeft(2, '0')}:00',
        end =
            block?['end'] as String? ??
            '${(hour + 1).toString().padLeft(2, '0')}:00';
    var color = block?['color'] as String? ?? _colors.first;
    var saving = false;
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(
                block == null ? 'New schedule block' : 'Edit schedule block',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat.yMMMEd().format(date)),
                      TextFormField(
                        initialValue: title,
                        autofocus: true,
                        enabled: !saving,
                        maxLength: 200,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: (v) => title = v,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: start,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'Start time',
                                hintText: '09:00',
                                helperText: '24-hour HH:mm',
                              ),
                              onChanged: (v) => start = v,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              initialValue: end,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                labelText: 'End time',
                                hintText: '17:00',
                                helperText: 'Same day',
                              ),
                              onChanged: (v) => end = v,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final c in _colors)
                            ChoiceChip(
                              label: Text(
                                c == _colors[0]
                                    ? 'Amber'
                                    : c == _colors[1]
                                    ? 'Blue'
                                    : c == _colors[2]
                                    ? 'Green'
                                    : c == _colors[3]
                                    ? 'Purple'
                                    : 'Teal',
                              ),
                              selected: c == color,
                              avatar: Icon(
                                Icons.circle,
                                color: _color(c),
                                size: 12,
                              ),
                              onSelected: saving
                                  ? null
                                  : (_) => update(() => color = c),
                            ),
                        ],
                      ),
                      TextFormField(
                        initialValue: note,
                        enabled: !saving,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Notes'),
                        onChanged: (v) => note = v,
                      ),
                      if (error != null) Text(error!),
                    ],
                  ),
                ),
              ),
              actions: [
                if (block != null)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                              context: ctx,
                              builder: (confirm) => AlertDialog(
                                title: const Text('Delete this block?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(confirm, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(confirm, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true || !ctx.mounted) return;
                            update(() => saving = true);
                            try {
                              await _service.call('deleteBlock', {
                                'blockId': block['id'],
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
                          },
                    child: const Text('Delete block'),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (title.trim().isEmpty) {
                            update(() => error = 'Enter a title.');
                            return;
                          }
                          final pattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
                          if (!pattern.hasMatch(start) ||
                              (end != '24:00' && !pattern.hasMatch(end)) ||
                              end.compareTo(start) <= 0) {
                            update(
                              () => error =
                                  'Use HH:mm, with end after start on the same day.',
                            );
                            return;
                          }
                          update(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await _service.call('saveBlock', {
                              'date': _iso(date),
                              'title': title.trim(),
                              'start': start,
                              'end': end,
                              'color': color,
                              'note': note,
                              if (block != null) 'blockId': block['id'],
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
                        },
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Widget _grid(double width) => ScheduleTimeline(
    week: _start,
    days: _days,
    onAnimationEnd: () => _followBottom = false,
    onToggleEarly: () => setState(() {
      _followBottom = false;
      _early = !_early;
    }),
    onToggleLate: () => setState(() {
      _followBottom = true;
      _late = !_late;
    }),
    onExtentChanged: () {
      if (!_followBottom) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _followBottom && _vertical.hasClients) {
          _vertical.jumpTo(_vertical.position.maxScrollExtent);
        }
      });
    },
    selected: _selected,
    blocks: _blocks,
    width: width,
    early: _early,
    late: _late,
    onCreate: (date, hour) => _edit(date, hour: hour),
    onEdit: (date, block) => _edit(date, block: block),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            const Text(
              'Schedule',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous period',
                  onPressed: _loading ? null : () => _navigate(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  _days == 1
                      ? DateFormat.yMMMEd().format(_start)
                      : '${DateFormat.MMMd().format(_start)} to ${DateFormat.yMMMd().format(_day(_days - 1))}',
                  key: const ValueKey('schedule-week'),
                ),
                IconButton(
                  tooltip: 'Next period',
                  onPressed: _loading ? null : () => _navigate(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  key: const ValueKey('schedule-days'),
                  value: _days,
                  items: [
                    for (var n = 1; n <= 7; n++)
                      DropdownMenuItem(
                        value: n,
                        child: Text(n == 1 ? '1 day' : '$n days'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _days = value);
                  },
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _selected = DateUtils.dateOnly(DateTime.now());
                            _start = _selected;
                          });
                          _load();
                        },
                  child: const Text('Today'),
                ),
                IconButton(
                  tooltip: 'Refresh schedule',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                FilledButton.icon(
                  onPressed: _loading || _error != null
                      ? null
                      : () => _edit(_selected),
                  icon: const Icon(Icons.add),
                  label: const Text('Add block'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      Expanded(
        child: _loading
            ? const SizedBox.shrink()
            : LayoutBuilder(
                builder: (ctx, size) => Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(
                        size.maxWidth,
                        ScheduleTimeline.gutter + _days * 140.0,
                      ),
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: _grid(
                          math.max(
                            size.maxWidth,
                            ScheduleTimeline.gutter + _days * 140.0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ],
  );
}
