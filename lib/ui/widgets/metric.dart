import 'package:flutter/material.dart';

import '../theme.dart';

/// A scoreboard-style number with a small uppercase label underneath.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.size = 34,
    this.color = AppColors.ink,
    this.labelColor = AppColors.muted,
    this.alignment = CrossAxisAlignment.center,
  });

  final String value;
  final String label;
  final String? unit;
  final double size;
  final Color color;
  final Color labelColor;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: numberStyle(size, color: color),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: numberStyle(size * 0.4, color: labelColor),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          style: labelStyle(color: labelColor, size: 11),
        ),
      ],
    );
  }
}
