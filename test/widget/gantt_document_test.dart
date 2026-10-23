import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/dashboard_page.dart';
import 'package:keening/pages/gantt_page.dart';
import 'package:keening/utils/local_store.dart';
import 'documents_page_test.dart' show FakeDocs;
import 'gantt_page_test.dart' show FakeGantt;

void main() {
  late FakeDocs docs;
  late FakeGantt gantt;
  late String roadmap;

  Future<void> load(
    WidgetTester tester, {
    String? viewKey,
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          key: UniqueKey(),
          padsService: docs,
          ganttService: gantt,
          viewKey: viewKey,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    docs = FakeDocs();
    gantt = FakeGantt();
    roadmap =
        docs.addDoc('Roadmap', kind: 'gantt', doc: {'version': 1})['id']
            as String;
    docs.addDoc(
      'Shopping',
      kind: 'notepad',
      doc: {'version': 1, 'text': 'Milk'},
    );
    gantt.calendars.add({'id': roadmap, 'name': 'Roadmap', 'color': '#2563EB'});
    final today = DateUtils.dateOnly(DateTime.now());
    String iso(DateTime d) => d.toIso8601String().substring(0, 10);
    gantt.items.addAll([
      for (final (i, title) in ['Design', 'Build'].indexed)
        {
          'id': 'p$i',
          'calendar_id': roadmap,
          'calendar_name': 'Roadmap',
          'kind': 'event',
          'title': title,
          'description': '',
          'start_date': iso(today.add(Duration(days: i * 3))),
          'end_date': iso(today.add(Duration(days: i * 3 + 2))),
          'completed': false,
          'prerequisite_id': null,
          'color': '#2563EB',
          'panels': [],
          'progress': {'done': 0, 'total': 0},
        },
    ]);
  });

  Future<void> openDocuments(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('nav-Documents')));
    await tester.pumpAndSettle();
  }

  Future<void> openRoadmap(WidgetTester tester) async {
    await openDocuments(tester);
    await tester.tap(find.byKey(ValueKey('doc-tile-$roadmap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-open')));
    await tester.pumpAndSettle();
  }

  testWidgets('Gantt is no longer a page of its own', (tester) async {
    await load(tester);
    expect(find.byKey(const ValueKey('nav-Gantt')), findsNothing);
    for (final page in [
      'Projects',
      'Calendar',
      'Boards',
      'Schedule',
      'Documents',
    ]) {
      expect(find.byKey(ValueKey('nav-$page')), findsOneWidget);
    }
  });

  testWidgets('a Gantt calendar is listed in Documents with the others', (
    tester,
  ) async {
    await load(tester);
    await openDocuments(tester);
    expect(find.byKey(ValueKey('doc-tile-$roadmap')), findsOneWidget);
    expect(find.text('Roadmap'), findsWidgets);
    // At the top level, beside the other documents.
    final tile = tester.getTopLeft(find.byKey(ValueKey('doc-tile-$roadmap')));
    final other = tester.getTopLeft(
      find.byKey(ValueKey('doc-tile-${docs.documents.keys.last}')),
    );
    expect(tile.dy, other.dy);
  });

  testWidgets('New document offers a Gantt calendar', (tester) async {
    await load(tester);
    await openDocuments(tester);
    await tester.tap(find.byKey(const ValueKey('document-create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('doc-type-gantt')), findsOneWidget);
    expect(find.text('Gantt calendar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doc-type-gantt')));
    await tester.pumpAndSettle();
    expect(find.text('New Gantt calendar'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Hiring plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    final made = docs.documents.values.firstWhere(
      (d) => d['name'] == 'Hiring plan',
    );
    expect(made['kind'], 'gantt');
    expect(made['folder_id'], isNull);
    // No content is saved for it: the calendar holds its own phases.
    expect(docs.saved, isEmpty);
    expect(find.byKey(ValueKey('doc-tile-${made['id']}')), findsOneWidget);
  });

  testWidgets('opening one shows its timeline in a tab of its own', (
    tester,
  ) async {
    await load(tester);
    await openRoadmap(tester);
    expect(find.byKey(ValueKey('workspace-tab-doc:$roadmap')), findsOneWidget);
    expect(find.byKey(const ValueKey('doc-screen-title')), findsOneWidget);
    expect(find.text('Design'), findsWidgets);
    expect(find.text('Build'), findsWidgets);
    // Only the phases of this calendar were asked for.
    expect(gantt.calls, contains('listItems'));
  });

  testWidgets('the calendar page has no calendar chooser or create button', (
    tester,
  ) async {
    await load(tester);
    await openRoadmap(tester);
    expect(find.text('Create calendar'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byTooltip('Rename calendar'), findsNothing);
    expect(find.byTooltip('Delete calendar'), findsNothing);
    // The phase controls are there.
    expect(find.text('New phase'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('a phase is added to the calendar the document is', (
    tester,
  ) async {
    await load(tester);
    await openRoadmap(tester);
    await tester.tap(find.text('New phase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Launch');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = gantt.items.firstWhere((i) => i['title'] == 'Launch');
    expect(saved['calendar_id'], roadmap);
  });

  testWidgets('it can go full screen and come back', (tester) async {
    await load(tester);
    await openRoadmap(tester);
    await tester.tap(find.byKey(const ValueKey('doc-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.text('Design'), findsWidgets);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();
    expect(find.text('Design'), findsWidgets);
    expect(find.byKey(ValueKey('workspace-tab-doc:$roadmap')), findsOneWidget);
  });

  testWidgets('the tab comes back after a reload', (tester) async {
    await load(tester, viewKey: 'gantt-doc-view');
    await openRoadmap(tester);
    await load(tester, viewKey: 'gantt-doc-view');
    expect(find.byKey(ValueKey('workspace-tab-doc:$roadmap')), findsOneWidget);
    expect(find.text('Design'), findsWidgets);
  });

  testWidgets('an old view with a Gantt page open is restored without it', (
    tester,
  ) async {
    localWrite(
      'old-gantt-view',
      '{"tabs": ["Gantt", "Boards"], "selected": "Gantt"}',
    );
    await load(tester, viewKey: 'old-gantt-view');
    expect(find.byKey(const ValueKey('workspace-tab-Gantt')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-tab-Boards')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a calendar that no longer exists says so', (tester) async {
    gantt.calendars.clear();
    await load(tester);
    await openRoadmap(tester);
    expect(
      find.text('This Gantt calendar could not be found.'),
      findsOneWidget,
    );
  });

  testWidgets('deleting the document closes its tab', (tester) async {
    await load(tester);
    await openRoadmap(tester);
    await openDocuments(tester);
    await tester.tap(find.byKey(ValueKey('doc-tile-$roadmap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('doc-details-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('workspace-tab-doc:$roadmap')), findsNothing);
  });

  testWidgets('the standalone calendar page still manages calendars', (
    tester,
  ) async {
    gantt.calendars.add({'id': 'other', 'name': 'Other', 'color': '#7C3AED'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GanttPage(service: gantt)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create calendar'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
  });
}
