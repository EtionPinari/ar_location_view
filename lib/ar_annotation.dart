import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

abstract class ArAnnotation {
  ArAnnotation({
    required this.uid,
    required this.position,
    this.markerColor = Colors.red,
    this.azimuth = 0,
    this.distanceFromUser = 0,
    this.isVisible = false,
    this.arPosition = const Offset(0, 0),
    this.arPositionOffset = const Offset(0, 0),
    this.scaleWithDistance = true,
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

  @override
  String toString() {
    return 'Annotation{position: $position, markerColor: $markerColor, azimuth: $azimuth, distanceFromUser: $distanceFromUser, isVisible: $isVisible, arPosition: $arPosition, scaleWithDistance: $scaleWithDistance}';
  }
}
