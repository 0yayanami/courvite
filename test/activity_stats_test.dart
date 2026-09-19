import 'package:courvite/data/activity_stats.dart';
import 'package:courvite/models/run.dart';
import 'package:flutter_test/flutter_test.dart';

RunSummary _run(DateTime start, double km, int minutes) => RunSummary(
  id: start.millisecondsSinceEpoch,
  startTime: start,
  duration: Duration(minutes: minutes),
  distanceMeters: km * 1000,
);

void main() {
  // Saturday.
  final now = DateTime(2026, 9, 19, 18);

  test('weeks start on Monday', () {
    expect(periodStart(now, Period.week), DateTime(2026, 9, 14));
    expect(
      periodStart(DateTime(2026, 9, 14, 0, 5), Period.week),
      DateTime(2026, 9, 14),
    );
    expect(
      periodStart(DateTime(2026, 9, 13, 23), Period.week),
      DateTime(2026, 9, 7),
    );
  });

  test('weekly aggregation', () {
    final runs = [
      _run(DateTime(2026, 9, 15, 7), 5, 25),
      _run(DateTime(2026, 9, 17, 7), 10, 55),
      _run(DateTime(2026, 9, 10, 7), 8, 40),
      _run(DateTime(2025, 1, 1), 42, 240), // outside the window
    ];
    final weeks = aggregate(runs, Period.week, now: now);
    expect(weeks, hasLength(12));
    expect(weeks.last.start, DateTime(2026, 9, 14));
    expect(weeks.last.runs, 2);
    expect(weeks.last.distanceMeters, 15000);
    expect(weeks.last.duration, const Duration(minutes: 80));
    expect(weeks[10].runs, 1);
    expect(weeks.first.start, DateTime(2026, 6, 29));
    expect(weeks.fold<int>(0, (n, w) => n + w.runs), 3);
  });

  test('monthly aggregation spans year boundaries', () {
    final runs = [
      _run(DateTime(2025, 10, 3), 5, 30),
      _run(DateTime(2026, 9, 1), 5, 30),
    ];
    final months = aggregate(runs, Period.month, now: now);
    expect(months.first.start, DateTime(2025, 10));
    expect(months.first.runs, 1);
    expect(months.last.start, DateTime(2026, 9));
    expect(months.last.paceSecPerKm, 360);
  });

  test('week days run Monday to Sunday', () {
    final days = weekDays([
      _run(DateTime(2026, 9, 14, 7), 5, 25),
      _run(DateTime(2026, 9, 14, 19), 3, 15),
      _run(DateTime(2026, 9, 20, 9), 10, 50),
      _run(DateTime(2026, 9, 21, 9), 10, 50), // next week
    ], now);
    expect(days.map((d) => d.start.day), [14, 15, 16, 17, 18, 19, 20]);
    expect(days.first.distanceMeters, 8000);
    expect(days.first.runs, 2);
    expect(days.last.distanceMeters, 10000);
  });

  test('month days cover the whole month', () {
    final days = monthDays([
      _run(DateTime(2026, 2, 28, 7), 5, 25),
    ], DateTime(2026, 2));
    expect(days, hasLength(28));
    expect(days.first.start, DateTime(2026, 2, 1));
    expect(days.last.distanceMeters, 5000);
    expect(monthDays(const [], DateTime(2026, 12)), hasLength(31));
  });

  test('day intensity scales from 35% to 100%', () {
    expect(dayIntensity(0, 2000, 10000), 0);
    expect(dayIntensity(2000, 2000, 10000), closeTo(0.35, 1e-9));
    expect(dayIntensity(6000, 2000, 10000), closeTo(0.675, 1e-9));
    expect(dayIntensity(10000, 2000, 10000), closeTo(1, 1e-9));
    expect(dayIntensity(5000, 5000, 5000), 1);
  });

  test('medals go to the three fastest runs per distance', () {
    RunSummary withEfforts(int id, DateTime start, Map<int, int> secs) =>
        RunSummary(
          id: id,
          startTime: start,
          duration: const Duration(hours: 1),
          distanceMeters: 10000,
          bestEfforts: {
            for (final e in secs.entries) e.key: Duration(seconds: e.value),
          },
        );
    final medals = medalRanks([
      withEfforts(1, DateTime(2026, 9, 1), {1: 280, 2: 600, 5: 1600}),
      withEfforts(2, DateTime(2026, 9, 5), {1: 270, 2: 610}),
      withEfforts(3, DateTime(2026, 9, 9), {1: 270, 2: 590, 5: 1650, 10: 3400}),
      withEfforts(4, DateTime(2026, 9, 12), {1: 300, 2: 650}),
    ]);
    // 1 km: runs 2 and 3 tie at 4:30, the earlier (2) gets gold.
    expect(medals[1], {1: 2, 2: 1, 5: 0});
    expect(medals[2], {1: 0, 2: 2});
    expect(medals[3], {1: 1, 2: 0, 5: 1, 10: 0});
    expect(medals[4], isNull, reason: '4th on 1k and 2k: no medal');
    expect(medalRanks(const []), isEmpty);
  });
}
