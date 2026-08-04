import 'package:flutter/material.dart';

/// Visual style configuration for path rendering
class PathStyle {
  const PathStyle({
    this.color = Colors.yellow,
    this.dotRadius = 2.0,
    this.dotSpacing = 8.0,
    this.elevation = 0.5,
  });

  /// Color of the path dots
  final Color color;

  /// Radius of each dot in pixels
  final double dotRadius;

  /// Spacing between dots in pixels
  final double dotSpacing;

  /// Height above tile surface (in tile height units)
  final double elevation;

  PathStyle copyWith({
    Color? color,
    double? dotRadius,
    double? dotSpacing,
    double? elevation,
  }) {
    return PathStyle(
      color: color ?? this.color,
      dotRadius: dotRadius ?? this.dotRadius,
      dotSpacing: dotSpacing ?? this.dotSpacing,
      elevation: elevation ?? this.elevation,
    );
  }
}
