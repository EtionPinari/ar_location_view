import 'dart:math';

import 'package:flutter/material.dart';

import 'ar_location_view.dart';

enum RadarPosition {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

class RadarPainter extends CustomPainter {
  const RadarPainter({
    required this.maxDistance,
    required this.arAnnotations,
    required this.heading,
    required this.background,
    this.fovAreaColor = Colors.blueAccent,
  });

  final angle = pi / 7;

  final Color background;
  final double maxDistance;
  final List<ArAnnotation> arAnnotations;
  final double heading;
  final Color fovAreaColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final double leftAngle = -angle;
    final double rightAngle = angle;
    final center = Offset(radius, radius);
    final Paint circlePaint = Paint()..color = background.withAlpha(100);
    canvas.drawCircle(center, radius, circlePaint);
    final leftPoint = Offset(
      center.dx + radius * sin(leftAngle),
      center.dy - radius * cos(leftAngle),
    );
    final rightPoint = Offset(
      center.dx + radius * sin(rightAngle),
      center.dy - radius * cos(rightAngle),
    );
    final Path conePath = Path()
      ..moveTo(leftPoint.dx, leftPoint.dy)
      ..lineTo(center.dx, center.dy)
      ..lineTo(rightPoint.dx, rightPoint.dy)
      ..arcToPoint(leftPoint, radius: Radius.circular(radius), clockwise: false);
 

    final Paint conePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          fovAreaColor.withAlpha(168),
          fovAreaColor.withAlpha(130),
          fovAreaColor.withAlpha(50),
          fovAreaColor.withAlpha(20),
        ],
      ).createShader(Rect.fromCircle(
        center: center,
        radius: radius,
      ))
      ..style = PaintingStyle.fill;
 
    canvas.drawPath(conePath, conePaint);
    drawMarker(canvas, arAnnotations, radius);
    _drawNorthIndicator(canvas, radius, center);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  void drawMarker(
      Canvas canvas, List<ArAnnotation> annotations, double radius) {
    for (final annotation in annotations) {
      final Paint paint = Paint()..color = annotation.markerColor;
      final distanceInRadar =
          annotation.distanceFromUser / maxDistance * radius;
      if (distanceInRadar <= radius) {
        final bearing = (annotation.azimuth - heading).toRadians;
        final dx = distanceInRadar * sin(bearing);
        final dy = -distanceInRadar * cos(bearing);
        final center = Offset(dx + radius, dy + radius);
        canvas.drawCircle(center, 3, paint);
      }
    }
  }

  void _drawNorthIndicator(Canvas canvas, double radius, Offset center) {
    final northBearing = -heading.toRadians;
    final indicatorRadius = radius + 8;
    // Radial: center → outward. Arrow tip points toward center.
    final rx = sin(northBearing);
    final ry = -cos(northBearing);
    final px = cos(northBearing); // perpendicular
    final py = sin(northBearing);

    // Tip closest to center, base furthest outward
    final tipX = center.dx + (indicatorRadius) * rx;
    final tipY = center.dy + (indicatorRadius) * ry;

    // Stylized arrow:    ^
    //                   /_\
    //                  // \\
    final arrow = Path()
      ..moveTo(tipX, tipY)
      ..lineTo(tipX + 4 * rx + 4 * px, tipY + 4 * ry + 4 * py)
      ..lineTo(tipX + 5 * rx + 4 * px, tipY + 5 * ry + 4 * py)
      ..lineTo(tipX + 12 * rx + 8 * px, tipY + 12 * ry + 8 * py)
      ..lineTo(tipX + 12 * rx - 8 * px, tipY + 12 * ry - 8 * py)
      ..lineTo(tipX + 5 * rx - 4 * px, tipY + 5 * ry - 4 * py)
      ..lineTo(tipX + 4 * rx - 4 * px, tipY + 4 * ry - 4 * py)
      ..close();

    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill,
    );
  }
}
