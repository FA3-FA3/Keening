import 'package:flutter/material.dart';
import '../utils/links_service.dart';

/// Both editors manage the same persisted event-to-task relationships.
class ItemLinks extends StatefulWidget {
  const ItemLinks({
    super.key,
    required this.source,
    this.eventId,
    this.sessionId,
    this.calendarEventId,
    this.workplaceId,
    this.taskId,
    this.enabled = true,
    this.service,
  });

  final String source;
  final String? eventId, calendarEventId, workplaceId, taskId, sessionId;
  final bool enabled;
  final LinksService? service;

  @override
  State<ItemLinks> createState() => _ItemLinksState();
}

class _ItemLinksState extends State<ItemLinks> {
  late final _service = widget.service ?? LinksService();
  List<Map<String, dynamic>> _options = [];
  bool _loading = false;
  String? _error;
  bool get _saved => widget.source == 'event'
      ? widget.eventId != null
      : widget.source == 'calendar'
      ? widget.calendarEventId != null
      : widget.source == 'session'
      ? widget.sessionId != null
      : widget.taskId != null;
  Map<String, dynamic> get _source => {
    'source': widget.source,
    if (widget.sessionId != null) 'sessionId': widget.sessionId,
    if (widget.eventId != null) 'eventId': widget.eventId,
    if (widget.calendarEventId != null)
      'calendarEventId': widget.calendarEventId,
    if (widget.workplaceId != null) 'workplaceId': widget.workplaceId,
    if (widget.taskId != null) 'taskId': widget.taskId,
  };

  @override
  void initState() {
    super.initState();
    if (_saved) _load();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object e) => e is StateError
      ? e.message.toString()
      : 'Unable to update links. Please try again.';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call({'action': 'list', ..._source});
      if (mounted) {
        setState(
          () => _options = (result['options'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manage() async {
    await _load();
    if (!mounted || _error != null) return;
    var search = '';
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final visible = _options
              .where(
                (o) => '${o['title']} ${o['location']}'.toLowerCase().contains(
                  search.toLowerCase(),
                ),
              )
              .toList();
          return PopScope(
            canPop: !busy,
            child: AlertDialog(
              title: const Text('Link items'),
              scrollable: true,
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Links are saved immediately and appear on both items.',
                    ),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search links',
                      ),
                      onChanged: (v) => update(() => search = v),
                    ),
                    if (error != null) Text(error!),
                    if (_options.isEmpty)
                      const Text(
                        'Create an item in another tab to link it here.',
                      ),
                    if (_options.isNotEmpty)
                      SizedBox(
                        height: 240,
                        child: visible.isEmpty
                            ? const Center(child: Text('No matches.'))
                            : ListView.builder(
                                itemCount: visible.length,
                                itemBuilder: (ctx, index) {
                                  final option = visible[index];
                                  return CheckboxListTile(
                                    title: Text(option['title'] as String),
                                    subtitle: Text(
                                      '${option['location']}${option['archived'] == true ? ' · Archived' : ''}',
                                    ),
                                    value: option['linked'] == true,
                                    onChanged: busy
                                        ? null
                                        : (linked) async {
                                            update(() {
                                              busy = true;
                                              error = null;
                                            });
                                            try {
                                              await _service.call({
                                                ..._source,
                                                if (option['target_type'] !=
                                                    null)
                                                  'targetType':
                                                      option['target_type'],
                                                if (option['calendar_event_id'] !=
                                                    null)
                                                  'calendarEventId':
                                                      option['calendar_event_id'],
                                                'action': linked == true
                                                    ? 'link'
                                                    : 'unlink',
                                                if (option['session_id'] !=
                                                    null)
                                                  'sessionId':
                                                      option['session_id'],
                                                if (option['event_id'] != null)
                                                  'eventId': option['event_id'],
                                                if (option['workplace_id'] !=
                                                    null)
                                                  'workplaceId':
                                                      option['workplace_id'],
                                                if (option['task_id'] != null)
                                                  'taskId': option['task_id'],
                                              });
                                              if (mounted) {
                                                setState(
                                                  () => option['linked'] =
                                                      linked == true,
                                                );
                                              }
                                            } catch (e) {
                                              if (ctx.mounted) {
                                                update(
                                                  () => error = _message(e),
                                                );
                                              }
                                            } finally {
                                              if (ctx.mounted) {
                                                update(() => busy = false);
                                              }
                                            }
                                          },
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final linked = _options.where((o) => o['linked'] == true).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Links', style: Theme.of(context).textTheme.titleMedium),
          if (!_saved)
            const Text('Save this item first to add links.')
          else ...[
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              Text(_error!)
            else if (linked.isEmpty)
              const Text('No links yet.')
            else
              for (final option in linked)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${option['title']} · ${option['location']}${option['archived'] == true ? ' · Archived' : ''}',
                  ),
                ),
            TextButton.icon(
              onPressed: !widget.enabled || _loading ? null : _manage,
              icon: const Icon(Icons.link),
              label: Text(_error == null ? 'Manage links' : 'Retry links'),
            ),
          ],
        ],
      ),
    );
  }
}
