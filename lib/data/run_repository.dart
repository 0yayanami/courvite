import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/run.dart';
import '../tracking/run_stats.dart';
import '../tracking/territory.dart';
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
      version: 3,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, from, to) async {
        if (from < 2) await _addStatsColumns(db);
        if (from < 3) await _addTerritory(db);
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
        await _addTerritory(db);
      },
    );
    final repo = RunRepository._(db);
    await repo._recoverUnfinishedRuns();
    // Not awaited: with many runs this can take a while, and the app should
    // open right away. Stats fill in as runs are processed.
    unawaited(repo._backfillStats());
    return repo;
  }

  /// Bump to recompute the derived stats of every stored run on next launch.
  static const _statsVersion = 3;

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

  /// Grid cells (see [Territory]) captured by each run. A cell captured by
  /// several runs has several rows; totals count it once.
  static Future<void> _addTerritory(Database db) async {
    await db.execute('ALTER TABLE runs ADD COLUMN captured_m2 REAL');
    await db.execute('''
      CREATE TABLE run_cells (
        cell INTEGER NOT NULL,
        run_id INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
        area_m2 REAL NOT NULL,
        PRIMARY KEY (cell, run_id)
      ) WITHOUT ROWID''');
    await db.execute('CREATE INDEX run_cells_by_run ON run_cells(run_id)');
  }

  /// Saves everything derived from a run's points: best efforts, elevation
  /// and captured territory, plus any [extra] columns of the run.
  Future<void> _saveDerived(
    int runId,
    RunStatsBuilder stats,
    List<TrackPoint> points, [
    Map<String, Object?> extra = const {},
  ]) async {
    // Flood-filling the grid can take a moment on long runs: off the UI thread.
    final cells = await compute(Territory.capture, points);
    final efforts = stats.bestEfforts();
    await _db.transaction((txn) async {
      await txn.update(
        'runs',
        {
          ...extra,
          for (final km in bestEffortDistancesKm)
            _bestColumn(km): efforts[km]?.inMilliseconds,
          'elev_gain_m': stats.elevationGainMeters,
          'elev_loss_m': stats.elevationLossMeters,
          'captured_m2': Territory.areaM2(cells),
          'stats_version': _statsVersion,
        },
        where: 'id = ?',
        whereArgs: [runId],
      );
      await txn.delete('run_cells', where: 'run_id = ?', whereArgs: [runId]);
      final batch = txn.batch();
      for (final cell in cells) {
        batch.insert('run_cells', {
          'cell': cell,
          'run_id': runId,
          'area_m2': Territory.cellAreaM2(Territory.keyY(cell)),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void>? _backfill;

  /// Computes the derived stats of runs saved before they existed, or of
  /// imported runs. Runs in the background; concurrent calls share one pass,
  /// which keeps going until no run is left behind.
  Future<void> _backfillStats() =>
      _backfill ??= _runBackfill().whenComplete(() => _backfill = null);

  Future<void> _runBackfill() async {
    final failed = <int>{};
    var sinceNotify = 0;
    try {
      while (true) {
        final rows = await _db.query(
          'runs',
          columns: ['id'],
          where:
              'end_time IS NOT NULL AND stats_version < ? '
              'AND id NOT IN (${failed.join(',')})',
          whereArgs: [_statsVersion],
          orderBy: 'start_time DESC', // Recent runs matter most: do them first.
          limit: 20,
        );
        if (rows.isEmpty) break;
        for (final row in rows) {
          final id = row['id'] as int;
          try {
            final points = await loadPoints(id);
            await _saveDerived(id, RunStatsBuilder.fromPoints(points), points);
          } on Object catch (e) {
            // E.g. the run was deleted meanwhile. Don't retry it in this pass.
            debugPrint('Could not update stats of run $id: $e');
            failed.add(id);
          }
          if (++sinceNotify >= 10) {
            sinceNotify = 0;
            notifyListeners();
          }
        }
      }
    } on Object catch (e) {
      // Nobody awaits this pass: log instead of leaving an uncaught error.
      // Remaining runs are picked up by the next pass (next import or launch).
      debugPrint('Stats backfill stopped: $e');
    } finally {
      if (sinceNotify > 0) notifyListeners();
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
          points: points,
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
    required List<TrackPoint> points,
  }) async {
    await _saveDerived(runId, stats, points, {
      'end_time': endTime.millisecondsSinceEpoch,
      'duration_ms': duration.inMilliseconds,
      'distance_m': stats.distanceMeters,
    });
    notifyListeners();
  }

  /// Total captured territory in m², each cell counted once.
  Future<double> territoryM2() async {
    final rows = await _db.rawQuery(
      'SELECT SUM(area_m2) AS a FROM '
      '(SELECT MAX(area_m2) AS area_m2 FROM run_cells GROUP BY cell)',
    );
    return (rows.first['a'] as num?)?.toDouble() ?? 0;
  }

  /// All captured cells, each once.
  Future<List<int>> territoryCells() async {
    final rows = await _db.rawQuery('SELECT DISTINCT cell FROM run_cells');
    return [for (final r in rows) r['cell'] as int];
  }

  Future<List<int>> runCells(int runId) async {
    final rows = await _db.query(
      'run_cells',
      columns: ['cell'],
      where: 'run_id = ?',
      whereArgs: [runId],
    );
    return [for (final r in rows) r['cell'] as int];
  }

  /// Area of [runId]'s capture that no earlier run had captured, in m².
  Future<double> newTerritoryM2(int runId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT SUM(c.area_m2) AS a FROM run_cells c
      WHERE c.run_id = ? AND NOT EXISTS (
        SELECT 1 FROM run_cells o JOIN runs r ON r.id = o.run_id
        WHERE o.cell = c.cell AND o.run_id != c.run_id
          AND r.start_time < (SELECT start_time FROM runs WHERE id = ?)
      )''',
      [runId, runId],
    );
    return (rows.first['a'] as num?)?.toDouble() ?? 0;
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
    notifyListeners();
    unawaited(_backfillStats()); // Best efforts, territory… fill in shortly.
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
    capturedM2: (r['captured_m2'] as num?)?.toDouble() ?? 0,
  );
}
