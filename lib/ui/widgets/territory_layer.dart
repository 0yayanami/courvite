import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../tracking/territory.dart';
import '../theme.dart';

/// Map layer filling captured territory cells in yellow.
///
/// Horizontally adjacent cells are merged into strips, so even a large
/// territory is only a few hundred rectangles to draw.
class TerritoryLayer extends StatefulWidget {
  const TerritoryLayer({super.key, required this.cells});

  final List<int> cells;

  /// Geographic bounds of [cells], or null if empty.
  static LatLngBounds? boundsOf(List<int> cells) {
    if (cells.isEmpty) return null;
    var minX = 1 << 30, maxX = -1, minY = 1 << 30, maxY = -1;
    for (final c in cells) {
      final x = Territory.keyX(c), y = Territory.keyY(c);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    return LatLngBounds(
      LatLng(Territory.latOfRow(maxY + 1), Territory.lonOfColumn(minX)),
      LatLng(Territory.latOfRow(minY), Territory.lonOfColumn(maxX + 1)),
    );
  }

  @override
  State<TerritoryLayer> createState() => _TerritoryLayerState();
}

class _TerritoryLayerState extends State<TerritoryLayer> {
  /// (top-left, bottom-right) corners of each strip.
  late List<(LatLng, LatLng)> _strips;

  @override
  void initState() {
    super.initState();
    _strips = _buildStrips(widget.cells);
  }

  @override
  void didUpdateWidget(TerritoryLayer old) {
    super.didUpdateWidget(old);
    if (old.cells != widget.cells) _strips = _buildStrips(widget.cells);
  }

  static List<(LatLng, LatLng)> _buildStrips(List<int> cells) {
    final sorted = [...cells]
      ..sort((a, b) {
        final byRow = Territory.keyY(a).compareTo(Territory.keyY(b));
        return byRow != 0
            ? byRow
            : Territory.keyX(a).compareTo(Territory.keyX(b));
      });
    final strips = <(LatLng, LatLng)>[];
    var i = 0;
    while (i < sorted.length) {
      final y = Territory.keyY(sorted[i]);
      final x0 = Territory.keyX(sorted[i]);
      var x1 = x0;
      while (i + 1 < sorted.length &&
          Territory.keyY(sorted[i + 1]) == y &&
          Territory.keyX(sorted[i + 1]) == x1 + 1) {
        x1++;
        i++;
      }
      strips.add((
        LatLng(Territory.latOfRow(y), Territory.lonOfColumn(x0)),
        LatLng(Territory.latOfRow(y + 1), Territory.lonOfColumn(x1 + 1)),
      ));
      i++;
    }
    return strips;
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        painter: _TerritoryPainter(camera, _strips),
        size: Size.infinite,
      ),
    );
  }
}

class _TerritoryPainter extends CustomPainter {
  _TerritoryPainter(this.camera, this.strips);

  final MapCamera camera;
  final List<(LatLng, LatLng)> strips;

  @override
  void paint(Canvas canvas, Size size) {
    // One path, so overlapping strip edges don't blend twice.
    final path = Path();
    for (final (topLeft, bottomRight) in strips) {
      path.addRect(
        Rect.fromPoints(
          camera.getOffsetFromOrigin(topLeft),
          camera.getOffsetFromOrigin(bottomRight),
        ).inflate(0.3),
      );
    }
    canvas.drawPath(
      path,
      Paint()..color = AppColors.volt.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_TerritoryPainter old) =>
      old.camera != camera || old.strips != strips;
}
