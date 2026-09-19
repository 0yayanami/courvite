import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../data/activity_stats.dart';
import '../../tracking/run_tracker.dart';
import '../format.dart';
import '../history/history_screen.dart';
import '../run_detail/run_detail_screen.dart';
import '../theme.dart';
import '../widgets/metric.dart';
import '../widgets/run_map.dart';
import '../widgets/splits_table.dart';

class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.visible});

  /// Whether this tab is currently shown; GPS preview only runs when it is.
  final bool visible;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _appVisible = true;

  RunTracker get _tracker => context.read<RunTracker>();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onShow: () {
        _appVisible = true;
        _syncPreview();
      },
      onHide: () {
        _appVisible = false;
        _syncPreview();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreview());
  }

  @override
  void didUpdateWidget(RunScreen old) {
    super.didUpdateWidget(old);
    if (old.visible != widget.visible) _syncPreview();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _syncPreview() {
    if (widget.visible && _appVisible) {
      _tracker.warmUp();
    } else {
      _tracker.stopPreview();
    }
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _tracker.ensurePermissions();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    HapticFeedback.heavyImpact();
    await _tracker.start();
  }

  Future<void> _finish() async {
    final tracker = _tracker;
    final tooShort = tracker.distanceMeters < 50;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FINISH RUN?'),
        content: Text(
          tooShort
              ? 'This run is very short. Save it anyway?'
              : 'Your run will be saved on this device.',
          style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'discard') {
      await tracker.discard();
      _syncPreview();
    } else if (choice == 'save') {
      final id = await tracker.stop();
      _syncPreview();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RunDetailScreen(runId: id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the run state here: each part below listens to just what it shows,
    // so the per-second tick doesn't rebuild the map.
    final idle = context.select<RunTracker, bool>(
      (t) => t.state == TrackerState.idle,
    );
    final height = MediaQuery.sizeOf(context).height;
    final panelHeight = idle ? 400.0 : height * 0.6;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              // Own layer: the per-second panel updates don't repaint the map.
              child: RepaintBoundary(
                child: _Map(showTrack: !idle, bottomInset: panelHeight),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 16,
              right: 16,
              child: Row(
                children: [const _Wordmark(), const Spacer(), const _GpsPill()],
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      color: Color(0x33000000),
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: RepaintBoundary(
                  child: idle
                      ? _IdlePanel(onStart: _start)
                      : _ActivePanel(onFinish: _finish),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live map. Rebuilds when the route grows or the runner moves by about
/// a meter, not on every tick or GPS jitter.
class _Map extends StatelessWidget {
  const _Map({required this.showTrack, required this.bottomInset});

  final bool showTrack;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final (version, lat, lon) = context.select<RunTracker, (int, int?, int?)>(
      (t) => (
        t.trackVersion,
        // ~1 m steps (1e-5°), so sub-meter noise doesn't rebuild the map.
        t.lastFix == null ? null : (t.lastFix!.latitude * 1e5).round(),
        t.lastFix == null ? null : (t.lastFix!.longitude * 1e5).round(),
      ),
    );
    final tracker = context.read<RunTracker>();
    return LiveRunMap(
      points: showTrack ? tracker.track : const [],
      trackVersion: version,
      position: lat == null ? null : LatLng(lat / 1e5, lon! / 1e5),
      bottomInset: bottomInset,
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: AppColors.volt, size: 20),
          const SizedBox(width: 2),
          Text('COURVITE', style: headlineStyle(18, color: Colors.white)),
        ],
      ),
    );
  }
}

class _GpsPill extends StatelessWidget {
  const _GpsPill();

  @override
  Widget build(BuildContext context) {
    final (label, color, fixable) = context
        .select<RunTracker, (String, Color, bool)>((t) {
          final fix = t.lastFix;
          if (t.gpsProblem != null) return ('No GPS', AppColors.danger, false);
          if (t.state == TrackerState.idle) {
            switch (t.access) {
              case GpsAccess.serviceOff:
                return ('Location off', AppColors.danger, true);
              case GpsAccess.denied:
                return ('Allow location', Colors.orange, true);
              case GpsAccess.approximate:
                return ('Precise location off', Colors.orange, true);
              case GpsAccess.ok:
                break;
            }
          }
          return switch (fix) {
            null => ('Searching GPS', Colors.orange, false),
            _ when t.hasGoodFix => (
              'GPS ±${fix.accuracy.round()} m',
              AppColors.go,
              false,
            ),
            _ when !RunTracker.hasAccuracyEstimate(fix) => (
              'GPS accuracy unknown',
              Colors.orange,
              false,
            ),
            _ => ('Weak GPS ±${fix.accuracy.round()} m', Colors.orange, false),
          };
        });
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      shadowColor: const Color(0x44000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: fixable ? () => _fix(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (fixable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fix(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<RunTracker>().requestAccess();
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 10),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _IdlePanel extends StatelessWidget {
  const _IdlePanel({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final (hasFix, access) = context.select<RunTracker, (bool, GpsAccess)>(
      (t) => (t.hasGoodFix, t.access),
    );
    return Column(
      children: [
        const _Grabber(),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: RunsLoader(
            builder: (context, runs) {
              final week = aggregate(
                runs ?? const [],
                Period.week,
                now: DateTime.now(),
                count: 1,
              ).single;
              return Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('THIS WEEK', style: labelStyle(size: 11)),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: formatKm(week.distanceMeters),
                                style: numberStyle(34),
                              ),
                              TextSpan(
                                text: ' KM',
                                style: numberStyle(16, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Metric(value: '${week.runs}', label: 'Runs', size: 26),
                    const SizedBox(width: 24),
                    Metric(
                      value: formatPace(week.paceSecPerKm),
                      label: 'Pace',
                      size: 26,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Spacer(),
        _GoButton(onPressed: onStart),
        const SizedBox(height: 14),
        Text(switch (access) {
          GpsAccess.serviceOff => 'Turn on location to record a run.',
          GpsAccess.denied => 'Courvite needs location access to track you.',
          GpsAccess.approximate => 'Courvite needs precise location.',
          GpsAccess.ok when hasFix => 'GPS locked. Let\'s go!',
          GpsAccess.ok => 'Waiting for a good GPS signal…',
        }, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
        const Spacer(),
      ],
    );
  }
}

class _GoButton extends StatelessWidget {
  const _GoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 136,
      height: 136,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.volt.withValues(alpha: 0.7),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Material(
        color: AppColors.volt,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.ink, width: 4),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 32, color: AppColors.ink),
                Text('GO', style: numberStyle(44)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivePanel extends StatelessWidget {
  const _ActivePanel({required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    // The stats change every second (time, average pace): this panel is the
    // one part of the screen that follows the ticker.
    final tracker = context.watch<RunTracker>();
    final paused = tracker.state == TrackerState.paused;
    final splits = tracker.splits.reversed.toList();
    return Column(
      children: [
        const _Grabber(),
        // Everything above the controls scrolls together, so the panel never
        // overflows on short screens or when the GPS banner is shown.
        Expanded(
          child: ShaderMask(
            // Fade the content out under the controls.
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.85, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 40),
              children: [
                Center(child: _StatusChip(paused: paused)),
                if (tracker.gpsProblem case final problem?)
                  _GpsProblemBanner(
                    message: problem,
                    onRetry: tracker.retryGps,
                  ),
                const SizedBox(height: 4),
                Metric(
                  value: formatKm(tracker.distanceMeters),
                  unit: 'KM',
                  label: 'Distance',
                  size: 96,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: Metric(
                            value: formatDuration(tracker.elapsed),
                            label: 'Time',
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Metric(
                            value: formatPace(tracker.averagePaceSecPerKm),
                            label: 'Avg /km',
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Metric(
                            value: formatPace(tracker.currentPaceSecPerKm),
                            label: 'Now /km',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionHeader('Splits'),
                SplitsTable(splits: splits),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _Controls(tracker: tracker, onFinish: onFinish),
          ),
        ),
      ],
    );
  }
}

class _GpsProblemBanner extends StatelessWidget {
  const _GpsProblemBanner({required this.message, required this.onRetry});

  final String message;
  final Future<String?> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Panel(
        color: AppColors.danger,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.location_disabled_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final error = await onRetry();
                if (error != null) {
                  messenger.showSnackBar(SnackBar(content: Text(error)));
                }
              },
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.paused});

  final bool paused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: paused ? AppColors.ink : AppColors.volt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paused ? Icons.pause_rounded : Icons.bolt_rounded,
            size: 16,
            color: paused ? AppColors.volt : AppColors.ink,
          ),
          const SizedBox(width: 4),
          Text(
            paused ? 'PAUSED' : 'RUNNING',
            style: labelStyle(
              color: paused ? AppColors.volt : AppColors.ink,
              size: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    required this.background,
    required this.foreground,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;
  final String tooltip;
  static const size = 84.0;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: Colors.black38,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.mediumImpact();
              onPressed();
            },
            child: Icon(icon, size: size * 0.45, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.tracker, required this.onFinish});

  final RunTracker tracker;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    if (tracker.state == TrackerState.running) {
      return _RoundButton(
        icon: Icons.pause_rounded,
        onPressed: tracker.pause,
        background: AppColors.ink,
        foreground: AppColors.volt,
        tooltip: 'Pause',
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: Icons.play_arrow_rounded,
          onPressed: tracker.resume,
          background: AppColors.volt,
          foreground: AppColors.ink,
          tooltip: 'Resume',
        ),
        const SizedBox(width: 28),
        _RoundButton(
          icon: Icons.stop_rounded,
          onPressed: onFinish,
          background: AppColors.ink,
          foreground: Colors.white,
          tooltip: 'Finish',
        ),
      ],
    );
  }
}
