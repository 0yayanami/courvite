import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../models/run.dart';
import '../theme.dart';
import 'territory_layer.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'io.github.courvite.courvite';

/// Mostly-desaturated tiles, so the yellow track is what stands out.
const _tileFilter = ColorFilter.matrix([
  0.45, 0.45, 0.10, 0, 12, //
  0.30, 0.60, 0.10, 0, 12, //
  0.30, 0.45, 0.25, 0, 12, //
  0, 0, 0, 1, 0,
]);

/// One filter over the whole tile layer: a single offscreen pass, instead of
/// one per tile when applied in `tileBuilder`.
Widget mapTiles() => ColorFiltered(
  colorFilter: _tileFilter,
  child: TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
);

List<Polyline> _polylines(List<TrackPoint> points) {
  final bySegment = <int, List<LatLng>>{};
  for (final p in points) {
    bySegment.putIfAbsent(p.segment, () => []).add(LatLng(p.lat, p.lon));
  }
  return [
    for (final seg in bySegment.values)
      if (seg.length > 1)
        Polyline(
          points: seg,
          strokeWidth: 6,
          color: AppColors.volt,
          borderStrokeWidth: 2,
          borderColor: AppColors.ink,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
  ];
}

Widget _marker({
  required Color fill,
  Color border = Colors.white,
  IconData? icon,
  Color iconColor = Colors.white,
}) => Container(
  decoration: BoxDecoration(
    color: fill,
    shape: BoxShape.circle,
    border: Border.all(color: border, width: 3),
    boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
  ),
  child: icon == null
      ? null
      : Center(child: Icon(icon, size: 14, color: iconColor)),
);

/// The runner: a yellow dot with a soft halo.
Widget _me() => Container(
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: AppColors.volt.withValues(alpha: 0.35),
  ),
  padding: const EdgeInsets.all(8),
  child: _marker(fill: AppColors.volt, border: AppColors.ink),
);

Widget mapAttribution({
  AttributionAlignment alignment = AttributionAlignment.bottomRight,
}) => RichAttributionWidget(
  alignment: alignment,
  showFlutterMapAttribution: false,
  attributions: const [TextSourceAttribution('OpenStreetMap contributors')],
);

/// Static map of a finished run, framed on the whole path.
class RunRouteMap extends StatelessWidget {
  const RunRouteMap({
    super.key,
    required this.points,
    this.interactive = true,
    this.captured = const [],
  });

  final List<TrackPoint> points;
  final bool interactive;

  /// Territory cells captured by the run, shaded under the route.
  final List<int> captured;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return ColoredBox(
        color: AppColors.card,
        child: Center(
          child: Text('NO GPS TRACK RECORDED', style: labelStyle()),
        ),
      );
    }
    final latLngs = [for (final p in points) LatLng(p.lat, p.lon)];
    final fit = latLngs.length > 1
        ? CameraFit.coordinates(
            coordinates: latLngs,
            padding: const EdgeInsets.all(32),
          )
        : null;
    return FlutterMap(
      options: MapOptions(
        initialCenter: latLngs.first,
        initialZoom: 16,
        initialCameraFit: fit,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        mapTiles(),
        if (captured.isNotEmpty) TerritoryLayer(cells: captured),
        PolylineLayer(polylines: _polylines(points)),
        MarkerLayer(
          markers: [
            Marker(
              point: latLngs.first,
              width: 22,
              height: 22,
              child: _marker(fill: AppColors.go),
            ),
            if (latLngs.length > 1)
              Marker(
                point: latLngs.last,
                width: 28,
                height: 28,
                child: _marker(fill: AppColors.ink, icon: Icons.flag_rounded),
              ),
          ],
        ),
        mapAttribution(),
      ],
    );
  }
}

/// Map shown while running: draws the path so far and follows the runner
/// until they pan the map themselves.
class LiveRunMap extends StatefulWidget {
  const LiveRunMap({
    super.key,
    required this.points,
    required this.position,
    this.trackVersion = 0,
    this.bottomInset = 0,
  });

  final List<TrackPoint> points;

  /// Changes whenever [points] grows (it may be the same list instance).
  final int trackVersion;
  final LatLng? position;

  /// Height of the panel covering the bottom of the map: controls and the
  /// runner's position are kept in the visible part above it.
  final double bottomInset;

  @override
  State<LiveRunMap> createState() => _LiveRunMapState();
}

class _LiveRunMapState extends State<LiveRunMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _follow = true;

  /// Where the camera was last centered; small moves are ignored.
  LatLng? _center;
  static const _recenterMeters = 3.0;

  /// Route polylines, rebuilt only when the route changes.
  List<Polyline> _lines = const [];
  int? _linesVersion;
  int? _linesLength;

  List<Polyline> _polylinesFor(LiveRunMap w) {
    if (w.trackVersion != _linesVersion || w.points.length != _linesLength) {
      _lines = _polylines(w.points);
      _linesVersion = w.trackVersion;
      _linesLength = w.points.length;
    }
    return _lines;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Centers [pos] in the part of the map not covered by the bottom panel.
  void _moveTo(LatLng pos, double zoom) {
    _center = pos;
    _controller.move(pos, zoom, offset: Offset(0, -widget.bottomInset / 2));
  }

  @override
  void didUpdateWidget(LiveRunMap old) {
    super.didUpdateWidget(old);
    final pos = widget.position;
    if (!_ready || !_follow || pos == null) return;
    if (old.position == null) {
      _moveTo(pos, 17); // First fix: zoom in from the world view.
    } else if (widget.bottomInset != old.bottomInset ||
        _center == null ||
        const Distance().as(LengthUnit.Meter, _center!, pos) >=
            _recenterMeters) {
      _moveTo(pos, _controller.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.position;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: pos ?? const LatLng(48.8566, 2.3522),
            initialZoom: pos == null ? 4 : 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              if (pos != null) _moveTo(pos, 17);
            },
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            mapTiles(),
            PolylineLayer(polylines: _polylinesFor(widget)),
            if (pos != null)
              MarkerLayer(
                markers: [
                  Marker(point: pos, width: 42, height: 42, child: _me()),
                ],
              ),
            // Kept visible above the bottom panel, away from the recenter button.
            Padding(
              padding: EdgeInsets.only(bottom: widget.bottomInset),
              child: mapAttribution(alignment: AttributionAlignment.bottomLeft),
            ),
          ],
        ),
        if (!_follow && pos != null)
          Positioned(
            right: 16,
            bottom: widget.bottomInset + 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: 'Recenter',
              backgroundColor: AppColors.canvas,
              foregroundColor: AppColors.ink,
              shape: const CircleBorder(),
              onPressed: () {
                setState(() => _follow = true);
                _moveTo(pos, _controller.camera.zoom);
              },
              child: const Icon(Icons.near_me_rounded),
            ),
          ),
      ],
    );
  }
}

/// Tile-free drawing of a route, for list thumbnails.
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RoutePainter(points), size: Size.infinite);
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points);

  final List<TrackPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // Equirectangular projection, good enough at the scale of a run.
    final cosLat = math.cos(points.first.lat * math.pi / 180);
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in points) {
      final x = p.lon * cosLat, y = -p.lat;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    const pad = 10.0;
    final w = size.width - 2 * pad, h = size.height - 2 * pad;
    final span = math.max(maxX - minX, maxY - minY);
    if (span == 0) return;
    final scale = math.min(w, h) / span;
    final dx = pad + (w - (maxX - minX) * scale) / 2;
    final dy = pad + (h - (maxY - minY) * scale) / 2;
    Offset project(TrackPoint p) => Offset(
      dx + (p.lon * cosLat - minX) * scale,
      dy + (-p.lat - minY) * scale,
    );

    final path = Path();
    int? segment;
    for (final p in points) {
      final o = project(p);
      if (p.segment != segment) {
        path.moveTo(o.dx, o.dy);
        segment = p.segment;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    Paint stroke(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke(AppColors.ink, 6));
    canvas.drawPath(path, stroke(AppColors.volt, 3));
    canvas.drawCircle(
      project(points.last),
      3.5,
      Paint()..color = AppColors.ink,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.points != points;
}
