import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../utils/messages_service.dart';
import '../utils/people_service.dart';
import '../utils/retro_theme.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/app_dialog.dart';
import '../utils/time_settings.dart';

List<Map<String, dynamic>> _list(Object? v) => [
  for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e as Map),
];

/// "14:05" for today, "3 Oct 14:05" for another day, from a server time.
String messageTime(Object? at, {DateTime? now}) {
  final t = DateTime.tryParse('$at')?.toLocal();
  if (t == null) return '';
  final today = now ?? DateTime.now();
  final sameDay =
      t.year == today.year && t.month == today.month && t.day == today.day;
  final clock = formatClock(t.hour, t.minute);
  return sameDay ? clock : '${DateFormat('d MMM').format(t)} $clock';
}

/// Messages: private conversations with friends. The list on the left holds
/// the conversations (with a count of what is unread); the one chosen is shown
/// on the right with a box to reply in. [initialUsername] opens a conversation
/// straight away. New messages are looked for every few seconds while the page
/// is open, and [onUnreadChanged] is told how many are unread overall.
class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    this.service,
    this.peopleService,
    this.initialUsername,
    this.onUnreadChanged,
    this.pollInterval = const Duration(seconds: 5),
  });
  final MessagesService? service;
  final PeopleService? peopleService;
  final String? initialUsername;
  final ValueChanged<int>? onUnreadChanged;

  /// How often new messages are looked for (null: never).
  final Duration? pollInterval;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late final MessagesService _service = widget.service ?? MessagesService();
  PeopleService? _people;
  PeopleService get _peopleService =>
      _people ??= widget.peopleService ?? PeopleService();
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();

  List<Map<String, dynamic>> _conversations = [];
  bool _loadingList = true;
  String? _listError;

  String? _selected;
  Map<String, dynamic>? _friend;
  List<Map<String, dynamic>> _messages = [];
  bool _more = false, _loadingThread = false, _loadingOlder = false;
  bool _sending = false;
  String? _threadError;
  Timer? _poll;
  var _ticks = 0, _threadRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    final name = widget.initialUsername;
    if (name != null) _open(name);
    final every = widget.pollInterval;
    if (every != null) _poll = Timer.periodic(every, (_) => _tick());
  }

  @override
  void didUpdateWidget(MessagesPage old) {
    super.didUpdateWidget(old);
    final name = widget.initialUsername;
    if (name != null && name != old.initialUsername && name != _selected) {
      _open(name);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _composerFocus.dispose();
    if (widget.service == null) _service.close();
    if (widget.peopleService == null) _people?.close();
    super.dispose();
  }

  String _error(Object e, [String fallback = 'Something went wrong.']) =>
      e is StateError ? e.message.toString() : '$fallback Please try again.';

  // ----------------------------------------------------------------- data

  Future<void> _loadConversations({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loadingList = true;
        _listError = null;
      });
    }
    try {
      final result = await _service.call('listConversations');
      if (!mounted) return;
      final list = _list(result['conversations']);
      setState(() {
        _conversations = list;
        _loadingList = false;
        _listError = null;
      });
      widget.onUnreadChanged?.call(
        list.fold<int>(0, (sum, c) => sum + ((c['unread'] as int?) ?? 0)),
      );
    } catch (e) {
      if (!mounted || quiet) return;
      setState(() {
        _loadingList = false;
        _listError = _error(e, 'Unable to load your messages.');
      });
    }
  }

  Future<void> _open(String username) async {
    final request = ++_threadRequest;
    setState(() {
      _selected = username;
      _friend = null;
      _messages = [];
      _more = false;
      _threadError = null;
      _loadingThread = true;
    });
    try {
      final result = await _service.call('getThread', {'username': username});
      if (!mounted || request != _threadRequest) return;
      setState(() {
        _friend = Map<String, dynamic>.from(result['friend'] as Map);
        _messages = _list(result['messages']);
        _more = result['more'] == true;
        _loadingThread = false;
      });
      // Reading the conversation cleared its unread count.
      _loadConversations(quiet: true);
      _composerFocus.requestFocus();
    } catch (e) {
      if (!mounted || request != _threadRequest) return;
      setState(() {
        _loadingThread = false;
        _threadError = _error(e, 'Unable to open this conversation.');
      });
    }
  }

  Future<void> _tick() async {
    _ticks++;
    final name = _selected;
    if (name != null && _friend != null && !_loadingThread) {
      final request = _threadRequest;
      try {
        final result = await _service.call('getThread', {
          'username': name,
          if (_messages.isNotEmpty) 'since': _messages.last['at'],
        });
        if (!mounted || request != _threadRequest || _selected != name) return;
        final fresh = _list(result['messages']);
        if (fresh.isNotEmpty) {
          final known = {for (final m in _messages) m['id']};
          setState(() {
            _messages = [
              ..._messages,
              for (final m in fresh)
                if (!known.contains(m['id'])) m,
            ];
          });
        }
      } catch (_) {
        // A missed check is made up for by the next one.
      }
    }
    if (_ticks % 3 == 0 || _selected == null) {
      await _loadConversations(quiet: true);
    }
  }

  Future<void> _older() async {
    final name = _selected;
    if (name == null || _messages.isEmpty || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final result = await _service.call('getThread', {
        'username': name,
        'before': _messages.first['at'],
      });
      if (!mounted || _selected != name) return;
      setState(() {
        _messages = [..._list(result['messages']), ..._messages];
        _more = result['more'] == true;
        _loadingOlder = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _threadError = _error(e, 'Unable to load earlier messages.');
      });
    }
  }

  Future<void> _send() async {
    final name = _selected;
    final body = _composer.text.trim();
    if (name == null || body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _threadError = null;
    });
    try {
      final result = await _service.call('send', {
        'username': name,
        'body': body,
      });
      if (!mounted || _selected != name) return;
      _composer.clear();
      setState(() {
        _messages = [
          ..._messages,
          Map<String, dynamic>.from(result['message'] as Map),
        ];
        _sending = false;
      });
      _composerFocus.requestFocus();
      _loadConversations(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _threadError = _error(e, 'Unable to send that.');
      });
    }
  }

  Future<void> _newMessage() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _FriendPicker(service: _peopleService),
    );
    if (name != null && mounted) await _open(name);
  }

  // ------------------------------------------------------------------ views

  Widget _conversationList() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const ValueKey('message-new'),
            onPressed: _newMessage,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('New message'),
          ),
        ),
        if (_listError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _listError!,
              key: const ValueKey('messages-list-error'),
              style: TextStyle(color: scheme.error),
            ),
          ),
        Expanded(
          child: _loadingList
              ? const Center(child: CircularProgressIndicator())
              : _conversations.isEmpty
              ? const Center(
                  key: ValueKey('conversations-empty'),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No conversations yet. Start one with New message.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final c in _conversations)
                      ListTile(
                        key: ValueKey('conversation-${c['username']}'),
                        selected: c['username'] == _selected,
                        leading: ProfileAvatar(
                          picture: c['profilePicture'] as String?,
                          radius: 20,
                        ),
                        title: Text(
                          '${c['username']}',
                          style: TextStyle(
                            fontWeight: ((c['unread'] as int?) ?? 0) > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '${c['mine'] == true ? 'You: ' : ''}${c['preview']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: ((c['unread'] as int?) ?? 0) > 0
                            ? Badge(
                                key: ValueKey('unread-${c['username']}'),
                                label: Text('${c['unread']}'),
                              )
                            : Text(
                                messageTime(c['at']),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                        onTap: () => _open(c['username'] as String),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _bubble(Map<String, dynamic> m, {required bool showSeen}) {
    final scheme = Theme.of(context).colorScheme;
    final mine = m['mine'] == true;
    return Align(
      key: ValueKey('message-${m['id']}'),
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.6,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: isRetro(context)
              ? BorderRadius.zero
              : BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText('${m['body']}'),
            const SizedBox(height: 2),
            Text(
              '${messageTime(m['at'])}${mine && showSeen ? ' · Seen' : ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _thread({required bool narrow}) {
    final name = _selected;
    if (name == null) {
      return const Center(
        key: ValueKey('thread-none'),
        child: Text('Choose a conversation, or start a new one.'),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // The newest message is last in the list from the server; the list view is
    // reversed so it stays pinned to the bottom.
    final reversed = _messages.reversed.toList();
    final lastMine = _messages.lastWhere(
      (m) => m['mine'] == true,
      orElse: () => const {},
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              if (narrow)
                IconButton(
                  key: const ValueKey('thread-back'),
                  tooltip: 'Back to conversations',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.arrow_back),
                ),
              ProfileAvatar(
                picture: _friend?['profilePicture'] as String?,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Text(
                name,
                key: const ValueKey('thread-title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingThread
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? Center(
                  key: const ValueKey('thread-empty'),
                  child: Text(
                    _friend == null
                        ? ''
                        : 'No messages yet. Say hello to $name.',
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('thread-list'),
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reversed.length + (_more ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == reversed.length) {
                      return Center(
                        child: TextButton(
                          key: const ValueKey('messages-older'),
                          onPressed: _loadingOlder ? null : _older,
                          child: Text(
                            _loadingOlder ? 'Loading...' : 'Earlier messages',
                          ),
                        ),
                      );
                    }
                    final m = reversed[i];
                    return _bubble(
                      m,
                      showSeen: m['id'] == lastMine['id'] && m['read'] == true,
                    );
                  },
                ),
        ),
        if (_threadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _threadError!,
              key: const ValueKey('thread-error'),
              style: TextStyle(color: scheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // Enter sends; Shift+Enter starts a new line.
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                  },
                  child: TextField(
                    key: const ValueKey('message-field'),
                    controller: _composer,
                    focusNode: _composerFocus,
                    enabled: _friend != null,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 4000,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Write a message',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('message-send'),
                tooltip: 'Send',
                onPressed: _sending || _friend == null ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final narrow = box.maxWidth < 720;
      if (narrow) {
        return _selected == null ? _conversationList() : _thread(narrow: true);
      }
      return Row(
        children: [
          SizedBox(width: 300, child: _conversationList()),
          const VerticalDivider(width: 1),
          Expanded(child: _thread(narrow: false)),
        ],
      );
    },
  );
}

/// Asks which friend to write to.
class _FriendPicker extends StatefulWidget {
  const _FriendPicker({required this.service});
  final PeopleService service;

  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  List<Map<String, dynamic>>? _friends;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.service
        .call('listFriends')
        .then((r) {
          if (mounted) setState(() => _friends = _list(r['friends']));
        })
        .catchError((Object e) {
          if (mounted) {
            setState(
              () => _error = e is StateError
                  ? e.message.toString()
                  : 'Unable to load your friends.',
            );
          }
        });
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    width: 360,
    key: const ValueKey('friend-picker'),
    title: const Text('New message'),
    content: SizedBox(
      height: 320,
      child: _error != null
          ? Text(_error!)
          : _friends == null
          ? const Center(child: CircularProgressIndicator())
          : _friends!.isEmpty
          ? const Text(
              'You have no friends to message yet. Add some on the People page.',
            )
          : ListView(
              children: [
                for (final f in _friends!)
                  ListTile(
                    key: ValueKey('pick-${f['username']}'),
                    leading: ProfileAvatar(
                      picture: f['profilePicture'] as String?,
                      radius: 18,
                    ),
                    title: Text('${f['username']}'),
                    onTap: () => Navigator.pop(context, f['username']),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
