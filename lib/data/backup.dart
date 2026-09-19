import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/run.dart';

/// A run with its full GPS track, as stored in a backup.
class BackupRun {
  const BackupRun({
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.distanceMeters,
    required this.points,
  });

  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final double distanceMeters;
  final List<TrackPoint> points;
}

/// `.courvite` backup files: gzip-compressed JSON, so they stay small and can
/// still be inspected with standard tools (`gunzip -c backup.courvite`).
///
/// ```json
/// {
///   "format": "courvite-backup",
///   "version": 1,
///   "exportedAt": "2026-09-19T15:30:00.000",
///   "runs": [{
///     "start": 1789812000000, "end": 1789813090000,   // ms since epoch
///     "durationMs": 1090000, "distanceM": 3576.2,
///     "points": [[segment, lat, lon, altitude, accuracy, ms since start], …]
///   }]
/// }
/// ```
///
/// Derived stats (splits, best efforts, elevation) are not stored: they are
/// recomputed from the points on import, so they always match the app version.
abstract final class Backup {
  static const extension = 'courvite';
  static const _format = 'courvite-backup';
  static const _version = 1;

  static Uint8List encode(List<BackupRun> runs, {DateTime? exportedAt}) {
    final json = {
      'format': _format,
      'version': _version,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'runs': [
        for (final run in runs)
          {
            'start': run.startTime.millisecondsSinceEpoch,
            'end': run.endTime.millisecondsSinceEpoch,
            'durationMs': run.duration.inMilliseconds,
            'distanceM': run.distanceMeters,
            'points': [
              for (final p in run.points)
                [
                  p.segment,
                  p.lat,
                  p.lon,
                  p.altitude,
                  p.accuracy,
                  p.time.difference(run.startTime).inMilliseconds,
                ],
            ],
          },
      ],
    };
    return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));
  }

  /// Parses a backup file. Throws a [FormatException] with a message that can
  /// be shown to the user when the file is not a valid backup.
  static List<BackupRun> decode(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } on Object {
      throw const FormatException('This is not a Courvite backup file.');
    }
    if (json is! Map || json['format'] != _format) {
      throw const FormatException('This is not a Courvite backup file.');
    }
    final version = json['version'];
    if (version is! int || version > _version) {
      throw const FormatException(
        'This backup was made by a newer version of Courvite. '
        'Update the app to import it.',
      );
    }
    try {
      return [
        for (final r in json['runs'] as List)
          _decodeRun(r as Map<String, dynamic>),
      ];
    } on Object {
      throw const FormatException('This backup file is damaged.');
    }
  }

  static BackupRun _decodeRun(Map<String, dynamic> r) {
    final start = DateTime.fromMillisecondsSinceEpoch(r['start'] as int);
    return BackupRun(
      startTime: start,
      endTime: DateTime.fromMillisecondsSinceEpoch(r['end'] as int),
      duration: Duration(milliseconds: r['durationMs'] as int),
      distanceMeters: (r['distanceM'] as num).toDouble(),
      points: [
        for (final p in r['points'] as List)
          TrackPoint(
            segment: p[0] as int,
            lat: (p[1] as num).toDouble(),
            lon: (p[2] as num).toDouble(),
            altitude: (p[3] as num?)?.toDouble(),
            accuracy: (p[4] as num?)?.toDouble(),
            time: start.add(Duration(milliseconds: p[5] as int)),
          ),
      ],
    );
  }
}
