import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/run.dart';

/// Territory captured by closing loops with a run.
///
/// The world is divided into a fixed grid: Web Mercator at zoom 21, i.e.
/// squares of about 19 m at the equator and 12.5 m at Paris. Because the grid
/// is global, the same patch of land is always the same cells, so captures
/// from different runs can be merged without double counting.
///
/// To capture, the path is drawn as a band [bandRadiusMeters] wide on the
/// grid; everything the band fully encloses is captured (flood fill from the
/// outside). The band closes the small gaps GPS leaves when a runner comes back
/// to their own track, while out-and-back runs enclose nothing.
abstract final class Territory {
  static const zoom = 21;
  static const _n = 1 << zoom;
  static const _earthCircumference = 40075016.686;

  /// Half-width of the band drawn along the path.
  static const bandRadiusMeters = 12.0;

  /// Enclosed pockets smaller than this are GPS artifacts, not captures.
  static const minPocketM2 = 600.0;

  /// Refuse absurdly large areas rather than allocating a huge grid.
  static const _maxGridCells = 16 * 1024 * 1024;

  static int key(int x, int y) => x * _n + y;
  static int keyX(int key) => key ~/ _n;
  static int keyY(int key) => key % _n;

  static double _mercX(double lon) => (lon + 180) / 360 * _n;
  static double _mercY(double lat) {
    final phi = lat * math.pi / 180;
    return (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2 * _n;
  }

  /// Latitude of the top edge of row [y].
  static double latOfRow(num y) {
    final n = math.pi * (1 - 2 * y / _n);
    return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  }

  static double lonOfColumn(num x) => x / _n * 360 - 180;

  /// Side of a cell in meters at [lat].
  static double cellSizeMeters(double lat) =>
      _earthCircumference * math.cos(lat * math.pi / 180) / _n;

  /// Area of the cells in row [y], in square meters.
  static double cellAreaM2(int y) {
    final size = cellSizeMeters(latOfRow(y + 0.5));
    return size * size;
  }

  static double areaM2(Iterable<int> cells) =>
      cells.fold(0, (sum, k) => sum + cellAreaM2(keyY(k)));

  /// Cells captured by a run, sorted. Pauses split the path: the gap between
  /// two segments is not part of the band.
  static Int64List capture(List<TrackPoint> points) {
    if (points.length < 3) return Int64List(0);

    final xs = [for (final p in points) _mercX(p.lon)];
    final ys = [for (final p in points) _mercY(p.lat)];
    final radius =
        bandRadiusMeters / cellSizeMeters(points.first.lat); // in cells
    final pad = radius.ceil() + 2;
    final minX = xs.reduce(math.min).floor() - pad;
    final minY = ys.reduce(math.min).floor() - pad;
    final width = xs.reduce(math.max).floor() + pad - minX + 1;
    final height = ys.reduce(math.max).floor() + pad - minY + 1;
    if (width * height > _maxGridCells) return Int64List(0);

    // 1 = band, 2 = reachable from outside, 3 = captured.
    final grid = Uint8List(width * height);

    void stamp(double cx, double cy) {
      final r2 = radius * radius;
      for (var y = (cy - radius).floor(); y <= (cy + radius).floor(); y++) {
        for (var x = (cx - radius).floor(); x <= (cx + radius).floor(); x++) {
          final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
          if (dx * dx + dy * dy <= r2) grid[(y - minY) * width + x - minX] = 1;
        }
      }
    }

    for (var i = 0; i < points.length; i++) {
      stamp(xs[i], ys[i]);
      if (i == 0 || points[i].segment != points[i - 1].segment) continue;
      final dx = xs[i] - xs[i - 1], dy = ys[i] - ys[i - 1];
      final steps = (math.sqrt(dx * dx + dy * dy) / 0.5).ceil();
      for (var s = 1; s < steps; s++) {
        stamp(xs[i - 1] + dx * s / steps, ys[i - 1] + dy * s / steps);
      }
    }

    // Flood the outside, starting from the border (always free thanks to pad).
    final queue = Queue<int>();
    void visit(int i) {
      if (grid[i] == 0) {
        grid[i] = 2;
        queue.add(i);
      }
    }

    for (var x = 0; x < width; x++) {
      visit(x);
      visit((height - 1) * width + x);
    }
    for (var y = 0; y < height; y++) {
      visit(y * width);
      visit(y * width + width - 1);
    }
    while (queue.isNotEmpty) {
      final i = queue.removeFirst();
      final x = i % width;
      if (x > 0) visit(i - 1);
      if (x < width - 1) visit(i + 1);
      if (i >= width) visit(i - width);
      if (i < width * (height - 1)) visit(i + width);
    }

    // Each enclosed pocket (still 0) that is big enough is captured, along
    // with the band cells bordering it.
    final cellArea = cellAreaM2(minY + height ~/ 2);
    final captured = <int>{};
    for (var start = 0; start < grid.length; start++) {
      if (grid[start] != 0) continue;
      final pocket = <int>[start];
      grid[start] = 3;
      for (var k = 0; k < pocket.length; k++) {
        final i = pocket[k];
        final x = i % width;
        for (final j in [
          if (x > 0) i - 1,
          if (x < width - 1) i + 1,
          i - width,
          i + width,
        ]) {
          if (grid[j] == 0) {
            grid[j] = 3;
            pocket.add(j);
          }
        }
      }
      if (pocket.length * cellArea < minPocketM2) continue;
      for (final i in pocket) {
        final x = i % width, y = i ~/ width;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final j = (y + dy) * width + x + dx;
            if (grid[j] != 2) captured.add(key(minX + x + dx, minY + y + dy));
          }
        }
      }
    }
    return Int64List.fromList(captured.toList()..sort());
  }
}
