import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keening/pages/settings_page.dart';

void main() {
  testWidgets('picture upload handles cancellation, errors, retry and removal', (
    tester,
  ) async {
    var cancel = true;
    var fail = true;
    var saves = 0;
    final profile = <String, dynamic>{
      'username': 'frank',
      'email': 'test@example.com',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => SettingsPage(
              profile: profile,
              loading: false,
              error: null,
              onRefresh: () {},
              pickImage: () async => cancel
                  ? null
                  : XFile.fromData(
                      base64Decode(
                        'iVBORw0KGgoAAAANSUhEUgAAABgAAAAQCAIAAACDRijCAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAIElEQVQ4jWMwLk+jCmIYNch4NIyMR9NR+WgWKSc/HQAAro6YEOGM2PcAAAAASUVORK5CYII=',
                      ),
                      name: 'photo.png',
                    ),
              onSavePicture: (image) async {
                saves++;
                if (fail) throw StateError('Upload failed.');
                update(
                  () => profile['profilePicture'] = image == null
                      ? null
                      : 'saved',
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add picture'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    cancel = false;
    Future<void> crop({bool cancelCrop = false}) async {
      await tester.tap(find.text('Add picture'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Crop profile picture'), findsOneWidget);
      if (!cancelCrop) {
        final slider = find.byKey(const ValueKey('profile-crop-zoom'));
        await tester.ensureVisible(slider);
        await tester.drag(slider, const Offset(60, 0));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).value, greaterThan(1));
        await tester.ensureVisible(
          find.byKey(const ValueKey('profile-crop-preview')),
        );
        await tester.drag(
          find.byKey(const ValueKey('profile-crop-preview')),
          const Offset(30, 20),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reset crop'));
        await tester.tap(find.text('Reset crop'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).value, 1);
      }
      await tester.tap(find.text(cancelCrop ? 'Cancel' : 'Apply'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    await crop(cancelCrop: true);
    expect(saves, 0);
    await crop();
    expect(find.text('Upload failed.'), findsOneWidget);
    fail = false;
    await crop();
    expect(find.text('Change picture'), findsOneWidget);
    expect(find.text('Upload failed.'), findsNothing);
    await tester.tap(find.text('Remove picture'));
    await tester.pumpAndSettle();
    expect(profile['profilePicture'], isNull);
    expect(find.text('Add picture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
