import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import 'ar_location_view.dart';

/// Signature for a function that creates a widget for a given annotation,
typedef AnnotationViewBuilder = Widget Function(
    BuildContext context, ArAnnotation annotation);

typedef ChangeLocationCallback = void Function(Position position);

class ArView extends StatefulWidget {
  const ArView({
    super.key,
    required this.annotations,
    required this.annotationViewBuilder,
    required this.frame,
    required this.onLocationChange,
    this.annotationWidth = 200,
    this.annotationHeight = 75,
    this.maxVisibleDistance = 1500,
    this.showDebugInfoSensor = true,
    this.paddingOverlap = 5,
    this.yOffsetOverlap,
    required this.minDistanceReload,
    this.scaleWithDistance = true,
    this.markerColor,
    this.backgroundRadar,
    this.radarPosition,
    this.showRadar = true,
    this.radarWidth,
    this.radarFovAreaColor = Colors.blueAccent,
    this.onARSensorUpdate,
    this.bandBottomFraction = 0.40,
    this.bandTopFraction = 0.80,
  });

  final List<ArAnnotation> annotations;
  final AnnotationViewBuilder annotationViewBuilder;
  final double annotationWidth;
  final double annotationHeight;

  final double maxVisibleDistance;

  final Size frame;

  final ChangeLocationCallback onLocationChange;

  final bool showDebugInfoSensor;

  final double paddingOverlap;
  final double? yOffsetOverlap;
  final double minDistanceReload;

  ///Scale annotation view with distance from user
  final bool scaleWithDistance;

  ///Radar

  /// marker color in radar
  final Color? markerColor;

  ///background radar color
  final Color? backgroundRadar;

  ///radar position in view
  final RadarPosition? radarPosition;

  ///Show radar in view
  final bool showRadar;

  ///Radar width
  final double? radarWidth;

  /// Color of area shown on radar to indicate FOV
  final Color radarFovAreaColor;

  final Function(ArSensor)? onARSensorUpdate;

  /// Bottom boundary of the annotation band as a fraction of screen height
  /// measured from bottom. Default 0.40 = bottom 40% of screen is clear.
  final double bandBottomFraction;

  /// Top boundary of the annotation band as a fraction of screen height
  /// measured from bottom. Default 0.80 = top 20% of screen is clear.
  final double bandTopFraction;

  @override
  State<ArView> createState() => _ArViewState();
}

class _ArViewState extends State<ArView> {
  ArStatus arStatus = ArStatus();
  Stream<ArSensor>? _arSensorStream;

  Position? position;

  @override
  void initState() {
    ArSensorManager.instance.init();
    _arSensorStream = ArSensorManager.instance.arSensor;
    super.initState();
  }

  @override
  void dispose() {
    ArSensorManager.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return StreamBuilder(
      stream: _arSensorStream,
      builder: (context, data) {
        if (data.hasData) {
          if (data.data != null) {
            final arSensor = data.data!;
            if (arSensor.location == null) {
              return loading();
            }
            if (widget.onARSensorUpdate != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                widget.onARSensorUpdate!(arSensor);
              });
            }
            _calculateFOV(arSensor.orientation, width, height);
            _updatePosition(arSensor.location!);
            final deviceLocation = arSensor.location!;
            final annotations = _filterAndSortArAnnotation(
                widget.annotations, arSensor, deviceLocation);

            // --- Band-constrained annotation positioning ---
            final topBound = height * (1 - widget.bandTopFraction);
            final bottomBound = height * (1 - widget.bandBottomFraction);
            final bandHeight = bottomBound - topBound;

            // Compute altitude-based baseline Y for each annotation
            _computeAltitudeBaselines(annotations, topBound, bandHeight);

            // Apply collision avoidance within the band
            _transformAnnotationsInBand(annotations, topBound, bottomBound);

            return Stack(
              children: [
                if (kDebugMode && widget.showDebugInfoSensor)
                  Positioned(
                    bottom: 0,
                    child: _debugInfo(context, arSensor),
                  ),
                Stack(
                  children: annotations.map(
                    (e) {
                      // Final Y = pitch offset + altitude baseline + collision offset
                      final finalTop = e.arPosition.dy + e.arPositionOffset.dy;

                      // Clamp to band bounds
                      final clampedTop =
                          finalTop.clamp(topBound, bottomBound - widget.annotationHeight);

                      // Determine if outside band
                      e.isOutsideBand =
                          finalTop < topBound || finalTop > bottomBound - widget.annotationHeight;

                      // Build indicator widget or full annotation widget
                      Widget childWidget;
                      if (e.isOutsideBand) {
                        childWidget = _buildBandIndicator(
                          context,
                          isAbove: finalTop < topBound,
                          markerColor: e.markerColor,
                        );
                      } else {
                        childWidget = Transform.scale(
                          scale:
                              e.scaleWithDistance && widget.scaleWithDistance
                                  ? 1 -
                                      (e.distanceFromUser /
                                          (widget.maxVisibleDistance + 1080))
                                  : 1,
                          child: SizedBox(
                            width: widget.annotationWidth,
                            height: widget.annotationHeight,
                            child: widget.annotationViewBuilder(context, e),
                          ),
                        );
                      }

                      return Positioned(
                        left: e.arPosition.dx,
                        top: clampedTop,
                        child: childWidget,
                      );
                    },
                  ).toList(),
                ),
                if (widget.showRadar)
                  _radarPosition(
                      context,
                      widget.radarPosition ?? RadarPosition.topLeft,
                      arSensor.heading,
                      widget.radarWidth != null
                          ? (widget.radarWidth! * 2)
                          : width)
              ],
            );
          }
        }
        return loading();
      },
    );
  }

  /// Computes altitude-based baseline Y positions for all annotations.
  /// Higher altitude annotations are placed higher on screen (lower Y).
  void _computeAltitudeBaselines(
      List<ArAnnotation> annotations, double topBound, double bandHeight) {
    if (annotations.isEmpty) return;

    double minAlt = double.infinity;
    double maxAlt = double.negativeInfinity;

    for (final a in annotations) {
      final alt = a.position.altitude;
      if (alt < minAlt) minAlt = alt;
      if (alt > maxAlt) maxAlt = alt;
    }

    final bool allSame = (maxAlt - minAlt).abs() < 0.001;

    for (final a in annotations) {
      if (allSame) {
        // All altitudes equal — center in band
        a.altitudeRelativeY = 0.5;
      } else {
        a.altitudeRelativeY =
            (a.position.altitude - minAlt) / (maxAlt - minAlt);
      }
      // Map normalized altitude to band Y position.
      // altitudeRelativeY=1.0 (highest POI) → topBound (highest on screen)
      // altitudeRelativeY=0.0 (lowest POI) → topBound + bandHeight - annotationHeight
      final usableHeight = bandHeight - widget.annotationHeight;
      a.arPositionOffset = Offset(
        0,
        topBound + (1.0 - a.altitudeRelativeY) * usableHeight,
      );
    }
  }

  /// Distributes overlapping annotations bidirectionally within the band.
  void _transformAnnotationsInBand(List<ArAnnotation> annotations,
      double topBound, double bottomBound) {
    annotations.sort((a, b) =>
        (a.distanceFromUser < b.distanceFromUser)
            ? -1
            : ((a.distanceFromUser > b.distanceFromUser) ? 1 : 0));

    // Group overlapping annotations by horizontal X collision
    final groups = <List<ArAnnotation>>[];
    for (final annotation in annotations) {
      bool addedToGroup = false;
      for (final group in groups) {
        final collidesWithGroup = group.any((other) =>
            intersects(annotation, other, widget.annotationWidth));
        if (collidesWithGroup) {
          group.add(annotation);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        groups.add([annotation]);
      }
    }

    // Distribute each group vertically within the band
    final stepSize =
        (widget.yOffsetOverlap ?? widget.annotationHeight) + widget.paddingOverlap;

    for (final group in groups) {
      if (group.length == 1) continue; // single annotation — no collision needed

      // Sort group by y position
      group.sort((a, b) => a.arPositionOffset.dy.compareTo(b.arPositionOffset.dy));

      // Calculate available vertical space in the band for this group
      final availableSpace = bottomBound - topBound - widget.annotationHeight;
      final neededSpace = (group.length - 1) * stepSize;

      if (neededSpace <= availableSpace) {
        // Distribute evenly around the group's center
        final centerY = group.fold<double>(
              0, (sum, a) => sum + a.arPositionOffset.dy) /
            group.length;
        final halfSpan = (group.length - 1) * stepSize / 2;
        var currentY = centerY - halfSpan;

        for (final annotation in group) {
          final clampedY = currentY.clamp(topBound, bottomBound - widget.annotationHeight);
          annotation.arPositionOffset = Offset(0, clampedY);
          currentY += stepSize;
        }
      } else {
        // Not enough space — pack as tightly as possible, spread from top
        var currentY = topBound;
        for (final annotation in group) {
          annotation.arPositionOffset = Offset(0, currentY);
          currentY += stepSize;
          if (currentY > bottomBound - widget.annotationHeight) break;
        }
        // Mark any that couldn't fit as outside band
        for (final annotation in group) {
          if (annotation.arPositionOffset.dy > bottomBound - widget.annotationHeight) {
            annotation.isOutsideBand = true;
          }
        }
      }
    }
  }

  /// Builds a small arrow indicator for annotations outside the band.
  Widget _buildBandIndicator(
      BuildContext context, {
        required bool isAbove,
        required Color markerColor,
      }) {
    return Container(
      width: widget.annotationWidth,
      height: 32,
      alignment: Alignment.center,
      child: Icon(
        isAbove ? Icons.arrow_drop_down : Icons.arrow_drop_up,
        size: 32,
        color: markerColor,
      ),
    );
  }

  Widget _radarPosition(BuildContext context, RadarPosition position,
      double heading, double width) {
    final radar = Padding(
      padding: const EdgeInsets.all(8.0),
      child: CustomPaint(
        size: Size(width / 2, width / 2),
        painter: RadarPainter(
          maxDistance: widget.maxVisibleDistance,
          arAnnotations: widget.annotations,
          heading: heading,
          background: widget.backgroundRadar ?? Colors.grey,
          fovAreaColor: widget.radarFovAreaColor,
        ),
      ),
    );
    final screenWidth = MediaQuery.of(context).size.width;
    switch (position) {
      case RadarPosition.topCenter:
        return Positioned(
          top: 0,
          left: screenWidth / 2 - width / 4,
          child: radar,
        );
      case RadarPosition.topRight:
        return Positioned(
          top: 0,
          right: 0,
          child: radar,
        );
      case RadarPosition.bottomLeft:
        return Positioned(
          bottom: 0,
          left: 0,
          child: radar,
        );
      case RadarPosition.bottomCenter:
        return Positioned(
          bottom: 0,
          left: screenWidth / 2 - width / 4,
          child: radar,
        );
      case RadarPosition.bottomRight:
        return Positioned(
          bottom: 0,
          right: 0,
          child: radar,
        );
      default:
        return radar;
    }
  }

  Widget _debugInfo(BuildContext context, ArSensor? arSensor) {
    return Container(
      color: Colors.white,
      width: MediaQuery.of(context).size.width,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latitude  : ${arSensor?.location?.latitude}'),
            Text('Longitude : ${arSensor?.location?.longitude}'),
            Text('Pitch     : ${arSensor?.pitch}'),
            Text('Heading   : ${arSensor?.heading}'),
          ],
        ),
      ),
    );
  }

  Widget loading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  void _calculateFOV(
      NativeDeviceOrientation orientation, double width, double height) {
    double hFov = 0;
    double vFov = 0;
    const tempFOv = 58.0;

    if (orientation == NativeDeviceOrientation.landscapeLeft ||
        orientation == NativeDeviceOrientation.landscapeRight) {
      hFov = tempFOv;
      vFov = (2 * atan(tan((hFov / 2).toRadians) * (height / width))).toDegrees;
    } else {
      vFov = tempFOv;
      hFov = (2 * atan(tan((vFov / 2).toRadians) * (width / height))).toDegrees;
    }

    arStatus.hFov = hFov;
    arStatus.vFov = vFov;
    arStatus.hPixelPerDegree = hFov > 0 ? (width / hFov) : 0;
    arStatus.vPixelPerDegree = vFov > 0 ? (height / vFov) : 0;
  }

  List<ArAnnotation> _visibleAnnotations(
      List<ArAnnotation> annotations, double heading) {
    final degreesDeltaH = arStatus.hFov;
    return annotations.where((ArAnnotation annotation) {
      final delta = ArMath.deltaAngle(heading, annotation.azimuth);
      final isVisible = delta.abs() < degreesDeltaH;
      annotation.isVisible = isVisible;
      return annotation.isVisible;
    }).toList();
  }

  List<ArAnnotation> _calculateDistanceAndBearingFromUser(
      List<ArAnnotation> annotations,
      Position deviceLocation,
      ArSensor arSensor) {
    return annotations.map((e) {
      final annotationLocation = e.position;
      e.azimuth = Geolocator.bearingBetween(
        deviceLocation.latitude,
        deviceLocation.longitude,
        annotationLocation.latitude,
        annotationLocation.longitude,
      );
      e.distanceFromUser = Geolocator.distanceBetween(
          deviceLocation.latitude,
          deviceLocation.longitude,
          annotationLocation.latitude,
          annotationLocation.longitude);
      final dy = arSensor.pitch * arStatus.vPixelPerDegree;
      final dx = ArMath.deltaAngle(e.azimuth, arSensor.heading) *
          arStatus.hPixelPerDegree;
      e.arPosition = Offset(dx, dy);
      return e;
    }).toList();
  }

  List<ArAnnotation> _filterAndSortArAnnotation(List<ArAnnotation> annotations,
      ArSensor arSensor, Position deviceLocation) {
    List<ArAnnotation> temps = _calculateDistanceAndBearingFromUser(
        annotations, deviceLocation, arSensor);
    temps = annotations
        .where(
            (element) => element.distanceFromUser < widget.maxVisibleDistance)
        .toList();
    temps = _visibleAnnotations(temps, arSensor.heading);
    return temps;
  }

  bool intersects(
      ArAnnotation annotation1, ArAnnotation annotation2, double width) {
    return (annotation2.arPosition.dx >= annotation1.arPosition.dx &&
            annotation2.arPosition.dx <= (annotation1.arPosition.dx + width)) ||
        (annotation1.arPosition.dx >= annotation2.arPosition.dx &&
            annotation1.arPosition.dx <= (annotation2.arPosition.dx + width));
  }

  void _updatePosition(Position newPosition) {
    if (position == null) {
      widget.onLocationChange(newPosition);
      position = newPosition;
    } else {
      final distance = Geolocator.distanceBetween(
        position!.latitude,
        position!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      if (distance > widget.minDistanceReload) {
        widget.onLocationChange(newPosition);
        widget.onLocationChange(newPosition);
        position = newPosition;
      }
    }
  }
}
