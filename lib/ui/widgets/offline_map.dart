/// Custom offline map.
///
/// No tile service, no API, no network: points are projected with a simple
/// equirectangular projection centred on the visible set and drawn on a
/// stylized grid so the user gets geographic context for every marker. This
/// widget is fully self-contained so it works in the field with no signal.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class MapMarker {
  const MapMarker({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.color,
    this.subtitle,
  });

  final String id;
  final String label;
  final String? subtitle;
  final double latitude;
  final double longitude;
  final Color color;
}

class OfflineMap extends StatelessWidget {
  const OfflineMap({
    super.key,
    required this.markers,
    this.center,
    this.showGrid = true,
    this.height,
  });

  /// Markers to draw. When empty a default region is shown.
  final List<MapMarker> markers;

  /// Optional explicit map centre; when null the marker centroid is used.
  final ({double latitude, double longitude})? center;

  final bool showGrid;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final all = markers;
    final effectiveCenter = center ??
        (all.isEmpty
            ? (latitude: 17.7, longitude: 83.3)
            : _centroid(all));
    final effectiveMarkers =
        all.isEmpty ? _defaultMarkers(context) : all;

    return SizedBox(
      height: height ?? 260,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _MapPainter(
            markers: effectiveMarkers,
            center: effectiveCenter,
            showGrid: showGrid,
            scheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
    );
  }

  static ({double latitude, double longitude}) _centroid(
    List<MapMarker> markers,
  ) {
    var lat = 0.0;
    var lng = 0.0;
    for (final m in markers) {
      lat += m.latitude;
      lng += m.longitude;
    }
    return (
      latitude: lat / markers.length,
      longitude: lng / markers.length,
    );
  }

  List<MapMarker> _defaultMarkers(BuildContext context) => [
        MapMarker(
          id: 'demo-region',
          label: 'Relief operations region',
          latitude: 17.7,
          longitude: 83.3,
          color: Theme.of(context).colorScheme.primary,
        ),
      ];
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.markers,
    required this.center,
    required this.showGrid,
    required this.scheme,
  });

  final List<MapMarker> markers;
  final ({double latitude, double longitude}) center;
  final bool showGrid;
  final ColorScheme scheme;

  static const double _latSpanDefault = 0.06;
  static const double _lngSpanDefault = 0.09;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFE8F0E8);
    canvas.drawRect(Offset.zero & size, background);

    // Bounding box around all markers with generous padding.
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLng = double.infinity, maxLng = -double.infinity;
    for (final m in markers) {
      minLat = math.min(minLat, m.latitude);
      maxLat = math.max(maxLat, m.latitude);
      minLng = math.min(minLng, m.longitude);
      maxLng = math.max(maxLng, m.longitude);
    }
    var latSpan = (maxLat - minLat) * 2.2 + _latSpanDefault;
    var lngSpan = (maxLng - minLng) * 2.2 + _lngSpanDefault;
    latSpan = math.max(latSpan, _latSpanDefault * 0.8);
    lngSpan = math.max(lngSpan, _lngSpanDefault * 0.8);

    // Grid (roads / blocks).
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke;
      const gridLines = 7;
      for (var i = 0; i <= gridLines; i++) {
        final x = size.width * i / gridLines;
        final y = size.height * i / gridLines;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      }

      // A stylised river through the centre for terrain context.
      final river = Paint()
        ..color = const Color(0xFFB3D4E8).withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(-size.height * 0.1, size.height * 0.35)
        ..cubicTo(
          size.width * 0.3,
          size.height * 0.2,
          size.width * 0.6,
          size.height * 0.55,
          size.width * 1.1,
          size.height * 0.4,
        );
      canvas.drawPath(path, river);

      final riverCore = Paint()
        ..color = const Color(0xFF8FC0DC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, riverCore);
    }

    // -=----- Markers ------
    for (final m in markers) {
      final dx = (m.longitude - center.longitude) / lngSpan + 0.5;
      final dy = (center.latitude - m.latitude) / latSpan + 0.5;
      final pos = Offset(dx * size.width, dy * size.height);

      final shadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos.translate(1.5, 2.5), 12, shadow);

      final dot = Paint()..color = m.color;
      canvas.drawCircle(pos, 11, dot);
      final ring = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(pos, 11, ring);
      canvas.drawCircle(pos, 3, Paint()..color = Colors.white);

      // Label.
      final tp = TextPainter(
        text: TextSpan(
          text: m.label,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 12,
            shadows: const [
              Shadow(blurRadius: 3, color: Colors.white),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos + const Offset(16, -14));
      if (m.subtitle != null) {
        final stp = TextPainter(
          text: TextSpan(
            text: m.subtitle,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
              shadows: const [
                Shadow(blurRadius: 3, color: Colors.white),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        stp.paint(canvas, pos + const Offset(16, 2));
      }
    }

    // Compass rose, top-right.
    final compassPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(
      Offset(size.width - 28, 28),
      14,
      compassPaint,
    );
    final needle = Paint()
      ..color = scheme.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      const Offset(0, 0) + Offset(size.width - 28, 28),
      Offset(size.width - 28, 28 - 12),
      needle,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.markers != markers ||
      oldDelegate.center != center ||
      oldDelegate.showGrid != showGrid;
}