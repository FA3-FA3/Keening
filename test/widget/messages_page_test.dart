import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/messages_page.dart';
import 'package:keening/utils/messages_service.dart';
import 'package:keening/utils/people_service.dart';

/// A stand-in for the server's messages routes.
class FakeMessages extends MessagesService {
  /// Messages by friend, oldest first: {id, mine, body, at, read}.
  final threads = <String, List<Map<String, dynamic>>>{};
  final friends = <String>['ann', 'bob'];
  final calls = <String>[];
  final unreadFrom = <String, int>{};
  bool failSend = false;
  var _n = 0;

  String _at() =>
      '2026-10-22T10:${(_n ~/ 60).toString().padLeft(2, '0')}:'
      '${(_n % 60).toString().padLeft(2, '0')}.000000Z';

  Map<String, dynamic> add(String friend, String body, {bool mine = false}) {
    final m = {
      'id': 'm${++_n}',
      'mine': mine,
      'body': body,
      'at': _at(),
      'read': false,
    };
    (threads[friend] ??= []).add(m);
    if (!mine) unreadFrom[friend] = (unreadFrom[friend] ?? 0) + 1;
    return m;
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    switch (action) {
      case 'listConversations':
        return {
          'conversations': [
            for (final e in threads.entries)
              if (e.value.isNotEmpty)
                {
                  'username': e.key,
                  'preview': e.value.last['body'],
                  'at': e.value.last['at'],
                  'mine': e.value.last['mine'],
                  'unread': unreadFrom[e.key] ?? 0,
                },
          ],
        };
      case 'unreadCount':
        return {'unread': unreadFrom.values.fold<int>(0, (a, b) => a + b)};
      case 'getThread':
        final name = data['username'] as String;
        if (!friends.contains(name)) {
          throw StateError('That person is not one of your friends.');
        }
        var list = threads[name] ?? [];
        if (data['since'] != null) {
          list = [
            for (final m in list)
              if ((m['at'] as String).compareTo(data['since'] as String) > 0) m,
          ];
        }
        if (data['before'] != null) {
          list = [
            for (final m in list)
              if ((m['at'] as String).compareTo(data['before'] as String) < 0)
                m,
          ];
        }
        final more = list.length > 50;
        final page = more ? list.sublist(list.length - 50) : list;
        if (data['before'] == null) unreadFrom.remove(name);
        return {
          'friend': {'username': name, 'profilePicture': null},
          'messages': List.of(page),
          'more': more,
        };
      case 'send':
        if (failSend) throw StateError('Unable to send.');
        return {
          'message': add(data['username'] as String, data['body'], mine: true),
        };
    }
    throw StateError('Unknown');
  }

  @override
  void close() {}
}

class FakeFriends extends PeopleService {
  FakeFriends(this.names);
  final List<String> names;
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async => {
    'friends': [
      for (final n in names) {'username': n},
    ],
  };
  @override
  void close() {}
}

Future<void> mount(
  WidgetTester tester,
  FakeMessages messages, {
  String? initial,
  ValueChanged<int>? onUnread,
  Duration? poll,
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MessagesPage(
          service: messages,
          peopleService: FakeFriends(messages.friends),
          initialUsername: initial,
          onUnreadChanged: onUnread,
          pollInterval: poll,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder field() => find.byKey(const ValueKey('message-field'));

void main() {
  testWidgets('with no conversations it says how to start one', (tester) async {
    await mount(tester, FakeMessages());
    expect(find.byKey(const ValueKey('conversations-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-none')), findsOneWidget);
  });

  testWidgets('conversations show the last message and what is unread', (
    tester,
  ) async {
    final m = FakeMessages()
      ..add('ann', 'Hello there')
      ..add('ann', 'Are you free?')
      ..add('bob', 'Sent by me', mine: true);
    int? unread;
    await mount(tester, m, onUnread: (n) => unread = n);
    expect(find.byKey(const ValueKey('conversation-ann')), findsOneWidget);
    expect(find.text('Are you free?'), findsOneWidget);
    expect(find.text('You: Sent by me'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-ann')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-bob')), findsNothing);
    expect(unread, 2);
  });

  testWidgets('opening a conversation shows its messages and marks it read', (
    tester,
  ) async {
    final m = FakeMessages()
      ..add('ann', 'Hello there')
      ..add('ann', 'Are you free?')
      ..add('ann', 'I am', mine: true);
    int? unread;
    await mount(tester, m, onUnread: (n) => unread = n);
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-title')), findsOneWidget);
    expect(find.text('Hello there'), findsOneWidget);
    expect(find.text('I am'), findsOneWidget);
    // Oldest at the top, newest at the bottom.
    expect(
      tester.getTopLeft(find.text('Hello there')).dy,
      lessThan(tester.getTopLeft(find.text('I am')).dy),
    );
    expect(find.byKey(const ValueKey('unread-ann')), findsNothing);
    expect(unread, 0);
  });

  testWidgets('a message is sent with the button and shown at the bottom', (
    tester,
  ) async {
    final m = FakeMessages()..add('ann', 'Hello there');
    await mount(tester, m);
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), '  On my way  ');
    await tester.tap(find.byKey(const ValueKey('message-send')));
    await tester.pumpAndSettle();
    // It is sent without the spaces round it.
    expect(m.threads['ann']!.last['body'], 'On my way');
    expect(find.text('On my way'), findsOneWidget);
    expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    // The conversation list now shows it as the latest.
    expect(find.text('You: On my way'), findsOneWidget);
  });

  testWidgets('Enter sends and nothing is sent when the box is empty', (
    tester,
  ) async {
    final m = FakeMessages()..add('ann', 'Hello there');
    await mount(tester, m);
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    await tester.tap(field());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.calls.where((c) => c == 'send'), isEmpty);
    await tester.enterText(field(), 'Quick one');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.calls.where((c) => c == 'send').length, 1);
    expect(m.threads['ann']!.last['body'], 'Quick one');
  });

  testWidgets('a message that fails to send stays in the box', (tester) async {
    final m = FakeMessages()
      ..add('ann', 'Hello there')
      ..failSend = true;
    await mount(tester, m);
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    await tester.enterText(field(), 'Will not go');
    await tester.tap(find.byKey(const ValueKey('message-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-error')), findsOneWidget);
    expect(tester.widget<TextField>(field()).controller!.text, 'Will not go');
    // And it can be sent once the problem is gone.
    m.failSend = false;
    await tester.tap(find.byKey(const ValueKey('message-send')));
    await tester.pumpAndSettle();
    expect(m.threads['ann']!.last['body'], 'Will not go');
    expect(find.byKey(const ValueKey('thread-error')), findsNothing);
  });

  testWidgets('new messages turn up while the conversation is open', (
    tester,
  ) async {
    final m = FakeMessages()..add('ann', 'Hello there');
    await mount(tester, m, poll: const Duration(seconds: 5));
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    expect(find.text('Anyone there?'), findsNothing);
    m.add('ann', 'Anyone there?');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Anyone there?'), findsOneWidget);
    // A message is not shown twice if it is seen again.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Anyone there?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new message can be started with any friend', (tester) async {
    final m = FakeMessages();
    await mount(tester, m);
    await tester.tap(find.byKey(const ValueKey('message-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('friend-picker')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-bob')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-title')), findsOneWidget);
    expect(find.text('bob'), findsWidgets);
    expect(find.byKey(const ValueKey('thread-empty')), findsOneWidget);
    await tester.enterText(field(), 'Hi Bob');
    await tester.tap(find.byKey(const ValueKey('message-send')));
    await tester.pumpAndSettle();
    expect(m.threads['bob']!.single['body'], 'Hi Bob');
    expect(find.byKey(const ValueKey('conversation-bob')), findsOneWidget);
  });

  testWidgets('a conversation can be opened straight away', (tester) async {
    final m = FakeMessages()..add('bob', 'Ping');
    await mount(tester, m, initial: 'bob');
    expect(find.byKey(const ValueKey('thread-title')), findsOneWidget);
    expect(find.text('Ping'), findsWidgets);
  });

  testWidgets('someone who is not a friend cannot be opened', (tester) async {
    await mount(tester, FakeMessages(), initial: 'stranger');
    expect(
      find.text('That person is not one of your friends.'),
      findsOneWidget,
    );
  });

  testWidgets('earlier messages are loaded on request', (tester) async {
    final m = FakeMessages();
    for (var i = 0; i < 60; i++) {
      m.add('ann', 'message $i');
    }
    await mount(tester, m, initial: 'ann');
    expect(find.byKey(const ValueKey('messages-older')), findsNothing);
    // The newest 50 are loaded; the button is at the very top of the list.
    await tester.drag(
      find.byKey(const ValueKey('thread-list')),
      const Offset(0, 20000),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('messages-older')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('messages-older')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('messages-older')), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('thread-list')),
      const Offset(0, 20000),
    );
    await tester.pumpAndSettle();
    expect(find.text('message 0'), findsOneWidget);
  });

  testWidgets('on a narrow screen the list and the conversation take turns', (
    tester,
  ) async {
    final m = FakeMessages()..add('ann', 'Hello there');
    await mount(tester, m, size: const Size(500, 800));
    expect(find.byKey(const ValueKey('conversation-ann')), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-none')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conversation-ann')), findsNothing);
    expect(find.byKey(const ValueKey('thread-title')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thread-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conversation-ann')), findsOneWidget);
  });

  test('times read as a clock time today and a date otherwise', () {
    final now = DateTime(2026, 10, 22, 12);
    final today = DateTime(2026, 10, 22, 9, 5).toUtc().toIso8601String();
    final other = DateTime(2026, 10, 3, 14, 30).toUtc().toIso8601String();
    expect(messageTime(today, now: now), '09:05');
    expect(messageTime(other, now: now), '3 Oct 14:30');
    expect(messageTime(null, now: now), '');
    expect(messageTime('rubbish', now: now), '');
  });
}
