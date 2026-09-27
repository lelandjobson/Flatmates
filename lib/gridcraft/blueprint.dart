import 'dart:ui';

/// A grid puzzle. Each step names its own spacing and paper margin.
class GridBlueprint {
  const GridBlueprint({
    required this.id,
    required this.name,
    required this.steps,
  });

  final String id;
  final String name;
  final List<GridStep> steps;

  GridBlueprint copyWith({List<GridStep>? steps}) {
    return GridBlueprint(id: id, name: name, steps: steps ?? this.steps);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': [for (final step in steps) step.toJson()],
  };

  factory GridBlueprint.fromJson(Map<String, dynamic> json) {
    final steps = json['steps'] as List? ?? const [];
    return GridBlueprint(
      id: json['id'] as String? ?? 'level',
      name: json['name'] as String? ?? 'Level',
      steps: [
        for (final step in steps)
          GridStep.fromJson(step as Map<String, dynamic>),
      ],
    );
  }
}

/// One blueprint step. Polygons are closed outlines in grid units.
class GridStep {
  const GridStep({
    required this.id,
    required this.label,
    required this.polygons,
    this.gridSpacing = 1,
    this.paperMargin = 3,
  });

  final String id;
  final String label;
  final double gridSpacing;
  final double paperMargin;
  final List<List<Offset>> polygons;

  /// Sheet around the outlines, grown by [paperMargin] cells on every side.
  Rect get paper {
    final bounds = polygonBounds(polygons);
    return bounds.inflate(paperMargin * gridSpacing);
  }

  List<Offset> get vertices => [
    for (final polygon in polygons) ...polygon,
  ];

  GridStep copyWith({List<List<Offset>>? polygons}) {
    return GridStep(
      id: id,
      label: label,
      polygons: polygons ?? this.polygons,
      gridSpacing: gridSpacing,
      paperMargin: paperMargin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'gridSpacing': gridSpacing,
    'paperMargin': paperMargin,
    'polygons': [
      for (final polygon in polygons)
        [
          for (final point in polygon) [point.dx, point.dy],
        ],
    ],
  };

  factory GridStep.fromJson(Map<String, dynamic> json) {
    final polygons = json['polygons'] as List? ?? const [];
    return GridStep(
      id: json['id'] as String? ?? 'step',
      label: json['label'] as String? ?? 'Step',
      gridSpacing: (json['gridSpacing'] as num?)?.toDouble() ?? 1,
      paperMargin: (json['paperMargin'] as num?)?.toDouble() ?? 3,
      polygons: [
        for (final polygon in polygons)
          [
            for (final point in polygon as List)
              Offset(
                ((point as List)[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              ),
          ],
      ],
    );
  }
}

Rect polygonBounds(List<List<Offset>> polygons) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final polygon in polygons) {
    for (final point in polygon) {
      minX = minX < point.dx ? minX : point.dx;
      minY = minY < point.dy ? minY : point.dy;
      maxX = maxX > point.dx ? maxX : point.dx;
      maxY = maxY > point.dy ? maxY : point.dy;
    }
  }
  if (minX == double.infinity) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}
