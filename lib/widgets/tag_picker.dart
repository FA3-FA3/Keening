import 'package:flutter/material.dart';

/// Picks tags for an item: the tags that can still be added are in a dropdown
/// menu, and the ones chosen are shown below it as chips (the way the available
/// tags used to be listed), each with a cross to take it off again.
///
/// With [multiple] false only one tag can be chosen; picking another replaces it.
class TagPicker extends StatelessWidget {
  const TagPicker({
    super.key,
    required this.tags,
    required this.selected,
    required this.colorOf,
    required this.onAdd,
    required this.onRemove,
    this.multiple = true,
    this.enabled = true,
  });

  /// Every tag there is (`id`, `name`, `color`).
  final List<Map<String, dynamic>> tags;

  /// The ids of the chosen tags.
  final Iterable<String> selected;
  final Color Function(String hex) colorOf;
  final ValueChanged<String> onAdd, onRemove;
  final bool multiple;
  final bool enabled;

  Widget _dot(Map<String, dynamic> tag) =>
      Icon(Icons.circle, size: 12, color: colorOf(tag['color'] as String));

  @override
  Widget build(BuildContext context) {
    final chosen = selected.toSet();
    final chosenTags = [
      for (final tag in tags)
        if (chosen.contains(tag['id'])) tag,
    ];
    final available = [
      for (final tag in tags)
        if (!chosen.contains(tag['id'])) tag,
    ];
    final canPick = enabled && available.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('tag-picker-menu'),
          enabled: canPick,
          tooltip: 'Add a tag',
          position: PopupMenuPosition.under,
          onSelected: (id) {
            if (!multiple) {
              for (final old in chosen) {
                onRemove(old);
              }
            }
            onAdd(id);
          },
          itemBuilder: (_) => [
            for (final tag in available)
              PopupMenuItem<String>(
                key: ValueKey('tag-option-${tag['id']}'),
                value: tag['id'] as String,
                child: Row(
                  children: [
                    _dot(tag),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tag['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: InputDecorator(
            decoration: InputDecoration(
              enabled: canPick,
              suffixIcon: const Icon(Icons.arrow_drop_down),
              border: const OutlineInputBorder(),
            ),
            child: Text(
              tags.isEmpty
                  ? 'No tags to add'
                  : available.isEmpty
                  ? 'All tags added'
                  : multiple
                  ? 'Add a tag'
                  : chosenTags.isEmpty
                  ? 'Choose a tag'
                  : 'Change the tag',
            ),
          ),
        ),
        if (chosenTags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in chosenTags)
                InputChip(
                  key: ValueKey('tag-chip-${tag['id']}'),
                  label: Text(tag['name'] as String),
                  avatar: _dot(tag),
                  onDeleted: enabled
                      ? () => onRemove(tag['id'] as String)
                      : null,
                  deleteButtonTooltipMessage: 'Remove tag',
                ),
            ],
          ),
        ],
      ],
    );
  }
}
