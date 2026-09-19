import 'dart:math' as math;

import 'package:courvite/models/run.dart';
import 'package:courvite/tracking/territory.dart';
import 'package:flutter_test/flutter_test.dart';

const _lat0 = 48.8566, _lon0 = 2.3522;
const _mPerDegLat = 111320.0;
final _mPerDegLon = 111320.0 * math.cos(_lat0 * math.pi / 180);

/// A path through (east, north) offsets in meters, one point every ~5 m.
List<TrackPoint> _path(List<(double, double)> corners, {int segment = 0}) {
  final pts = <TrackPoint>[];
  var t = DateTime(2026, 9, 19, 8);
  for (var c = 0; c < corners.length - 1; c++) {
    final (x0, y0) = corners[c];
    final (x1, y1) = corners[c + 1];
    final steps = (math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2)) / 5)
        .ceil();
    for (var s = 0; s < steps; s++) {
      final x = x0 + (x1 - x0) * s / steps, y = y0 + (y1 - y0) * s / steps;
      pts.add(
        TrackPoint(
          lat: _lat0 + y / _mPerDegLat,
          lon: _lon0 + x / _mPerDegLon,
          time: t = t.add(const Duration(seconds: 2)),
          segment: segment,
        ),
      );
    }
  }
  final (x, y) = corners.last;
  pts.add(
    TrackPoint(
      lat: _lat0 + y / _mPerDegLat,
      lon: _lon0 + x / _mPerDegLon,
      time: t.add(const Duration(seconds: 2)),
      segment: segment,
    ),
  );
  return pts;
}

double _km2(List<TrackPoint> pts) =>
    Territory.areaM2(Territory.capture(pts)) / 1e6;

void main() {
  test('a 500 m square loop captures about 0.25 km²', () {
    final loop = _path([(0, 0), (500, 0), (500, 500), (0, 500), (0, 0)]);
    // Interior plus the inner half of the band around it.
    expect(_km2(loop), inInclusiveRange(0.24, 0.28));
  });

  test('a loop that almost closes still captures', () {
    // Ends 15 m from where it started, like GPS coming back to a crossroad.
    final loop = _path([(0, 0), (500, 0), (500, 500), (0, 500), (0, 15)]);
    expect(_km2(loop), greaterThan(0.24));
  });

  test('out-and-back and straight runs capture nothing', () {
    expect(_km2(_path([(0, 0), (2000, 0)])), 0);
    // Coming back 6 m beside the outbound line.
    expect(_km2(_path([(0, 0), (2000, 0), (2000, 6), (0, 6)])), 0);
  });

  test('a figure eight captures both loops', () {
    final eight = _path([
      (0, 0),
      (300, 300),
      (300, 0),
      (0, 300),
      (-300, 0),
      (-300, 300),
      (0, 0),
    ]);
    // Two triangles of 300 × 150 m / 2 … ×2 sides = 0.045 km² each.
    expect(_km2(eight), inInclusiveRange(0.08, 0.12));
  });

  test('a pause does not close a loop', () {
    final first = _path([(0, 0), (500, 0), (500, 500)]);
    final second = _path([(0, 500), (0, 0)], segment: 1);
    expect(_km2([...first, ...second]), 0);
  });

  test('the grid is global: the same loop gives the same cells', () {
    final a = Territory.capture(
      _path([(0, 0), (400, 0), (400, 400), (0, 400), (0, 0)]),
    );
    final b = Territory.capture(
      _path([(400, 400), (0, 400), (0, 0), (400, 0), (400, 400)]),
    );
    expect(b.toSet().difference(a.toSet()).length, lessThan(a.length * 0.02));
  });
}
