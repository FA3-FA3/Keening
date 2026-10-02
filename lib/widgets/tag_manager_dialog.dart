import 'package:flutter/material.dart';

/// Colour choices shared by the tags on the Boards, Schedule and Calendar pages.
const tagColors = [
  '#D97706',
  '#2563EB',
  '#059669',
  '#7C3AED',
  '#0891B2',
  '#DC2626',
  '#DB2777',
  '#EA580C',
  '#65A30D',
  '#4F46E5',
  '#9333EA',
  '#475569',
];

Color tagColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

typedef TagList = List<Map<String, dynamic>>;

/// Lists a page's tags and lets the user create, edit and delete them. Each
/// callback saves one change and returns the page's refreshed tag list.
/// Deleting is only offered from a tag's edit form.
class TagManagerDialog extends StatefulWidget {
  const TagManagerDialog({
    super.key,
    required this.tags,
    required this.onCreate,
    required this.onUpdate,
    required this.onDelete,
    this.title = 'Tags',
    this.deleteWarning = 'This removes the tag from everything it is on.',
    this.maxNameLength = 40,
    this.maxTags = 50,
    this.messageOf,
  });

  /// For pages that store every tag as one list saved in a single call.
  factory TagManagerDialog.list({
    Key? key,
    required TagList tags,
    required Future<TagList> Function(TagList tags) save,
    String title = 'Tags',
    String deleteWarning = 'This removes the tag from everything it is on.',
  }) {
    var current = tags.map((t) => Map<String, dynamic>.from(t)).toList();
    Future<TagList> commit(TagList next) async => current = await save(next);
    return TagManagerDialog(
      key: key,
      title: title,
      deleteWarning: deleteWarning,
      tags: current,
      onCreate: (name, color) => commit([
        ...current,
        {
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'name': name,
          'color': color,
        },
      ]),
      onUpdate: (id, name, color) => commit([
        for (final t in current)
          t['id'] == id ? {...t, 'name': name, 'color': color} : t,
      ]),
      onDelete: (id) => commit([
        for (final t in current)
          if (t['id'] != id) t,
      ]),
    );
  }

  final TagList tags;
  final Future<TagList> Function(String name, String color) onCreate;
  final Future<TagList> Function(String id, String name, String color) onUpdate;
  final Future<TagList> Function(String id) onDelete;
  final String title, deleteWarning;
  final int maxNameLength, maxTags;
  final String Function(Object error)? messageOf;
  @override
  State<TagManagerDialog> createState() => _TagManagerDialogState();
}

class _TagManagerDialogState extends State<TagManagerDialog> {
  late TagList _tags = widget.tags
      .map((t) => Map<String, dynamic>.from(t))
      .toList();

  String _message(Object e) =>
      widget.messageOf?.call(e) ??
      (e is StateError
          ? e.message.toString()
          : 'Unable to save tag. Please try again.');

  Future<void> _form({Map<String, dynamic>? existing}) async {
    var name = existing?['name'] as String? ?? '';
    var color =
        existing?['color'] as String? ??
        tagColors[_tags.length % tagColors.length];
    var saving = false;
    String? error;
    final changed = await showDialog<TagList>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Future<void> run(Future<TagList> Function() action) async {
            update(() {
              saving = true;
              error = null;
            });
            try {
              final next = await action();
              if (ctx.mounted) Navigator.pop(ctx, next);
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
              title: Text(existing == null ? 'New tag' : 'Edit tag'),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        initialValue: name,
                        autofocus: true,
                        enabled: !saving,
                        maxLength: widget.maxNameLength,
                        decoration: const InputDecoration(
                          labelText: 'Tag name',
                        ),
                        onChanged: (v) => name = v,
                      ),
                      const SizedBox(height: 8),
                      const Text('Colour'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final c in {...tagColors, color})
                            Semantics(
                              label: 'Colour $c',
                              selected: color == c,
                              child: IconButton(
                                tooltip: c,
                                style: IconButton.styleFrom(
                                  backgroundColor: tagColor(c),
                                ),
                                onPressed: saving
                                    ? null
                                    : () => update(() => color = c),
                                icon: Icon(
                                  color == c ? Icons.check : null,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                              context: ctx,
                              builder: (confirm) => AlertDialog(
                                title: const Text('Delete tag?'),
                                content: Text(widget.deleteWarning),
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
                            if (yes == true && ctx.mounted) {
                              await run(
                                () => widget.onDelete(existing['id'] as String),
                              );
                            }
                          },
                    child: const Text('Delete tag'),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () {
                          if (name.trim().isEmpty) {
                            update(() => error = 'Enter a tag name.');
                            return;
                          }
                          run(
                            () => existing == null
                                ? widget.onCreate(name.trim(), color)
                                : widget.onUpdate(
                                    existing['id'] as String,
                                    name.trim(),
                                    color,
                                  ),
                          );
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
          );
        },
      ),
    );
    if (changed != null && mounted) {
      setState(
        () => _tags = changed.map((t) => Map<String, dynamic>.from(t)).toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 380,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_tags.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Create a tag, give it a name and choose its colour.',
                ),
              ),
            for (final tag in _tags)
              ListTile(
                key: ValueKey('tag-${tag['id']}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.circle,
                  size: 16,
                  color: tagColor(tag['color'] as String? ?? tagColors.first),
                ),
                title: Text(tag['name'] as String),
                trailing: IconButton(
                  tooltip: 'Edit ${tag['name']}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _form(existing: tag),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _tags.length >= widget.maxTags
                    ? null
                    : () => _form(),
                icon: const Icon(Icons.add),
                label: const Text('New tag'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, _tags),
        child: const Text('Done'),
      ),
    ],
  );
}
