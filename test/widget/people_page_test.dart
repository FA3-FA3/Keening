import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/people_page.dart';
import 'package:keening/utils/people_service.dart';

/// A stand-in for the server's people routes.
class FakePeople extends PeopleService {
  final friends = <String>['ann'];
  final incoming = <Map<String, dynamic>>[];
  final outgoing = <Map<String, dynamic>>[];
  final calls = <String>[];
  bool fail = false;
  var _next = 1;

  void receive(String name) =>
      incoming.add({'id': 'in${_next++}', 'username': name});

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    if (fail) throw StateError('People are unavailable.');
    switch (action) {
      case 'listFriends':
        return {
          'friends': [
            for (final f in friends) {'username': f},
          ],
        };
      case 'listRequests':
        return {'incoming': List.of(incoming), 'outgoing': List.of(outgoing)};
      case 'sendRequest':
        final who = data['who'] as String;
        if (who == 'nobody') {
          throw StateError('No one with that username or email was found.');
        }
        if (friends.contains(who)) throw StateError('You are already friends.');
        if (incoming.any((r) => r['username'] == who)) {
          incoming.removeWhere((r) => r['username'] == who);
          friends.add(who);
          return {'status': 'friends', 'username': who};
        }
        outgoing.add({'id': 'out${_next++}', 'username': who});
        return {'status': 'sent', 'username': who};
      case 'acceptRequest':
        final r = incoming.firstWhere((r) => r['id'] == data['requestId']);
        incoming.remove(r);
        friends.add(r['username'] as String);
        return {'accepted': true, 'username': r['username']};
      case 'declineRequest':
        incoming.removeWhere((r) => r['id'] == data['requestId']);
        return {'removed': true};
      case 'cancelRequest':
        outgoing.removeWhere((r) => r['id'] == data['requestId']);
        return {'removed': true};
      case 'removeFriend':
        friends.remove(data['username']);
        return {'removed': true};
    }
    throw StateError('Unknown');
  }

  @override
  void close() {}
}

Future<FakePeople> mount(
  WidgetTester tester, {
  void Function(String)? onMessage,
  FakePeople? people,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = people ?? FakePeople();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PeoplePage(
          service: fake,
          onMessage: onMessage,
          pollInterval: null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> openRequests(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('people-tab-requests')));
  await tester.pumpAndSettle();
}

Future<void> addFriend(WidgetTester tester, String who) async {
  await tester.enterText(find.byKey(const ValueKey('people-add-field')), who);
  await tester.tap(find.byKey(const ValueKey('people-add-send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('has a friends tab and a requests tab', (tester) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('people-tab-friends')), findsOneWidget);
    expect(find.byKey(const ValueKey('people-tab-requests')), findsOneWidget);
    expect(find.text('Friends (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-ann')), findsOneWidget);
    await openRequests(tester);
    expect(find.byKey(const ValueKey('requests-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-ann')), findsNothing);
  });

  testWidgets('with no friends it says how to add some', (tester) async {
    final people = FakePeople()..friends.clear();
    await mount(tester, people: people);
    expect(find.byKey(const ValueKey('friends-empty')), findsOneWidget);
  });

  testWidgets('a request is sent by username or email and listed as sent', (
    tester,
  ) async {
    final people = await mount(tester);
    await addFriend(tester, '  bob  ');
    expect(find.text('Request sent to bob.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('people-add-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(people.outgoing.single['username'], 'bob');
    await addFriend(tester, 'cat@example.com');
    expect(people.outgoing.length, 2);
    await openRequests(tester);
    expect(find.text('Sent (2)'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('asking someone who already asked you makes you friends', (
    tester,
  ) async {
    final people = FakePeople()..receive('bob');
    await mount(tester, people: people);
    await addFriend(tester, 'bob');
    expect(find.text('You and bob are now friends.'), findsOneWidget);
    expect(find.byKey(const ValueKey('friend-bob')), findsOneWidget);
  });

  testWidgets('a request that cannot be sent says why, and keeps the text', (
    tester,
  ) async {
    await mount(tester);
    await addFriend(tester, 'nobody');
    expect(
      find.text('No one with that username or email was found.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('people-add-field')))
          .controller!
          .text,
      'nobody',
    );
    await addFriend(tester, 'ann');
    expect(find.text('You are already friends.'), findsOneWidget);
    expect(find.byKey(const ValueKey('people-add-notice')), findsNothing);
  });

  testWidgets('an empty box is refused without asking the server', (
    tester,
  ) async {
    final people = await mount(tester);
    final before = people.calls.length;
    await tester.tap(find.byKey(const ValueKey('people-add-send')));
    await tester.pump();
    expect(find.text('Enter a username or an email address.'), findsOneWidget);
    expect(people.calls.length, before);
  });

  testWidgets('requests you were sent can be accepted or declined', (
    tester,
  ) async {
    final people = FakePeople()
      ..receive('bob')
      ..receive('cat');
    await mount(tester, people: people);
    // A badge on the tab shows how many are waiting.
    expect(find.byType(Badge), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await openRequests(tester);
    expect(find.text('Received (2)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('request-accept-in1')));
    await tester.pumpAndSettle();
    expect(people.friends, contains('bob'));
    expect(find.text('Received (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('request-decline-in2')));
    await tester.pumpAndSettle();
    expect(people.friends, isNot(contains('cat')));
    expect(find.byKey(const ValueKey('requests-empty')), findsOneWidget);
    expect(find.text('Friends (2)'), findsOneWidget);
  });

  testWidgets('a request you sent can be cancelled', (tester) async {
    final people = FakePeople();
    await mount(tester, people: people);
    await addFriend(tester, 'bob');
    await openRequests(tester);
    final id = people.outgoing.single['id'];
    await tester.tap(find.byKey(ValueKey('request-cancel-$id')));
    await tester.pumpAndSettle();
    expect(people.outgoing, isEmpty);
    expect(find.byKey(const ValueKey('requests-empty')), findsOneWidget);
  });

  testWidgets('a friend is removed only after confirming', (tester) async {
    final people = await mount(tester);
    await tester.tap(find.byKey(const ValueKey('friend-remove-ann')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(people.friends, ['ann']);
    await tester.tap(find.byKey(const ValueKey('friend-remove-ann')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-remove-confirm')));
    await tester.pumpAndSettle();
    expect(people.friends, isEmpty);
    expect(find.byKey(const ValueKey('friends-empty')), findsOneWidget);
  });

  testWidgets('the message button starts a conversation with that friend', (
    tester,
  ) async {
    String? opened;
    await mount(tester, onMessage: (u) => opened = u);
    await tester.tap(find.byKey(const ValueKey('friend-message-ann')));
    expect(opened, 'ann');
  });

  testWidgets('a failure to load can be retried', (tester) async {
    final people = FakePeople()..fail = true;
    await mount(tester, people: people);
    expect(find.byKey(const ValueKey('people-error')), findsOneWidget);
    people.fail = false;
    await tester.tap(find.byKey(const ValueKey('people-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('people-error')), findsNothing);
    expect(find.byKey(const ValueKey('friend-ann')), findsOneWidget);
  });

  testWidgets('new requests turn up while the page is open', (tester) async {
    final people = FakePeople();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeoplePage(
            service: people,
            pollInterval: const Duration(seconds: 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    people.receive('dan');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    // Closing the page stops the checking.
    await tester.pumpWidget(const SizedBox());
    final before = people.calls.length;
    await tester.pump(const Duration(seconds: 30));
    expect(people.calls.length, before);
  });
}
