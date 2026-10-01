import 'dart:ui';

import 'rules.dart';

/// A blueprint, also called a craft: an ordered list of levels.
class GridBlueprint {
  const GridBlueprint({
    required this.id,
    required this.name,
    required this.steps,
  });

  final String id;
  final String name;
  final List<GridStep> steps;

  GridBlueprint copyWith({String? name, List<GridStep>? steps}) {
    return GridBlueprint(
      id: id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
    );
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

/// Penned edges are the piece outline. The blade can track them.
/// Penciled edges are fold lines the puzzle requires: dashed, in the outline
/// color, and not a tracking guide unless a collinear penned edge shares
/// their axis.
enum EdgeStyle { penned, penciled }

/// A crafting tool the level can allow or budget. Select is never filtered.
enum CraftTool { scissors, folder, holePunch }

/// Optional allow-list. A missing filter means every tool, with unlimited uses.
class ToolFilter {
  const ToolFilter(this.uses);

  /// Null budget means the tool is allowed with unlimited uses.
  final Map<CraftTool, double?> uses;

  bool allows(CraftTool tool) => uses.containsKey(tool);

  double? budget(CraftTool tool) => uses[tool];

  bool get isEmpty => uses.isEmpty;

  ToolFilter copyWithUse(CraftTool tool, double? budget) {
    return ToolFilter({...uses, tool: budget});
  }

  ToolFilter without(CraftTool tool) {
    final next = Map<CraftTool, double?>.of(uses)..remove(tool);
    return ToolFilter(next);
  }

  Map<String, dynamic> toJson() => {
    for (final entry in uses.entries) entry.key.name: entry.value,
  };

  factory ToolFilter.fromJson(Object? raw) {
    if (raw is! Map) return const ToolFilter({});
    final uses = <CraftTool, double?>{};
    for (final tool in CraftTool.values) {
      if (!raw.containsKey(tool.name)) continue;
      final value = raw[tool.name];
      uses[tool] = value == null ? null : (value as num).toDouble();
    }
    return ToolFilter(uses);
  }
}

/// Scissor attachments. Authored on the level, not chosen in play.
class ScissorAttachment {
  const ScissorAttachment({this.flashlightThrow, this.thickCut = 0});

  /// Cone length in grid units. Null leaves the flashlight off.
  final double? flashlightThrow;

  /// Half-width of the removed strip, in grid units. Zero is a hairline cut.
  final double thickCut;

  bool get isEmpty => flashlightThrow == null && thickCut == 0;

  ScissorAttachment copyWith({
    double? flashlightThrow,
    bool clearThrow = false,
    double? thickCut,
  }) {
    return ScissorAttachment(
      flashlightThrow: clearThrow
          ? null
          : (flashlightThrow ?? this.flashlightThrow),
      thickCut: thickCut ?? this.thickCut,
    );
  }

  Map<String, dynamic> toJson() => {
    if (flashlightThrow != null) 'throw': flashlightThrow,
    if (thickCut != 0) 'thickCut': thickCut,
  };

  factory ScissorAttachment.fromJson(Object? raw) {
    if (raw is! Map) return const ScissorAttachment();
    return ScissorAttachment(
      flashlightThrow: (raw['throw'] as num?)?.toDouble(),
      thickCut: (raw['thickCut'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Level permutations: darkness, mirror axes, and no-fold zones.
class LevelPermutation {
  const LevelPermutation({
    this.darkness = false,
    this.mirrorX = false,
    this.mirrorY = false,
    this.noFold = const [],
  });

  final bool darkness;

  /// Reflect across the vertical line through the paper center.
  final bool mirrorX;

  /// Reflect across the horizontal line through the paper center.
  final bool mirrorY;

  /// Regions of paper that cannot be folded.
  final List<List<Offset>> noFold;

  bool get isEmpty => !darkness && !mirrorX && !mirrorY && noFold.isEmpty;

  LevelPermutation copyWith({
    bool? darkness,
    bool? mirrorX,
    bool? mirrorY,
    List<List<Offset>>? noFold,
  }) {
    return LevelPermutation(
      darkness: darkness ?? this.darkness,
      mirrorX: mirrorX ?? this.mirrorX,
      mirrorY: mirrorY ?? this.mirrorY,
      noFold: noFold ?? this.noFold,
    );
  }

  LevelPermutation turned(double radians, Offset Function(Offset point) turn) {
    final quarter = (radians / (3.141592653589793 / 2)).round() % 4;
    var mirrorX = this.mirrorX;
    var mirrorY = this.mirrorY;
    if (quarter == 1 || quarter == 3) {
      final swap = mirrorX;
      mirrorX = mirrorY;
      mirrorY = swap;
    }
    return LevelPermutation(
      darkness: darkness,
      mirrorX: mirrorX,
      mirrorY: mirrorY,
      noFold: [
        for (final zone in noFold) [for (final point in zone) turn(point)],
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    if (darkness) 'darkness': true,
    if (mirrorX) 'mirrorX': true,
    if (mirrorY) 'mirrorY': true,
    if (noFold.isNotEmpty)
      'noFold': [
        for (final zone in noFold)
          [
            for (final point in zone) [point.dx, point.dy],
          ],
      ],
  };

  factory LevelPermutation.fromJson(Object? raw) {
    if (raw is! Map) return const LevelPermutation();
    final zones = raw['noFold'] as List? ?? const [];
    return LevelPermutation(
      darkness: raw['darkness'] == true,
      mirrorX: raw['mirrorX'] == true,
      mirrorY: raw['mirrorY'] == true,
      noFold: [
        for (final zone in zones)
          [
            for (final point in zone as List)
              Offset(
                ((point as List)[0] as num).toDouble(),
                (point[1] as num).toDouble(),
              ),
          ],
      ],
    );
  }
}

/// A level: one blueprint step. Each ring in [polygons] is a blueprint piece.
class GridStep {
  const GridStep({
    required this.id,
    required this.label,
    required this.polygons,
    this.gridSpacing = 1,
    this.paperMargin = 2,
    this.rules = const GridRules(),
    this.edgeStyles = const [],
    this.collisions = const [],
    this.ringClosed = const [],
    this.tools,
    this.attachment = const ScissorAttachment(),
    this.permutation = const LevelPermutation(),
  });

  final String id;
  final String label;
  final double gridSpacing;
  final double paperMargin;
  final List<List<Offset>> polygons;
  final GridRules rules;
  final List<List<EdgeStyle>> edgeStyles;
  final List<int?> collisions;

  /// Parallel to [polygons]. Missing entries are closed rings.
  /// An open entry is a polyline and is not joined back to its first point.
  final List<bool> ringClosed;
  final ToolFilter? tools;
  final ScissorAttachment attachment;
  final LevelPermutation permutation;

  /// Sheet around the outlines and rule marks, grown by [paperMargin] cells.
  Rect get paper {
    return pointBounds([
      for (final polygon in polygons) ...polygon,
      for (final zone in permutation.noFold) ...zone,
      ...rules.anchors,
    ]).inflate(paperMargin * gridSpacing);
  }

  List<Offset> get vertices => [for (final polygon in polygons) ...polygon];

  List<EdgeStyle> edgeStyleOf(int index) {
    final ring = polygons[index];
    if (index >= edgeStyles.length || edgeStyles[index].length != ring.length) {
      return List<EdgeStyle>.filled(ring.length, EdgeStyle.penned);
    }
    return edgeStyles[index];
  }

  int? collisionOf(int index) {
    if (index < 0 || index >= collisions.length) return null;
    return collisions[index];
  }

  /// Closed rings only. Open polylines are strokes, not filled pieces.
  List<List<Offset>> get closedPolygons => [
    for (var i = 0; i < polygons.length; i++)
      if (isRingClosed(i)) polygons[i],
  ];

  bool isRingClosed(int index) {
    if (index < 0 || index >= ringClosed.length) return true;
    return ringClosed[index];
  }

  int edgeCountOf(int index) {
    final ring = polygons[index];
    if (ring.length < 2) return 0;
    return isRingClosed(index) ? ring.length : ring.length - 1;
  }

  /// Scissor length budget in grid units. Rules and the tool filter share it.
  double? get scissorLengthBudget {
    final ruled = rules.maxLength;
    final filter = tools;
    if (filter == null) return ruled;
    if (!filter.allows(CraftTool.scissors)) return 0;
    final toolCap = filter.budget(CraftTool.scissors);
    if (ruled == null) return toolCap;
    if (toolCap == null) return ruled;
    return ruled < toolCap ? ruled : toolCap;
  }

  GridStep filterPieces(bool Function(int index) keep) {
    final nextPolygons = <List<Offset>>[];
    final nextStyles = <List<EdgeStyle>>[];
    final nextCollisions = <int?>[];
    final nextClosed = <bool>[];
    for (var i = 0; i < polygons.length; i++) {
      if (!keep(i)) continue;
      nextPolygons.add(polygons[i]);
      nextStyles.add(edgeStyleOf(i));
      nextCollisions.add(collisionOf(i));
      nextClosed.add(isRingClosed(i));
    }
    return copyWith(
      polygons: nextPolygons,
      edgeStyles: nextStyles,
      collisions: nextCollisions,
      ringClosed: nextClosed,
    );
  }

  GridStep copyWith({
    List<List<Offset>>? polygons,
    GridRules? rules,
    double? paperMargin,
    List<List<EdgeStyle>>? edgeStyles,
    List<int?>? collisions,
    List<bool>? ringClosed,
    ToolFilter? tools,
    bool clearTools = false,
    ScissorAttachment? attachment,
    LevelPermutation? permutation,
  }) {
    return GridStep(
      id: id,
      label: label,
      polygons: polygons ?? this.polygons,
      gridSpacing: gridSpacing,
      paperMargin: paperMargin ?? this.paperMargin,
      rules: rules ?? this.rules,
      edgeStyles: edgeStyles ?? this.edgeStyles,
      collisions: collisions ?? this.collisions,
      ringClosed: ringClosed ?? this.ringClosed,
      tools: clearTools ? null : (tools ?? this.tools),
      attachment: attachment ?? this.attachment,
      permutation: permutation ?? this.permutation,
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
    if (_stylesStored)
      'edgeStyles': [
        for (var i = 0; i < polygons.length; i++)
          [for (final style in edgeStyleOf(i)) style.name],
      ],
    if (collisions.any((count) => count != null))
      'collisions': [for (var i = 0; i < polygons.length; i++) collisionOf(i)],
    if (ringClosed.any((closed) => !closed))
      'ringClosed': [for (var i = 0; i < polygons.length; i++) isRingClosed(i)],
    if (tools != null) 'tools': tools!.toJson(),
    if (!attachment.isEmpty) 'attachments': attachment.toJson(),
    if (!permutation.isEmpty) 'permutations': permutation.toJson(),
    if (!rules.isEmpty) 'rules': rules.toJson(),
  };

  bool get _stylesStored {
    for (var i = 0; i < polygons.length; i++) {
      if (edgeStyleOf(i).any((style) => style != EdgeStyle.penned)) {
        return true;
      }
    }
    return false;
  }

  factory GridStep.fromJson(Map<String, dynamic> json) {
    final polygons = json['polygons'] as List? ?? const [];
    final styles = json['edgeStyles'] as List? ?? const [];
    final collisions = json['collisions'] as List? ?? const [];
    final closed = json['ringClosed'] as List? ?? const [];
    return GridStep(
      id: json['id'] as String? ?? 'level',
      label: json['label'] as String? ?? 'Level',
      gridSpacing: (json['gridSpacing'] as num?)?.toDouble() ?? 1,
      paperMargin: (json['paperMargin'] as num?)?.toDouble() ?? 2,
      rules: GridRules.fromJson(json['rules']),
      tools: json.containsKey('tools')
          ? ToolFilter.fromJson(json['tools'])
          : null,
      attachment: ScissorAttachment.fromJson(json['attachments']),
      permutation: LevelPermutation.fromJson(json['permutations']),
      edgeStyles: [
        for (final row in styles)
          [
            for (final name in row as List)
              name == 'penciled' ? EdgeStyle.penciled : EdgeStyle.penned,
          ],
      ],
      collisions: [for (final value in collisions) (value as num?)?.toInt()],
      ringClosed: [for (final value in closed) value == true],
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
  return pointBounds([for (final polygon in polygons) ...polygon]);
}

Rect pointBounds(Iterable<Offset> points) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in points) {
    minX = minX < point.dx ? minX : point.dx;
    minY = minY < point.dy ? minY : point.dy;
    maxX = maxX > point.dx ? maxX : point.dx;
    maxY = maxY > point.dy ? maxY : point.dy;
  }
  if (minX == double.infinity) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Deep copy through JSON so later edits do not mutate the snapshot.
GridBlueprint cloneGridBlueprint(GridBlueprint blueprint) {
  return GridBlueprint.fromJson(blueprint.toJson());
}

/// Empty blueprint with one level. [stamp] keeps ids stable in tests.
GridBlueprint blankPuzzle({int? stamp}) {
  final id = 'puzzle-${stamp ?? DateTime.now().millisecondsSinceEpoch}';
  return GridBlueprint(
    id: id,
    name: 'Untitled',
    steps: const [GridStep(id: 'level', label: 'Level', polygons: [])],
  );
}

/// Unsaved duplicate. The caller writes it when they save.
GridBlueprint copyPuzzle(GridBlueprint source, {int? stamp}) {
  final clone = cloneGridBlueprint(source);
  return GridBlueprint(
    id: 'puzzle-${stamp ?? DateTime.now().millisecondsSinceEpoch}',
    name: 'Copy of ${source.name}',
    steps: clone.steps,
  );
}

/// A level. Prefer this name in new gridcraft code.
typedef Level = GridStep;

/// A blueprint, also called a craft. Prefer this name in new gridcraft code.
typedef Blueprint = GridBlueprint;
