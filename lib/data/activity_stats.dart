import '../models/run.dart';

enum Period { day, week, month }

/// Totals for one day, calendar week (starting Monday) or month.
class PeriodTotals {
  PeriodTotals(this.start);

  final DateTime start;
  int runs = 0;
  double distanceMeters = 0;
  Duration duration = Duration.zero;

  double? get paceSecPerKm => paceFor(distanceMeters, duration);
}

DateTime periodStart(DateTime t, Period period) => switch (period) {
  Period.day => DateTime(t.year, t.month, t.day),
  // Day arithmetic via the constructor stays correct across DST changes.
  Period.week => DateTime(
    t.year,
    t.month,
    t.day - (t.weekday - DateTime.monday),
  ),
  Period.month => DateTime(t.year, t.month),
};

DateTime _shift(DateTime start, Period period, int n) => switch (period) {
  Period.day => DateTime(start.year, start.month, start.day + n),
  Period.week => DateTime(start.year, start.month, start.day + 7 * n),
  Period.month => DateTime(start.year, start.month + n),
};

/// The last [count] periods up to and including the one containing [now],
/// oldest first, with the totals of the runs that started in each.
List<PeriodTotals> aggregate(
  Iterable<RunSummary> runs,
  Period period, {
  required DateTime now,
  int count = 12,
}) {
  final current = periodStart(now, period);
  final buckets = [
    for (var i = count - 1; i >= 0; i--)
      PeriodTotals(_shift(current, period, -i)),
  ];
  final byStart = {for (final b in buckets) b.start: b};
  for (final run in runs) {
    final bucket = byStart[periodStart(run.startTime, period)];
    if (bucket == null) continue;
    bucket.runs++;
    bucket.distanceMeters += run.distanceMeters;
    bucket.duration += run.duration;
  }
  return buckets;
}

/// The days of the week containing [now], Monday first.
List<PeriodTotals> weekDays(Iterable<RunSummary> runs, DateTime now) {
  final monday = periodStart(now, Period.week);
  return aggregate(
    runs,
    Period.day,
    now: DateTime(monday.year, monday.month, monday.day + 6),
    count: 7,
  );
}

/// Every day of [month], first day first.
List<PeriodTotals> monthDays(Iterable<RunSummary> runs, DateTime month) {
  final last = DateTime(month.year, month.month + 1, 0);
  return aggregate(runs, Period.day, now: last, count: last.day);
}

/// Color intensity of an active day in the calendar: 0.35 for the smallest
/// distance of the month, 1.0 for the largest, linear in between.
/// Returns 0 for a day without any distance.
double dayIntensity(double meters, double minMeters, double maxMeters) {
  if (meters <= 0) return 0;
  if (maxMeters <= minMeters) return 1;
  return 0.35 + 0.65 * (meters - minMeters) / (maxMeters - minMeters);
}

/// Medals won by each run: run id → {distance km → rank}, where rank 0 is
/// gold (fastest time ever over that distance), 1 silver and 2 bronze.
/// Ties go to the earliest run.
Map<int, Map<int, int>> medalRanks(Iterable<RunSummary> runs) {
  final medals = <int, Map<int, int>>{};
  for (final km in bestEffortDistancesKm) {
    final contenders =
        [
          for (final run in runs)
            if (run.bestEfforts[km] case final time?)
              (time, run.startTime, run.id),
        ]..sort((a, b) {
          final byTime = a.$1.compareTo(b.$1);
          return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
        });
    for (var rank = 0; rank < contenders.length && rank < 3; rank++) {
      (medals[contenders[rank].$3] ??= {})[km] = rank;
    }
  }
  return medals;
}
