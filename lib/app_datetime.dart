import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Financial business dates remain independent of immutable recorded instants.
/// New events already store UTC ISO-8601 in confirmed_at / created_at / voided_at.
class AppDateTime {
  static DateTime? parse(Object? value) {
    if (value is! String) {
      return null;
    }
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.parse(match[1]!),
        month = int.parse(match[2]!),
        day = int.parse(match[3]!);
    final hour = int.parse(match[4]!),
        minute = int.parse(match[5]!),
        second = int.parse(match[6]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    final zone = match[7]!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4, 6)) > 59)) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static final current = ValueNotifier<String>('Etc/UTC');
  static bool _initialized = false;
  static void initialize() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  static void configure(String zoneId) {
    initialize();
    tz.getLocation(
      zoneId,
    ); // Reject invalid configured zones rather than mislabel timestamps.
    current.value = zoneId;
  }

  static DateTime today() {
    initialize();
    final now = tz.TZDateTime.now(tz.getLocation(current.value));
    return DateTime(now.year, now.month, now.day);
  }

  /// UTC bounds for the current calendar month in the configured business zone.
  /// This includes the right local dates when a zone observes daylight saving.
  static (DateTime, DateTime) currentMonthUtcRange() {
    initialize();
    final location = tz.getLocation(current.value);
    final now = tz.TZDateTime.now(location);
    final start = tz.TZDateTime(location, now.year, now.month);
    final end = tz.TZDateTime(location, now.year, now.month + 1);
    return (start.toUtc(), end.toUtc());
  }

  /// Calendar day bounds use the configured business zone, including DST days.
  static (DateTime, DateTime) currentDayUtcRange({DateTime? at}) {
    initialize();
    final location = tz.getLocation(current.value);
    final now = at == null
        ? tz.TZDateTime.now(location)
        : tz.TZDateTime.from(at, location);
    return (
      tz.TZDateTime(location, now.year, now.month, now.day).toUtc(),
      tz.TZDateTime(location, now.year, now.month, now.day + 1).toUtc(),
    );
  }

  /// UTC instants remain unchanged in storage. Only their display changes.
  /// The offset argument is retained for deterministic tests and explicit conversions.
  static String format(Object? value, {Duration? offset}) {
    final instant = parse(value);
    if (instant == null) return '—';
    initialize();
    final DateTime local = offset == null
        ? tz.TZDateTime.from(instant, tz.getLocation(current.value))
        : instant.add(offset);
    String two(int n) => n.toString().padLeft(2, '0');
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final period = local.hour < 12 ? 'am' : 'pm';
    return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} '
        '${two(hour)}:${two(local.minute)} $period';
  }
}
