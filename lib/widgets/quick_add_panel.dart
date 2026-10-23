import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/boards_service.dart';
import '../utils/calendar_service.dart';
import '../utils/document_defaults.dart';
import '../utils/gantt_service.dart';
import '../utils/pads_service.dart';
import '../utils/projects_service.dart';
import '../utils/schedule_service.dart';

/// Something the quick-add panel can create, and the dashboard tab it belongs to.
enum QuickAddKind {
  document('Document', 'Documents', Icons.description_outlined),
  folder('Folder', 'Documents', Icons.folder_outlined),
  project('Project', 'Projects', Icons.work_outline),
  phase('Gantt phase', 'Gantt', Icons.view_timeline_outlined),
  event('Calendar event', 'Calendar', Icons.event_outlined),
  board('Board', 'Boards', Icons.dashboard_outlined),
  task('Board task', 'Boards', Icons.task_alt),
  session('Schedule session', 'Schedule', Icons.schedule);

  const QuickAddKind(this.label, this.tab, this.icon);
  final String label;
  final String tab;
  final IconData icon;
}

const _documentKinds = {
  'pad': 'Dynamic Pad',
  'notepad': 'Notepad',
  'sheet': 'Spreadsheet',
  'gantt': 'Gantt calendar',
};
const _defaultColor = '#2563EB';

/// A small panel pinned to the bottom right of the screen for creating things on
/// any page without leaving the one that is open. It is not modal: the page
/// behind it stays usable and is not dimmed.
class QuickAddPanel extends StatefulWidget {
  const QuickAddPanel({
    super.key,
    required this.onClose,
    required this.onCreated,
    this.padsService,
    this.projectsService,
    this.calendarService,
    this.ganttService,
    this.boardsService,
    this.scheduleService,
  });

  final VoidCallback onClose;

  /// Called after something is created, with the tab it appears on.
  final ValueChanged<String> onCreated;
  final PadsService? padsService;
  final ProjectsService? projectsService;
  final CalendarService? calendarService;
  final GanttService? ganttService;
  final BoardsService? boardsService;
  final ScheduleService? scheduleService;

  @override
  State<QuickAddPanel> createState() => _QuickAddPanelState();
}

class _QuickAddPanelState extends State<QuickAddPanel> {
  late final _pads = widget.padsService ?? PadsService();
  late final _projects = widget.projectsService ?? ProjectsService();
  late final _calendar = widget.calendarService ?? CalendarService();
  late final _gantt = widget.ganttService ?? GanttService();
  late final _boards = widget.boardsService ?? BoardsService();
  late final _schedule = widget.scheduleService ?? ScheduleService();

  var _kind = QuickAddKind.document;
  final _title = TextEditingController();
  final _date = TextEditingController(text: _iso(DateTime.now()));
  final _endDate = TextEditingController(text: _iso(DateTime.now()));
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '10:00');
  var _documentKind = 'notepad';
  var _timed = false;
  var _saving = false;
  String? _error, _done;

  // Choices that come from the server, loaded when a kind needs them.
  List<Map<String, dynamic>> _ganttCalendars = [], _workplaces = [];
  List<Map<String, dynamic>> _columns = [];
  String? _ganttCalendar, _workplace, _column;
  var _loadingChoices = false;

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  void initState() {
    super.initState();
    _title.addListener(() {
      if (_done != null) setState(() => _done = null);
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _date, _endDate, _start, _end]) {
      c.dispose();
    }
    if (widget.padsService == null) _pads.close();
    if (widget.projectsService == null) _projects.close();
    if (widget.calendarService == null) _calendar.close();
    if (widget.ganttService == null) _gantt.close();
    if (widget.boardsService == null) _boards.close();
    if (widget.scheduleService == null) _schedule.close();
    super.dispose();
  }

  List<Map<String, dynamic>> _list(Object? v) => [
    for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e),
  ];

  String _message(Object e) {
    final text = e.toString();
    return text.startsWith('Exception: ')
        ? text.substring(11)
        : 'Could not add that. Please try again.';
  }

  Future<void> _select(QuickAddKind kind) async {
    setState(() {
      _kind = kind;
      _error = null;
      _done = null;
    });
    if (kind == QuickAddKind.phase && _ganttCalendars.isEmpty) {
      await _loadChoices(() async {
        final r = await _gantt.call('listCalendars');
        _ganttCalendars = _list(r['calendars']);
        _ganttCalendar ??= _ganttCalendars.firstOrNull?['id'] as String?;
      });
    } else if (kind == QuickAddKind.task && _workplaces.isEmpty) {
      await _loadChoices(() async {
        final r = await _boards.call('listWorkplaces');
        _workplaces = _list(r['workplaces']);
        _workplace ??= _workplaces.firstOrNull?['id'] as String?;
        await _loadColumns();
      });
    }
  }

  Future<void> _loadColumns() async {
    final id = _workplace;
    if (id == null) {
      _columns = [];
      _column = null;
      return;
    }
    final r = await _boards.call('getBoard', {'workplaceId': id});
    if (id != _workplace) return;
    _columns = _list(r['columns']);
    _column = _columns.any((c) => c['id'] == _column)
        ? _column
        : _columns.firstOrNull?['id'] as String?;
  }

  Future<void> _loadChoices(Future<void> Function() load) async {
    setState(() => _loadingChoices = true);
    try {
      await load();
    } catch (e) {
      if (mounted) _error = _message(e);
    }
    if (mounted) setState(() => _loadingChoices = false);
  }

  bool _validDate(String s) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
      DateTime.tryParse(s) != null;
  bool _validTime(String s) =>
      RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(s);

  Future<void> _add() async {
    final title = _title.text.trim();
    final label = _kind == QuickAddKind.folder || _kind == QuickAddKind.board
        ? 'a name'
        : 'a title';
    if (title.isEmpty) {
      setState(() => _error = 'Enter $label.');
      return;
    }
    final needsDate = const [
      QuickAddKind.event,
      QuickAddKind.session,
      QuickAddKind.phase,
    ].contains(_kind);
    if (needsDate && !_validDate(_date.text.trim())) {
      setState(() => _error = 'Enter the date as yyyy-mm-dd.');
      return;
    }
    if (_kind == QuickAddKind.phase) {
      if (!_validDate(_endDate.text.trim()) ||
          _endDate.text.trim().compareTo(_date.text.trim()) < 0) {
        setState(() => _error = 'Enter an end date on or after the start.');
        return;
      }
      if (_ganttCalendar == null) {
        setState(
          () => _error =
              'Create a Gantt calendar first (New document, then Gantt calendar).',
        );
        return;
      }
    }
    final timed =
        _kind == QuickAddKind.session ||
        (_kind == QuickAddKind.event && _timed);
    if (timed) {
      final s = _start.text.trim(), e = _end.text.trim();
      if (!_validTime(s) ||
          !(e == '24:00' || _validTime(e)) ||
          e.compareTo(s) <= 0) {
        setState(
          () => _error = 'Enter HH:mm times, with the end after the start.',
        );
        return;
      }
    }
    if (_kind == QuickAddKind.task && (_workplace == null || _column == null)) {
      setState(
        () => _error = 'Create a board with a panel on the Boards page first.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _done = null;
    });
    try {
      await _create(title);
      if (!mounted) return;
      _title.clear();
      setState(() {
        _saving = false;
        _done = '${_kind.label} added.';
      });
      widget.onCreated(_kind.tab);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _create(String title) async {
    final date = _date.text.trim();
    switch (_kind) {
      case QuickAddKind.document:
        final created = await _pads.call('createPad', {
          'name': title,
          'description': '',
          'kind': _documentKind,
          'folderId': null,
        });
        final id = (created['pad'] as Map?)?['id'];
        if (id is String) {
          await applyDocumentDefaults(_pads, id, _documentKind);
        }
      case QuickAddKind.folder:
        await _pads.call('createFolder', {'name': title, 'parentId': null});
      case QuickAddKind.project:
        await _projects.call('createProject', {
          'name': title,
          'description': '',
          'color': _defaultColor,
        });
      case QuickAddKind.phase:
        await _gantt.call('saveItem', {
          'calendar_id': _ganttCalendar,
          'item_id': null,
          'kind': 'event',
          'title': title,
          'description': '',
          'start_date': date,
          'end_date': _endDate.text.trim(),
          'completed': false,
          'prerequisite_id': null,
        });
      case QuickAddKind.event:
        final calendars = _list(
          (await _calendar.call('listCalendars'))['calendars'],
        );
        var calendar = calendars.firstOrNull?['id'] as String?;
        if (calendar == null) {
          final created = await _calendar.call('createCalendar', {
            'name': 'Calendar',
            'color': '#2E7D5B',
          });
          calendar = created['calendar']['id'] as String;
        }
        await _calendar.call('saveItem', {
          'calendar_id': calendar,
          'item_id': null,
          'kind': 'event',
          'title': title,
          'description': '',
          'location': '',
          'tag_id': null,
          'start_date': date,
          'end_date': date,
          'start_time': _timed ? _start.text.trim() : null,
          'end_time': _timed ? _end.text.trim() : null,
          'completed': false,
          'prerequisite_id': null,
        });
      case QuickAddKind.board:
        await _boards.call('createWorkplace', {
          'workplaceId': null,
          'name': title,
          'color': _defaultColor,
        });
        _workplaces = [];
      case QuickAddKind.task:
        await _boards.call('createOrgTask', {
          'workplaceId': _workplace,
          'columnId': _column,
          'title': title,
          'description': '',
          'color': _defaultColor,
          'tagIds': <String>[],
          'completed': false,
        });
      case QuickAddKind.session:
        await _schedule.call('saveBlock', {
          'date': date,
          'title': title,
          'start': _start.text.trim(),
          'end': _end.text.trim(),
          'color': _defaultColor,
          'tagId': null,
          'note': '',
          'location': '',
        });
    }
  }

  Widget _field(
    TextEditingController c,
    String label, {
    Key? key,
    int? maxLength,
    VoidCallback? onSubmit,
  }) => TextField(
    key: key,
    controller: c,
    enabled: !_saving,
    maxLength: maxLength,
    textInputAction: onSubmit == null
        ? TextInputAction.next
        : TextInputAction.done,
    onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
    decoration: InputDecoration(
      labelText: label,
      isDense: false,
      counterText: '',
    ),
  );

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) => DropdownButtonFormField<T>(
    isExpanded: true,
    initialValue: value,
    decoration: InputDecoration(labelText: label, isDense: true),
    items: items,
    onChanged: _saving ? null : onChanged,
  );

  List<Widget> _fields() {
    final kind = _kind;
    final nameLabel = kind == QuickAddKind.folder || kind == QuickAddKind.board
        ? 'Name'
        : kind == QuickAddKind.project || kind == QuickAddKind.document
        ? 'Name'
        : 'Title';
    return [
      _field(
        _title,
        nameLabel,
        key: const ValueKey('quick-add-title'),
        maxLength: 200,
        onSubmit: _add,
      ),
      if (kind == QuickAddKind.document)
        _dropdown<String>(
          label: 'Type',
          value: _documentKind,
          items: [
            for (final e in _documentKinds.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _documentKind = v ?? 'notepad'),
        ),
      if (kind == QuickAddKind.phase)
        _dropdown<String>(
          label: 'Gantt calendar',
          value: _ganttCalendar,
          items: [
            for (final c in _ganttCalendars)
              DropdownMenuItem(
                value: c['id'] as String,
                child: Text(
                  c['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _ganttCalendar = v),
        ),
      if (kind == QuickAddKind.task) ...[
        _dropdown<String>(
          label: 'Board',
          value: _workplace,
          items: [
            for (final w in _workplaces)
              DropdownMenuItem(
                value: w['id'] as String,
                child: Text(
                  w['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) async {
            setState(() => _workplace = v);
            await _loadChoices(_loadColumns);
          },
        ),
        _dropdown<String>(
          label: 'Panel',
          value: _column,
          items: [
            for (final c in _columns)
              DropdownMenuItem(
                value: c['id'] as String,
                child: Text(
                  c['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _column = v),
        ),
      ],
      if (kind == QuickAddKind.event ||
          kind == QuickAddKind.session ||
          kind == QuickAddKind.phase)
        Row(
          children: [
            Expanded(
              child: _field(
                _date,
                kind == QuickAddKind.phase
                    ? 'Start (yyyy-mm-dd)'
                    : 'Date (yyyy-mm-dd)',
              ),
            ),
            if (kind == QuickAddKind.phase) ...[
              const SizedBox(width: 8),
              Expanded(child: _field(_endDate, 'End (yyyy-mm-dd)')),
            ],
          ],
        ),
      if (kind == QuickAddKind.event)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Set a time'),
          value: _timed,
          onChanged: _saving
              ? null
              : (v) => setState(() => _timed = v ?? false),
        ),
      if (kind == QuickAddKind.session ||
          (kind == QuickAddKind.event && _timed))
        Row(
          children: [
            Expanded(child: _field(_start, 'Start (HH:mm)')),
            const SizedBox(width: 8),
            Expanded(child: _field(_end, 'End (HH:mm)')),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = _fields();
    return Material(
      key: const ValueKey('quick-add-panel'),
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: AppColors.surface(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height - 96,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Quick add',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('quick-add-close'),
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in QuickAddKind.values)
                      ChoiceChip(
                        key: ValueKey('quick-add-${k.name}'),
                        avatar: Icon(k.icon, size: 16),
                        label: Text(k.label),
                        selected: _kind == k,
                        onSelected: _saving ? null : (_) => _select(k),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loadingChoices) const LinearProgressIndicator(),
                for (final f in fields) ...[f, const SizedBox(height: 12)],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                if (_done != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _done!,
                      style: TextStyle(color: scheme.primary),
                    ),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  key: const ValueKey('quick-add-submit'),
                  onPressed: _saving || _loadingChoices ? null : _add,
                  child: Text(
                    _saving ? 'Adding...' : 'Add ${_kind.label.toLowerCase()}',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
