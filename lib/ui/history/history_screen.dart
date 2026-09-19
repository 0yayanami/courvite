import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/activity_stats.dart';
import '../../data/run_repository.dart';
import '../../models/run.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/medal.dart';
import '../widgets/run_map.dart';
import '../run_detail/run_detail_screen.dart';

/// Reloads the list of finished runs whenever the repository changes.
class RunsLoader extends StatefulWidget {
  const RunsLoader({super.key, required this.builder});

  final Widget Function(BuildContext context, List<RunSummary>? runs) builder;

  @override
  State<RunsLoader> createState() => _RunsLoaderState();
}

class _RunsLoaderState extends State<RunsLoader> {
  late final RunRepository _repo = context.read<RunRepository>();
  List<RunSummary>? _runs;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _repo.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final runs = await _repo.listRuns();
    if (mounted) setState(() => _runs = runs);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _runs);
}

/// Tracks for the thumbnails, loaded once per run.
final _trackCache = <int, Future<List<TrackPoint>>>{};

/// List of past runs, grouped by month.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return RunsLoader(
      builder: (context, runs) {
        if (runs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (runs.isEmpty) return const _EmptyHistory();
        final medals = medalRanks(runs);
        final items = <Object>[];
        String? month;
        for (final run in runs) {
          final m = DateFormat.yMMMM().format(run.startTime);
          if (m != month) items.add(month = m);
          items.add(run);
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: items.length,
          itemBuilder: (context, i) => switch (items[i]) {
            final String header => SectionHeader(header),
            final RunSummary run => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _RunCard(run: run, medals: medals[run.id] ?? const {}),
            ),
            _ => const SizedBox.shrink(),
          },
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.volt,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_run_rounded,
                size: 48,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            Text('NO RUNS YET', style: headlineStyle(30)),
            const SizedBox(height: 8),
            const Text(
              'Your finished runs will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, this.medals = const {}});

  final RunSummary run;

  /// Medals won by this run: distance km → rank (0 gold, 1 silver, 2 bronze).
  final Map<int, int> medals;

  @override
  Widget build(BuildContext context) {
    final track = _trackCache.putIfAbsent(
      run.id,
      () => context.read<RunRepository>().loadPoints(run.id),
    );
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => RunDetailScreen(runId: run.id)),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FutureBuilder(
              future: track,
              builder: (context, snap) =>
                  RouteThumbnail(points: snap.data ?? const []),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDate(run.startTime).toUpperCase(),
                  style: labelStyle(size: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  runTitle(run.startTime),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 2,
                  children: [
                    _Stat(
                      icon: Icons.timer_outlined,
                      text: formatDuration(run.duration),
                    ),
                    _Stat(
                      icon: Icons.speed_rounded,
                      text: '${formatPace(run.paceSecPerKm)} /km',
                    ),
                    if (run.capturedM2 > 0)
                      _Stat(
                        icon: Icons.flag_rounded,
                        text: '${formatArea(run.capturedM2)} km²',
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatKm(run.distanceMeters), style: numberStyle(34)),
                Text('KM', style: labelStyle(size: 11)),
                if (medals.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final km in bestEffortDistancesKm)
                        if (medals[km] case final rank?)
                          Padding(
                            padding: const EdgeInsets.only(left: 3),
                            child: Medal(km: km, rank: rank, size: 24),
                          ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    );
  }
}
