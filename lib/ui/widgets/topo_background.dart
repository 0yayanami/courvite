import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative topographic contour lines, like an elevation map.
///
/// Contours are traced (marching squares) over a smooth, fixed "terrain"
/// made of a few hills, so lines never cross and the pattern is identical on
/// every build. Every fifth line is brighter, like index contours on real maps.
class TopoBackground extends StatelessWidget {
  const TopoBackground({
    super.key,
    this.color = const Color(0xFF2B2B2B),
    this.indexColor = const Color(0xFF3A3A3A),
  });

  final Color color;
  final Color indexColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TopoPainter(color, indexColor),
        size: Size.infinite,
      ),
    );
  }
}

class _Hill {
  const _Hill(this.x, this.y, this.height, this.spreadX, this.spreadY);

  /// Center, in fractions of the width and height.
  final double x, y;

  /// Negative for a basin.
  final double height;
  final double spreadX, spreadY;
}

class _TopoPainter extends CustomPainter {
  _TopoPainter(this.color, this.indexColor);

  final Color color;
  final Color indexColor;

  static const _hills = [
    _Hill(0.82, 0.22, 1.00, 0.30, 0.45),
    _Hill(0.62, 0.85, 0.70, 0.28, 0.40),
    _Hill(0.10, 0.95, 0.55, 0.25, 0.35),
    _Hill(0.35, 0.30, -0.35, 0.22, 0.30),
    _Hill(1.05, 0.95, 0.45, 0.18, 0.30),
  ];

  static const _levels = 22;
  static const _cell = 6.0;

  double _height(double u, double v) {
    var h = 0.0;
    for (final hill in _hills) {
      final dx = (u - hill.x) / hill.spreadX;
      final dy = (v - hill.y) / hill.spreadY;
      h += hill.height * math.exp(-(dx * dx + dy * dy));
    }
    // A little long-wave ripple so the lines wander naturally.
    return h + 0.06 * math.sin(u * 7.3 + v * 2.1) * math.cos(v * 5.7 - u * 1.3);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final cols = (size.width / _cell).ceil();
    final rows = (size.height / _cell).ceil();
    final field = [
      for (var j = 0; j <= rows; j++)
        [
          for (var i = 0; i <= cols; i++)
            _height(i * _cell / size.width, j * _cell / size.height),
        ],
    ];

    var lo = double.infinity, hi = -double.infinity;
    for (final row in field) {
      for (final h in row) {
        lo = math.min(lo, h);
        hi = math.max(hi, h);
      }
    }
    final step = (hi - lo) / (_levels + 1);

    final regular = Path(), index = Path();
    for (var k = 1; k <= _levels; k++) {
      final level = lo + k * step;
      final path = k % 5 == 0 ? index : regular;
      for (var j = 0; j < rows; j++) {
        for (var i = 0; i < cols; i++) {
          _march(path, field, i, j, level);
        }
      }
    }

    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(regular, stroke(color, 1.1));
    canvas.drawPath(index, stroke(indexColor, 1.6));
  }

  /// Adds the contour segment(s) of [level] crossing grid cell (i, j).
  void _march(Path path, List<List<double>> f, int i, int j, double level) {
    final a = f[j][i], b = f[j][i + 1], c = f[j + 1][i + 1], d = f[j + 1][i];
    final mask =
        (a > level ? 8 : 0) |
        (b > level ? 4 : 0) |
        (c > level ? 2 : 0) |
        (d > level ? 1 : 0);
    if (mask == 0 || mask == 15) return;

    final x = i * _cell, y = j * _cell;
    double t(double p, double q) => (level - p) / (q - p);
    Offset top() => Offset(x + _cell * t(a, b), y);
    Offset right() => Offset(x + _cell, y + _cell * t(b, c));
    Offset bottom() => Offset(x + _cell * t(d, c), y + _cell);
    Offset left() => Offset(x, y + _cell * t(a, d));

    void line(Offset p, Offset q) => path
      ..moveTo(p.dx, p.dy)
      ..lineTo(q.dx, q.dy);

    switch (mask) {
      case 1 || 14:
        line(left(), bottom());
      case 2 || 13:
        line(bottom(), right());
      case 3 || 12:
        line(left(), right());
      case 4 || 11:
        line(top(), right());
      case 6 || 9:
        line(top(), bottom());
      case 7 || 8:
        line(left(), top());
      case 5:
        line(left(), top());
        line(bottom(), right());
      case 10:
        line(top(), right());
        line(left(), bottom());
    }
  }

  @override
  bool shouldRepaint(_TopoPainter old) =>
      old.color != color || old.indexColor != indexColor;
}
