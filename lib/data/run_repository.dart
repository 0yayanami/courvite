import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/run.dart';
import '../tracking/run_stats.dart';
import 'backup.dart';

/// Local SQLite storage for runs and their GPS tracks. Nothing ever leaves
/// the device.
class RunRepository extends ChangeNotifier {
  RunRepository._(this._db);

  final Database _db;

  static Future<RunRepository> open() async {
    final path = p.join(await getDatabasesPath(), 'courvite.db');
    final db = await openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, from, to) async {
        if (from < 2) await _addStatsColumns(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            distance_m REAL NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE points (
            run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            segment INTEGER NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            altitude REAL,
            accuracy REAL,
            time INTEGER NOT NULL,
            PRIMARY KEY (run_id, seq)
          )''');
        await _addStatsColumns(db);
      },
    );
    final repo = RunRepository._(db);
    await repo._recoverUnfinishedRuns();
    await repo._backfillStats();
    return repo;
  }

  /// Bump to recompute the derived stats of every stored run on next launch.
  static const _statsVersion = 1;

  static String _bestColumn(int km) => 'best_${km}k_ms';

  static Future<void> _addStatsColumns(Database db) async {
    for (final km in bestEffortDistancesKm) {
      await db.execute(
        'ALTER TABLE runs ADD COLUMN ${_bestColumn(km)} INTEGER',
      );
    }
    await db.execute('ALTER TABLE runs ADD COLUMN elev_gain_m REAL');
    await db.execute('ALTER TABLE runs ADD COLUMN elev_loss_m REAL');
    await db.execute(
      'ALTER TABLE runs ADD COLUMN stats_version INTEGER NOT NULL DEFAULT 0',
    );
  }

  Map<String, Object?> _statsColumns(RunStatsBuilder stats) {
    final efforts = stats.bestEfforts();
    return {
      for (final km in bestEffortDistancesKm)
        _bestColumn(km): efforts[km]?.inMilliseconds,
      'elev_gain_m': stats.elevationGainMeters,
      'elev_loss_m': stats.elevationLossMeters,
      'stats_version': _statsVersion,
    };
  }

  /// Computes best efforts and elevation for runs saved before they existed.
  Future<void> _backfillStats() async {
    final rows = await _db.query(
      'runs',
      columns: ['id'],
      where: 'end_time IS NOT NULL AND stats_version < ?',
      whereArgs: [_statsVersion],
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final stats = RunStatsBuilder.fromPoints(await loadPoints(id));
      await _db.update(
        'runs',
        _statsColumns(stats),
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// A run whose end_time is null was interrupted (e.g. the app process was
  /// killed). Its points were saved as they came, so close it properly.
  Future<void> _recoverUnfinishedRuns() async {
    final rows = await _db.query(
      'runs',
      columns: ['id'],
      where: 'end_time IS NULL',
    );
    for (final row in rows) {
      final id = row['id'] as int;
      final points = await loadPoints(id);
      final stats = RunStatsBuilder.fromPoints(points);
      if (points.isEmpty || stats.distanceMeters < 10) {
        await deleteRun(id);
      } else {
        await finishRun(
          id,
          endTime: points.last.time,
          duration: stats.activeTime,
          stats: stats,
        );
      }
    }
  }

  Future<int> startRun(DateTime start) =>
      _db.insert('runs', {'start_time': start.millisecondsSinceEpoch});

  Future<void> addPoint(int runId, int seq, TrackPoint pt) =>
      _db.insert('points', _pointRow(runId, seq, pt));

  static Map<String, Object?> _pointRow(int runId, int seq, TrackPoint pt) => {
    'run_id': runId,
    'seq': seq,
    'segment': pt.segment,
    'lat': pt.lat,
    'lon': pt.lon,
    'altitude': pt.altitude,
    'accuracy': pt.accuracy,
    'time': pt.time.millisecondsSinceEpoch,
  };

  Future<void> finishRun(
    int runId, {
    required DateTime endTime,
    required Duration duration,
    required RunStatsBuilder stats,
  }) async {
    await _db.update(
      'runs',
      {
        'end_time': endTime.millisecondsSinceEpoch,
        'duration_ms': duration.inMilliseconds,
        'distance_m': stats.distanceMeters,
        ..._statsColumns(stats),
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
    notifyListeners();
  }

  /// Every finished run with its track, oldest first, for a backup.
  Future<List<BackupRun>> exportRuns() async {
    final rows = await _db.query(
      'runs',
      where: 'end_time IS NOT NULL',
      orderBy: 'start_time',
    );
    return [
      for (final r in rows)
        BackupRun(
          startTime: DateTime.fromMillisecondsSinceEpoch(
            r['start_time'] as int,
          ),
          endTime: DateTime.fromMillisecondsSinceEpoch(r['end_time'] as int),
          duration: Duration(milliseconds: r['duration_ms'] as int),
          distanceMeters: (r['distance_m'] as num).toDouble(),
          points: await loadPoints(r['id'] as int),
        ),
    ];
  }

  /// Adds the runs of a backup. Runs already on this device (same start
  /// time) are skipped, so importing the same backup twice is harmless.
  /// Returns how many runs were added and skipped.
  Future<({int added, int skipped})> importRuns(List<BackupRun> runs) async {
    var added = 0;
    var skipped = 0;
    await _db.transaction((txn) async {
      final existing = {
        for (final r in await txn.query('runs', columns: ['start_time']))
          r['start_time'] as int,
      };
      for (final run in runs) {
        final start = run.startTime.millisecondsSinceEpoch;
        if (!existing.add(start)) {
          skipped++;
          continue;
        }
        final id = await txn.insert('runs', {
          'start_time': start,
          'end_time': run.endTime.millisecondsSinceEpoch,
          'duration_ms': run.duration.inMilliseconds,
          'distance_m': run.distanceMeters,
          'stats_version': 0, // Best efforts etc. are computed below.
        });
        final batch = txn.batch();
        for (final (seq, p) in run.points.indexed) {
          batch.insert('points', _pointRow(id, seq, p));
        }
        await batch.commit(noResult: true);
        added++;
      }
    });
    await _backfillStats();
    notifyListeners();
    return (added: added, skipped: skipped);
  }

  Future<void> deleteRun(int runId) async {
    await _db.delete('runs', where: 'id = ?', whereArgs: [runId]);
    notifyListeners();
  }

  /// Finished runs, newest first.
  Future<List<RunSummary>> listRuns() async {
    final rows = await _db.query(
      'runs',
      where: 'end_time IS NOT NULL',
      orderBy: 'start_time DESC',
    );
    return rows.map(_summaryFromRow).toList();
  }

  Future<RunSummary?> getRun(int id) async {
    final rows = await _db.query('runs', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _summaryFromRow(rows.first);
  }

  Future<List<TrackPoint>> loadPoints(int runId) async {
    final rows = await _db.query(
      'points',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'seq',
    );
    return rows
        .map(
          (r) => TrackPoint(
            lat: r['lat'] as double,
            lon: r['lon'] as double,
            segment: r['segment'] as int,
            altitude: r['altitude'] as double?,
            accuracy: r['accuracy'] as double?,
            time: DateTime.fromMillisecondsSinceEpoch(r['time'] as int),
          ),
        )
        .toList();
  }

  RunSummary _summaryFromRow(Map<String, Object?> r) => RunSummary(
    id: r['id'] as int,
    startTime: DateTime.fromMillisecondsSinceEpoch(r['start_time'] as int),
    endTime: r['end_time'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['end_time'] as int),
    duration: Duration(milliseconds: r['duration_ms'] as int),
    distanceMeters: (r['distance_m'] as num).toDouble(),
    bestEfforts: {
      for (final km in bestEffortDistancesKm)
        if (r[_bestColumn(km)] case final int ms)
          km: Duration(milliseconds: ms),
    },
    elevationGainMeters: (r['elev_gain_m'] as num?)?.toDouble(),
    elevationLossMeters: (r['elev_loss_m'] as num?)?.toDouble(),
  );
}
