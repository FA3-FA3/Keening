import '../widgets/app_dropdown.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/item_attachments.dart';
import 'package:intl/intl.dart';
import '../utils/schedule_service.dart';
import '../widgets/multi_date_calendar.dart';
import '../widgets/schedule_timeline.dart';
import '../widgets/tag_manager_dialog.dart';
import '../widgets/item_links.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    this.searchTarget,
    required this.date,
    this.service,
    this.openRequest = 0,
    this.refreshRequest = 0,
  });
  final int openRequest, refreshRequest;
  final DateTime date;
  final ScheduleService? service;
  final Map<String, dynamic>? searchTarget;
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
  List<Map<String, dynamic>> _tags = [];
  bool _early = false, _late = false;
  bool _loading = true;
  String? _error;
  int _request = 0;
  /// Sessions without a tag are grey.
  static const _defaultColor = '#6B7280';
  DateTime _day(int offset) =>
      DateTime(_start.year, _start.month, _start.day + offset);
  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to update schedule. Please try again.';
  Color _color(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  Future<void> _openSearch() async {
    final target = widget.searchTarget!;
    final date = DateTime.tryParse(target['date'] as String? ?? '');
    if (date == null) return;
    _selected = date;
    _start = date;
    await _load();
    if (!mounted || widget.searchTarget != target || _error != null) return;
    final block = _blocks.where((i) => i['id'] == target['id']).firstOrNull;
    if (block != null) await _edit(date, block: block);
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
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchTarget != oldWidget.searchTarget &&
        widget.searchTarget != null) {
      _openSearch();
      return;
    }
    if (widget.openRequest != oldWidget.openRequest ||
        !DateUtils.isSameDay(widget.date, oldWidget.date)) {
      _selected = DateUtils.dateOnly(widget.date);
      _start = _selected;
      _load();
    } else if (widget.refreshRequest != oldWidget.refreshRequest) {
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
          _tags = (data['tagDefinitions'] as List? ?? [])
              .map((t) => Map<String, dynamic>.from(t))
              .toList();
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

  Future<void> _editTags() async {
    final saved = await showDialog<TagList>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TagManagerDialog.list(
        title: 'Session tags',
        deleteWarning: 'This removes the tag from all sessions.',
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

  Future<void> _edit(
    DateTime date, {
    int hour = 9,
    Map<String, dynamic>? block,
  }) async {
    var sessionDate = DateUtils.dateOnly(date);
    var title = block?['title'] as String? ?? '',
        note = block?['note'] as String? ?? '';
    var location = block?['location'] as String? ?? '';
    var start =
            block?['start'] as String? ??
            '${hour.toString().padLeft(2, '0')}:00',
        end =
            block?['end'] as String? ??
            '${(hour + 1).toString().padLeft(2, '0')}:00';
    var color = block?['color'] as String? ?? _defaultColor;
    String? tagId = block?['tagId'] as String?;
    var saving = false;
    var repeat = false;
    final repeatDates = <DateTime>{};
    var sessionSaved = false;
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(block == null ? 'New session' : 'Edit session'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('session-date'),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        label: Text(DateFormat.yMMMEd().format(sessionDate)),
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: sessionDate,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200, 12, 31),
                                  helpText: 'Session date',
                                );
                                if (picked != null && ctx.mounted) {
                                  update(() => sessionDate = picked);
                                }
                              },
                      ),
                      if (block == null) ...[
                        SwitchListTile(
                          key: const ValueKey('session-repeat'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Recurring session'),
                          subtitle: const Text('Also happens on other days'),
                          value: repeat,
                          onChanged: saving
                              ? null
                              : (v) => update(() => repeat = v),
                        ),
                        if (repeat) ...[
                          MultiDateCalendar(
                            fixed: sessionDate,
                            selected: repeatDates,
                            enabled: !saving,
                            onChanged: (d) => update(() {
                              repeatDates
                                ..clear()
                                ..addAll(d);
                            }),
                          ),
                          Text(
                            repeatDates.isEmpty
                                ? 'Tap days to repeat this session on.'
                                : 'Repeats on ${repeatDates.length} other ${repeatDates.length == 1 ? 'day' : 'days'}.',
                          ),
                        ],
                      ],
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
                      const Text('Tag'),
                      if (_tags.isEmpty)
                        const Text(
                          'Create tags using the Tags menu on Schedule.',
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
                                color: _color(tag['color'] as String),
                                size: 12,
                              ),
                              onSelected: saving
                                  ? null
                                  : (_) => update(() {
                                      tagId = tag['id'] as String;
                                      color = tag['color'] as String;
                                    }),
                            ),
                        ],
                      ),
                      TextFormField(
                        key: const ValueKey('session-location'),
                        initialValue: location,
                        enabled: !saving,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                        ),
                        onChanged: (v) => location = v,
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
                      ItemLinks(
                        source: 'session',
                        sessionId: block?['id'] as String?,
                        enabled: !saving,
                      ),
                      ItemAttachments(
                        itemType: 'session',
                        itemId: block?['id'] as String?,
                        enabled: !saving,
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
                                title: const Text('Delete this session?'),
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
                    child: const Text('Delete session'),
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
                              'date': _iso(sessionDate),
                              'title': title.trim(),
                              'start': start,
                              'end': end,
                              'color': color,
                              'tagId': tagId,
                              'note': note,
                              'location': location.trim(),
                              if (block != null) 'blockId': block['id'],
                              if (block == null &&
                                  repeat &&
                                  repeatDates.isNotEmpty)
                                'repeatDates': [
                                  for (final d in repeatDates)
                                    if (d != sessionDate) _iso(d),
                                ]..sort(),
                            });
                            sessionSaved = true;
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
    if (changed == true && mounted) {
      if (sessionSaved) {
        setState(() {
          _selected = sessionDate;
          if (sessionDate.isBefore(_start) ||
              !sessionDate.isBefore(_day(_days))) {
            _start = sessionDate;
          }
        });
      }
      await _load();
    }
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
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: _content(context)),
      const SizedBox(key: ValueKey('schedule-right-margin'), width: 24),
    ],
  );

  Widget _content(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final width = math.max(
        size.maxWidth,
        ScheduleTimeline.gutter + _days * 140.0,
      );
      return Scrollbar(
        controller: _vertical,
        thumbVisibility: true,
        child: CustomScrollView(
          key: const ValueKey('workspace-page-scroll'),
          controller: _vertical,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
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
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
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
                            AppDropdownButton<int>(
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
                                if (value != null) {
                                  setState(() => _days = value);
                                }
                              },
                            ),
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () {
                                      setState(() {
                                        _selected = DateUtils.dateOnly(
                                          DateTime.now(),
                                        );
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
                            TextButton.icon(
                              key: const ValueKey('schedule-tags'),
                              onPressed: _loading || _error != null
                                  ? null
                                  : _editTags,
                              icon: const Icon(Icons.label_outline),
                              label: const Text('Tags'),
                            ),
                            FilledButton.icon(
                              onPressed: _loading || _error != null
                                  ? null
                                  : () => _edit(_selected),
                              icon: const Icon(Icons.add),
                              label: const Text('Add session'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final tag in _tags)
                            Chip(
                              avatar: Icon(
                                Icons.circle,
                                size: 14,
                                color: _color(tag['color'] as String),
                              ),
                              label: Text(tag['name'] as String),
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
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (!_loading) ...[
              SliverPersistentHeader(
                pinned: true,
                delegate: _ScheduleHeaderDelegate(
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _horizontal,
                      builder: (context, _) => OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: width,
                        maxWidth: width,
                        child: Transform.translate(
                          offset: Offset(
                            _horizontal.hasClients ? -_horizontal.offset : 0,
                            0,
                          ),
                          child: ScheduleDayHeader(
                            week: _start,
                            selected: _selected,
                            days: _days,
                            width: width,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: width, child: _grid(width)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _ScheduleHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ScheduleHeaderDelegate({required this.child});
  final Widget child;
  @override
  double get minExtent => 38;
  @override
  double get maxExtent => 38;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => child;
  @override
  bool shouldRebuild(covariant _ScheduleHeaderDelegate oldDelegate) => true;
}
