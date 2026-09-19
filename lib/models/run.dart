/// A single GPS fix recorded during a run.
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.time,
    this.segment = 0,
    this.altitude,
    this.accuracy,
  });

  final double lat;
  final double lon;
  final DateTime time;

  /// Index of the continuous (un-paused) stretch this point belongs to.
  /// Distance and time are never accumulated across two segments.
  final int segment;
  final double? altitude;

  /// Horizontal accuracy in meters, as reported by the location provider.
  final double? accuracy;

  TrackPoint copyWith({int? segment}) => TrackPoint(
    lat: lat,
    lon: lon,
    time: time,
    segment: segment ?? this.segment,
    altitude: altitude,
    accuracy: accuracy,
  );
}

/// Distances (km) for which best efforts are tracked and medals awarded.
const bestEffortDistancesKm = [1, 2, 5, 10];

/// Summary of a stored run, as listed in the history.
class RunSummary {
  const RunSummary({
    required this.id,
    required this.startTime,
    required this.duration,
    required this.distanceMeters,
    this.endTime,
    this.bestEfforts = const {},
    this.elevationGainMeters,
    this.elevationLossMeters,
    this.capturedM2 = 0,
  });

  final int id;
  final DateTime startTime;
  final DateTime? endTime;

  /// Active time, excluding pauses.
  final Duration duration;
  final double distanceMeters;

  /// Fastest time over any continuous 1, 2, 5 and 10 km of the run, keyed by
  /// km. Only distances the run actually covered are present.
  final Map<int, Duration> bestEfforts;

  final double? elevationGainMeters;
  final double? elevationLossMeters;

  /// Area enclosed by the loops of this run (see Territory), in m².
  final double capturedM2;

  /// Average pace in seconds per kilometer, or null when no distance was covered.
  double? get paceSecPerKm => paceFor(distanceMeters, duration);
}

/// One kilometer split (or the final partial split).
class KmSplit {
  const KmSplit({
    required this.index,
    required this.distanceMeters,
    required this.duration,
  });

  /// 1-based split number.
  final int index;

  /// 1000 for full splits, less for the final partial split.
  final double distanceMeters;
  final Duration duration;

  bool get isPartial => distanceMeters < 999.5;

  double? get paceSecPerKm => paceFor(distanceMeters, duration);
}

double? paceFor(double distanceMeters, Duration duration) {
  if (distanceMeters < 1) return null;
  return duration.inMilliseconds / 1000 / (distanceMeters / 1000);
}
