import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../models/run.dart';
import '../theme.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'io.github.courvite.courvite';

/// Mostly-desaturated tiles, so the yellow track is what stands out.
const _tileFilter = ColorFilter.matrix([
  0.45, 0.45, 0.10, 0, 12, //
  0.30, 0.60, 0.10, 0, 12, //
  0.30, 0.45, 0.25, 0, 12, //
  0, 0, 0, 1, 0,
]);

Widget _tiles() => TileLayer(
  urlTemplate: _tileUrl,
  userAgentPackageName: _userAgent,
  tileBuilder: (context, tile, _) =>
      ColorFiltered(colorFilter: _tileFilter, child: tile),
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

Widget _attribution() => const RichAttributionWidget(
  showFlutterMapAttribution: false,
  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
);

/// Static map of a finished run, framed on the whole path.
class RunRouteMap extends StatelessWidget {
  const RunRouteMap({super.key, required this.points, this.interactive = true});

  final List<TrackPoint> points;
  final bool interactive;

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
        _tiles(),
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
        _attribution(),
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
    this.bottomInset = 0,
  });

  final List<TrackPoint> points;
  final LatLng? position;

  /// Height of what overlaps the bottom of the map (keeps controls visible).
  final double bottomInset;

  @override
  State<LiveRunMap> createState() => _LiveRunMapState();
}

class _LiveRunMapState extends State<LiveRunMap> {
  final _controller = MapController();
  bool _ready = false;
  bool _follow = true;

  /// Centers [pos] in the part of the map not covered by the bottom panel.
  void _moveTo(LatLng pos, double zoom) =>
      _controller.move(pos, zoom, offset: Offset(0, -widget.bottomInset / 2));

  @override
  void didUpdateWidget(LiveRunMap old) {
    super.didUpdateWidget(old);
    final pos = widget.position;
    if (!_ready || !_follow || pos == null) return;
    if (old.position == null) {
      _moveTo(pos, 17); // First fix: zoom in from the world view.
    } else if (pos != old.position || widget.bottomInset != old.bottomInset) {
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
            _tiles(),
            PolylineLayer(polylines: _polylines(widget.points)),
            if (pos != null)
              MarkerLayer(
                markers: [
                  Marker(point: pos, width: 42, height: 42, child: _me()),
                ],
              ),
            _attribution(),
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
