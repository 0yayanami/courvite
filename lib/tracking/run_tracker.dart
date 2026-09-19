import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/run_repository.dart';
import '../models/run.dart';
import 'run_stats.dart';

enum TrackerState { idle, running, paused }

/// Records a run: listens to GPS through a foreground service (so tracking
/// continues with the screen off), computes live stats and persists every
/// accepted point immediately so nothing is lost if the process dies.
class RunTracker extends ChangeNotifier {
  RunTracker(this._repo);

  final RunRepository _repo;

  TrackerState _state = TrackerState.idle;
  TrackerState get state => _state;

  int? _runId;
  int _segment = 0;
  int _seq = 0;
  RunStatsBuilder _stats = RunStatsBuilder();
  final List<TrackPoint> _track = [];
  Position? _lastFix;

  Duration _accumulated = Duration.zero;
  DateTime? _segmentStart;

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  Future<void> _writes = Future.value();

  List<TrackPoint> get track => List.unmodifiable(_track);
  Position? get lastFix => _lastFix;
  double get distanceMeters => _stats.distanceMeters;
  double? get currentPaceSecPerKm =>
      _state == TrackerState.running ? _stats.currentPaceSecPerKm : null;
  double? get averagePaceSecPerKm => paceFor(distanceMeters, elapsed);
  List<KmSplit> get splits => _stats.splits(total: elapsed);

  /// Whether the last fix is precise enough to be recorded.
  bool get hasGoodFix =>
      _lastFix != null &&
      _lastFix!.accuracy <= RunStatsBuilder.maxAccuracyMeters;

  /// Active time, excluding pauses.
  Duration get elapsed {
    final start = _segmentStart;
    if (_state != TrackerState.running || start == null) return _accumulated;
    return _accumulated + DateTime.now().difference(start);
  }

  /// Makes sure location is on and permitted. Returns an error message to show
  /// to the user, or null when everything is fine.
  Future<String?> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      return 'Please turn on location to record a run.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return 'Location permission is required to record a run.';
    }
    if (perm == LocationPermission.denied) {
      return 'Location permission is required to record a run.';
    }
    // Needed to display the ongoing-run notification; tracking works without.
    await Permission.notification.request();
    return null;
  }

  /// Listens to GPS without recording, so the runner can see the signal
  /// quality and their position before starting. Only while the app is
  /// visible: no foreground service is involved.
  Future<void> warmUp() async {
    if (_state != TrackerState.idle || _sub != null) return;
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return;
    }
    if (_state != TrackerState.idle || _sub != null) return;
    _lastFix = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: true,
    );
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: true,
      ),
    ).listen(_onPosition, onError: (Object e) => debugPrint('GPS error: $e'));
    notifyListeners();
  }

  void coolDown() {
    if (_state != TrackerState.idle) return;
    _sub?.cancel();
    _sub = null;
  }

  Future<void> start() async {
    if (_state != TrackerState.idle) return;
    coolDown();
    final now = DateTime.now();
    _runId = await _repo.startRun(now);
    _stats = RunStatsBuilder();
    _track.clear();
    _segment = 0;
    _seq = 0;
    _accumulated = Duration.zero;
    _segmentStart = now;
    _state = TrackerState.running;

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        // Raw GNSS through the platform LocationManager: no Google services.
        forceLocationManager: true,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Run in progress',
          notificationText: 'Courvite is recording your run.',
          notificationChannelName: 'Run recording',
          notificationIcon: AndroidResource(
            name: 'ic_stat_run',
            defType: 'drawable',
          ),
          setOngoing: true,
          enableWakeLock: true,
        ),
      ),
    ).listen(_onPosition, onError: (Object e) => debugPrint('GPS error: $e'));

    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  void _onPosition(Position pos) {
    _lastFix = pos;
    if (_state == TrackerState.running) {
      final pt = TrackPoint(
        lat: pos.latitude,
        lon: pos.longitude,
        // Android reports 0 with 0 accuracy when the fix has no altitude.
        altitude: pos.altitude == 0 && pos.altitudeAccuracy == 0
            ? null
            : pos.altitude,
        accuracy: pos.accuracy,
        time: pos.timestamp,
        segment: _segment,
      );
      if (_stats.add(pt)) {
        _track.add(pt);
        final runId = _runId!;
        final seq = _seq++;
        _writes = _writes.then((_) => _repo.addPoint(runId, seq, pt));
      }
    }
    notifyListeners();
  }

  void pause() {
    if (_state != TrackerState.running) return;
    _accumulated = elapsed;
    _segmentStart = null;
    _state = TrackerState.paused;
    notifyListeners();
  }

  void resume() {
    if (_state != TrackerState.paused) return;
    _segment++;
    _segmentStart = DateTime.now();
    _state = TrackerState.running;
    notifyListeners();
  }

  /// Ends the run and saves it. Returns the id of the stored run.
  Future<int> stop() async {
    final runId = _runId!;
    final duration = elapsed;
    await _teardown();
    await _repo.finishRun(
      runId,
      endTime: DateTime.now(),
      duration: duration,
      stats: _stats,
    );
    return runId;
  }

  /// Ends the run and throws it away.
  Future<void> discard() async {
    final runId = _runId!;
    await _teardown();
    await _repo.deleteRun(runId);
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    await _writes;
    _state = TrackerState.idle;
    _runId = null;
    _segmentStart = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
