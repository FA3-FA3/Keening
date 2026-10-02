import 'package:flutter/material.dart';

const sessionColors = [
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
Color sessionColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

class SessionTagsDialog extends StatefulWidget {
  const SessionTagsDialog({
    super.key,
    required this.tags,
    required this.onSave,
    this.title = 'Session tags',
  });
  final List<Map<String, dynamic>> tags;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
  onSave;
  final String title;
  @override
  State<SessionTagsDialog> createState() => _SessionTagsDialogState();
}

class _SessionTagsDialogState extends State<SessionTagsDialog> {
  late final _tags = widget.tags
      .map((t) => Map<String, dynamic>.from(t))
      .toList();
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_tags.any((t) => (t['name'] as String).trim().isEmpty)) {
      setState(() => _error = 'Enter a name for each tag.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.onSave(_tags);
      if (mounted) Navigator.pop(context, data['tagDefinitions']);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is StateError
              ? e.message.toString()
              : 'Unable to save tags. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Create a tag, give it a name and choose its colour.',
                  ),
                ),
              for (final tag in _tags)
                Padding(
                  key: ValueKey(tag['id']),
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: tag['name'] as String,
                              enabled: !_saving,
                              maxLength: 40,
                              decoration: const InputDecoration(
                                labelText: 'Tag name',
                              ),
                              onChanged: (v) => tag['name'] = v,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete tag',
                            onPressed: _saving
                                ? null
                                : () => setState(() => _tags.remove(tag)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final color in {
                            ...sessionColors,
                            tag['color'] as String,
                          })
                            Semantics(
                              label: 'Colour $color',
                              selected: tag['color'] == color,
                              child: IconButton(
                                tooltip: color,
                                style: IconButton.styleFrom(
                                  backgroundColor: sessionColor(color),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () =>
                                          setState(() => tag['color'] = color),
                                icon: Icon(
                                  tag['color'] == color ? Icons.check : null,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _saving || _tags.length >= 50
                    ? null
                    : () => setState(
                        () => _tags.add({
                          'id': DateTime.now().microsecondsSinceEpoch
                              .toString(),
                          'name': '',
                          'color':
                              sessionColors[_tags.length %
                                  sessionColors.length],
                        }),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Create tag'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save tags'),
        ),
      ],
    ),
  );
}
