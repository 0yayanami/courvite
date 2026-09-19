import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionActions;

import '../data/run_repository.dart';
import '../models/run.dart';
import 'run_stats.dart';

enum TrackerState { idle, running, paused }

/// Whether GPS can be used, as far as settings and permissions go.
enum GpsAccess {
  /// Not checked yet, or everything is fine.
  ok,

  /// Location is switched off on the phone.
  serviceOff,

  /// Location permission not granted (or a one-time grant that expired).
  denied,

  /// Only approximate location allowed: GPS needs precise location.
  approximate,
}

/// Records a run: listens to GPS through a foreground service (so tracking
/// continues with the screen off), computes live stats and persists accepted
/// points in small batches, so at most a few seconds are lost if the process
/// dies.
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

  /// Point writes, chained so they are stored in order. Each write handles its
  /// own failure, so one failed insert never breaks the chain.
  Future<void> _writes = Future.value();

  /// Accepted points not yet written. Writing them in batches means one disk
  /// transaction every ~10 s instead of one per second.
  final List<(int, TrackPoint)> _buffer = [];
  static const _batchSize = 10;

  /// Stops the per-second ticker while the app is hidden (screen off).
  AppLifecycleListener? _lifecycle;
  bool _appVisible = true;

  /// Bumped whenever a point is added to [track], so widgets can rebuild only
  /// when the route actually changes.
  int _trackVersion = 0;
  int get trackVersion => _trackVersion;

  /// Points whose write failed, retried when the run ends.
  final List<(int, TrackPoint)> _unsaved = [];

  /// Bumped whenever the GPS subscription is replaced, so a [warmUp] that
  /// was waiting on the platform knows it's no longer wanted.
  int _gpsGeneration = 0;

  /// When the last fix arrived (receipt time, not the fix's own timestamp).
  DateTime? _lastFixAt;

  /// Set when the location stream reports an error during a run.
  String? _gpsError;

  GpsAccess _access = GpsAccess.ok;
  GpsAccess get access => _access;

  /// Watches the location switch while previewing, so turning location on
  /// from the quick settings is picked up without leaving the app.
  StreamSubscription<ServiceStatus>? _serviceSub;

  /// A read-only view (no copy) of the recorded route.
  List<TrackPoint> get track => UnmodifiableListView(_track);
  Position? get lastFix => _lastFix;
  double get distanceMeters => _stats.distanceMeters;
  double? get currentPaceSecPerKm =>
      _state == TrackerState.running ? _stats.currentPaceSecPerKm : null;
  double? get averagePaceSecPerKm => paceFor(distanceMeters, elapsed);
  List<KmSplit> get splits => _stats.splits(total: elapsed);

  /// Whether the last fix is precise enough to be recorded.
  bool get hasGoodFix => _lastFix != null && _isAccurate(_lastFix!);

  static bool _isAccurate(Position p) =>
      hasAccuracyEstimate(p) && p.accuracy <= RunStatsBuilder.maxAccuracyMeters;

  /// A fix without an accuracy estimate comes through with accuracy 0.
  /// (`Position.hasAccuracy` can't be used: geolocator_android reports it as
  /// false even for fixes that do have an accuracy.)
  static bool hasAccuracyEstimate(Position p) => p.accuracy > 0;

  /// A problem the runner should know about while recording: the location
  /// stream failed, or no fix has arrived for a while. Null when all is well.
  String? get gpsProblem {
    if (_state == TrackerState.idle) return null;
    if (_gpsError != null) return _gpsError;
    final last = _lastFixAt;
    if (last != null &&
        DateTime.now().difference(last) > const Duration(seconds: 15)) {
      return 'No GPS signal. Distance is not being recorded.';
    }
    return null;
  }

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
    if (await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced) {
      // Asking again offers to upgrade approximate to precise location.
      await Geolocator.requestPermission();
      if (await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced) {
        await Geolocator.openAppSettings();
        return 'Courvite needs precise location to measure your runs. '
            'Turn on "Use precise location" in its location permission.';
      }
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
    final generation = ++_gpsGeneration;
    // Anything may have happened while waiting on the platform: the run may
    // have started (with its own stream) or the preview been cancelled.
    bool stale() =>
        generation != _gpsGeneration ||
        _state != TrackerState.idle ||
        _sub != null;
    _serviceSub ??= Geolocator.getServiceStatusStream().listen((_) {
      // Location switched on or off: check again from scratch.
      coolDown();
      warmUp();
    });
    final access = await _checkAccess();
    if (stale()) return;
    if (access != _access) {
      _access = access;
      notifyListeners();
    }
    if (access != GpsAccess.ok) return;
    final last = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: true,
    );
    if (stale()) return;
    _lastFix = last;
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: true,
      ),
    ).listen(_onPosition, onError: _onPreviewError);
    notifyListeners();
  }

  static Future<GpsAccess> _checkAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GpsAccess.serviceOff;
    }
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return GpsAccess.denied;
    }
    if (await Geolocator.getLocationAccuracy() ==
        LocationAccuracyStatus.reduced) {
      return GpsAccess.approximate;
    }
    return GpsAccess.ok;
  }

  void _onPreviewError(Object e) {
    debugPrint('GPS preview error: $e');
    if (_state != TrackerState.idle) return;
    // Drop the broken stream so the next warmUp() starts a fresh one.
    _sub?.cancel();
    _sub = null;
    _access = switch (e) {
      LocationServiceDisabledException() => GpsAccess.serviceOff,
      PermissionDeniedException() => GpsAccess.denied,
      _ => _access,
    };
    _lastFix = null;
    notifyListeners();
  }

  /// Asks for whatever is missing (location on, permission, precise
  /// location), then restarts the preview. Returns an error to show, if any.
  Future<String?> requestAccess() async {
    final error = await ensurePermissions();
    coolDown();
    await warmUp();
    return error;
  }

  void coolDown() {
    if (_state != TrackerState.idle) return;
    _gpsGeneration++;
    _sub?.cancel();
    _sub = null;
  }

  /// Stops everything the preview uses, including the location switch watch.
  void stopPreview() {
    coolDown();
    _serviceSub?.cancel();
    _serviceSub = null;
  }

  Future<void> start() async {
    if (_state != TrackerState.idle) return;
    stopPreview();
    final now = DateTime.now();
    _runId = await _repo.startRun(now);
    _stats = RunStatsBuilder();
    _track.clear();
    _segment = 0;
    _seq = 0;
    _accumulated = Duration.zero;
    _segmentStart = now;
    _unsaved.clear();
    _buffer.clear();
    _writes = Future.value();
    _trackVersion++;
    _state = TrackerState.running;
    _listenForRun();
    _lifecycle ??= AppLifecycleListener(
      onShow: () {
        _appVisible = true;
        _syncTicker();
        notifyListeners(); // Catch up on what happened while hidden.
      },
      onHide: () {
        _appVisible = false;
        _syncTicker();
        _flush(); // Don't keep points only in memory while in background.
      },
    );
    _syncTicker();
    notifyListeners();
  }

  /// The ticker only updates the displayed time: it runs while a run is in
  /// progress (not paused) and the app is visible.
  void _syncTicker() {
    final wanted = _state == TrackerState.running && _appVisible;
    if (wanted && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    } else if (!wanted) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// (Re)subscribes to GPS through the foreground service.
  void _listenForRun() {
    _gpsGeneration++;
    _sub?.cancel();
    _gpsError = null;
    _lastFixAt = DateTime.now(); // Grace period before "no signal".
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
    ).listen(_onPosition, onError: _onGpsError);
  }

  void _onGpsError(Object e) {
    debugPrint('GPS error: $e');
    if (_state == TrackerState.idle) return;
    _gpsError = switch (e) {
      LocationServiceDisabledException() =>
        'Location is turned off. Distance is not being recorded.',
      PermissionDeniedException() =>
        'Location permission was removed. Distance is not being recorded.',
      _ => 'GPS stopped working. Distance is not being recorded.',
    };
    notifyListeners();
  }

  /// Restarts GPS after [gpsProblem] was reported, once the runner fixed it.
  /// Returns an error message if location is still unavailable.
  Future<String?> retryGps() async {
    if (_state == TrackerState.idle) return null;
    final error = await ensurePermissions();
    if (error != null) return error;
    _listenForRun();
    notifyListeners();
    return null;
  }

  void _onPosition(Position pos) {
    _lastFix = pos;
    _lastFixAt = DateTime.now();
    _gpsError = null;
    if (_state == TrackerState.running && hasAccuracyEstimate(pos)) {
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
        _trackVersion++;
        _buffer.add((_seq++, pt));
        if (_buffer.length >= _batchSize) _flush();
      }
    }
    notifyListeners();
  }

  /// Queues the buffered points for writing, in one transaction.
  void _flush() {
    final runId = _runId;
    if (runId == null || _buffer.isEmpty) return;
    final batch = List.of(_buffer);
    _buffer.clear();
    _writes = _writes.then((_) => _save(runId, batch));
  }

  Future<void> _save(int runId, List<(int, TrackPoint)> batch) async {
    try {
      await _repo.addPoints(runId, batch);
    } on Object catch (e) {
      debugPrint('Could not save ${batch.length} points: $e');
      _unsaved.addAll(batch);
    }
  }

  void pause() {
    if (_state != TrackerState.running) return;
    _accumulated = elapsed;
    _segmentStart = null;
    _state = TrackerState.paused;
    _syncTicker();
    _flush();
    notifyListeners();
  }

  void resume() {
    if (_state != TrackerState.paused) return;
    _segment++;
    _segmentStart = DateTime.now();
    _state = TrackerState.running;
    _syncTicker();
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
      points: List.of(_track),
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
    _gpsGeneration++;
    await _sub?.cancel();
    _sub = null;
    _ticker?.cancel();
    _ticker = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _appVisible = true;
    _flush();
    await _writes;
    // Second chance for points that failed to save (e.g. a transient error).
    final runId = _runId;
    if (runId != null && _unsaved.isNotEmpty) {
      try {
        await _repo.addPoints(runId, _unsaved);
        _unsaved.clear();
      } on Object catch (e) {
        debugPrint('${_unsaved.length} points are lost: $e');
      }
    }
    _gpsError = null;
    _lastFixAt = null;
    _state = TrackerState.idle;
    _runId = null;
    _segmentStart = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _serviceSub?.cancel();
    _ticker?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
