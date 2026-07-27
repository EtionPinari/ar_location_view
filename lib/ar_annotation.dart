import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

abstract class ArAnnotation {
  ArAnnotation({
    required this.uid,
    required this.position,
    this.markerColor = Colors.red,
    this.azimuth = 0,
    this.distanceFromUser = 0,
    this.isVisible = true,
    this.arPosition = const Offset(0, 0),
    this.arPositionOffset = const Offset(0, 0),
    this.scaleWithDistance = true,
    this.isOutsideBand = false,
    this.altitudeRelativeY = 0.0,
  });

  String uid;
  Position position;
  double azimuth;
  double distanceFromUser;
  bool isVisible;
  Offset arPosition;
  Offset arPositionOffset;
  Color markerColor;
  bool scaleWithDistance;

  /// Whether this annotation falls outside the configured vertical band.
  /// When true, a minimal indicator is shown instead of the full widget.
  bool isOutsideBand;

  /// Normalized altitude-based Y position within the band [0.0, 1.0].
  /// 0.0 = lowest altitude (lowest on screen), 1.0 = highest altitude (highest on screen).
  double altitudeRelativeY;

  @override
  String toString() {
    return 'Annotation{position: $position, markerColor: $markerColor, azimuth: $azimuth, distanceFromUser: $distanceFromUser, isVisible: $isVisible, arPosition: $arPosition, scaleWithDistance: $scaleWithDistance, isOutsideBand: $isOutsideBand}';
  }
}
