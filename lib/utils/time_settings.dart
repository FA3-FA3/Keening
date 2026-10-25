import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'local_store.dart';

/// How times are shown and which time zone the app's clock follows. Remembered
/// on this device.
@immutable
class TimeSettings {
  const TimeSettings({this.zone, this.hour24 = true, this.colon = true});

  /// The name of a time zone ("Europe/London"), or null for the device's own.
  final String? zone;

  /// True for a 24-hour clock (13:00), false for 12-hour (1:00 PM).
  final bool hour24;

  /// True to put a colon between hours and minutes (13:00), false for none
  /// (1300).
  final bool colon;

  static const standard = TimeSettings();

  TimeSettings copyWith({Object? zone = _keep, bool? hour24, bool? colon}) =>
      TimeSettings(
        zone: identical(zone, _keep) ? this.zone : zone as String?,
        hour24: hour24 ?? this.hour24,
        colon: colon ?? this.colon,
      );

  Map<String, dynamic> toJson() => {
    if (zone != null) 'zone': zone,
    'hour24': hour24,
    'colon': colon,
  };

  static TimeSettings fromJson(Object? json) {
    if (json is! Map) return standard;
    final zone = json['zone'];
    return TimeSettings(
      zone: zone is String && zone.isNotEmpty ? zone : null,
      hour24: json['hour24'] is bool ? json['hour24'] as bool : true,
      colon: json['colon'] is bool ? json['colon'] as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TimeSettings &&
      other.zone == zone &&
      other.hour24 == hour24 &&
      other.colon == colon;

  @override
  int get hashCode => Object.hash(zone, hour24, colon);
}

const _keep = Object();
const _timeKey = 'keening.time';

TimeSettings _readTime() {
  try {
    final raw = localRead(_timeKey);
    return raw == null
        ? TimeSettings.standard
        : TimeSettings.fromJson(jsonDecode(raw));
  } catch (_) {
    return TimeSettings.standard;
  }
}

/// The time settings chosen in the settings page.
final ValueNotifier<TimeSettings> timeSettings =
    ValueNotifier<TimeSettings>(_readTime())..addListener(() {
      try {
        localWrite(_timeKey, jsonEncode(timeSettings.value.toJson()));
      } catch (_) {
        // The choice just is not remembered.
      }
    });

var _zonesReady = false;

void _loadZones() {
  if (_zonesReady) return;
  tzdata.initializeTimeZones();
  _zonesReady = true;
}

/// The names of every time zone that can be chosen, in order.
List<String> timeZoneNames() {
  _loadZones();
  return tz.timeZoneDatabase.locations.keys.toList()..sort();
}

/// What the clock on the wall shows now, in the chosen time zone (the device's
/// own if none is chosen), as a plain date and time.
DateTime appNow({TimeSettings? settings, DateTime? at}) {
  final zone = (settings ?? timeSettings.value).zone;
  final instant = at ?? DateTime.now();
  if (zone == null) return instant;
  try {
    _loadZones();
    final t = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  } catch (_) {
    return instant;
  }
}

/// The time as the chosen settings write it: "13:00", "1300", "1:00 PM" or
/// "0100 PM".
String formatClock(int hour, int minute, {TimeSettings? settings}) {
  final s = settings ?? timeSettings.value;
  String two(int n) => n.toString().padLeft(2, '0');
  if (s.hour24) {
    return s.colon
        ? '${two(hour)}:${two(minute)}'
        : '${two(hour)}${two(minute)}';
  }
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final suffix = hour % 24 < 12 ? 'AM' : 'PM';
  return s.colon
      ? '$h12:${two(minute)} $suffix'
      : '${two(h12)}${two(minute)} $suffix';
}

/// A stored time ("13:00", or "24:00" for the end of the day) written as the
/// chosen settings say; text that is not a time is returned as it is.
String formatHHmm(Object? text, {TimeSettings? settings}) {
  final raw = '${text ?? ''}';
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw);
  if (m == null) return raw;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 24 || minute > 59) return raw;
  if (hour == 24) {
    final s = settings ?? timeSettings.value;
    return s.hour24
        ? (s.colon ? '24:00' : '2400')
        : formatClock(0, 0, settings: s);
  }
  return formatClock(hour, minute, settings: settings);
}

/// "13:00 - 14:30" written as the chosen settings say.
String formatTimeRange(
  Object? start,
  Object? end, {
  String separator = ' - ',
}) => '${formatHHmm(start)}$separator${formatHHmm(end)}';
