import '../widgets/scrollable_workspace.dart';
import 'package:flutter/material.dart';
import '../widgets/item_attachments.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/boards_service.dart';
import '../widgets/item_links.dart';
import '../widgets/tag_manager_dialog.dart';

/// Shared colour palette for panels, tasks, and tags across this page.
const List<String> _kColorPalette = [
  '#2563EB',
  '#059669',
  '#D97706',
  '#7C3AED',
  '#0891B2',
];

Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final cleaned = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  } catch (_) {
    return null;
  }
}

/// A row of colour swatches plus a leading "no colour" option. [selected] is
/// '' for "no colour" or a hex string; pass [includeNone] false when a
/// colour is mandatory (e.g. tags).
Widget _colorSwatchRow({
  required String selected,
  required ValueChanged<String> onSelect,
  bool includeNone = true,
}) {
  Widget swatch(String value, Widget child) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _parseColor(value),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.black : AppColors.grey400,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (includeNone)
        swatch('', Icon(Icons.close, size: 14, color: AppColors.grey400)),
      for (final c in _kColorPalette) swatch(c, const SizedBox.shrink()),
    ],
  );
}

/// Small colour dot used next to panel names and on task cards.
Widget _colorDot(Color? color, {double size = 8}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: color ?? AppColors.grey400,
    shape: BoxShape.circle,
  ),
);

/// Small colour-coded pill used to render a tag chip.
Widget _tagChip(Map<String, dynamic> tag) {
  final color = _parseColor(tag['color'] as String?) ?? AppColors.grey400;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      tag['name'] as String? ?? '',
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

/// A small icon + label pair used in a detail dialog's read-only metadata row.
Widget _metaEntry(IconData icon, String label) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 14, color: AppColors.grey500),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 12, color: AppColors.grey500)),
  ],
);

/// Formats an ISO timestamp for a detail dialog's metadata row, or '—' if
/// [iso] is missing/unparsable.
String _formatDateTime(String? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat.yMMMd().add_jm().format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '—';
  }
}

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key, this.service, this.searchTarget});
  final BoardsService? service;
  final Map<String, dynamic>? searchTarget;
  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> {
  late final BoardsService _service;
  final _revision = ValueNotifier<int>(0);
  List<Map<String, dynamic>> _workplaces = [],
      _columns = [],
      _tasks = [],
      _tags = [];
  String? _selected, _error;
  bool _loading = true, _busy = false, _archived = false;
  int _request = 0;
  Future<void> _openSearch() async {
    final target = widget.searchTarget!;
    _archived = target['archived'] == true;
    await _loadWorkplaces(preferred: target['parentId'] as String?);
    if (!mounted || widget.searchTarget != target || _error != null) return;
    if (target['type'] == 'Task') {
      final task = _tasks.where((i) => i['id'] == target['id']).firstOrNull;
      if (task != null) {
        await _taskDialog(task['column_id'] as String, existing: task);
      }
    } else if (target['type'] == 'Panel') {
      final panel = _columns.where((i) => i['id'] == target['id']).firstOrNull;
      if (panel != null) await _openPanel(panel);
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BoardsService();
    if (widget.searchTarget != null) {
      _openSearch();
    } else {
      _loadWorkplaces();
    }
  }

  @override
  void didUpdateWidget(covariant BoardsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchTarget != oldWidget.searchTarget &&
        widget.searchTarget != null) {
      _openSearch();
    }
  }

  @override
  void dispose() {
    _revision.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to connect. Please try again.';
  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> _inPanel(String id) {
    final tasks = _tasks.where(
      (t) => t['column_id'] == id && t['archived'] == _archived,
    );
    // Keep manual ordering within each group while placing completed tasks last.
    return [
      ...tasks.where((t) => t['completed'] != true),
      ...tasks.where((t) => t['completed'] == true),
    ];
  }

  Future<void> _loadWorkplaces({String? preferred}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call('listWorkplaces');
      if (!mounted) return;
      _workplaces = _list(result['workplaces']);
      final choice = preferred ?? _selected;
      _selected = _workplaces.any((w) => w['id'] == choice)
          ? choice
          : _workplaces.firstOrNull?['id'] as String?;
      await _loadBoard();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _loadBoard() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _selected == null
          ? {'columns': [], 'tasks': [], 'tags': []}
          : await _service.call('getBoard', {'workplaceId': _selected});
      if (!mounted || request != _request) return;
      setState(() {
        _columns = _list(result['columns']);
        _tasks = _list(result['tasks']);
        _tags = _list(result['tags']);
        _loading = false;
      });
      _revision.value++;
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<bool> _run(String action, Map<String, dynamic> data) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await _service.call(action, {'workplaceId': _selected, ...data});
      if (mounted) await _loadBoard();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(e))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _nameDialog(
    String kind, {
    Map<String, dynamic>? existing,
  }) async {
    final noun = kind == 'workplace' ? 'board' : kind;
    var name = existing?['name'] as String? ?? '';
    var color = existing?['color'] as String? ?? '';
    var saving = false;
    String? error;
    final workplace = _selected;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(
              existing == null
                  ? (kind == 'workplace' ? 'Create board' : 'New $kind')
                  : 'Rename $noun',
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: name,
                      autofocus: true,
                      enabled: !saving,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText:
                            '${noun[0].toUpperCase()}${noun.substring(1)} name',
                      ),
                      onChanged: (v) => name = v,
                    ),
                    if (kind != 'workplace') ...[
                      const SizedBox(height: 12),
                      const Text('Colour'),
                      const SizedBox(height: 8),
                      IgnorePointer(
                        ignoring: saving,
                        child: _colorSwatchRow(
                          selected: color,
                          onSelect: (v) => update(() => color = v),
                        ),
                      ),
                    ],
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
                onPressed: saving
                    ? null
                    : () async {
                        if (name.trim().isEmpty) {
                          update(() => error = 'Enter a $noun name.');
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final action = kind == 'workplace'
                              ? (existing == null
                                    ? 'createWorkplace'
                                    : 'renameWorkplace')
                              : (existing == null
                                    ? 'createTaskColumn'
                                    : 'updateTaskColumn');
                          final data = await _service.call(action, {
                            'workplaceId': workplace,
                            'name': name.trim(),
                            'color': color,
                            if (kind == 'panel' && existing != null)
                              'columnId': existing['id'],
                          });
                          if (ctx.mounted) {
                            Navigator.pop(
                              ctx,
                              kind == 'workplace' && existing == null
                                  ? data['workplace']['id'] as String
                                  : 'saved',
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
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
                      : existing == null
                      ? 'Create'
                      : 'Save',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      if (kind == 'workplace') {
        await _loadWorkplaces(preferred: result == 'saved' ? null : result);
      } else {
        await _loadBoard();
      }
    }
  }

  Future<void> _taskDialog(
    String columnId, {
    Map<String, dynamic>? existing,
  }) async {
    var title = existing?['title'] as String? ?? '',
        description = existing?['description'] as String? ?? '';
    var color = existing?['color'] as String? ?? '';
    var completed = existing?['completed'] == true;
    final selectedTags = (existing?['tags'] as List? ?? [])
        .map((t) => t['id'] as String)
        .toSet();
    var saving = false;
    String? error;
    final workplace = _selected;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Future<void> save({String? action}) async {
            if (saving) return;
            if (action == null && title.trim().isEmpty) {
              update(() => error = 'Enter a task title.');
              return;
            }
            if (action == 'deleteOrgTask') {
              if (!await _confirm(
                    'Delete task?',
                    'This permanently deletes the task.',
                  ) ||
                  !ctx.mounted) {
                return;
              }
            }
            update(() {
              saving = true;
              error = null;
            });
            try {
              await _service.call(
                action ??
                    (existing == null ? 'createOrgTask' : 'updateOrgTask'),
                {
                  'workplaceId': workplace,
                  'columnId': columnId,
                  if (existing != null) 'taskId': existing['id'],
                  if (action == null) ...{
                    'title': title.trim(),
                    'description': description.trim(),
                    'color': color,
                    'tagIds': selectedTags.toList(),
                    'completed': completed,
                  },
                  if (action == 'updateOrgTask')
                    'archived': !(existing?['archived'] == true),
                },
              );
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
            child: Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 688),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        existing == null ? 'New task' : 'Task details',
                        style: Theme.of(ctx).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      if (existing != null) ...[
                        _metaEntry(
                          Icons.event_outlined,
                          'Created ${_formatDateTime(existing['created_at'] as String?)}',
                        ),
                        const SizedBox(height: 12),
                      ],
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
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 12),
                      const Text('Colour'),
                      const SizedBox(height: 8),
                      IgnorePointer(
                        ignoring: saving,
                        child: _colorSwatchRow(
                          selected: color,
                          onSelect: (v) => update(() => color = v),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Tags'),
                      const SizedBox(height: 8),
                      if (_tags.isEmpty)
                        const Text(
                          'No tags yet. Create tags using Tags on the board.',
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tag in _tags)
                            FilterChip(
                              label: Text(tag['name'] as String),
                              selected: selectedTags.contains(tag['id']),
                              onSelected: saving
                                  ? null
                                  : (v) => update(() {
                                      if (v) {
                                        selectedTags.add(tag['id'] as String);
                                      } else {
                                        selectedTags.remove(tag['id']);
                                      }
                                    }),
                            ),
                        ],
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
                        source: 'task',
                        workplaceId: workplace,
                        taskId: existing?['id'] as String?,
                        enabled: !saving,
                      ),
                      ItemAttachments(
                        itemType: 'task',
                        itemId: existing?['id'] as String?,
                        enabled: !saving,
                      ),
                      if (error != null) Text(error!),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (existing != null) ...[
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => save(action: 'updateOrgTask'),
                                child: Text(
                                  existing['archived'] == true
                                      ? 'Restore task'
                                      : 'Archive task',
                                ),
                              ),
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => save(action: 'deleteOrgTask'),
                                child: const Text('Delete task'),
                              ),
                            ],
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: saving ? null : () => save(),
                              child: Text(saving ? 'Saving...' : 'Save'),
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
        },
      ),
    );
    if (changed == true && mounted) await _loadBoard();
  }

  Future<void> _moveTask(String taskId, String columnId, [int? index]) async {
    if (_busy) return;
    final task = _tasks.where((t) => t['id'] == taskId).firstOrNull;
    if (task == null || task['archived'] == true) {
      return;
    }
    final order = _inPanel(columnId).map((t) => t['id'] as String).toList();
    final oldIndex = order.indexOf(taskId);
    var destination = index ?? order.length;
    if (oldIndex >= 0 && oldIndex < destination) destination--;
    order.remove(taskId);
    order.insert(destination.clamp(0, order.length), taskId);
    if (oldIndex == order.indexOf(taskId)) return;
    await _run('reorderOrgTasks', {'columnId': columnId, 'taskIds': order});
  }

  Future<void> _manageTags() async {
    final workplace = _selected;
    Future<TagList> save(String action, Map<String, dynamic> data) async {
      await _service.call(action, {'workplaceId': workplace, ...data});
      if (mounted) await _loadBoard();
      return _tags;
    }

    await showDialog<TagList>(
      context: context,
      builder: (_) => TagManagerDialog(
        title: 'Tags',
        deleteWarning: 'This removes the tag from all tasks on this board.',
        maxNameLength: 50,
        maxTags: 100,
        messageOf: _message,
        tags: _tags,
        onCreate: (name, color) =>
            save('createTaskTag', {'name': name, 'color': color}),
        onUpdate: (id, name, color) =>
            save('updateTaskTag', {'tagId': id, 'name': name, 'color': color}),
        onDelete: (id) => save('deleteTaskTag', {'tagId': id}),
      ),
    );
  }

  Future<void> _openPanel(Map<String, dynamic> panel) async {
    final id = panel['id'] as String;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: MediaQuery.sizeOf(ctx).width * 0.7071067811865476,
          height: MediaQuery.sizeOf(ctx).height * 0.7071067811865476,
          child: ValueListenableBuilder<int>(
            valueListenable: _revision,
            builder: (_, revision, child) {
              final current = _columns.where((c) => c['id'] == id).firstOrNull;
              if (current == null) {
                return Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Panel deleted. Close'),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close panel'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              _nameDialog('panel', existing: current),
                          child: const Text('Edit panel details'),
                        ),
                        FilledButton(
                          onPressed: () => _taskDialog(id),
                          child: const Text('Add task'),
                        ),
                        IconButton(
                          tooltip: 'Delete panel',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await _confirm(
                                  'Delete panel?',
                                  'This deletes all tasks in this panel, including archived tasks.',
                                ) &&
                                mounted) {
                              await _run('deleteTaskColumn', {'columnId': id});
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        Text(
                          current['name'] as String,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        _metaEntry(
                          Icons.event_outlined,
                          'Created ${_formatDateTime(current['created_at'] as String?)}',
                        ),
                        const SizedBox(height: 24),
                        for (final task in _inPanel(id))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TaskCard(
                              task: task,
                              expanded: true,
                              onEdit: () => _taskDialog(id, existing: task),
                              onCompletedChanged: (value) => _run(
                                'updateOrgTask',
                                {'taskId': task['id'], 'completed': value},
                              ),
                            ),
                          ),
                        if (_inPanel(id).isEmpty)
                          const Text('No tasks in this panel yet.'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _loading || _busy;
    return ScrollableWorkspace(
      minimumBodyHeight: 520,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Boards',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                FilledButton.icon(
                  onPressed: disabled || _error != null
                      ? null
                      : () => _nameDialog('workplace'),
                  icon: const Icon(Icons.add),
                  label: const Text('Create board'),
                ),
                IconButton(
                  tooltip: 'Refresh boards',
                  onPressed: disabled ? null : _loadWorkplaces,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          if (_workplaces.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final w in _workplaces)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(w['name'] as String),
                          selected: w['id'] == _selected,
                          onSelected: disabled
                              ? null
                              : (_) {
                                  if (w['id'] != _selected) {
                                    _selected = w['id'] as String;
                                    _archived = false;
                                    _loadBoard();
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
                children: [
                  OutlinedButton.icon(
                    onPressed: disabled ? null : () => _nameDialog('panel'),
                    icon: const Icon(Icons.add),
                    label: const Text('New panel'),
                  ),
                  TextButton.icon(
                    onPressed: disabled ? null : _manageTags,
                    icon: const Icon(Icons.label_outline),
                    label: const Text('Tags'),
                  ),
                  TextButton.icon(
                    onPressed: disabled
                        ? null
                        : () => setState(() => _archived = !_archived),
                    icon: Icon(
                      _archived
                          ? Icons.view_kanban_outlined
                          : Icons.archive_outlined,
                    ),
                    label: Text(_archived ? 'Back to board' : 'Archive'),
                  ),
                  IconButton(
                    tooltip: 'Rename board',
                    onPressed: disabled
                        ? null
                        : () => _nameDialog(
                            'workplace',
                            existing: _workplaces.firstWhere(
                              (w) => w['id'] == _selected,
                            ),
                          ),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete board',
                    onPressed: disabled
                        ? null
                        : () async {
                            if (!await _confirm(
                                  'Delete board?',
                                  'This permanently deletes its panels, tasks, tags, and archived tasks.',
                                ) ||
                                !mounted) {
                              return;
                            }
                            setState(() => _busy = true);
                            try {
                              await _service.call('deleteWorkplace', {
                                'workplaceId': _selected,
                              });
                              if (mounted) await _loadWorkplaces();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_message(e))),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _loadWorkplaces,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _selected == null
          ? const Center(child: Text('Create your first board to get started.'))
          : _archived
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Archived tasks',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (!_tasks.any((t) => t['archived'] == true))
                  const Text('No archived tasks'),
                for (final task in _tasks.where((t) => t['archived'] == true))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TaskCard(
                          task: task,
                          expanded: true,
                          onEdit: () => _taskDialog(
                            task['column_id'] as String,
                            existing: task,
                          ),
                          onCompletedChanged: (value) => _run('updateOrgTask', {
                            'taskId': task['id'],
                            'completed': value,
                          }),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: disabled
                                ? null
                                : () => _run('updateOrgTask', {
                                    'taskId': task['id'],
                                    'archived': false,
                                  }),
                            child: const Text('Restore task'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          : _columns.isEmpty
          ? const Center(
              child: Text(
                'No panels yet. Create a panel to start adding tasks.',
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ReorderableListView(
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                onReorderItem: (oldIndex, newIndex) {
                  if (disabled) return;
                  if (oldIndex == newIndex) return;
                  final order = _columns.map((c) => c['id'] as String).toList();
                  order.insert(newIndex, order.removeAt(oldIndex));
                  _run('reorderTaskColumns', {'columnIds': order});
                },
                children: [
                  for (final column in _columns)
                    Padding(
                      key: ValueKey(column['id']),
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 280,
                        child: _KanbanColumn(
                          column: column,
                          index: _columns.indexOf(column),
                          tasks: _inPanel(column['id'] as String),
                          canManage: !disabled,
                          onDropTask: (id, index) =>
                              _moveTask(id, column['id'] as String, index),
                          onAddTask: () => _taskDialog(column['id'] as String),
                          onEditTask: (task) => _taskDialog(
                            column['id'] as String,
                            existing: task,
                          ),
                          onTaskCompleted: (task, value) => _run(
                            'updateOrgTask',
                            {'taskId': task['id'], 'completed': value},
                          ),
                          onOpenPanelDetails: () => _openPanel(column),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _KanbanColumn extends StatefulWidget {
  final int index;
  final bool canManage;
  final Map<String, dynamic> column;
  final List<Map<String, dynamic>> tasks;
  final void Function(String taskId, int index) onDropTask;
  final VoidCallback onAddTask;
  final void Function(Map<String, dynamic> task) onEditTask;
  final void Function(Map<String, dynamic>, bool) onTaskCompleted;
  final VoidCallback onOpenPanelDetails;

  const _KanbanColumn({
    required this.index,
    required this.canManage,
    required this.column,
    required this.tasks,
    required this.onDropTask,
    required this.onAddTask,
    required this.onEditTask,
    required this.onTaskCompleted,
    required this.onOpenPanelDetails,
  });

  @override
  State<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends State<_KanbanColumn> {
  bool _pointerHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final panelColor = _parseColor(widget.column['color'] as String?);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => widget.canManage,
      onAcceptWithDetails: (details) =>
          widget.onDropTask(details.data, widget.tasks.length),
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty;
        final isHovering = _pointerHovering || isDraggingOver;
        // Use the panel colour on pointer hover and during drag-and-drop.
        final hoverColor =
            panelColor ?? (isDark ? AppColors.grey500 : AppColors.grey600);
        final borderColor = isHovering
            ? hoverColor
            : (isDark ? AppColors.grey800 : AppColors.grey300);

        // Open the expanded panel from its header or empty space.
        return MouseRegion(
          onEnter: (_) => setState(() => _pointerHovering = true),
          onExit: (_) => setState(() => _pointerHovering = false),
          child: GestureDetector(
            onTap: widget.onOpenPanelDetails,
            onDoubleTap: widget.onOpenPanelDetails,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              key: ValueKey('task-panel-${widget.column['id']}'),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceCard : AppColors.grey100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 2),
                boxShadow: isDraggingOver
                    ? [
                        BoxShadow(
                          color: hoverColor.withValues(alpha: 0.55),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ReorderableDragStartListener(
                        index: widget.index,
                        enabled: widget.canManage,
                        child: MouseRegion(
                          cursor: widget.canManage
                              ? SystemMouseCursors.grab
                              : SystemMouseCursors.basic,
                          child: Padding(
                            key: ValueKey('panel-drag-${widget.column['id']}'),
                            padding: const EdgeInsets.only(
                              right: 6,
                              top: 8,
                              bottom: 8,
                            ),
                            child: const Tooltip(
                              message: 'Drag to reorder panel',
                              child: Icon(Icons.drag_indicator, size: 18),
                            ),
                          ),
                        ),
                      ),
                      _colorDot(panelColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.column['name'] as String? ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.tasks.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey500,
                        ),
                      ),
                    ],
                  ),
                  if (widget.canManage)
                    InkWell(
                      onTap: widget.canManage ? widget.onAddTask : null,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 14, color: AppColors.grey500),
                            const SizedBox(width: 4),
                            Text(
                              'Add task',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.grey500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: widget.tasks.isEmpty
                        ? Center(
                            child: Text(
                              'No tasks',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.grey500,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: widget.tasks.length,
                            itemBuilder: (context, index) {
                              final task = widget.tasks[index];
                              return _TaskDropZone(
                                key: ValueKey('task-drop-${task['id']}'),
                                taskId: task['id'] as String,
                                enabled: widget.canManage,
                                onDrop: (id, after) => widget.onDropTask(
                                  id,
                                  index + (after ? 1 : 0),
                                ),
                                child: _TaskCard(
                                  task: task,
                                  showDragHandle: widget.canManage,
                                  onEdit: () => widget.onEditTask(task),
                                  onCompletedChanged: (value) =>
                                      widget.onTaskCompleted(task, value),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TaskDropZone extends StatefulWidget {
  const _TaskDropZone({
    super.key,
    required this.taskId,
    required this.enabled,
    required this.onDrop,
    required this.child,
  });
  final String taskId;
  final bool enabled;
  final void Function(String id, bool after) onDrop;
  final Widget child;
  @override
  State<_TaskDropZone> createState() => _TaskDropZoneState();
}

class _TaskDropZoneState extends State<_TaskDropZone> {
  bool _after = false;
  void _position(DragTargetDetails<String> details) {
    final box = context.findRenderObject() as RenderBox;
    final after = box.globalToLocal(details.offset).dy > box.size.height / 2;
    if (after != _after) setState(() => _after = after);
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) {
      _position(details);
      return widget.enabled;
    },
    onMove: _position,
    onAcceptWithDetails: (details) {
      if (details.data != widget.taskId) widget.onDrop(details.data, _after);
    },
    builder: (context, candidates, rejected) {
      final line = BorderSide(
        color: candidates.isEmpty
            ? Colors.transparent
            : Theme.of(context).colorScheme.primary,
        width: 3,
      );
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          border: Border(
            top: _after
                ? const BorderSide(color: Colors.transparent, width: 3)
                : line,
            bottom: _after
                ? line
                : const BorderSide(color: Colors.transparent, width: 3),
          ),
        ),
        child: widget.child,
      );
    },
  );
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool expanded;
  final bool showDragHandle;
  final VoidCallback? onEdit;
  final ValueChanged<bool>? onCompletedChanged;

  const _TaskCard({
    required this.task,
    this.expanded = false,
    this.showDragHandle = false,
    this.onEdit,
    this.onCompletedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final description = task['description'] as String?;
    final taskColor = _parseColor(task['color'] as String?);
    final tags = ((task['tags'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();

    final card = Card(
      margin: EdgeInsets.zero,
      color: isDark ? AppColors.grey800 : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: taskColor != null
            ? BorderSide(color: taskColor, width: 3)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (showDragHandle)
                  Draggable<String>(
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    data: task['id'] as String,
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 240, child: _TaskCard(task: task)),
                    ),
                    childWhenDragging: const SizedBox(width: 24, height: 34),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        key: ValueKey('task-drag-${task['id']}'),
                        padding: const EdgeInsets.only(
                          right: 6,
                          top: 8,
                          bottom: 8,
                        ),
                        child: const Tooltip(
                          message: 'Drag to reorder task',
                          child: Icon(Icons.drag_indicator, size: 18),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    task['title'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: task['completed'] == true
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                Checkbox(
                  key: ValueKey('task-completion-${task['id']}'),
                  value: task['completed'] == true,
                  onChanged: onCompletedChanged == null
                      ? null
                      : (value) => onCompletedChanged!(value!),
                  semanticLabel: 'Complete ${task['title'] ?? 'task'}',
                ),
              ],
            ),
            if (description != null && description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: expanded ? null : 2,
                overflow: expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.grey500),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final tag in tags) _tagChip(tag)],
              ),
            ],
          ],
        ),
      ),
    );

    // Double-click opens the full-detail view (replaces the old edit icon).
    return onEdit != null
        ? Semantics(
            container: true,
            explicitChildNodes: true,
            button: true,
            label: 'Open task ${task['title']}',
            onTap: onEdit,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: () {},
              onDoubleTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: card,
            ),
          )
        : card;
  }
}
