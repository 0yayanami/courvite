import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../data/run_repository.dart';
import '../../models/run.dart';
import '../format.dart';
import '../history/history_screen.dart';
import '../theme.dart';
import '../widgets/metric.dart';
import '../widgets/run_map.dart';
import '../widgets/territory_layer.dart';
import '../widgets/topo_background.dart';

/// Everything the runner has captured by closing loops, merged.
class TerritoryView extends StatelessWidget {
  const TerritoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return RunsLoader(
      builder: (context, runs) {
        if (runs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // Keyed on the run list so it reloads whenever runs change.
        return _TerritoryContent(key: ObjectKey(runs), runs: runs);
      },
    );
  }
}

class _TerritoryContent extends StatefulWidget {
  const _TerritoryContent({super.key, required this.runs});

  final List<RunSummary> runs;

  @override
  State<_TerritoryContent> createState() => _TerritoryContentState();
}

class _TerritoryContentState extends State<_TerritoryContent> {
  late final Future<(double, List<int>)> _territory = _load();

  Future<(double, List<int>)> _load() async {
    final repo = context.read<RunRepository>();
    return (await repo.territoryM2(), await repo.territoryCells());
  }

  @override
  Widget build(BuildContext context) {
    final capturing = widget.runs.where((r) => r.capturedM2 > 0);
    final biggest = capturing.fold<double>(
      0,
      (m, r) => r.capturedM2 > m ? r.capturedM2 : m,
    );
    return FutureBuilder(
      future: _territory,
      builder: (context, snap) {
        final (totalM2, cells) = snap.data ?? (0.0, const <int>[]);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Panel(
              color: AppColors.ink,
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  const Positioned.fill(child: TopoBackground()),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR TERRITORY',
                          style: labelStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Metric(
                          value: formatArea(totalM2),
                          unit: 'KM²',
                          label: 'Captured',
                          size: 72,
                          color: AppColors.volt,
                          labelColor: Colors.white70,
                          alignment: CrossAxisAlignment.start,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Metric(
                                value: '${capturing.length}',
                                label: 'Capturing runs',
                                size: 28,
                                color: Colors.white,
                                labelColor: Colors.white70,
                                alignment: CrossAxisAlignment.start,
                              ),
                            ),
                            Expanded(
                              child: Metric(
                                value: formatArea(biggest),
                                unit: 'KM²',
                                label: 'Biggest capture',
                                size: 28,
                                color: Colors.white,
                                labelColor: Colors.white70,
                                alignment: CrossAxisAlignment.start,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (snap.hasData && cells.isEmpty)
              const _NoTerritory()
            else if (snap.hasData)
              _TerritoryMapPreview(cells: cells),
          ],
        );
      },
    );
  }
}

class _NoTerritory extends StatelessWidget {
  const _NoTerritory();

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.volt,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flag_rounded,
              size: 36,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text('CLAIM YOUR GROUND', style: headlineStyle(26)),
          const SizedBox(height: 8),
          const Text(
            'Run a loop around a block, a park or a whole neighbourhood: '
            'the land inside becomes yours.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _TerritoryMapPreview extends StatelessWidget {
  const _TerritoryMapPreview({required this.cells});

  final List<int> cells;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            TerritoryMap(cells: cells, interactive: false),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('TERRITORY')),
                        body: TerritoryMap(cells: cells),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              // Decoration only: taps go through to the map below.
              child: IgnorePointer(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Map framed on all captured cells.
class TerritoryMap extends StatelessWidget {
  const TerritoryMap({super.key, required this.cells, this.interactive = true});

  final List<int> cells;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final bounds = TerritoryLayer.boundsOf(cells)!;
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(32),
          maxZoom: 17,
        ),
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        mapTiles(),
        TerritoryLayer(cells: cells),
        mapAttribution(),
      ],
    );
  }
}
