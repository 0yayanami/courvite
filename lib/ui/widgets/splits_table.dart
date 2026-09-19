import 'package:flutter/material.dart';

import '../../models/run.dart';
import '../format.dart';
import '../theme.dart';

/// Per-kilometer splits with a bar showing each split's relative speed.
class SplitsTable extends StatelessWidget {
  const SplitsTable({super.key, required this.splits});

  final List<KmSplit> splits;

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Panel(
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Splits appear after your first kilometer.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final paces = splits
        .where((s) => !s.isPartial)
        .map((s) => s.paceSecPerKm)
        .whereType<double>();
    final all = splits.map((s) => s.paceSecPerKm).whereType<double>();
    final fastest = paces.isEmpty
        ? null
        : paces.reduce((a, b) => a < b ? a : b);
    final minPace = all.isEmpty ? null : all.reduce((a, b) => a < b ? a : b);
    final maxPace = all.isEmpty ? null : all.reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text('KM', style: labelStyle())),
                SizedBox(width: 72, child: Text('PACE', style: labelStyle())),
              ],
            ),
          ),
          for (final s in splits)
            _SplitRow(
              split: s,
              isFastest:
                  !s.isPartial && s.paceSecPerKm == fastest && paces.length > 1,
              fraction: _fraction(s.paceSecPerKm, minPace, maxPace),
            ),
        ],
      ),
    );
  }

  /// Fastest split gets a full bar, slowest a 30% one.
  static double _fraction(double? pace, double? fastest, double? slowest) {
    if (pace == null || fastest == null || slowest == null) return 0;
    if (slowest == fastest) return 1;
    return (1 - 0.7 * (pace - fastest) / (slowest - fastest)).clamp(0.0, 1.0);
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.split,
    required this.isFastest,
    required this.fraction,
  });

  final KmSplit split;
  final bool isFastest;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final km = split.isPartial
        ? (split.distanceMeters / 1000).toStringAsFixed(2)
        : '${split.index}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(km, style: numberStyle(20, color: AppColors.muted)),
          ),
          SizedBox(
            width: 72,
            child: Text(formatPace(split.paceSecPerKm), style: numberStyle(22)),
          ),
          Expanded(
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: isFastest ? AppColors.ink : AppColors.volt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 6),
                  child: isFastest
                      ? const Icon(
                          Icons.bolt_rounded,
                          size: 18,
                          color: AppColors.volt,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
