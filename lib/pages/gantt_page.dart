import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/gantt_service.dart';
import '../widgets/calendar_dependency_arrows.dart';
import '../widgets/item_links.dart';

String _iso(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
int _daysBetween(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);
Color _calendarColor(Map<String, dynamic> item, BuildContext context) {
  final hex = item['color'] ?? item['department_color'];
  if (hex is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }
  return Theme.of(context).colorScheme.primary;
}

// showDateRangePicker's calendar mode is forced full-screen by Flutter, so
// the range is picked with a compact popup showing both calendars instead.
Future<DateTimeRange?> _pickDateRange({
  required BuildContext context,
  required DateTimeRange initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _DateRangePickerPopup(
      initialDateRange: initialDateRange,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _DateRangePickerPopup extends StatefulWidget {
  final DateTimeRange initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  const _DateRangePickerPopup({
    required this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DateRangePickerPopup> createState() => _DateRangePickerPopupState();
}

class _DateRangePickerPopupState extends State<_DateRangePickerPopup> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialDateRange.start;
    _end = widget.initialDateRange.end;
  }

  Widget _column(String label, Widget calendar) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          calendar,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select dates',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _column(
                      'Start date',
                      CalendarDatePicker(
                        initialDate: _start,
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onDateChanged: (date) => setState(() {
                          _start = date;
                          if (_end.isBefore(_start)) _end = _start;
                        }),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    _column(
                      'End date',
                      CalendarDatePicker(
                        key: ValueKey(_start),
                        initialDate: _end,
                        firstDate: _start,
                        lastDate: widget.lastDate,
                        onDateChanged: (date) => setState(() => _end = date),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      DateTimeRange(start: _start, end: _end),
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sorbit's Gantt timeline adapted for user-owned Keening calendars.
class GanttPage extends StatefulWidget {
  const GanttPage({super.key, this.service});
  final GanttService? service;
  @override
  State<GanttPage> createState() => _GanttPageState();
}

class _GanttPageState extends State<GanttPage> {
  late final GanttService _service;
  List<Map<String, dynamic>> _calendars = [];
  List<Map<String, dynamic>> _items = [];
  String? _selected;
  String? _error;
  bool _loading = true;
  bool _savingOrder = false;
  int _request = 0;
  int _days = 28;
  late DateTime _start;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GanttService();
    final today = DateUtils.dateOnly(DateTime.now());
    _start = _addDays(today, 1 - today.weekday);
    _loadCalendars();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object error) => error is StateError
      ? error.message.toString()
      : 'Unable to connect. Please try again.';

  Future<void> _loadCalendars({String? preferred}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.call('listCalendars');
      if (!mounted) return;
      _calendars = (data['calendars'] as List).cast<Map<String, dynamic>>();
      final choice = preferred ?? _selected;
      _selected = _calendars.any((c) => c['id'] == choice)
          ? choice
          : _calendars.firstOrNull?['id'] as String?;
      await _loadItems();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadItems() async {
    final request = ++_request;
    final selected = _selected;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = selected == null
          ? <String, dynamic>{'items': []}
          : await _service.call('listItems', {'calendar_id': selected});
      if (!mounted || request != _request) return;
      setState(() {
        _items = (data['items'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = _message(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _calendarDialog({bool rename = false}) async {
    final selected = _selected;
    var name = rename
        ? _calendars.firstWhere((c) => c['id'] == selected)['name'] as String
        : '';
    var color = '#2E7D5B';
    var saving = false;
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(rename ? 'Rename calendar' : 'Create calendar'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: name,
                      autofocus: true,
                      enabled: !saving,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Calendar name',
                      ),
                      onChanged: (v) => name = v,
                    ),
                    if (!rename)
                      DropdownButtonFormField<String>(
                        initialValue: color,
                        decoration: const InputDecoration(labelText: 'Colour'),
                        items: const [
                          DropdownMenuItem(
                            value: '#2E7D5B',
                            child: Text('Green'),
                          ),
                          DropdownMenuItem(
                            value: '#2563EB',
                            child: Text('Blue'),
                          ),
                          DropdownMenuItem(
                            value: '#7C3AED',
                            child: Text('Purple'),
                          ),
                          DropdownMenuItem(
                            value: '#0D9488',
                            child: Text('Teal'),
                          ),
                          DropdownMenuItem(
                            value: '#A16207',
                            child: Text('Gold'),
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => update(() => color = v!),
                      ),
                    if (error != null) Text(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (name.trim().isEmpty) {
                          update(() => error = 'Enter a calendar name.');
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final data = await _service.call(
                            rename ? 'renameCalendar' : 'createCalendar',
                            {
                              'name': name.trim(),
                              if (rename) 'calendar_id': selected,
                              if (!rename) 'color': color,
                            },
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(
                              dialogContext,
                              rename
                                  ? selected
                                  : data['calendar']['id'] as String,
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            update(() {
                              saving = false;
                              error = _message(e);
                            });
                          }
                        }
                      },
                child: Text(
                  saving
                      ? 'Saving...'
                      : rename
                      ? 'Save'
                      : 'Create',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null && mounted) await _loadCalendars(preferred: result);
  }

  Future<void> _deleteCalendar() async {
    final selected = _selected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete calendar?'),
        content: const Text(
          'This permanently deletes this calendar and all its events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _service.call('deleteCalendar', {'calendar_id': selected});
      if (mounted) await _loadCalendars();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _editItem({Map<String, dynamic>? item}) async {
    final calendarId = _selected;
    var title = item?['title'] as String? ?? '';
    var description = item?['description'] as String? ?? '';
    var completed = item?['completed'] == true;
    var prerequisite = item?['prerequisite_id'] as String? ?? '';
    final initialStart =
        DateTime.tryParse(item?['start_date'] as String? ?? '') ??
        DateUtils.dateOnly(DateTime.now());
    var range = DateTimeRange(
      start: initialStart,
      end:
          DateTime.tryParse(item?['end_date'] as String? ?? '') ?? initialStart,
    );
    final byId = {for (final entry in _items) entry['id']: entry};
    bool createsCycle(Map<String, dynamic> candidate) {
      final seen = <String>{};
      String? id = candidate['id'] as String;
      while (id != null) {
        if (id == item?['id'] || !seen.add(id)) return true;
        id = byId[id]?['prerequisite_id'] as String?;
      }
      return false;
    }

    final options = _items.where((entry) => !createsCycle(entry)).toList();
    var saving = false;
    String? error;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> persist({bool remove = false}) async {
            if (saving) return;
            if (!remove && title.trim().isEmpty) {
              update(() => error = 'Enter a title.');
              return;
            }
            if (remove) {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete item?'),
                  content: const Text(
                    'This also removes links that depend on this item.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
            }
            update(() {
              saving = true;
              error = null;
            });
            try {
              await _service.call(remove ? 'deleteItem' : 'saveItem', {
                'calendar_id': calendarId,
                'item_id': item?['id'],
                if (!remove) ...{
                  'kind': 'event',
                  'title': title.trim(),
                  'description': description.trim(),
                  'start_date': _iso(range.start),
                  'end_date': _iso(range.end),
                  'completed': completed,
                  'prerequisite_id': prerequisite.isEmpty ? null : prerequisite,
                },
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            } catch (e) {
              if (context.mounted) {
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
              title: Text(item == null ? 'New event' : 'Event details'),
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
                      TextFormField(
                        initialValue: description,
                        enabled: !saving,
                        maxLength: 5000,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: prerequisite,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Prerequisite (optional)',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('None'),
                          ),
                          for (final entry in options)
                            DropdownMenuItem(
                              value: entry['id'] as String,
                              child: Text(
                                entry['title'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => update(() => prerequisite = v ?? ''),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await _pickDateRange(
                                  context: context,
                                  initialDateRange: range,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200, 12, 31),
                                );
                                if (picked != null && context.mounted) {
                                  update(() => range = picked);
                                }
                              },
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          '${DateFormat.yMMMd().format(range.start)} – ${DateFormat.yMMMd().format(range.end)}',
                        ),
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
                        source: 'event',
                        eventId: item?['id'] as String?,
                        enabled: !saving,
                      ),
                      if (error != null) Text(error!),
                    ],
                  ),
                ),
              ),
              actions: [
                if (item != null)
                  TextButton(
                    onPressed: saving ? null : () => persist(remove: true),
                    child: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : persist,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (changed == true && mounted) await _loadItems();
  }

  Future<void> _reorderRows(
    List<Map<String, dynamic>> visible,
    int oldIndex,
    int newIndex,
  ) async {
    if (_savingOrder) return;
    if (oldIndex < newIndex) newIndex--;
    if (oldIndex == newIndex) return;
    final previous = List<Map<String, dynamic>>.from(_items);
    final reordered = List<Map<String, dynamic>>.from(visible);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    final keys = visible.map((item) => item['id']).toSet();
    var index = 0;
    setState(() {
      _items = [
        for (final item in _items)
          keys.contains(item['id']) ? reordered[index++] : item,
      ];
      _savingOrder = true;
    });
    try {
      await _service.call('reorderItems', {
        'calendar_id': _selected,
        'item_ids': _items.map((item) => item['id']).toList(),
      });
    } catch (e) {
      if (mounted) {
        setState(() => _items = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(e))));
      }
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final end = _addDays(_start, _days - 1);
    final visible = _items
        .where(
          (item) =>
              DateTime.parse(item['start_date'] as String).compareTo(end) <=
                  0 &&
              DateTime.parse(item['end_date'] as String).compareTo(_start) >= 0,
        )
        .toList();
    final busy = _loading || _savingOrder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Gantt', style: Theme.of(context).textTheme.headlineMedium),
              FilledButton.icon(
                onPressed: busy || _error != null
                    ? null
                    : () => _calendarDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Create calendar'),
              ),
              IconButton(
                tooltip: 'Refresh calendars',
                onPressed: busy ? null : _loadCalendars,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_calendars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final calendar in _calendars)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(calendar['name'] as String),
                        selected: calendar['id'] == _selected,
                        selectedColor: _calendarColor(
                          calendar,
                          context,
                        ).withValues(alpha: 0.18),
                        onSelected: busy
                            ? null
                            : (_) {
                                if (calendar['id'] != _selected) {
                                  _selected = calendar['id'] as String;
                                  _loadItems();
                                }
                              },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous period',
                      onPressed: () =>
                          setState(() => _start = _addDays(_start, -_days)),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _start = DateUtils.dateOnly(DateTime.now()),
                      ),
                      child: const Text('Today'),
                    ),
                    IconButton(
                      tooltip: 'Next period',
                      onPressed: () =>
                          setState(() => _start = _addDays(_start, _days)),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Text(
                  '${DateFormat.MMMd().format(_start)} – ${DateFormat.yMMMd().format(end)}',
                ),
                DropdownButton<int>(
                  value: _days,
                  items: const [
                    DropdownMenuItem(value: 14, child: Text('2 weeks')),
                    DropdownMenuItem(value: 28, child: Text('4 weeks')),
                    DropdownMenuItem(value: 84, child: Text('12 weeks')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _days = v);
                  },
                ),
                FilledButton.icon(
                  onPressed: busy || _error != null ? null : () => _editItem(),
                  icon: const Icon(Icons.add),
                  label: const Text('New event'),
                ),
                IconButton(
                  tooltip: 'Rename calendar',
                  onPressed: busy ? null : () => _calendarDialog(rename: true),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete calendar',
                  onPressed: busy ? null : _deleteCalendar,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                        onPressed: _loadCalendars,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _selected == null
              ? const Center(
                  child: Text(
                    'Create your first Gantt calendar to get started.',
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 16),
                  child: _GanttTimeline(
                    start: _start,
                    days: _days,
                    items: visible,
                    onOpen: (item) {
                      if (!busy) _editItem(item: item);
                    },
                    showDragHandles: true,
                    onReorder: _savingOrder
                        ? null
                        : (oldIndex, newIndex) =>
                              _reorderRows(visible, oldIndex, newIndex),
                  ),
                ),
        ),
      ],
    );
  }
}

class _GanttTimeline extends StatefulWidget {
  final DateTime start;
  final int days;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ReorderCallback? onReorder;
  final bool showDragHandles;
  const _GanttTimeline({
    required this.start,
    required this.days,
    required this.items,
    required this.onOpen,
    this.onReorder,
    required this.showDragHandles,
  });

  @override
  State<_GanttTimeline> createState() => _GanttTimelineState();
}

class _GanttTimelineState extends State<_GanttTimeline> {
  static const double _minimumDayWidth = 44;
  static const double _rowHeight = 64;

  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_refreshScroll);
    _vertical.addListener(_refreshScroll);
  }

  void _refreshScroll() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  // Identifies the row currently under the pointer so the label and the
  // matching Gantt bar row can be highlighted together, whichever is hovered.
  Object? _hoveredKey;

  static Object _keyOf(Map<String, dynamic> item) =>
      '${item['kind']}-${item['id']}';

  void _setHovered(Object key) {
    if (_hoveredKey != key) setState(() => _hoveredKey = key);
  }

  void _clearHovered(Object key) {
    if (_hoveredKey == key) setState(() => _hoveredKey = null);
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final days = widget.days;
    final items = widget.items;
    final onOpen = widget.onOpen;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = math.min(220.0, constraints.maxWidth * 0.35);
        final dayWidth = math.max(
          _minimumDayWidth,
          (constraints.maxWidth - labelWidth) / days,
        );
        final today = _daysBetween(start, DateTime.now());
        final scheme = Theme.of(context).colorScheme;
        Widget grid({Map<String, dynamic>? item}) {
          final first = item == null
              ? 0
              : _daysBetween(
                  start,
                  DateTime.parse(item['start_date'] as String),
                );
          final last = item == null
              ? 0
              : _daysBetween(start, DateTime.parse(item['end_date'] as String));
          final left = math.max(0, first);
          final right = math.min(days - 1, last);
          final color = item == null
              ? scheme.primary
              : _calendarColor(item, context);
          final rowKey = item == null ? null : _keyOf(item);
          final isHovered = rowKey != null && _hoveredKey == rowKey;
          final row = SizedBox(
            height: _rowHeight,
            width: days * dayWidth,
            child: Stack(
              children: [
                Row(
                  children: List.generate(
                    days,
                    (index) => Container(
                      width: dayWidth,
                      decoration: BoxDecoration(
                        color: index == today
                            ? scheme.primary.withValues(alpha: 0.08)
                            : _addDays(start, index).weekday >= 6
                            ? AppColors.grey400.withValues(alpha: 0.06)
                            : null,
                        border: Border(
                          right: BorderSide(color: scheme.outlineVariant),
                          bottom: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                ),
                if (item != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        color: isHovered
                            ? scheme.primary.withValues(alpha: 0.06)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                if (item != null)
                  Positioned(
                    left: left * dayWidth + 3,
                    width: (right - left + 1) * dayWidth - 6,
                    top: 16,
                    height: 32,
                    child: Tooltip(
                      message:
                          '${item['title']}\n${item['start_date']} – ${item['end_date']}',
                      child: Semantics(
                        label:
                            '${item['title']}, ${item['start_date']} to ${item['end_date']}',
                        button: true,
                        child: Material(
                          key: ValueKey(
                            'calendar-bar-${item['kind']}-${item['id']}',
                          ),
                          color: color.withValues(
                            alpha: item['completed'] == true ? 0.45 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                item['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color:
                                      ThemeData.estimateBrightnessForColor(
                                            color,
                                          ) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                  fontSize: 12,
                                  decoration: item['completed'] == true
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
          if (item == null) return row;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _setHovered(rowKey!),
            onExit: (_) => _clearHovered(rowKey!),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(item),
              child: row,
            ),
          );
        }

        final horizontalOffset = _horizontal.hasClients
            ? _horizontal.offset
            : 0.0;
        final verticalOffset = _vertical.hasClients ? _vertical.offset : 0.0;
        Widget timelineRow(Map<String, dynamic>? item) => ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: days * dayWidth,
            maxWidth: days * dayWidth,
            minHeight: _rowHeight,
            maxHeight: _rowHeight,
            child: Transform.translate(
              offset: Offset(-horizontalOffset, 0),
              child: grid(item: item),
            ),
          ),
        );
        final links =
            calendarDependencyLinks(items, start, days, dayWidth, _rowHeight)
                .map(
                  (link) => CalendarDependencyLink(
                    link.prerequisiteKey,
                    link.dependentKey,
                    link.points
                        .map(
                          (point) => point.translate(
                            -horizontalOffset,
                            -verticalOffset - _rowHeight,
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList();

        return Column(
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No scheduled events in this period.'),
              ),
            Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  height: _rowHeight,
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Events',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(days, (index) {
                        final date = _addDays(start, index);
                        return Container(
                          width: dayWidth,
                          height: _rowHeight,
                          alignment: Alignment.center,
                          color: index == today
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerLow,
                          child: Text(
                            '${DateFormat.MMMd().format(date)}\n${DateFormat.E().format(date)}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Stack(
                children: [
                  if (items.isEmpty)
                    SizedBox(
                      height: _rowHeight,
                      child: Row(
                        children: [
                          SizedBox(width: labelWidth),
                          Expanded(child: timelineRow(null)),
                        ],
                      ),
                    )
                  else
                    ReorderableListView.builder(
                      key: const ValueKey('calendar-rows'),
                      scrollController: _vertical,
                      buildDefaultDragHandles: false,
                      itemExtent: _rowHeight,
                      itemCount: items.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          widget.onReorder?.call(
                            oldIndex,
                            oldIndex < newIndex ? newIndex + 1 : newIndex,
                          ),
                      onReorderStart: (_) => setState(() => _dragging = true),
                      onReorderEnd: (_) => setState(() => _dragging = false),
                      proxyDecorator: (child, index, animation) => Material(
                        elevation: 4,
                        color: scheme.surface,
                        child: child,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Row(
                          key: ValueKey('calendar-row-${_keyOf(item)}'),
                          children: [
                            SizedBox(
                              width: labelWidth,
                              height: _rowHeight,
                              child: MouseRegion(
                                onEnter: (_) => _setHovered(_keyOf(item)),
                                onExit: (_) => _clearHovered(_keyOf(item)),
                                child: Container(
                                  color: _hoveredKey == _keyOf(item)
                                      ? scheme.primary.withValues(alpha: 0.06)
                                      : null,
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minLeadingWidth: 20,
                                    horizontalTitleGap: 4,
                                    leading: !widget.showDragHandles
                                        ? null
                                        : ReorderableDragStartListener(
                                            key: ValueKey(
                                              'calendar-drag-${_keyOf(item)}',
                                            ),
                                            index: index,
                                            enabled: widget.onReorder != null,
                                            child: const MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Tooltip(
                                                message: 'Drag to reorder',
                                                child: Padding(
                                                  padding: EdgeInsets.all(4),
                                                  child: Icon(
                                                    Icons.drag_handle,
                                                    color: AppColors.grey400,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                    onTap: () => onOpen(item),
                                    title: Text(
                                      item['title'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${item['calendar_name']} · Event',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: _rowHeight,
                                child: timelineRow(item),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  Positioned.fill(
                    left: labelWidth,
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('calendar-dependency-arrows'),
                        painter: CalendarDependencyPainter(
                          links: _dragging ? [] : links,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
