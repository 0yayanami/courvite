import 'dart:math' as math;

import '../models/run.dart';

/// Great-circle distance in meters between two coordinates.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371008.8;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadius * math.asin(math.sqrt(a));
}

/// Incrementally computes distance, active time and kilometer splits from a
/// stream of GPS fixes. Used both live while running and to rebuild the stats
/// of a stored run from its points, so both always agree.
class RunStatsBuilder {
  /// Fixes less accurate than this are ignored.
  static const maxAccuracyMeters = 25.0;

  /// Movements shorter than this are treated as GPS jitter.
  static const minStepMeters = 3.0;

  /// Faster than any human runner: such a jump is a GPS glitch.
  static const maxSpeedMps = 12.0;

  TrackPoint? _last;
  double _distance = 0;
  int _activeMs = 0;
  final List<int> _splitEndsMs = [];

  /// Recent (activeMs, distance) samples for the current pace.
  final List<(int, double)> _recent = [];

  /// Cumulative (activeMs, distance) at every accepted point, for best efforts.
  final List<(int, double)> _cumulative = [];

  final _elevation = ElevationAccumulator();

  double get distanceMeters => _distance;

  /// Time covered by the accepted points, excluding gaps between segments.
  Duration get activeTime => Duration(milliseconds: _activeMs);
  TrackPoint? get lastPoint => _last;

  /// Adds a fix. Returns true when the point was accepted as part of the track
  /// (and should therefore be stored and drawn).
  bool add(TrackPoint p) {
    if (p.accuracy != null && p.accuracy! > maxAccuracyMeters) return false;
    final last = _last;
    if (last == null || last.segment != p.segment) {
      _last = p;
      _recent.clear();
      if (_cumulative.isEmpty) _cumulative.add((0, 0));
      _elevation.add(p.altitude);
      return true;
    }
    final dtMs = p.time.difference(last.time).inMilliseconds;
    if (dtMs <= 0) return false;
    final d = haversineMeters(last.lat, last.lon, p.lat, p.lon);
    if (d < minStepMeters) return false;
    if (d / (dtMs / 1000) > maxSpeedMps) return false;

    final prevDistance = _distance;
    final prevMs = _activeMs;
    _distance += d;
    _activeMs += dtMs;
    // Record the (interpolated) moment each kilometer boundary was crossed.
    var nextKm = (_splitEndsMs.length + 1) * 1000.0;
    while (_distance >= nextKm) {
      final ratio = (nextKm - prevDistance) / d;
      _splitEndsMs.add(prevMs + (dtMs * ratio).round());
      nextKm += 1000;
    }
    _recent.add((_activeMs, _distance));
    _recent.removeWhere((s) => _activeMs - s.$1 > 30000);
    _cumulative.add((_activeMs, _distance));
    _elevation.add(p.altitude);
    _last = p;
    return true;
  }

  /// Pace over roughly the last 30 seconds, in seconds per km.
  double? get currentPaceSecPerKm {
    if (_recent.length < 2) return null;
    final first = _recent.first;
    final last = _recent.last;
    return paceFor(
      last.$2 - first.$2,
      Duration(milliseconds: last.$1 - first.$1),
    );
  }

  /// Completed kilometer splits, plus the ongoing partial one if [total] is
  /// given. [total] is the authoritative active time (e.g. the stopwatch) so
  /// that splits add up to the displayed duration.
  List<KmSplit> splits({Duration? total}) {
    final result = <KmSplit>[];
    var prev = 0;
    for (var i = 0; i < _splitEndsMs.length; i++) {
      result.add(
        KmSplit(
          index: i + 1,
          distanceMeters: 1000,
          duration: Duration(milliseconds: _splitEndsMs[i] - prev),
        ),
      );
      prev = _splitEndsMs[i];
    }
    final rest = _distance - _splitEndsMs.length * 1000;
    if (total != null && rest >= 10) {
      final ms = math.max(0, total.inMilliseconds - prev);
      result.add(
        KmSplit(
          index: _splitEndsMs.length + 1,
          distanceMeters: rest,
          duration: Duration(milliseconds: ms),
        ),
      );
    }
    return result;
  }

  double get elevationGainMeters => _elevation.gain;
  double get elevationLossMeters => _elevation.loss;

  /// Fastest time over any continuous [meters] of the run (pauses excluded),
  /// or null if the run is shorter than that.
  Duration? bestEffort(double meters) {
    final c = _cumulative;
    if (c.isEmpty || c.last.$2 < meters) return null;
    int? best;
    var i = 0;
    for (var j = 1; j < c.length; j++) {
      final startDistance = c[j].$2 - meters;
      if (startDistance < 0) continue;
      // Move i to the last sample at or before the start of the window.
      while (c[i + 1].$2 <= startDistance) {
        i++;
      }
      final (t0, d0) = c[i];
      final (t1, d1) = c[i + 1];
      final startMs = d1 == d0
          ? t0.toDouble()
          : t0 + (t1 - t0) * (startDistance - d0) / (d1 - d0);
      final ms = (c[j].$1 - startMs).round();
      if (best == null || ms < best) best = ms;
    }
    return best == null ? null : Duration(milliseconds: best);
  }

  /// Best efforts for all [bestEffortDistancesKm].
  Map<int, Duration> bestEfforts() => {
    for (final km in bestEffortDistancesKm) km: ?bestEffort(km * 1000.0),
  };

  static RunStatsBuilder fromPoints(Iterable<TrackPoint> points) {
    final b = RunStatsBuilder();
    points.forEach(b.add);
    return b;
  }
}

/// Cumulative elevation gain/loss from noisy GPS altitudes: altitudes are
/// averaged over a few fixes, and a change only counts once it exceeds a
/// threshold, so random jitter around a flat road adds nothing.
class ElevationAccumulator {
  static const window = 5;
  static const thresholdMeters = 3.0;

  final List<double> _recent = [];
  double? _reference;
  double gain = 0;
  double loss = 0;

  void add(double? altitude) {
    if (altitude == null) return;
    _recent.add(altitude);
    if (_recent.length > window) _recent.removeAt(0);
    final smoothed = _recent.reduce((a, b) => a + b) / _recent.length;
    final ref = _reference;
    if (ref == null) {
      _reference = smoothed;
    } else if (smoothed - ref >= thresholdMeters) {
      gain += smoothed - ref;
      _reference = smoothed;
    } else if (ref - smoothed >= thresholdMeters) {
      loss += ref - smoothed;
      _reference = smoothed;
    }
  }
}
