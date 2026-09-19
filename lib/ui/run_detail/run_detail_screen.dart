import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/activity_stats.dart';
import '../../data/run_repository.dart';
import '../../models/run.dart';
import '../../tracking/run_stats.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/medal.dart';
import '../widgets/metric.dart';
import '../widgets/run_map.dart';
import '../widgets/splits_table.dart';

class _RunDetail {
  _RunDetail(this.run, this.points, this.medals)
    : splits = RunStatsBuilder.fromPoints(points).splits(total: run.duration);

  final RunSummary run;
  final List<TrackPoint> points;
  final List<KmSplit> splits;

  /// Medals won by this run: distance km → rank (0 gold, 1 silver, 2 bronze).
  final Map<int, int> medals;
}

class RunDetailScreen extends StatefulWidget {
  const RunDetailScreen({super.key, required this.runId});

  final int runId;

  @override
  State<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends State<RunDetailScreen> {
  late final Future<_RunDetail?> _detail = _load();

  Future<_RunDetail?> _load() async {
    final repo = context.read<RunRepository>();
    final run = await repo.getRun(widget.runId);
    if (run == null) return null;
    return _RunDetail(
      run,
      await repo.loadPoints(widget.runId),
      medalRanks(await repo.listRuns())[run.id] ?? const {},
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DELETE RUN?'),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(fontSize: 16, color: AppColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<RunRepository>().deleteRun(widget.runId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _detail,
      builder: (context, snap) {
        final detail = snap.data;
        return Scaffold(
          body: switch (snap.connectionState) {
            ConnectionState.done when detail == null => const Center(
              child: Text('Run not found'),
            ),
            ConnectionState.done => _DetailBody(
              detail: detail!,
              onDelete: _delete,
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: AppColors.ink),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.onDelete});

  final _RunDetail detail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final run = detail.run;
    final full = detail.splits.where((s) => !s.isPartial);
    final fastest = full.isEmpty
        ? null
        : full.reduce((a, b) => a.paceSecPerKm! <= b.paceSecPerKm! ? a : b);
    final top = MediaQuery.paddingOf(context).top;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: 360 + top,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  child: Stack(
                    children: [
                      RunRouteMap(points: detail.points, interactive: false),
                      Positioned.fill(
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: detail.points.isEmpty
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          _FullMapScreen(points: detail.points),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: top + 8,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    _CircleAction(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    _CircleAction(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
              if (detail.points.isNotEmpty)
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.open_in_full_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'EXPAND',
                          style: labelStyle(color: Colors.white, size: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDateTime(run.startTime).toUpperCase(),
                style: labelStyle(),
              ),
              const SizedBox(height: 4),
              Text(
                runTitle(run.startTime).toUpperCase(),
                style: headlineStyle(40),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Panel(
            color: AppColors.ink,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              children: [
                Metric(
                  value: formatKm(run.distanceMeters),
                  unit: 'KM',
                  label: 'Distance',
                  size: 80,
                  color: AppColors.volt,
                  labelColor: Colors.white70,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Metric(
                        value: formatDuration(run.duration),
                        label: 'Time',
                        color: Colors.white,
                        labelColor: Colors.white70,
                      ),
                    ),
                    Container(width: 1, height: 44, color: Colors.white24),
                    Expanded(
                      child: Metric(
                        value: formatPace(run.paceSecPerKm),
                        label: 'Avg pace /km',
                        color: Colors.white,
                        labelColor: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (fastest != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Panel(
              color: AppColors.volt,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: AppColors.ink),
                  const SizedBox(width: 8),
                  Text('FASTEST KM', style: labelStyle(color: AppColors.ink)),
                  const Spacer(),
                  Text('#${fastest.index}  ', style: numberStyle(22)),
                  Text(
                    formatPace(fastest.paceSecPerKm),
                    style: numberStyle(28),
                  ),
                  Text(' /KM', style: numberStyle(14)),
                ],
              ),
            ),
          ),
        if (run.elevationGainMeters != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: _ElevationTile(
                    icon: Icons.north_east_rounded,
                    meters: run.elevationGainMeters!,
                    label: 'Elev. gain',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ElevationTile(
                    icon: Icons.south_east_rounded,
                    meters: run.elevationLossMeters ?? 0,
                    label: 'Elev. loss',
                  ),
                ),
              ],
            ),
          ),
        if (run.bestEfforts.isNotEmpty) ...[
          const SectionHeader('Best efforts'),
          for (final MapEntry(key: km, value: time) in run.bestEfforts.entries)
            _BestEffortRow(km: km, time: time, rank: detail.medals[km]),
        ],
        const SectionHeader('Splits'),
        SplitsTable(splits: detail.splits),
        SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

class _ElevationTile extends StatelessWidget {
  const _ElevationTile({
    required this.icon,
    required this.meters,
    required this.label,
  });

  final IconData icon;
  final double meters;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.canvas,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Metric(
                value: '${meters.round()}',
                unit: 'M',
                label: label,
                size: 28,
                alignment: CrossAxisAlignment.start,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "2K  ·  9:41  ·  4:50 /km", with a medal when it's in the all-time top 3.
class _BestEffortRow extends StatelessWidget {
  const _BestEffortRow({
    required this.km,
    required this.time,
    required this.rank,
  });

  final int km;
  final Duration time;

  /// All-time rank for this distance (0 gold, 1 silver, 2 bronze), if any.
  final int? rank;

  static const _titles = ['ALL-TIME BEST', '2ND BEST EVER', '3RD BEST EVER'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (rank case final rank?)
              Medal(km: km, rank: rank, size: 40)
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${km}K',
                  style: numberStyle(17, color: AppColors.muted),
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(formatDuration(time), style: numberStyle(26)),
                  const SizedBox(height: 2),
                  Text(
                    rank == null ? 'BEST $km KM IN THIS RUN' : _titles[rank!],
                    style: labelStyle(
                      size: 10,
                      color: rank == null
                          ? AppColors.muted
                          : Medal.labelColors[rank!],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatPace(paceFor(km * 1000.0, time)),
              style: numberStyle(22, color: AppColors.inkSoft),
            ),
            Text(' /KM', style: numberStyle(12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _FullMapScreen extends StatelessWidget {
  const _FullMapScreen({required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ROUTE')),
      body: RunRouteMap(points: points),
    );
  }
}
