import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/attachments_service.dart';
import 'package:keening/widgets/item_attachments.dart';

// A valid 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class FakeAttachments implements AttachmentsService {
  final stored = <String, Map<String, dynamic>>{};
  final calls = <String>[];
  String? failWith;
  int _next = 0;

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    calls.add(action);
    if (failWith != null) throw StateError(failWith!);
    switch (action) {
      case 'list':
        return {
          'attachments': [
            for (final f in stored.values) {...f}..remove('data'),
          ],
        };
      case 'upload':
        final bytes = base64Decode(data['data'] as String);
        final id = 'a${_next++}';
        stored[id] = {
          'id': id,
          'name': data['name'],
          'mime': data['mime'],
          'size': bytes.length,
          'data': data['data'],
        };
        return {
          'attachment': {...stored[id]!}..remove('data'),
        };
      case 'get':
        return {...stored[data['attachmentId']]!};
      case 'delete':
        stored.remove(data['attachmentId']);
        return {'ok': true};
    }
    throw StateError('unexpected $action');
  }

  @override
  void close() {}
}

Future<void> mount(
  WidgetTester tester,
  FakeAttachments api, {
  String? itemId = 'item-1',
  List<PickedFile> Function()? pick,
  Future<bool> Function(String, Uint8List, String)? save,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ItemAttachments(
            itemType: 'task',
            itemId: itemId,
            service: api,
            pickFiles: () async => pick?.call() ?? [],
            saveFile: save,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PickedFile text(String name, String body) =>
    PickedFile(name, Uint8List.fromList(utf8.encode(body)));

void main() {
  test('content types come from the browser or the file name', () {
    expect(attachmentMime('a.png'), 'image/png');
    expect(attachmentMime('a.JPG'), 'image/jpeg');
    expect(attachmentMime('notes.txt'), 'text/plain');
    expect(attachmentMime('data.json'), 'application/json');
    expect(attachmentMime('archive.zip'), 'application/octet-stream');
    expect(attachmentMime('a.zip', 'application/zip'), 'application/zip');
    expect(attachmentSize(500), '500 B');
    expect(attachmentSize(2048), '2.0 KB');
    expect(attachmentSize(3 * 1024 * 1024), '3.0 MB');
  });

  testWidgets('an unsaved item asks to be saved first', (tester) async {
    final api = FakeAttachments();
    await mount(tester, api, itemId: null);
    expect(
      find.byKey(const ValueKey('attachments-save-first')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('attachment-add')), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('files can be added, opened, downloaded and deleted', (
    tester,
  ) async {
    final api = FakeAttachments();
    final saved = <String>[];
    late List<PickedFile> next;
    await mount(
      tester,
      api,
      pick: () => next,
      save: (name, bytes, mime) async {
        saved.add('$name:$mime:${bytes.length}');
        return true;
      },
    );
    expect(find.textContaining('No attachments yet'), findsOneWidget);

    next = [
      text('notes.txt', 'hello there'),
      PickedFile('pic.png', _png),
      PickedFile('data.bin', Uint8List.fromList([1, 2, 3])),
    ];
    await tester.tap(find.byKey(const ValueKey('attachment-add')));
    await tester.pumpAndSettle();
    expect(api.stored.length, 3);
    expect(api.stored['a0']!['mime'], 'text/plain');
    expect(api.stored['a1']!['mime'], 'image/png');
    expect(api.stored['a2']!['mime'], 'application/octet-stream');
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('11 B'), findsOneWidget);

    // A text file opens in a viewer.
    await tester.tap(find.byKey(const ValueKey('attachment-a0')));
    await tester.pumpAndSettle();
    expect(find.text('hello there'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    // A picture opens in a viewer.
    await tester.tap(find.byKey(const ValueKey('attachment-a1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attachment-image')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    // Other files download when clicked.
    await tester.tap(find.byKey(const ValueKey('attachment-a2')));
    await tester.pumpAndSettle();
    expect(saved, ['data.bin:application/octet-stream:3']);
    await tester.tap(find.byKey(const ValueKey('attachment-download-a0')));
    await tester.pumpAndSettle();
    expect(saved.last, 'notes.txt:text/plain:11');

    // Deleting asks first.
    await tester.tap(find.byKey(const ValueKey('attachment-delete-a0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.stored.length, 3);
    await tester.tap(find.byKey(const ValueKey('attachment-delete-a0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.stored.keys, ['a1', 'a2']);
    expect(find.text('notes.txt'), findsNothing);
  });

  testWidgets('existing attachments are listed when the item opens', (
    tester,
  ) async {
    final api = FakeAttachments();
    api.stored['x'] = {
      'id': 'x',
      'name': 'old.csv',
      'mime': 'text/csv',
      'size': 2048,
      'data': '',
    };
    await mount(tester, api);
    expect(find.text('old.csv'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
  });

  testWidgets('empty, oversized and rejected files explain why', (
    tester,
  ) async {
    final api = FakeAttachments();
    late List<PickedFile> next;
    await mount(tester, api, pick: () => next);
    next = [
      PickedFile('empty.txt', Uint8List(0)),
      PickedFile('huge.bin', Uint8List(attachmentMaxBytes + 1)),
    ];
    await tester.tap(find.byKey(const ValueKey('attachment-add')));
    await tester.pumpAndSettle();
    expect(api.calls, ['list'], reason: 'nothing was uploaded');
    final message = tester
        .widget<Text>(find.byKey(const ValueKey('attachment-error')))
        .data!;
    expect(message, contains('empty.txt is empty.'));
    expect(message, contains('huge.bin is larger than 5.0 MB.'));

    api.failWith = 'Attachments can use up to 100 MB in total.';
    next = [text('a.txt', 'a')];
    await tester.tap(find.byKey(const ValueKey('attachment-add')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('a.txt: Attachments can use up to 100 MB'),
      findsOneWidget,
    );
    expect(api.stored, isEmpty);
  });

  testWidgets('the add button stops at ten attachments', (tester) async {
    final api = FakeAttachments();
    for (var i = 0; i < attachmentsPerItem; i++) {
      api.stored['f$i'] = {
        'id': 'f$i',
        'name': 'f$i.txt',
        'mime': 'text/plain',
        'size': 1,
        'data': '',
      };
    }
    await mount(tester, api);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('attachment-add')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('a failed list shows the reason', (tester) async {
    final api = FakeAttachments()..failWith = 'Attachments are unavailable.';
    await mount(tester, api);
    expect(find.text('Attachments are unavailable.'), findsOneWidget);
  });

  testWidgets('downloads say when the platform cannot save files', (
    tester,
  ) async {
    final api = FakeAttachments();
    api.stored['x'] = {
      'id': 'x',
      'name': 'a.zip',
      'mime': 'application/zip',
      'size': 3,
      'data': base64Encode([1, 2, 3]),
    };
    await mount(tester, api, save: (_, _, _) async => false);
    await tester.tap(find.byKey(const ValueKey('attachment-download-x')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('only available in the browser'),
      findsOneWidget,
    );
  });
}
