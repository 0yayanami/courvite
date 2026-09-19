import 'package:courvite/models/run.dart';
import 'package:courvite/tracking/run_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// Meters per degree of latitude (on the sphere used by haversineMeters).
const _mPerDegLat = 6371008.8 * 3.141592653589793 / 180;

final _t0 = DateTime(2026, 9, 19, 8);

/// A point [meters] north of the origin, [seconds] after [_t0].
TrackPoint _pt(
  double meters,
  int seconds, {
  int segment = 0,
  double accuracy = 5,
  double? altitude,
}) => TrackPoint(
  lat: 45 + meters / _mPerDegLat,
  lon: 5,
  time: _t0.add(Duration(seconds: seconds)),
  segment: segment,
  accuracy: accuracy,
  altitude: altitude,
);

extension on TrackPoint {
  TrackPoint copyWithTime(DateTime time) => TrackPoint(
    lat: lat,
    lon: lon,
    time: time,
    segment: segment,
    accuracy: accuracy,
  );
}

void main() {
  test('constant pace run produces exact kilometer splits', () {
    // 2.5 km at 5:00 /km, one fix every 10 m (3 s per 10 m).
    final b = RunStatsBuilder();
    for (var i = 0; i <= 250; i++) {
      expect(b.add(_pt(i * 10.0, i * 3)), isTrue);
    }
    expect(b.distanceMeters, closeTo(2500, 0.5));
    expect(b.activeTime, const Duration(seconds: 750));

    final splits = b.splits(total: b.activeTime);
    expect(splits.map((s) => s.index), [1, 2, 3]);
    expect(splits[0].duration.inSeconds, closeTo(300, 1));
    expect(splits[1].duration.inSeconds, closeTo(300, 1));
    expect(splits[2].isPartial, isTrue);
    expect(splits[2].distanceMeters, closeTo(500, 0.5));
    expect(splits[2].paceSecPerKm, closeTo(300, 1));
  });

  test('inaccurate fixes, jitter and GPS jumps are ignored', () {
    final b = RunStatsBuilder();
    expect(b.add(_pt(0, 0)), isTrue);
    expect(b.add(_pt(50, 10, accuracy: 60)), isFalse, reason: 'inaccurate');
    expect(b.add(_pt(1, 11)), isFalse, reason: 'jitter');
    expect(b.add(_pt(500, 12)), isFalse, reason: 'too fast');
    expect(b.add(_pt(30, 20)), isTrue);
    expect(b.distanceMeters, closeTo(30, 0.1));
    expect(b.activeTime, const Duration(seconds: 20));
  });

  test('no distance or time is counted across a pause', () {
    final b = RunStatsBuilder();
    b.add(_pt(0, 0));
    b.add(_pt(100, 30));
    // Resumed 10 minutes later, 400 m away.
    b.add(_pt(500, 630, segment: 1));
    b.add(_pt(600, 660, segment: 1));
    expect(b.distanceMeters, closeTo(200, 0.1));
    expect(b.activeTime, const Duration(seconds: 60));
  });

  test('pace formatting helper', () {
    expect(paceFor(0, const Duration(minutes: 5)), isNull);
    expect(paceFor(2000, const Duration(minutes: 10)), 300);
  });

  test('best effort finds the fastest stretch anywhere in the run', () {
    // 3 km: first km at 6:00, second at 4:00, third at 5:00; fix every 10 m.
    final b = RunStatsBuilder();
    var t = 0.0;
    for (var i = 0; i <= 300; i++) {
      if (i > 0) t += i <= 100 ? 3.6 : (i <= 200 ? 2.4 : 3.0);
      b.add(
        _pt(
          i * 10.0,
          0,
        ).copyWithTime(_t0.add(Duration(milliseconds: (t * 1000).round()))),
      );
    }
    expect(b.bestEffort(1000)!.inMilliseconds, closeTo(240000, 50));
    // Best 2 km is km 2 + km 3 (4:00 + 5:00), not km 1 + km 2.
    expect(b.bestEffort(2000)!.inMilliseconds, closeTo(540000, 50));
    expect(b.bestEffort(5000), isNull);
    expect(b.bestEfforts().keys, [1, 2]);
  });

  test('best effort ignores the time spent paused', () {
    final b = RunStatsBuilder();
    for (var i = 0; i <= 50; i++) {
      b.add(_pt(i * 10.0, i * 3));
    }
    // 10 minute pause, then another 500 m at the same pace.
    for (var i = 0; i <= 50; i++) {
      b.add(_pt(600 + i * 10.0, 750 + i * 3, segment: 1));
    }
    expect(b.distanceMeters, closeTo(1000, 0.5));
    expect(b.bestEffort(1000)!.inSeconds, closeTo(300, 1));
  });

  test('elevation ignores jitter but counts real climbs', () {
    final flat = ElevationAccumulator();
    for (var i = 0; i < 200; i++) {
      flat.add(100 + (i.isEven ? 2.0 : -2.0));
    }
    expect(flat.gain, 0);
    expect(flat.loss, 0);

    final hill = ElevationAccumulator();
    for (var i = 0; i <= 100; i++) {
      hill.add(100 + i * 0.5); // climb 50 m
    }
    for (var i = 0; i <= 60; i++) {
      hill.add(150 - i * 0.5); // descend 30 m
    }
    expect(hill.gain, closeTo(50, 4));
    expect(hill.loss, closeTo(30, 4));
  });

  test('elevation is unknown when the GPS gave no altitude', () {
    final b = RunStatsBuilder();
    for (var i = 0; i <= 50; i++) {
      b.add(_pt(i * 10.0, i * 3));
    }
    expect(b.elevationGainMeters, isNull);
    expect(b.elevationLossMeters, isNull);

    final withAltitude = RunStatsBuilder();
    for (var i = 0; i <= 50; i++) {
      withAltitude.add(_pt(i * 10.0, i * 3, altitude: 80));
    }
    expect(withAltitude.elevationGainMeters, 0);
  });

  test('current pace slows down, then disappears, when standing still', () {
    final b = RunStatsBuilder();
    for (var i = 0; i <= 20; i++) {
      b.add(_pt(i * 10.0, i * 3)); // 5:00 /km
    }
    expect(b.currentPaceSecPerKm, closeTo(300, 1));
    // Stopped at a red light: fixes keep coming at the same place.
    for (var s = 61; s <= 75; s++) {
      b.add(_pt(200, s));
    }
    expect(b.currentPaceSecPerKm, greaterThan(400));
    for (var s = 76; s <= 110; s++) {
      b.add(_pt(200, s));
    }
    expect(b.currentPaceSecPerKm, isNull);
    // Running again.
    for (var i = 1; i <= 12; i++) {
      b.add(_pt(200 + i * 10.0, 110 + i * 3));
    }
    expect(b.currentPaceSecPerKm, lessThan(700));
  });
}
