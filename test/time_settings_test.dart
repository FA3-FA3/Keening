import 'package:flutter_test/flutter_test.dart';
import 'package:keening/utils/local_store.dart';
import 'package:keening/utils/time_settings.dart';

void main() {
  tearDown(() => timeSettings.value = TimeSettings.standard);

  group('writing a time', () {
    const h24 = TimeSettings();
    const h24plain = TimeSettings(colon: false);
    const h12 = TimeSettings(hour24: false);
    const h12plain = TimeSettings(hour24: false, colon: false);

    test('24-hour, with and without the colon', () {
      expect(formatClock(13, 0, settings: h24), '13:00');
      expect(formatClock(13, 0, settings: h24plain), '1300');
      expect(formatClock(0, 5, settings: h24), '00:05');
      expect(formatClock(0, 5, settings: h24plain), '0005');
      expect(formatClock(9, 30, settings: h24), '09:30');
    });

    test('12-hour, with and without the colon', () {
      expect(formatClock(13, 0, settings: h12), '1:00 PM');
      expect(formatClock(13, 0, settings: h12plain), '0100 PM');
      expect(formatClock(0, 5, settings: h12), '12:05 AM');
      expect(formatClock(12, 0, settings: h12), '12:00 PM');
      expect(formatClock(23, 59, settings: h12), '11:59 PM');
      expect(formatClock(9, 30, settings: h12plain), '0930 AM');
    });

    test('a stored time is written as the settings say', () {
      expect(formatHHmm('13:00', settings: h24plain), '1300');
      expect(formatHHmm('09:05', settings: h12), '9:05 AM');
      expect(formatHHmm('9:05', settings: h12), '9:05 AM');
      expect(formatHHmm('00:00', settings: h12), '12:00 AM');
    });

    test(
      'the end of the day reads as 24:00, or midnight on a 12-hour clock',
      () {
        expect(formatHHmm('24:00', settings: h24), '24:00');
        expect(formatHHmm('24:00', settings: h24plain), '2400');
        expect(formatHHmm('24:00', settings: h12), '12:00 AM');
      },
    );

    test('anything that is not a time is left as it was', () {
      for (final bad in ['', 'All day', '25:00', '12:60', '1300', null]) {
        expect(formatHHmm(bad, settings: h12), bad ?? '', reason: '$bad');
      }
    });

    test('a range uses the settings for both ends', () {
      timeSettings.value = h12plain;
      expect(formatTimeRange('09:00', '10:30'), '0900 AM - 1030 AM');
      expect(
        formatTimeRange('13:00', '14:00', separator: ' – '),
        '0100 PM – 0200 PM',
      );
      timeSettings.value = h24;
      expect(formatTimeRange('09:00', '10:30'), '09:00 - 10:30');
    });

    test('the chosen settings are used when none are given', () {
      timeSettings.value = h12;
      expect(formatClock(15, 45), '3:45 PM');
      timeSettings.value = h24plain;
      expect(formatClock(15, 45), '1545');
    });
  });

  group('time zones', () {
    final noon = DateTime.utc(2026, 1, 15, 12);
    final summer = DateTime.utc(2026, 7, 15, 12);

    test('the device\'s own is used unless one is chosen', () {
      final now = DateTime(2026, 3, 3, 4, 5, 6);
      expect(appNow(settings: const TimeSettings(), at: now), now);
    });

    test('a chosen zone gives the time on its clock', () {
      expect(
        appNow(
          settings: const TimeSettings(zone: 'Asia/Tokyo'),
          at: noon,
        ),
        DateTime(2026, 1, 15, 21),
      );
      expect(
        appNow(
          settings: const TimeSettings(zone: 'America/New_York'),
          at: noon,
        ),
        DateTime(2026, 1, 15, 7),
      );
    });

    test('daylight saving time is allowed for', () {
      const london = TimeSettings(zone: 'Europe/London');
      expect(appNow(settings: london, at: noon).hour, 12);
      expect(appNow(settings: london, at: summer).hour, 13);
      const ny = TimeSettings(zone: 'America/New_York');
      expect(appNow(settings: ny, at: summer).hour, 8);
    });

    test('the date can change with the zone', () {
      final late = DateTime.utc(2026, 1, 15, 23, 30);
      expect(
        appNow(
          settings: const TimeSettings(zone: 'Pacific/Auckland'),
          at: late,
        ).day,
        16,
      );
    });

    test('an unknown zone falls back to the instant given', () {
      final at = DateTime(2026, 1, 15, 12);
      expect(
        appNow(
          settings: const TimeSettings(zone: 'Mars/Base'),
          at: at,
        ),
        at,
      );
    });

    test('the zones to choose from are listed in order', () {
      final names = timeZoneNames();
      expect(
        names,
        containsAll([
          'Europe/London',
          'America/New_York',
          'Asia/Tokyo',
          'Etc/UTC',
        ]),
      );
      expect(names.length, greaterThan(300));
      expect(names, orderedEquals([...names]..sort()));
    });

    test('appNow follows the settings by default', () {
      timeSettings.value = const TimeSettings(zone: 'Asia/Tokyo');
      final tokyo = appNow();
      final utc = DateTime.now().toUtc();
      final gap = DateTime(
        tokyo.year,
        tokyo.month,
        tokyo.day,
        tokyo.hour,
      ).difference(DateTime(utc.year, utc.month, utc.day, utc.hour)).inHours;
      expect(gap, 9);
    });
  });

  group('remembering the settings', () {
    test('they are saved as the person chooses them', () {
      timeSettings.value = const TimeSettings(
        zone: 'Europe/Paris',
        hour24: false,
        colon: false,
      );
      final saved = localRead('keening.time')!;
      expect(saved, contains('Europe/Paris'));
      expect(
        TimeSettings.fromJson({
          'zone': 'Europe/Paris',
          'hour24': false,
          'colon': false,
        }),
        timeSettings.value,
      );
    });

    test('damaged or missing values are the standard ones', () {
      expect(TimeSettings.fromJson(null), TimeSettings.standard);
      expect(TimeSettings.fromJson('x'), TimeSettings.standard);
      expect(
        TimeSettings.fromJson({'zone': 5, 'hour24': 'yes'}),
        TimeSettings.standard,
      );
      expect(TimeSettings.fromJson({'zone': ''}), TimeSettings.standard);
    });

    test('copying can clear the zone', () {
      const t = TimeSettings(zone: 'Asia/Tokyo');
      expect(t.copyWith(zone: null).zone, isNull);
      expect(t.copyWith(hour24: false).zone, 'Asia/Tokyo');
      expect(t.copyWith().zone, 'Asia/Tokyo');
    });
  });
}
