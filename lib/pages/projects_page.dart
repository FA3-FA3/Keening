import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../utils/projects_service.dart';
import '../widgets/project_timeline.dart';
import 'documents_page.dart' show documentTypeOf;

/// Colours offered for a project.
const projectColors = [
  '#2563EB',
  '#7C3AED',
  '#DB2777',
  '#DC2626',
  '#EA580C',
  '#D97706',
  '#059669',
  '#0891B2',
];

Color _hex(String? hex, [Color fallback = const Color(0xFF2563EB)]) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
    return fallback;
  }
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

DateTime _date(Object? value) =>
    DateTime.tryParse('${value ?? ''}'.split('T').first) ?? DateTime.now();

String _plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

enum _Tab { overview, timeline, boards, documents, items }

extension on _Tab {
  String get label => switch (this) {
    _Tab.overview => 'Overview',
    _Tab.timeline => 'Timeline',
    _Tab.boards => 'Boards',
    _Tab.documents => 'Documents',
    _Tab.items => 'Linked items',
  };
  IconData get icon => switch (this) {
    _Tab.overview => Icons.dashboard_outlined,
    _Tab.timeline => Icons.view_timeline_outlined,
    _Tab.boards => Icons.view_kanban_outlined,
    _Tab.documents => Icons.description_outlined,
    _Tab.items => Icons.link,
  };
}

/// Projects: a named group of Gantt calendars, boards, documents and folders,
/// with all of them shown together (overview, combined timeline, boards and
/// documents). [onOpenItem] asks the dashboard to open an item on its own page.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key, this.service, this.onOpenItem, this.today});
  final ProjectsService? service;
  final void Function(String page, Map<String, dynamic> target)? onOpenItem;

  /// The day to treat as today (tests set it).
  final DateTime? today;

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  late final ProjectsService _service;
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  String? _error;

  String? _openId;
  Map<String, dynamic>? _detail;
  bool _detailLoading = false;
  String? _detailError;
  _Tab _tab = _Tab.overview;
  bool _showArchived = false;
  String _documentFilter = 'all';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProjectsService();
    _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object e, [String fallback = 'Something went wrong.']) =>
      e is StateError ? e.message.toString() : '$fallback Please try again.';

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  // ------------------------------------------------------------------ data

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call('listProjects');
      if (!mounted || request != _request) return;
      setState(() {
        _projects = [
          for (final p in result['projects'] as List)
            Map<String, dynamic>.from(p as Map),
        ];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = _message(e, 'Unable to load your projects.');
      });
    }
  }

  Future<void> _openProject(String id) async {
    setState(() {
      _openId = id;
      _detail = null;
      _tab = _Tab.overview;
    });
    await _reloadDetail();
  }

  Future<void> _reloadDetail() async {
    final id = _openId;
    if (id == null) return;
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final result = await _service.call('getProject', {'projectId': id});
      if (!mounted || _openId != id) return;
      setState(() {
        _detail = Map<String, dynamic>.from(result);
        _detailLoading = false;
      });
    } catch (e) {
      if (!mounted || _openId != id) return;
      setState(() {
        _detailLoading = false;
        _detailError = _message(e, 'Unable to open the project.');
      });
    }
  }

  void _closeProject() {
    setState(() {
      _openId = null;
      _detail = null;
    });
    _load();
  }

  List<Map<String, dynamic>> _list(String key) => [
    for (final e in (_detail?[key] as List? ?? []))
      Map<String, dynamic>.from(e as Map),
  ];

  Map<String, dynamic> get _project =>
      Map<String, dynamic>.from(_detail?['project'] as Map? ?? {});

  // --------------------------------------------------------------- opening

  void _openOnPage(String page, Map<String, dynamic> target) =>
      widget.onOpenItem?.call(page, {...target, 'page': page});

  void _openCalendar(Map<String, dynamic> c) => _openOnPage('Gantt', {
    'type': 'Gantt calendar',
    'id': c['id'],
    'parentId': c['id'],
  });

  void _openPhase(Map<String, dynamic> calendar, Map<String, dynamic> item) =>
      _openOnPage('Gantt', {
        'type': 'Phase',
        'id': item['id'],
        'parentId': calendar['id'],
        'date': item['start_date'],
      });

  void _openBoard(Map<String, dynamic> b) => _openOnPage('Boards', {
    'type': 'Board',
    'id': b['id'],
    'parentId': b['id'],
  });

  void _openTask(Map<String, dynamic> board, Map<String, dynamic> task) =>
      _openOnPage('Boards', {
        'type': 'Task',
        'id': task['id'],
        'parentId': board['id'],
      });

  void _openFolder(Map<String, dynamic> f) =>
      _openOnPage('Documents', {'type': 'Folder', 'id': f['id']});

  void _openDocument(Map<String, dynamic> d) => _openOnPage('Documents', {
    'type': documentTypeOf(d['kind'] as String?).label,
    'id': d['id'],
    'parentId': d['folder_id'],
  });

  // --------------------------------------------------------------- actions

  Future<void> _projectForm({Map<String, dynamic>? existing}) async {
    var name = existing?['name'] as String? ?? '';
    var description = existing?['description'] as String? ?? '';
    var color = (existing?['color'] as String? ?? projectColors.first)
        .toUpperCase();
    var saving = false;
    String? error;
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          key: const ValueKey('project-form'),
          title: Text(existing == null ? 'New project' : 'Edit project'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey('project-name-field'),
                    initialValue: name,
                    autofocus: true,
                    enabled: !saving,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                    ),
                    onChanged: (v) => name = v,
                  ),
                  TextFormField(
                    key: const ValueKey('project-description-field'),
                    initialValue: description,
                    enabled: !saving,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                    onChanged: (v) => description = v,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final hex in projectColors)
                        InkWell(
                          key: ValueKey('project-color-$hex'),
                          customBorder: const CircleBorder(),
                          onTap: saving
                              ? null
                              : () => update(() => color = hex),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _hex(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: hex == color
                                    ? Theme.of(ctx).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      key: const ValueKey('project-form-error'),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ],
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
              key: const ValueKey('project-form-save'),
              onPressed: saving
                  ? null
                  : () async {
                      if (name.trim().isEmpty) {
                        update(() => error = 'Enter a project name.');
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final result = existing == null
                            ? await _service.call('createProject', {
                                'name': name.trim(),
                                'description': description.trim(),
                                'color': color,
                              })
                            : await _service.call('updateProject', {
                                'projectId': existing['id'],
                                'name': name.trim(),
                                'description': description.trim(),
                                'color': color,
                              });
                        if (ctx.mounted) {
                          Navigator.pop(
                            ctx,
                            Map<String, dynamic>.from(result['project'] as Map),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          update(() {
                            saving = false;
                            error = _message(e, 'Unable to save.');
                          });
                        }
                      }
                    },
              child: Text(
                saving
                    ? 'Saving…'
                    : existing == null
                    ? 'Create'
                    : 'Save',
              ),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    if (existing == null) {
      await _load();
      await _openProject(saved['id'] as String);
    } else {
      await _reloadDetail();
    }
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('project-delete-dialog'),
        title: const Text('Delete project?'),
        content: const Text(
          'This deletes the project only. The calendars, boards and documents '
          'linked to it are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('project-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _service.call('deleteProject', {'projectId': _openId});
      if (mounted) _closeProject();
    } catch (e) {
      _snack(_message(e, 'Unable to delete the project.'));
    }
  }

  Future<void> _linkItems() async {
    final linked = <String>{
      for (final c in _list('gantt')) 'gantt:${c['id']}',
      for (final b in _list('boards')) 'board:${b['id']}',
      for (final f in _list('folders')) 'folder:${f['id']}',
      for (final d in _list('documents'))
        if (d['direct'] == true) 'document:${d['id']}',
    };
    final chosen = await showDialog<List<Map<String, String>>>(
      context: context,
      builder: (_) => _LinkDialog(service: _service, linked: linked),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    try {
      await _service.call('linkItems', {'projectId': _openId, 'items': chosen});
      await _reloadDetail();
      _snack('Linked ${_plural(chosen.length, 'item')}.');
    } catch (e) {
      _snack(_message(e, 'Unable to link those items.'));
    }
  }

  Future<void> _unlink(String kind, String id) async {
    try {
      await _service.call('unlinkItem', {
        'projectId': _openId,
        'kind': kind,
        'targetId': id,
      });
      await _reloadDetail();
    } catch (e) {
      _snack(_message(e, 'Unable to unlink that.'));
    }
  }

  // ------------------------------------------------------------- the list

  Widget _projectCard(Map<String, dynamic> p) {
    final counts = Map<String, dynamic>.from(p['counts'] as Map? ?? {});
    int n(String k) => (counts[k] as num?)?.toInt() ?? 0;
    final parts = [
      if (n('gantt') > 0) _plural(n('gantt'), 'Gantt calendar'),
      if (n('board') > 0) _plural(n('board'), 'board'),
      if (n('folder') > 0) _plural(n('folder'), 'folder'),
      if (n('document') > 0) _plural(n('document'), 'document'),
    ];
    return SizedBox(
      width: 280,
      child: Card(
        key: ValueKey('project-card-${p['id']}'),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openProject(p['id'] as String),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 8, color: _hex(p['color'] as String?)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['name'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if ((p['description'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            p['description'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          parts.isEmpty
                              ? 'Nothing linked yet'
                              : parts.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list_() {
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
              Text(
                'Projects',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('project-create'),
                onPressed: _loading ? null : () => _projectForm(),
                icon: const Icon(Icons.add),
                label: const Text('New project'),
              ),
              IconButton(
                tooltip: 'Refresh projects',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _loading && _projects.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _projects.isEmpty
              ? const Center(
                  child: Text(
                    'Create your first project to group calendars, boards and '
                    'documents.',
                    key: ValueKey('projects-empty'),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final p in _projects) _projectCard(p)],
                  ),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ the project

  Widget _header() {
    final p = _project;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('project-back'),
            tooltip: 'Back to projects',
            onPressed: _closeProject,
            icon: const Icon(Icons.arrow_back),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _hex(p['color'] as String?),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p['name'] as String? ?? '',
                  key: const ValueKey('project-title'),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if ((p['description'] as String? ?? '').isNotEmpty)
                  Text(
                    p['description'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('project-link'),
            onPressed: _detail == null ? null : _linkItems,
            icon: const Icon(Icons.add_link),
            label: const Text('Link items'),
          ),
          IconButton(
            key: const ValueKey('project-edit'),
            tooltip: 'Edit project',
            onPressed: _detail == null
                ? null
                : () => _projectForm(existing: _project),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: const ValueKey('project-delete'),
            tooltip: 'Delete project',
            onPressed: _detail == null ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _detailLoading ? null : _reloadDetail,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _tabs() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final t in _Tab.values)
          ChoiceChip(
            key: ValueKey('project-tab-${t.name}'),
            avatar: Icon(t.icon, size: 18),
            label: Text(t.label),
            selected: _tab == t,
            onSelected: (_) => setState(() => _tab = t),
          ),
      ],
    ),
  );

  // Phases of every linked Gantt calendar, with where they came from.
  List<({Map<String, dynamic> calendar, Map<String, dynamic> item})>
  get _phases => [
    for (final c in _list('gantt'))
      for (final i in (c['items'] as List? ?? []))
        (calendar: c, item: Map<String, dynamic>.from(i as Map)),
  ];

  List<TimelineGroup> get _groups => [
    for (final c in _list('gantt'))
      TimelineGroup(
        id: c['id'] as String,
        name: c['name'] as String,
        color: _hex(c['color'] as String?, const Color(0xFF2E7D5B)),
        items: [
          for (final i in (c['items'] as List? ?? []))
            TimelineItem(
              id: (i as Map)['id'] as String,
              title: i['title'] as String,
              start: _date(i['start_date']),
              end: _date(i['end_date']),
              completed: i['completed'] == true,
            ),
        ],
      ),
  ];

  Widget _section(
    String title,
    Widget child, {
    _Tab? more,
    String? key,
    Widget? trailing,
  }) => Card(
    key: key == null ? null : ValueKey(key),
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?trailing,
              if (more != null)
                TextButton(
                  onPressed: () => setState(() => _tab = more),
                  child: Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );

  Widget _stat(
    String key,
    IconData icon,
    String title,
    String value, {
    String? detail,
    double? progress,
    Color? detailColor,
  }) => SizedBox(
    width: 240,
    child: Card(
      key: ValueKey(key),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(title, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            if (progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress),
            ],
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: detailColor),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _overview() {
    final phases = _phases;
    final doneP = phases.where((p) => p.item['completed'] == true).length;
    final overdue = phases.where((p) {
      return p.item['completed'] != true &&
          _date(p.item['end_date']).isBefore(_today);
    }).length;
    final boards = _list('boards');
    var tasks = 0, doneT = 0;
    for (final b in boards) {
      for (final t in (b['tasks'] as List? ?? [])) {
        if ((t as Map)['archived'] == true) continue;
        tasks++;
        if (t['completed'] == true) doneT++;
      }
    }
    final docs = _list('documents');
    final folders = _list('folders');
    final upcoming =
        [
          for (final p in phases)
            if (p.item['completed'] != true) p,
        ]..sort(
          (a, b) =>
              _date(a.item['end_date']).compareTo(_date(b.item['end_date'])),
        );
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy');
    final empty =
        phases.isEmpty && boards.isEmpty && docs.isEmpty && folders.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (empty)
          Card(
            key: const ValueKey('project-empty'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 28),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Nothing is linked to this project yet. Link Gantt '
                      'calendars, boards, folders or single documents to see '
                      'them all here.',
                    ),
                  ),
                  FilledButton(
                    onPressed: _linkItems,
                    child: const Text('Link items'),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(
                'stat-gantt',
                Icons.view_timeline_outlined,
                'Gantt phases',
                '$doneP / ${phases.length} done',
                progress: phases.isEmpty ? null : doneP / phases.length,
                detail: overdue > 0
                    ? '${_plural(overdue, 'phase')} overdue'
                    : (phases.isEmpty ? 'No phases yet' : 'Nothing overdue'),
                detailColor: overdue > 0 ? scheme.error : null,
              ),
              _stat(
                'stat-boards',
                Icons.view_kanban_outlined,
                'Board tasks',
                '$doneT / $tasks done',
                progress: tasks == 0 ? null : doneT / tasks,
                detail: _plural(boards.length, 'board'),
              ),
              _stat(
                'stat-documents',
                Icons.description_outlined,
                'Documents',
                '${docs.length}',
                detail:
                    '${_plural(folders.length, 'linked folder')}, '
                    '${_plural(docs.where((d) => d['direct'] == true).length, 'single document')}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (phases.isNotEmpty) ...[
            _section(
              'Coming up',
              key: 'section-upcoming',
              upcoming.isEmpty
                  ? const Text('Every phase is done.')
                  : Column(
                      children: [
                        for (final p in upcoming.take(6))
                          ListTile(
                            key: ValueKey('upcoming-${p.item['id']}'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _hex(p.calendar['color'] as String?),
                                shape: BoxShape.circle,
                              ),
                            ),
                            title: Text(p.item['title'] as String),
                            subtitle: Text(p.calendar['name'] as String),
                            trailing: Text(
                              _date(p.item['end_date']).isBefore(_today)
                                  ? 'Overdue · ${fmt.format(_date(p.item['end_date']))}'
                                  : 'Due ${fmt.format(_date(p.item['end_date']))}',
                              style: TextStyle(
                                color:
                                    _date(p.item['end_date']).isBefore(_today)
                                    ? scheme.error
                                    : null,
                              ),
                            ),
                            onTap: () => _openPhase(p.calendar, p.item),
                          ),
                      ],
                    ),
            ),
            _section(
              'Timeline',
              key: 'section-timeline',
              more: _Tab.timeline,
              ProjectTimeline(
                groups: _groups,
                today: widget.today,
                compact: true,
                onOpen: (g, i) {
                  final c = _list('gantt').firstWhere((c) => c['id'] == g.id);
                  final item = (c['items'] as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .firstWhere((e) => e['id'] == i.id);
                  _openPhase(c, item);
                },
              ),
            ),
          ],
          if (boards.isNotEmpty)
            _section(
              'Boards',
              key: 'section-boards',
              more: _Tab.boards,
              Column(children: [for (final b in boards) _boardSummary(b)]),
            ),
          if (docs.isNotEmpty)
            _section(
              'Recent documents',
              key: 'section-documents',
              more: _Tab.documents,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final d in docs.take(6)) _documentTile(d)],
              ),
            ),
        ],
      ],
    );
  }

  Widget _boardSummary(Map<String, dynamic> b) {
    final tasks = [
      for (final t in (b['tasks'] as List? ?? []))
        if ((t as Map)['archived'] != true) Map<String, dynamic>.from(t),
    ];
    final done = tasks.where((t) => t['completed'] == true).length;
    final columns = [
      for (final c in (b['columns'] as List? ?? []))
        Map<String, dynamic>.from(c as Map),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  b['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('$done / ${tasks.length} done'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: tasks.isEmpty ? 0 : done / tasks.length,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in columns)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${c['name']} ${tasks.where((t) => t['column_id'] == c['id']).length}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _documentTile(Map<String, dynamic> d, {bool wide = false}) {
    final type = documentTypeOf(d['kind'] as String?);
    final text = (d['description'] as String? ?? '').trim().isNotEmpty
        ? d['description'] as String
        : (d['preview'] as String? ?? '').trim();
    final updated = DateTime.tryParse(d['updated_at'] as String? ?? '');
    final path = d['path'] as String? ?? '';
    return SizedBox(
      width: wide ? double.infinity : 250,
      child: Card(
        key: ValueKey('project-doc-${d['id']}'),
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => _openDocument(d),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(type.icon, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          type.label,
                          if (path.isNotEmpty) path,
                          if (updated != null)
                            DateFormat('d MMM yyyy').format(updated.toLocal()),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            text,
                            maxLines: wide ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timelineTab() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: ProjectTimeline(
      key: const ValueKey('project-timeline'),
      groups: _groups,
      today: widget.today,
      onOpen: (g, i) {
        final c = _list('gantt').firstWhere((c) => c['id'] == g.id);
        final item = (c['items'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .firstWhere((e) => e['id'] == i.id);
        _openPhase(c, item);
      },
    ),
  );

  Widget _boardsTab() {
    final boards = _list('boards');
    if (boards.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No boards are linked to this project yet.',
          key: ValueKey('boards-empty'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          key: const ValueKey('project-show-archived'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show archived tasks'),
          value: _showArchived,
          onChanged: (v) => setState(() => _showArchived = v),
        ),
        for (final b in boards) _boardCard(b),
      ],
    );
  }

  Widget _boardCard(Map<String, dynamic> b) {
    final columns = [
      for (final c in (b['columns'] as List? ?? []))
        Map<String, dynamic>.from(c as Map),
    ];
    final tasks = [
      for (final t in (b['tasks'] as List? ?? []))
        Map<String, dynamic>.from(t as Map),
    ];
    final tags = {
      for (final t in (b['tags'] as List? ?? []))
        (t as Map)['id']: Map<String, dynamic>.from(t),
    };
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('project-board-${b['id']}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b['name'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('open-board-${b['id']}'),
                  onPressed: () => _openBoard(b),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open board'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (columns.isEmpty)
              const Text('This board has no panels yet.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in columns)
                      Container(
                        width: 240,
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: .5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c['name']}  '
                              '${tasks.where((t) => t['column_id'] == c['id'] && (_showArchived || t['archived'] != true)).length}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            for (final t in tasks.where(
                              (t) =>
                                  t['column_id'] == c['id'] &&
                                  (_showArchived || t['archived'] != true),
                            ))
                              Card(
                                key: ValueKey('project-task-${t['id']}'),
                                margin: const EdgeInsets.only(bottom: 6),
                                child: InkWell(
                                  onTap: () => _openTask(b, t),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              t['completed'] == true
                                                  ? Icons.check_circle
                                                  : Icons
                                                        .radio_button_unchecked,
                                              size: 16,
                                              color: t['completed'] == true
                                                  ? Colors.green
                                                  : null,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                t['title'] as String,
                                                style: TextStyle(
                                                  decoration:
                                                      t['completed'] == true
                                                      ? TextDecoration
                                                            .lineThrough
                                                      : null,
                                                  color: t['archived'] == true
                                                      ? scheme.onSurfaceVariant
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if ((t['tag_ids'] as List? ?? [])
                                            .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 2,
                                              children: [
                                                for (final id
                                                    in t['tag_ids'] as List)
                                                  if (tags[id] != null)
                                                    Chip(
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      label: Text(
                                                        tags[id]!['name']
                                                            as String,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _documentsTab() {
    final all = _list('documents');
    final shown = all
        .where(
          (d) => switch (_documentFilter) {
            'single' => d['direct'] == true,
            'folders' => d['direct'] != true,
            _ => true,
          },
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (key, label) in const [
              ('all', 'All'),
              ('single', 'Single documents'),
              ('folders', 'From linked folders'),
            ])
              ChoiceChip(
                key: ValueKey('doc-filter-$key'),
                label: Text(label),
                selected: _documentFilter == key,
                onSelected: (_) => setState(() => _documentFilter = key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Text(
            'No documents here. Link a folder or single documents to the '
            'project.',
            key: ValueKey('documents-empty'),
          )
        else
          for (final d in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _documentTile(d, wide: true),
            ),
      ],
    );
  }

  Widget _itemRow(
    String key,
    IconData icon,
    String title,
    String? subtitle, {
    required VoidCallback onOpen,
    required VoidCallback onUnlink,
    Color? color,
  }) => ListTile(
    key: ValueKey(key),
    leading: Icon(icon, color: color),
    title: Text(title),
    subtitle: subtitle == null || subtitle.isEmpty ? null : Text(subtitle),
    onTap: onOpen,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onOpen, child: const Text('Open')),
        IconButton(
          key: ValueKey('$key-unlink'),
          tooltip: 'Unlink from this project',
          onPressed: onUnlink,
          icon: const Icon(Icons.link_off),
        ),
      ],
    ),
  );

  Widget _itemsTab() {
    final gantt = _list('gantt');
    final boards = _list('boards');
    final folders = _list('folders');
    final singles = _list(
      'documents',
    ).where((d) => d['direct'] == true).toList();
    Widget group(String title, List<Widget> rows) => rows.isEmpty
        ? const SizedBox.shrink()
        : _section(title, Column(children: rows));
    final nothing =
        gantt.isEmpty && boards.isEmpty && folders.isEmpty && singles.isEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (nothing)
          const Text(
            'Nothing is linked yet. Use Link items to add some.',
            key: ValueKey('items-empty'),
          ),
        group('Gantt calendars', [
          for (final c in gantt)
            _itemRow(
              'item-gantt-${c['id']}',
              Icons.view_timeline_outlined,
              c['name'] as String,
              _plural((c['items'] as List? ?? []).length, 'phase'),
              color: _hex(c['color'] as String?, const Color(0xFF2E7D5B)),
              onOpen: () => _openCalendar(c),
              onUnlink: () => _unlink('gantt', c['id'] as String),
            ),
        ]),
        group('Boards', [
          for (final b in boards)
            _itemRow(
              'item-board-${b['id']}',
              Icons.view_kanban_outlined,
              b['name'] as String,
              _plural(
                (b['tasks'] as List? ?? [])
                    .where((t) => (t as Map)['archived'] != true)
                    .length,
                'task',
              ),
              onOpen: () => _openBoard(b),
              onUnlink: () => _unlink('board', b['id'] as String),
            ),
        ]),
        group('Folders', [
          for (final f in folders)
            _itemRow(
              'item-folder-${f['id']}',
              Icons.folder_outlined,
              (f['path'] as String? ?? '').isEmpty
                  ? f['name'] as String
                  : f['path'] as String,
              '${_plural((f['documents'] as num?)?.toInt() ?? 0, 'document')}, '
                  '${_plural((f['subfolders'] as num?)?.toInt() ?? 0, 'sub-folder')}',
              onOpen: () => _openFolder(f),
              onUnlink: () => _unlink('folder', f['id'] as String),
            ),
        ]),
        group('Single documents', [
          for (final d in singles)
            _itemRow(
              'item-document-${d['id']}',
              documentTypeOf(d['kind'] as String?).icon,
              d['name'] as String,
              [
                documentTypeOf(d['kind'] as String?).label,
                if ((d['path'] as String? ?? '').isNotEmpty)
                  d['path'] as String,
              ].join(' · '),
              onOpen: () => _openDocument(d),
              onUnlink: () => _unlink('document', d['id'] as String),
            ),
        ]),
      ],
    );
  }

  Widget _project_() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _tabs(),
        const Divider(height: 1),
        Expanded(
          child: _detailError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_detailError!),
                      TextButton(
                        onPressed: _reloadDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _detail == null
              ? const Center(child: CircularProgressIndicator())
              : switch (_tab) {
                  _Tab.overview => _overview(),
                  _Tab.timeline => _timelineTab(),
                  _Tab.boards => _boardsTab(),
                  _Tab.documents => _documentsTab(),
                  _Tab.items => _itemsTab(),
                },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      _openId == null ? _list_() : _project_();
}

// ----------------------------------------------------------- link dialog

/// Choose Gantt calendars, boards, folders and documents to link. Returns the
/// chosen `{kind, id}` pairs.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.service, required this.linked});
  final ProjectsService service;

  /// `kind:id` of what is already linked.
  final Set<String> linked;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  Map<String, List<Map<String, dynamic>>>? _data;
  String? _error;
  final _chosen = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.service.call('listLinkable');
      if (!mounted) return;
      setState(() {
        _data = {
          for (final k in const ['gantt', 'board', 'folder', 'document'])
            k: [
              for (final e in (r[k] as List? ?? []))
                Map<String, dynamic>.from(e as Map),
            ],
        };
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is StateError
              ? e.message.toString()
              : 'Unable to load your items. Please try again.',
        );
      }
    }
  }

  bool _matches(Map<String, dynamic> e) {
    if (_query.trim().isEmpty) return true;
    final text = '${e['name']} ${e['path'] ?? ''}'.toLowerCase();
    return _query.toLowerCase().split(RegExp(r'\s+')).every(text.contains);
  }

  Widget _group(
    String kind,
    String title,
    IconData Function(Map<String, dynamic>) icon,
    String Function(Map<String, dynamic>) subtitle,
  ) {
    final rows = (_data?[kind] ?? []).where(_matches).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final e in rows)
          CheckboxListTile(
            key: ValueKey('link-$kind-${e['id']}'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Icon(icon(e)),
            title: Text(e['name'] as String),
            subtitle: Text(
              widget.linked.contains('$kind:${e['id']}')
                  ? 'Already linked'
                  : subtitle(e),
            ),
            value:
                widget.linked.contains('$kind:${e['id']}') ||
                _chosen.contains('$kind:${e['id']}'),
            onChanged: widget.linked.contains('$kind:${e['id']}')
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _chosen.add('$kind:${e['id']}');
                    } else {
                      _chosen.remove('$kind:${e['id']}');
                    }
                  }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final nothing = data != null && data.values.every((l) => l.isEmpty);
    return AlertDialog(
      key: const ValueKey('link-dialog'),
      title: const Text('Link items'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            : data == null
            ? const Center(child: CircularProgressIndicator())
            : nothing
            ? const Center(
                child: Text(
                  'You have no Gantt calendars, boards or documents to link yet.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: [
                  TextField(
                    key: const ValueKey('link-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        _group(
                          'gantt',
                          'Gantt calendars',
                          (_) => Icons.view_timeline_outlined,
                          (_) => '',
                        ),
                        _group(
                          'board',
                          'Boards',
                          (_) => Icons.view_kanban_outlined,
                          (_) => '',
                        ),
                        _group(
                          'folder',
                          'Folders (with everything inside)',
                          (_) => Icons.folder_outlined,
                          (e) => e['path'] as String? ?? '',
                        ),
                        _group(
                          'document',
                          'Single documents',
                          (e) => documentTypeOf(e['kind'] as String?).icon,
                          (e) => [
                            documentTypeOf(e['kind'] as String?).label,
                            if ((e['path'] as String? ?? '').isNotEmpty)
                              e['path'] as String,
                          ].join(' · '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('link-confirm'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final c in _chosen)
                    {'kind': c.split(':').first, 'id': c.split(':').last},
                ]),
          child: Text(
            _chosen.isEmpty
                ? 'Link'
                : 'Link ${_plural(_chosen.length, 'item')}',
          ),
        ),
      ],
    );
  }
}
