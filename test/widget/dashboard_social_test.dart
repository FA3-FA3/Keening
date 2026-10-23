import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'messages_page_test.dart' show FakeMessages;
import 'people_page_test.dart' show FakePeople;

Future<(FakeMessages, FakePeople)> mount(
  WidgetTester tester, {
  Size size = const Size(1300, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final messages = FakeMessages()
    ..add('ann', 'Hello there')
    ..add('ann', 'Are you free?');
  final people = FakePeople();
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardPage(peopleService: people, messagesService: messages),
    ),
  );
  await tester.pumpAndSettle();
  return (messages, people);
}

void main() {
  testWidgets('the messages button sits next to the profile picture', (
    tester,
  ) async {
    await mount(tester);
    final button = find.byKey(const ValueKey('messages-button'));
    final profile = find.byKey(const ValueKey('account-settings'));
    expect(button, findsOneWidget);
    // Immediately to the left of the profile button, on the same line.
    expect(
      tester.getCenter(button).dy,
      closeTo(tester.getCenter(profile).dy, 1),
    );
    expect(
      tester.getRect(button).right,
      lessThanOrEqualTo(tester.getRect(profile).left + 1),
    );
    expect(
      tester.getRect(profile).left - tester.getRect(button).right,
      lessThan(40),
    );
    // And after the quick add button.
    expect(
      tester.getRect(find.byKey(const ValueKey('quick-add'))).right,
      lessThanOrEqualTo(tester.getRect(button).left + 1),
    );
  });

  testWidgets('the number of unread messages shows on the button', (
    tester,
  ) async {
    await mount(tester);
    final badge = tester.widget<Badge>(
      find.byKey(const ValueKey('messages-badge')),
    );
    expect(badge.isLabelVisible, isTrue);
    expect((badge.label as Text).data, '2');
    expect(find.byTooltip('Messages (2 unread)'), findsOneWidget);
  });

  testWidgets('with nothing unread there is no badge', (tester) async {
    tester.view.physicalSize = const Size(1300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          peopleService: FakePeople(),
          messagesService: FakeMessages(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(find.byKey(const ValueKey('messages-badge')))
          .isLabelVisible,
      isFalse,
    );
  });

  testWidgets('the button opens the Messages page in a tab', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('messages-button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tab-Messages')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('conversation-ann')), findsOneWidget);
    // Reading the conversation clears the badge.
    await tester.tap(find.byKey(const ValueKey('conversation-ann')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(find.byKey(const ValueKey('messages-badge')))
          .isLabelVisible,
      isFalse,
    );
  });

  testWidgets('People is a page in the sidebar', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('nav-People')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-tab-People')), findsOneWidget);
    expect(find.byKey(const ValueKey('people-tab-friends')), findsOneWidget);
    expect(find.byKey(const ValueKey('people-tab-requests')), findsOneWidget);
    // Messages is reached from the top bar, not the sidebar.
    expect(find.byKey(const ValueKey('nav-Messages')), findsNothing);
  });

  testWidgets('Message on a friend opens a conversation with them', (
    tester,
  ) async {
    final (messages, _) = await mount(tester);
    messages.friends.add('ann');
    await tester.tap(find.byKey(const ValueKey('nav-People')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friend-message-ann')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace-tab-Messages')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('thread-title')), findsOneWidget);
    expect(find.text('Are you free?'), findsWidgets);
  });

  testWidgets('narrow screens still fit the top bar', (tester) async {
    await mount(tester, size: const Size(420, 800));
    expect(find.byKey(const ValueKey('messages-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
