import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/boards_service.dart';
import 'package:keening/utils/calendar_service.dart';
import 'package:keening/utils/gantt_service.dart';
import 'package:keening/utils/pads_service.dart';
import 'package:keening/utils/projects_service.dart';
import 'package:keening/utils/schedule_service.dart';
import 'package:keening/widgets/quick_add_panel.dart';

class _Recorder {
  final calls = <String>[];
  final data = <Map<String, dynamic>>[];

  Map<String, dynamic> record(
    String prefix,
    String action,
    Map<String, dynamic> d,
  ) {
    calls.add('$prefix$action');
    data.add(d);
    return switch (action) {
      'listCalendars' => {
        'calendars': [
          {'id': 'cal1', 'name': 'Main'},
        ],
      },
      'listWorkplaces' => {
        'workplaces': [
          {'id': 'w1', 'name': 'Keening'},
        ],
      },
      'getBoard' => {
        'columns': [
          {'id': 'c1', 'name': 'To do'},
        ],
      },
      _ => {},
    };
  }
}

class _Pads extends PadsService {
  _Pads(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('', a, d);
  @override
  void close() {}
}

class _Projects extends ProjectsService {
  _Projects(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('', a, d);
  @override
  void close() {}
}

class _Gantt extends GanttService {
  _Gantt(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('gantt:', a, d);
  @override
  void close() {}
}

class _Boards extends BoardsService {
  _Boards(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('boards:', a, d);
  @override
  void close() {}
}

class _Calendar extends CalendarService {
  _Calendar(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('calendar:', a, d);
  @override
  void close() {}
}

class _Schedule extends ScheduleService {
  _Schedule(this.r);
  final _Recorder r;
  @override
  Future<Map<String, dynamic>> call(
    String a, [
    Map<String, dynamic> d = const {},
  ]) async => r.record('schedule:', a, d);
  @override
  void close() {}
}

Future<_Recorder> _pump(WidgetTester tester, List<String> created) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = _Recorder();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Center(child: Text('page behind', key: ValueKey('behind'))),
            Positioned(
              right: 16,
              bottom: 16,
              child: QuickAddPanel(
                padsService: _Pads(r),
                projectsService: _Projects(r),
                ganttService: _Gantt(r),
                boardsService: _Boards(r),
                calendarService: _Calendar(r),
                scheduleService: _Schedule(r),
                onClose: () {},
                onCreated: created.add,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return r;
}

Future<void> _add(WidgetTester tester, String title) async {
  await tester.enterText(find.byKey(const ValueKey('quick-add-title')), title);
  await tester.tap(find.byKey(const ValueKey('quick-add-submit')));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String kind) async {
  await tester.tap(find.byKey(ValueKey('quick-add-$kind')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sits at the bottom right and leaves the page undimmed', (
    tester,
  ) async {
    await _pump(tester, []);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('behind')), findsOneWidget);
    final corner = tester.getBottomRight(
      find.byKey(const ValueKey('quick-add-panel')),
    );
    expect(corner, const Offset(1200 - 16, 900 - 16));
  });

  testWidgets('creates a document at the top level', (tester) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _add(tester, 'Plan');
    expect(r.calls, ['createPad']);
    expect(r.data.single['name'], 'Plan');
    expect(r.data.single['kind'], 'notepad');
    expect(r.data.single['folderId'], isNull);
    expect(created, ['Documents']);
    expect(find.text('Document added.'), findsOneWidget);
  });

  testWidgets('requires a name', (tester) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await tester.tap(find.byKey(const ValueKey('quick-add-submit')));
    await tester.pump();
    expect(find.text('Enter a title.'), findsOneWidget);
    expect(r.calls, isEmpty);
    expect(created, isEmpty);
  });

  testWidgets('creates a project and a folder', (tester) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _choose(tester, 'project');
    await _add(tester, 'Launch');
    await _choose(tester, 'folder');
    await _add(tester, 'Notes');
    expect(r.calls, ['createProject', 'createFolder']);
    expect(created, ['Projects', 'Documents']);
  });

  testWidgets('creates a calendar event in the first calendar', (tester) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _choose(tester, 'event');
    await _add(tester, 'Dentist');
    expect(r.calls, ['calendar:listCalendars', 'calendar:saveItem']);
    expect(r.data.last['calendar_id'], 'cal1');
    expect(r.data.last['title'], 'Dentist');
    expect(r.data.last['start_time'], isNull);
    expect(created, ['Calendar']);
  });

  testWidgets('creates a schedule session after checking its times', (
    tester,
  ) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _choose(tester, 'session');
    await tester.enterText(find.widgetWithText(TextField, '10:00'), '08:00');
    await _add(tester, 'Gym');
    expect(find.textContaining('HH:mm'), findsWidgets);
    expect(r.calls, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, '08:00'), '11:00');
    await _add(tester, 'Gym');
    expect(r.calls, ['schedule:saveBlock']);
    expect(r.data.single['start'], '09:00');
    expect(created, ['Schedule']);
  });

  testWidgets('creates a Gantt phase in the chosen calendar', (tester) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _choose(tester, 'phase');
    await _add(tester, 'Build');
    expect(r.calls, ['gantt:listCalendars', 'gantt:saveItem']);
    expect(r.data.last['calendar_id'], 'cal1');
    expect(created, ['Gantt']);
  });

  testWidgets('creates a board task in a panel of the chosen board', (
    tester,
  ) async {
    final created = <String>[];
    final r = await _pump(tester, created);
    await _choose(tester, 'task');
    await _add(tester, 'Fix bug');
    expect(r.calls, [
      'boards:listWorkplaces',
      'boards:getBoard',
      'boards:createOrgTask',
    ]);
    expect(r.data.last['workplaceId'], 'w1');
    expect(r.data.last['columnId'], 'c1');
    expect(created, ['Boards']);
  });
}
