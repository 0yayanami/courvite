import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:courvite/data/backup.dart';
import 'package:courvite/models/run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 9, 19, 8);
  final run = BackupRun(
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    duration: const Duration(minutes: 28),
    distanceMeters: 5012.5,
    points: [
      TrackPoint(lat: 48.8566, lon: 2.3522, time: start, altitude: 60, accuracy: 4),
      TrackPoint(
        lat: 48.8576,
        lon: 2.3532,
        time: start.add(const Duration(seconds: 30, milliseconds: 250)),
        segment: 1,
      ),
    ],
  );

  test('round trip keeps every run and point', () {
    final decoded = Backup.decode(Backup.encode([run, run]));
    expect(decoded, hasLength(2));
    final r = decoded.first;
    expect(r.startTime, run.startTime);
    expect(r.endTime, run.endTime);
    expect(r.duration, run.duration);
    expect(r.distanceMeters, run.distanceMeters);
    expect(r.points, hasLength(2));
    expect(r.points[0].altitude, 60);
    expect(r.points[0].accuracy, 4);
    expect(r.points[1].lat, 48.8576);
    expect(r.points[1].segment, 1);
    expect(r.points[1].altitude, isNull);
    expect(r.points[1].time, run.points[1].time);
  });

  test('backups are gzip-compressed JSON', () {
    final json = jsonDecode(utf8.decode(gzip.decode(Backup.encode([run]))));
    expect(json['format'], 'courvite-backup');
    expect(json['version'], 1);
  });

  Uint8List gz(Object json) =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));

  test('invalid files are rejected with a readable message', () {
    expect(
      () => Backup.decode(Uint8List.fromList(utf8.encode('hello'))),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Backup.decode(gz({'format': 'other'})),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Backup.decode(gz({'format': 'courvite-backup', 'version': 99})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
    expect(
      () => Backup.decode(
        gz({
          'format': 'courvite-backup',
          'version': 1,
          'runs': [
            {'start': 'x'},
          ],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
