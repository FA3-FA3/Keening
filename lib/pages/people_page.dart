import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/people_service.dart';
import '../widgets/profile_avatar.dart';

List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e as Map),
];

/// People: the friends you have, the requests you have been sent and the ones
/// you have sent. Friends are added by username or email address, which sends
/// them a request they can accept or decline. [onMessage] opens a conversation
/// with a friend.
class PeoplePage extends StatefulWidget {
  const PeoplePage({
    super.key,
    this.service,
    this.onMessage,
    this.pollInterval = const Duration(seconds: 30),
  });
  final PeopleService? service;
  final void Function(String username)? onMessage;

  /// How often new requests are looked for while the page is open (null: never).
  final Duration? pollInterval;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  late final PeopleService _service = widget.service ?? PeopleService();
  final _who = TextEditingController();
  List<Map<String, dynamic>> _friends = [], _incoming = [], _outgoing = [];
  bool _loading = true, _sending = false;
  String? _error, _notice, _addError;
  Timer? _poll;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
    final every = widget.pollInterval;
    if (every != null) {
      _poll = Timer.periodic(every, (_) => _load(quiet: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _who.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String _message(Object e, [String fallback = 'Something went wrong.']) =>
      e is StateError ? e.message.toString() : '$fallback Please try again.';

  Future<void> _load({bool quiet = false}) async {
    final request = ++_request;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _service.call('listFriends'),
        _service.call('listRequests'),
      ]);
      if (!mounted || request != _request) return;
      setState(() {
        _friends = _list(results[0]['friends']);
        _incoming = _list(results[1]['incoming']);
        _outgoing = _list(results[1]['outgoing']);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || request != _request || quiet) return;
      setState(() {
        _loading = false;
        _error = _message(e, 'Unable to load your people.');
      });
    }
  }

  Future<void> _sendRequest() async {
    final who = _who.text.trim();
    if (who.isEmpty) {
      setState(() {
        _addError = 'Enter a username or an email address.';
        _notice = null;
      });
      return;
    }
    setState(() {
      _sending = true;
      _addError = null;
      _notice = null;
    });
    try {
      final result = await _service.call('sendRequest', {'who': who});
      if (!mounted) return;
      final name = result['username'];
      _who.clear();
      setState(() {
        _sending = false;
        _notice = result['status'] == 'friends'
            ? 'You and $name are now friends.'
            : 'Request sent to $name.';
      });
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _addError = _message(e, 'Unable to send the request.');
      });
    }
  }

  /// Runs a change, then reloads; a failure is shown on the page.
  Future<void> _act(String action, Map<String, dynamic> data) async {
    try {
      await _service.call(action, data);
      if (!mounted) return;
      setState(() => _error = null);
      await _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(e));
    }
  }

  Future<void> _remove(Map<String, dynamic> friend) async {
    final name = friend['username'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          '$name will no longer be able to message you, and you will not be '
          'able to message them. You can send a new request later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('friend-remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await _act('removeFriend', {'username': name});
  }

  Widget _addBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextField(
                  key: const ValueKey('people-add-field'),
                  controller: _who,
                  enabled: !_sending,
                  onSubmitted: (_) => _sendRequest(),
                  decoration: const InputDecoration(
                    labelText: 'Add a friend',
                    hintText: 'Username or email address',
                    prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const ValueKey('people-add-send'),
              onPressed: _sending ? null : _sendRequest,
              child: Text(_sending ? 'Sending...' : 'Send request'),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('people-refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_addError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _addError!,
              key: const ValueKey('people-add-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _notice!,
              key: const ValueKey('people-add-notice'),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    ),
  );

  Widget _friendsTab() {
    if (_friends.isEmpty) {
      return const Center(
        key: ValueKey('friends-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No friends yet. Add someone by their username or email address '
            'and they can accept your request.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final f in _friends)
          ListTile(
            key: ValueKey('friend-${f['username']}'),
            leading: ProfileAvatar(
              picture: f['profilePicture'] as String?,
              radius: 20,
            ),
            title: Text('${f['username']}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                if (widget.onMessage != null)
                  FilledButton.tonalIcon(
                    key: ValueKey('friend-message-${f['username']}'),
                    onPressed: () => widget.onMessage!(f['username'] as String),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Message'),
                  ),
                IconButton(
                  key: ValueKey('friend-remove-${f['username']}'),
                  tooltip: 'Remove friend',
                  onPressed: () => _remove(f),
                  icon: const Icon(Icons.person_remove_outlined),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _requestsTab() {
    if (_incoming.isEmpty && _outgoing.isEmpty) {
      return const Center(
        key: ValueKey('requests-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No friend requests.'),
        ),
      );
    }
    final heading = Theme.of(context).textTheme.titleSmall;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Received (${_incoming.length})', style: heading),
        ),
        if (_incoming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Nobody is waiting for an answer from you.'),
          ),
        for (final r in _incoming)
          ListTile(
            key: ValueKey('incoming-${r['id']}'),
            leading: ProfileAvatar(
              picture: r['profilePicture'] as String?,
              radius: 20,
            ),
            title: Text('${r['username']}'),
            subtitle: const Text('wants to be your friend'),
            trailing: Wrap(
              spacing: 4,
              children: [
                FilledButton(
                  key: ValueKey('request-accept-${r['id']}'),
                  onPressed: () =>
                      _act('acceptRequest', {'requestId': r['id']}),
                  child: const Text('Accept'),
                ),
                OutlinedButton(
                  key: ValueKey('request-decline-${r['id']}'),
                  onPressed: () =>
                      _act('declineRequest', {'requestId': r['id']}),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Sent (${_outgoing.length})', style: heading),
        ),
        if (_outgoing.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('You have no requests waiting.'),
          ),
        for (final r in _outgoing)
          ListTile(
            key: ValueKey('outgoing-${r['id']}'),
            leading: ProfileAvatar(
              picture: r['profilePicture'] as String?,
              radius: 20,
            ),
            title: Text('${r['username']}'),
            subtitle: const Text('waiting for them to answer'),
            trailing: OutlinedButton(
              key: ValueKey('request-cancel-${r['id']}'),
              onPressed: () => _act('cancelRequest', {'requestId': r['id']}),
              child: const Text('Cancel'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _addBar(),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              key: const ValueKey('people-tab-friends'),
              text: 'Friends (${_friends.length})',
            ),
            Tab(
              key: const ValueKey('people-tab-requests'),
              child: Badge(
                isLabelVisible: _incoming.isNotEmpty,
                label: Text('${_incoming.length}'),
                offset: const Offset(14, -6),
                child: const Text('Requests'),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    key: const ValueKey('people-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('people-retry'),
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(children: [_friendsTab(), _requestsTab()]),
        ),
      ],
    ),
  );
}
