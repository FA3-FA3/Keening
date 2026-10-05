import 'dart:async';
import 'package:flutter/material.dart';

class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({super.key, required this.search});
  final Future<Map<String, dynamic>> Function(String query, int offset) search;
  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  final _text = TextEditingController();
  Timer? _debounce;
  int _request = 0, _total = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _request++;
    setState(() {
      _results = [];
      _total = 0;
      _error = null;
      _loading = value.trim().isNotEmpty;
    });
    if (value.trim().isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _search());
    }
  }

  Future<void> _search({bool more = false}) async {
    _debounce?.cancel();
    final query = _text.text.trim();
    if (query.isEmpty) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.search(query, more ? _results.length : 0);
      if (!mounted || request != _request) return;
      setState(() {
        _results = [
          if (more) ..._results,
          ...(data['results'] as List).cast<Map<String, dynamic>>(),
        ];
        _total = data['total'] as int;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _error = 'Unable to search. Please try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    maxLength: 200,
                    onChanged: _changed,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      labelText: 'Search all pages',
                      hintText: 'Titles, notes, locations or tags',
                      prefixIcon: Icon(Icons.search),
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close search',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Row(
                children: [
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: () => _search(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            if (!_loading && _error == null && _text.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('$_total results'),
              ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _text.text.trim().isEmpty
                            ? 'Search phases, events, sessions, tasks, panels, boards and documents.'
                            : _loading
                            ? 'Searching…'
                            : _error != null
                            ? ''
                            : 'No matches found.',
                      ),
                    )
                  : ListView.builder(
                      itemCount:
                          _results.length + (_results.length < _total ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _results.length) {
                          return TextButton(
                            onPressed: _loading
                                ? null
                                : () => _search(more: true),
                            child: const Text('Load more'),
                          );
                        }
                        final r = _results[i];
                        final detail = [
                          r['type'],
                          r['parent'],
                          r['date'],
                          r['time'],
                          r['location'],
                          if (r['archived'] == true) 'Archived',
                          if (r['completed'] == true) 'Completed',
                        ].where((s) => s != null && s != '').join(' · ');
                        return ListTile(
                          title: Text(r['title'] as String),
                          subtitle: Text(
                            [
                              detail,
                              if ((r['description'] ?? '') != '')
                                r['description'],
                            ].join('\n'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.open_in_new, size: 18),
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
